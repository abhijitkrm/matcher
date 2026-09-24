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
spec/        SPEC.md (semantics contract) · SCHEMA.md (vector format) · BENCH.md
vectors/     golden corpus — *.cmd.jsonl in, canonical *.evt.jsonl out
tools/       vectorgen — deterministic benchmark-workload generator
scripts/     verify.sh — runs every impl repo's golden tests
docs/        RESULTS.md — cross-language benchmark matrix
```

## How parity works

Each implementation repo vendors a copy of `spec/` + `vectors/`. Its golden
runner replays every `*.cmd.jsonl` and asserts the emitted stream matches the
canonical `*.evt.jsonl` byte-for-byte — in every index mode the vector
declares. `scripts/verify.sh` runs all three suites when the impl repos are
checked out as siblings (`../matcher-rust` etc).

## Benchmarks

`tools/vectorgen` emits seeded `<prefix>.setup.cmd.jsonl` +
`<prefix>.run.cmd.jsonl` corpora — same seed, byte-identical workloads in
every language. Protocol and reporting format: `spec/BENCH.md`. Measured
results: `docs/RESULTS.md`.

## Contributing

Semantics changes start here: `spec/SPEC.md`, a new golden vector, then the
change lands in every impl repo. See `CONTRIBUTING.md`.

## License

Licensed under either of [Apache-2.0](LICENSE-APACHE) or
[MIT](LICENSE-MIT) at your option.
