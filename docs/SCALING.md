# SCALING — threading and partitioning model

How a matcher deployment grows from one symbol to many markets, and why the
single-threaded core *is* the scaling design.

## The rule: one writer per book

An `OrderBook` is a **single-writer** domain. It is not internally
synchronized — that is deliberate, not a missing feature. Matching engines at
real venues (CME Globex market segments, Nasdaq INET partitions) pin one
deterministic thread per book because:

- Lock-free single-writer is faster than any shared-state scheme — no
  atomics, no coherence traffic, no priority inversions.
- Determinism requires a total order on commands; a single writer trivially
  provides it. Concurrent submitters would need a sequencer anyway.

The caller supplies sequencing. Options, in order of typical deployment:

1. **Direct call** — the producer thread is the writer (backtests, harnesses).
2. **A queue in front** — one consumer thread drains a ring/MPSC queue and is
   the sole `apply` caller (the standard production shape).
3. **Never** two threads calling `apply` on the same book concurrently.

The `Sink` runs on the writer's thread inside `apply`. Keep sink work cheap
or hand events off to an egress ring — a slow sink is head-of-line blocking.

## Within one thread: `Engine`

`Engine` routes `(symbol, cmd)` to per-symbol `OrderBook`s — many markets on
one writer thread. Semantics (SPEC §6):

- Order-id namespace is **per-symbol** — `order_id=7` can live on many books.
- `seq` is **per-book** — cross-symbol interleaving in the sink is fine;
  each book's own sequence stays dense from 1.
- Books are created lazily on first submit with the engine's default config.
- Commands are atomic **per book only** — nothing touches two books.

This is exercised byte-for-byte by `vectors/engine/001_multisymbol`.

## Beyond one core: partition by symbol

Scale out the way venues do — static symbol partitioning:

```
                    ┌─ engine #1 (core 3): sym partition A ─ sink → journal/md A
gateway/sequencer ──┼─ engine #2 (core 5): sym partition B ─ sink → journal/md B
                    └─ engine #3 (core 7): sym partition C ─ sink → journal/md C
```

- **Static assignment** — a symbol's whole lifetime lives on exactly one
  engine thread. The gateway routes by a partition table (or `hash(sym)`);
  clients never need to know the mapping.
- **Linear throughput** — engines share no state, so N pinned cores give ~N×
  the single-core number (minus gateway overhead, which becomes the
  bottleneck next — that's a transport problem, not a matching problem).
- **Sequence numbers are per-engine/per-book** — never promise a global
  cross-market order. Consumers merge streams by receipt order or a
  gateway-stamped timestamp if they need a unified view (this is exactly the
  ITCH/iLink model: per-channel sequence).
- **Journals/snapshots replicate per engine** — engine *i* owns
  `cmd-i.journal`, `events-i.journal`, `snap-i.bin`. Recovery replays each
  partition independently; determinism guarantees byte-identical replay.

## Rebalancing

To move a symbol between engines: drain its command flow, snapshot the book
(engine `book(sym)` gives access), hand the snapshot to the target engine,
cut over at the gateway. Live-migration isn't built in — on purpose; it's a
pause-the-symbol operation in production too.

## What breaks the model

Any feature needing **atomicity across books** forces the affected books onto
one engine thread — or out of the core entirely:

- **Implied orders** (futures spread ⇒ leg prices): matching one book mutates
  sibling books; they must co-locate. Needs spec-level implied-in/out rules
  first (SPEC §9 reserved).
- **Cross-market self-trade prevention**: cannot be atomic across engines.
  Venues solve it at the gateway (route a trader's symbols to one partition)
  or per-book only.
- **Cross-currency/cross-product risk**: lives in the risk gateway, before
  commands reach the engine — not in the matcher.

Rule of thumb: *independent markets shard freely; coupled markets co-locate.*

## Deployment checklist

- [ ] Pin each engine thread to an isolated core (`isolcpus` +
      `sched_setaffinity`); never two engines per core.
- [ ] NUMA-local allocation for pools; hugepages for large books.
- [ ] One input queue + one output journal per engine; no shared channels.
- [ ] Symbol→partition map owned by the gateway; versioned, restart-safe.
- [ ] Per-engine journals/snapshots; recovery = snapshot + journal tail.
- [ ] Consumer merges by per-engine seq, not a global order.
