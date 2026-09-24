//! matcher — a deterministic, zero-allocation FIFO limit order book and
//! matching engine core.
//!
//! Design mirrors real exchange matchers (CME Globex, Nasdaq INET):
//! single-writer book per symbol, commands in, monotonically sequenced events
//! out. All I/O hangs off the [`Sink`] seam — journaling, market data and
//! gateways live outside the core.
//!
//! Semantics are defined by `../spec/SPEC.md`; every implementation must emit
//! byte-identical canonical event streams for a given command stream (see
//! `../vectors/` golden corpus).
//!
//! ```
//! use matcher::*;
//!
//! let mut book = OrderBook::new(BookConfig::default());
//! let mut sink = VecSink::new();
//!
//! book.apply(Command::new(1, Side::Ask, 100, 10, Tif::Gtc), &mut sink);
//! book.apply(Command::new(2, Side::Bid, 100, 4, Tif::Gtc), &mut sink);
//!
//! // order 2 filled 4 @100 against order 1 and closed; order 1 keeps 6 resting.
//! assert_eq!(book.order(1).unwrap().qty, 6);
//! assert!(book.order(2).is_none());
//! ```

#![forbid(unsafe_code)]

mod book;
mod engine;
mod index;
mod level;
mod ordermap;
mod pool;
mod sink;
mod types;

#[doc(hidden)]
pub mod jsonflat;

pub use book::{OrderBook, OrderInfo};
pub use engine::Engine;
pub use sink::{LinesSink, NullSink, Sink, VecSink};
pub use types::*;
