# Changelog

## v0.1.0 — 2025-01-XX

Initial release.

- `matcher-rust` — reference implementation: `OrderBook` + `Engine`,
  `Sink` event seam, pooled orders, intrusive FIFO levels, bitmap ladder
  index with top-of-book cursor, `std::BTreeMap` fallback for unbounded
  prices. `#![forbid(unsafe_code)]`, zero dependencies.
- `matcher-go` — Go port, zero dependencies.
- `matcher-cpp` — header-only C++20 port, enum-dispatched index.
- Semantics: Limit/Market, New/Cancel/Replace, GTC/IOC/FOK/Post-Only,
  FIFO price-time priority, maker-price execution.
- `spec/` contract, 41 golden vectors, `tools/vectorgen` deterministic
  corpus generator, `scripts/verify.sh` cross-implementation parity check.
- Benchmark baseline in `docs/RESULTS.md` (Apple M1): ~4–23M commands/sec
  cache-resident, ~2–4M at 1M-order depth.
