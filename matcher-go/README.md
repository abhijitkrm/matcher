# matcher-go

Deterministic, zero-allocation-steady-state FIFO limit order book and matching
engine core — Go port of the reference Rust implementation.

```go
import "github.com/abhijitkrm/matcher/matcher-go/matcher"
```

```go
book := matcher.NewOrderBook(matcher.DefaultConfig())
sink := &matcher.VecSink{}

book.Apply(matcher.NewLimit(1, matcher.Ask, 100, 10, matcher.GTC), sink)
book.Apply(matcher.NewLimit(2, matcher.Bid, 100, 4, matcher.GTC), sink)
// order 2 filled 4 @100 against order 1 and closed; order 1 keeps 6 resting.
```

## Features

- Limit + Market orders, New / Cancel / Replace
- GTC, IOC, FOK, Post-Only
- FIFO price-time priority, maker-price execution
- Pooled orders, intrusive FIFO price levels, bitmap ladder index
- Deterministic event streams — byte-identical to the Rust and C++
  implementations, verified against the shared golden vector corpus
- Zero dependencies

## Test

```bash
go test ./...   # runs all golden vectors from ../vectors
```

Semantics contract: `spec/SPEC.md` in the repository root.

## License

MIT OR Apache-2.0
