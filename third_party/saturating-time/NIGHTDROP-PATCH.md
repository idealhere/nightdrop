# Patched copy of saturating-time 0.3.0

Upstream: <https://crates.io/crates/saturating-time> (now maintained inside arti), MIT OR Apache-2.0.
Used through `[patch.crates-io]` in the workspace `Cargo.toml`.

**Why:** on Windows, `find_limit` loops forever. `SystemTime` there counts 100ns ticks, so a step
under 100ns rounds to zero and returns `Some` unchanged; the search never reaches the 1ns `None`
that ends it. arti calls `max_value()` while parsing bridge descriptors, so Tor over bridges never
bootstrapped on Windows: one core at 100%, logs frozen (found 2026-09-30 in a Windows 11 VM, stack
taken with cdb). Upstream: arti#2678, arti#2726; fix expected with saturating-time 0.5.0 (arti#2753).

**What changed** (the patch posted on arti#2726):

- `internal.rs`: `SaturatingTime` requires `PartialEq`, and `find_limit` returns when a step makes
  no progress. Plus a test with a simulated 100ns clock that did not terminate before.
- `lib.rs`: `unwrap_or(max_value())` became `unwrap_or_else(max_value)` (and `min_value`), so an
  ordinary saturating add no longer computes the limit eagerly.

No effect on Linux or Android, where `SystemTime` has 1ns resolution and the new check never fires.

**Remove this directory and the `[patch.crates-io]` entry** once arti ships a saturating-time with
the fix and Night Drop moves to that arti.
