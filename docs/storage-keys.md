# Storage Keys Reference

This document enumerates every `DataKey` variant defined by each contract in
`dabdub_contracts/contracts/`, together with the storage type it lives in, the
Rust value type stored at that key, and its TTL / lifetime characteristics.

> **Maintenance note:** this table MUST be updated whenever a new `DataKey`
> variant is added to (or removed from) any contract. A PR that adds a storage
> key without updating this file should be considered incomplete.

## Legend

- **Storage type** — the Soroban storage tier used: `instance`, `persistent`,
  or `temporary`.
- **Value type** — the Rust type written at the key.
- **TTL** — lifetime behaviour. `instance` entries live as long as the contract
  instance (bumped with the instance TTL). `persistent` entries survive archival
  and must be bumped explicitly. `temporary` entries expire and are not
  restorable.
- **Set in** — whether the key is written in the constructor (`__constructor`)
  or only at runtime by a contract method.

## admin_timelock

| Contract | Key | Storage type | Value type | TTL | Set in |
| --- | --- | --- | --- | --- | --- |
| admin_timelock | `Admin` | instance | `Address` | instance TTL | constructor |
| admin_timelock | `Counter` | instance | `u64` | instance TTL | constructor |
| admin_timelock | `Change(BytesN<32>)` | persistent | `ScheduledChange` | persistent (bump on access) | runtime (`schedule_change`) |
| admin_timelock | `PendingList` | instance | `Vec<BytesN<32>>` | instance TTL | constructor |

## Notes

- `admin_timelock` initialises `Admin`, `Counter`, and `PendingList` in the
  constructor. `Change(id)` entries are created at runtime by
  `schedule_change` and removed by `prune_change`.
- `Change(id)` is stored in `persistent` storage so queued changes survive
  archival; callers should bump its TTL when reading/writing.

## Adding new keys

When introducing a new `DataKey` variant:

1. Add a row to the relevant contract table above with the storage type, value
   type, TTL behaviour, and whether it is set in the constructor or at runtime.
2. If the contract is not yet listed, add a new `## <contract>` section.
