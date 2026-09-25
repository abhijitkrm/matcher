# matcher

[![ci](https://github.com/abhijitkrm/matcher/actions/workflows/ci.yml/badge.svg)](https://github.com/abhijitkrm/matcher/actions/workflows/ci.yml)
[![license](https://img.shields.io/badge/license-MIT%20OR%20Apache--2.0-blue.svg)](LICENSE-MIT)

**The specification repo for the matcher project** — a small, deterministic,
exchange-grade order-matching core shipped as idiomatic, zero-dependency
packages in multiple languages.

This repo holds the shared contract: semantics spec, golden test vectors,
workload generator, and benchmark methodology. The implementations live in
their own repos and prove byte-identical behavior against `vectors/`.

## Implementations

| Repo | Language | Package |
|---|---|---|
| [matcher-rust](https://github.com/abhijitkrm/matcher-rust) | Rust | `matcher` on crates.io |
| [matcher-go](https://github.com/abhijitkrm/matcher-go) | Go | `github.com/abhijitkrm/matcher-go` |
| [matcher-cpp](https://github.com/abhijitkrm/matcher-cpp) | C++20 | header-only CMake lib |
| [matcher-ts](https://github.com/abhijitkrm/matcher-ts) | TypeScript | `@abhijitkrm/matcher` on npm |
| [matcher-java](https://github.com/abhijitkrm/matcher-java) | Java 17+ | `io.github.abhijitkrm:matcher` |

## The design

Mirrors how real exchanges structure their matchers (CME Globex, Nasdaq
Genium INET): a single-writer limit order book per symbol, commands in, a
monotonically sequenced event stream out. Everything else — sessions,
protocols, persistence, HA — lives outside, behind the event-sink seam.

- Order types: Limit, Market · Commands: New, Cancel, Replace
- TIF: GTC, IOC, FOK, Post-Only · FIFO price-time priority
- Zero-allocation steady state: pooled orders, intrusive FIFO levels,
  direct-indexed bitmap price ladder (O(1) best price) + ordered-map fallback
- Deterministic: no wall-clock, no randomness; every command yields a
  sequenced event stream
- Explicit non-goals: networking, FIX, persistence, fees, risk checks — see
  `spec/SPEC.md`

## Layout

```
spec/        SPEC.md (semantics contract) · SCHEMA.md (vector format) ·
             BENCH.md · JOURNAL.md (persistence/recovery contract)
vectors/     golden corpus — *.cmd.jsonl in, canonical *.evt.jsonl out
tools/       vectorgen — deterministic benchmark-workload generator ·
             fuzzgen — adversarial + exhaustive stream generator
scripts/     verify.sh — runs every impl repo's golden tests ·
             diffuzz.sh — seeded differential fuzzing ·
             exhaustive.sh — bounded exhaustive parity proof ·
             e2e.sh — end-to-end journal/snapshot/recovery loop ·
             snapdiff.sh — cross-language snapshot parity
docs/        RESULTS.md — cross-language benchmark matrix · SCALING.md —
             threading + symbol-partitioning model
```

## How parity works

Each implementation repo vendors a copy of `spec/` + `vectors/`. Its golden
runner replays every `*.cmd.jsonl` and asserts the emitted stream matches the
canonical `*.evt.jsonl` byte-for-byte — in every index mode the vector
declares. `scripts/verify.sh` runs the impl suites when the impl repos are
checked out as siblings (`../matcher-rust` etc).

Beyond curated vectors, `tools/fuzzgen` + `scripts/diffuzz.sh` do
**differential fuzzing**: seeded adversarial command streams (crossing orders,
duplicate/unknown ids, qty=0, out-of-range prices, 8 interleaved symbols) are
replayed through every implementation's `matcherfuzz` harness and the
canonical event streams must be byte-identical — the strongest parity check
available. `SAN=1` additionally runs matcher-cpp under ASan+UBSan, and the
Rust harness asserts book invariants after every command.

`scripts/exhaustive.sh` escalates fuzzing into **bounded exhaustive proof**:
`fuzzgen --exhaustive D` emits *every* length-D sequence over an 8-command
alphabet covering the semantic space (crossing both directions, FIFO ties,
IOC/FOK/PostOnly, duplicate/unknown ids, cancel, replace) alternating two
symbols — every impl runs every sequence, all byte-identical. Within the
bounded domain this is a proof of equivalence on the real code, not sampling.

## Persistence & recovery (spec/JOURNAL.md)

Determinism makes persistence recording, not magic: commands journal before
apply, events journal at the sink, snapshots capture resting state as flat
`{"rec":...}` lines. Every impl ships `matcherrun`/`matcherrecover`
(`snapdump` for snapshots) and `scripts/e2e.sh` proves the full loop per impl
— **plus a 5×5 cross-impl matrix: a snapshot written by any implementation
restores byte-identically in every other**.

## Benchmarks

`tools/vectorgen` emits seeded `<prefix>.setup.cmd.jsonl` +
`<prefix>.run.cmd.jsonl` corpora — same seed, byte-identical workloads in
every language. Protocol and reporting format: `spec/BENCH.md`.

Peak throughput per implementation (single-threaded, per `spec/BENCH.md`):

| Implementation | Peak ops/s | Workload |
|---|---:|---|
| [matcher-cpp](https://github.com/abhijitkrm/matcher-cpp) | ~23M | w5 depth=1k |
| [matcher-rust](https://github.com/abhijitkrm/matcher-rust) | ~19M | w5 depth=1k |
| [matcher-java](https://github.com/abhijitkrm/matcher-java) | ~11M | w2 sweep |
| [matcher-go](https://github.com/abhijitkrm/matcher-go) | ~9M | w5 depth=1k |
| [matcher-ts](https://github.com/abhijitkrm/matcher-ts) | ~5M | w5 depth=1k |

Peak is the cache-resident ceiling; deep books are memory-latency-bound
(~4M ops/s at depth=1M for the native impls). Full workload matrix, latency
percentiles, and environment details: [`docs/RESULTS.md`](docs/RESULTS.md).

## Contributing

Semantics changes start here: `spec/SPEC.md`, a new golden vector, then the
change lands in every impl repo. See `CONTRIBUTING.md`.

## License

Licensed under either of [Apache-2.0](LICENSE-APACHE) or
[MIT](LICENSE-MIT) at your option.
