# matcher-cpp

Deterministic FIFO limit order book and matching engine core — header-only
C++20, port of the reference Rust implementation.

```cpp
#include <matcher/matcher.hpp>
```

```cpp
matcher::OrderBook book(matcher::BookConfig{});
matcher::VecSink sink;

book.apply(matcher::Command::new_limit(1, matcher::Side::Ask, 100, 10,
                                       matcher::Tif::Gtc), sink);
book.apply(matcher::Command::new_limit(2, matcher::Side::Bid, 100, 4,
                                       matcher::Tif::Gtc), sink);
// order 2 filled 4 @100 against order 1 and closed; order 1 keeps 6 resting.
```

## Use it

Header-only — either add `include/` to your include path, or via CMake:

```cmake
add_subdirectory(matcher-cpp)
target_link_libraries(your_target PRIVATE matcher)
```

Requires C++20. Zero dependencies.

## Features

- Limit + Market orders, New / Cancel / Replace
- GTC, IOC, FOK, Post-Only
- FIFO price-time priority, maker-price execution
- Pooled orders, intrusive FIFO price levels, bitmap ladder index
  with `std::map` fallback for unbounded prices
- Enum-dispatched index (no virtual dispatch on the hot path)
- Deterministic event streams — byte-identical to the Rust and Go
  implementations, verified against the shared golden vector corpus

## Test

```bash
cmake -B build && cmake --build build && ctest --test-dir build
```

Semantics contract: `spec/SPEC.md` in the repository root.

## License

MIT OR Apache-2.0
