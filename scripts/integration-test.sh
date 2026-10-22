#!/usr/bin/env bash
# Integration test runner for the full payment lifecycle.
#
# Exercises: deploy all contracts -> register merchant -> create escrow
# deposit -> release -> record settlement, against the local testnet started
# from docker-compose. Prints PASS/FAIL per step with transaction hashes.
#
# Usage: scripts/integration-test.sh
#   Requires: docker compose up (local testnet), stellar CLI, jq.
set -uo pipefail

NETWORK="${NETWORK:-local}"
RPC_URL="${RPC_URL:-http://localhost:8000/soroban/rpc}"
NETWORK_PASSPHRASE="${NETWORK_PASSPHRASE:-Standalone Network ; February 2017}"
SOURCE="${SOURCE:-integration-admin}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WASM_DIR="${WASM_DIR:-$ROOT_DIR/target/wasm32-unknown-unknown/release}"

FAILED=0

log()  { printf '%s\n' "$*"; }
pass() { printf 'PASS  %s  tx=%s\n' "$1" "${2:-n/a}"; }
fail() { printf 'FAIL  %s  %s\n' "$1" "${2:-}"; FAILED=1; }

# Run a stellar CLI invocation, capturing stdout. Returns non-zero on failure.
run() { stellar "$@" 2>&1; }

# Extract a transaction hash from CLI output (best-effort).
tx_hash() { printf '%s' "$1" | grep -Eo '[0-9a-f]{64}' | head -n1; }

require() {
  command -v "$1" >/dev/null 2>&1 || { log "missing required tool: $1"; exit 1; }
}

require stellar
require jq

log "== Payment lifecycle integration test =="
log "network=$NETWORK rpc=$RPC_URL"

# ---------------------------------------------------------------------------
# Step 1: deploy all contracts
# ---------------------------------------------------------------------------
DEPLOYED=()
for name in merchant_registry payment_escrow fee_calculator settlement_ledger; do
  wasm="$WASM_DIR/${name}.wasm"
  if [[ ! -f "$wasm" ]]; then
    fail "deploy $name" "wasm not found: $wasm (build contracts first)"
    continue
  fi
  out=$(run contract deploy --wasm "$wasm" --source "$SOURCE" \
        --network "$NETWORK" --rpc-url "$RPC_URL" \
        --network-passphrase "$NETWORK_PASSPHRASE") || {
    fail "deploy $name" "$out"; continue
  }
  id=$(printf '%s' "$out" | grep -Eo 'C[A-Z0-9]{55}' | head -n1)
  if [[ -z "$id" ]]; then
    fail "deploy $name" "could not parse contract id from: $out"; continue
  fi
  DEPLOYED+=("$name=$id")
  pass "deploy $name" "$id"
  declare "CONTRACT_${name^^}=$id"
done

if [[ ${#DEPLOYED[@]} -lt 4 ]]; then
  log "aborting: not all contracts deployed"
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 2: register merchant
# ---------------------------------------------------------------------------
MERCHANT="${MERCHANT:-integration-merchant}"
out=$(run contract invoke --id "$CONTRACT_MERCHANT_REGISTRY" --source "$SOURCE" \
      --network "$NETWORK" --rpc-url "$RPC_URL" \
      --network-passphrase "$NETWORK_PASSPHRASE" \
      -- register_merchant --merchant "$MERCHANT") || {
  fail "register merchant" "$out"; exit 1
}
pass "register merchant" "$(tx_hash "$out")"

# ---------------------------------------------------------------------------
# Step 3: create escrow deposit
# ---------------------------------------------------------------------------
PAYMENT_ID="${PAYMENT_ID:-$(printf '%064d' 1)}"
AMOUNT="${AMOUNT:-10000000}"
out=$(run contract invoke --id "$CONTRACT_PAYMENT_ESCROW" --source "$SOURCE" \
      --network "$NETWORK" --rpc-url "$RPC_URL" \
      --network-passphrase "$NETWORK_PASSPHRASE" \
      -- deposit --payment_id "$PAYMENT_ID" --merchant "$MERCHANT" \
      --amount "$AMOUNT") || {
  fail "create escrow deposit" "$out"; exit 1
}
pass "create escrow deposit" "$(tx_hash "$out")"

# ---------------------------------------------------------------------------
# Step 4: release escrow
# ---------------------------------------------------------------------------
out=$(run contract invoke --id "$CONTRACT_PAYMENT_ESCROW" --source "$SOURCE" \
      --network "$NETWORK" --rpc-url "$RPC_URL" \
      --network-passphrase "$NETWORK_PASSPHRASE" \
      -- release --payment_id "$PAYMENT_ID") || {
  fail "release escrow" "$out"; exit 1
}
pass "release escrow" "$(tx_hash "$out")"

# ---------------------------------------------------------------------------
# Step 5: record settlement
# ---------------------------------------------------------------------------
out=$(run contract invoke --id "$CONTRACT_SETTLEMENT_LEDGER" --source "$SOURCE" \
      --network "$NETWORK" --rpc-url "$RPC_URL" \
      --network-passphrase "$NETWORK_PASSPHRASE" \
      -- record_settlement --payment_id "$PAYMENT_ID" --merchant "$MERCHANT" \
      --amount "$AMOUNT") || {
  fail "record settlement" "$out"; exit 1
}
pass "record settlement" "$(tx_hash "$out")"

log "== done =="
if [[ $FAILED -ne 0 ]]; then
  log "RESULT: FAIL"
  exit 1
fi
log "RESULT: PASS"
