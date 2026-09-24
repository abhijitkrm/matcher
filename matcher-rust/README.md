# matcher

Deterministic, zero-allocation FIFO limit order book and matching engine core.

Single-writer book per symbol, commands in, monotonically sequenced events out —
the same shape as real exchange matchers. All I/O hangs off the `Sink` seam;
there is no networking, persistence, or clock dependence in the core.

```rust
use matcher::*;

let mut book = OrderBook::new(BookConfig::default());
let mut sink = VecSink::new();

book.apply(Command::new(1, Side::Ask, 100, 10, Tif::Gtc), &mut sink);
book.apply(Command::new(2, Side::Bid, 100, 4, Tif::Gtc), &mut sink);

// order 2 filled 4 @100 against order 1 and closed; order 1 keeps 6 resting.
assert_eq!(book.order(1).unwrap().qty, 6);
assert!(book.order(2).is_none());
```

## Features

- Limit + Market orders, New / Cancel / Replace
- GTC, IOC, FOK, Post-Only
- FIFO price-time priority, maker-price execution, partial fills, sweeps
- Pooled orders, intrusive FIFO price levels, bitmap ladder index
  (O(1) best-price) with ordered-map fallback for unbounded prices
- `#![forbid(unsafe_code)]`, zero dependencies
- Deterministic event streams — byte-identical to the Go and C++ ports,
  verified against a shared golden vector corpus

## Docs

Semantics contract: `spec/SPEC.md` in the
[repository](https://github.com/abhijitkrm/matcher).

## License

MIT OR Apache-2.0
