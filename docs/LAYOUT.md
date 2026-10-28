# LAYOUT — reference data structures (v0.3)

The hot-path memory layout every implementation uses (BENCH.md §4: identical
structures and algorithms). Semantics are unchanged from `spec/SPEC.md`;
this file only fixes *how* state is stored so ports stay comparable.
matcher-cpp `include/matcher/detail/internals.hpp` + `book.hpp` is the
reference code.

Design goal: minimise dependent cache misses per command. Measured on an
Apple M1 (128-byte lines), v0.2 cost up to ~7 random lines per cancel
(map key/val/used arrays, order record, prev + next neighbours, level) and
one random line per maker filled in a sweep. v0.3 targets: an absent-id
check touches 1 byte; cancel touches tag + map entry + one chunk + level;
a sweep reads makers sequentially.

## 1. Order store — chunked per-level FIFO, orders inline

There is **no per-order record**. A resting order lives in a slot of its
price level's queue. Each level's queue is an unrolled doubly-linked list of
fixed 128-byte chunks:

```
Chunk (128 B, aligned to 128):
  price   i64        level price (orders in a chunk share it)
  prev    u32        chunk index or NIL (= u32::MAX)
  next    u32
  head    u8         first slot that may be live
  tail    u8         next free slot; live slots are in [head, tail)
  live    u8         live slots in this chunk
  side    u8         0 = bid, 1 = ask
  _pad    u32
  slots   6 × { id u64, qty u64 }
  tif     8 × u8     tif of slot i (6 used)
```

- **Dead slot ⇔ qty == 0.** A resting order always has qty > 0, so no
  separate flag exists.
- **location** `loc = chunk << 3 | slot` (u32) identifies an order; it is
  the order-map value. Orders never move while resting, so a loc is stable
  until the order leaves the book.
- **push(level, side, price, id, qty, tif)**: if the level's tail chunk is
  NIL or full (`tail == 6`), allocate a chunk, link it at the tail; write
  slot `tail++`, `live++`, `level.total += qty`, `store.live++`.
- **unlink(level, loc)**: `level.total -= slot.qty`, `slot.qty = 0`,
  `store.live--`; if the chunk's `live` hits 0, unlink and free the chunk.
- **front(level)**: advance the head chunk's `head` past dead slots, return
  that loc. (The head chunk always has a live slot: empty chunks are freed.)
- **Matching** fills `front()` repeatedly. A fully filled maker is retired
  in place (`qty` already 0 → `live--`, free chunk at 0) — the level total
  was already reduced by the fill.
- **Iteration** (snapshots, depth): chunks head→tail, slots `head..tail`,
  skipping dead ones. This is FIFO order.
- **Chunk pool**: `Vec<Chunk>` reserved to `max_orders` (chunks in use ≤ live
  orders, since every in-use chunk has ≥ 1 live slot), a LIFO free list
  through `next`, and a high-water mark `used`. `prefault()` commits the
  whole reservation up front (resize / touch) so no page fault or
  allocation lands in a timed section.
- `order_count()` = `store.live`; `book_full` ⇔ `store.live >= max_orders`.

Languages without value-type arrays (Java, TS, Go if needed) use the same
layout as parallel primitive arrays indexed by chunk (`chunkPrice: long[]`,
`chunkPrev/Next: int[]`, `chunkHead/Tail/Live/Side: byte[]`) and by
`loc` (`slotId: long[]`, `slotQty: long[]`, `slotTif: byte[]`, length
`8 × chunks`). That keeps the miss count per operation the same in spirit:
one slot read (id+qty adjacent if the language allows interleaving them in
one `long[]` at `2*loc`, `2*loc+1` — preferred) plus the chunk header.

## 2. Price level

```
Level { head u32, tail u32 (chunk indices), total u64 }   // 16 B
```

Empty ⇔ `head == NIL`. Ladder and tree indexes are unchanged from v0.2
(direct-indexed ladder + occupancy bitmap + summary words + best cursor;
ordered-map fallback for `index: tree`).

## 3. Order map — order_id → loc

Open addressing, linear probing, capacity = smallest power of two ≥
2 × max_orders, backward-shift deletion (Knuth 6.4R, no tombstones), as in
v0.2. Storage is split in two:

```
tags:    u8[cap]           0 = empty, else 0x80 | (h >> 57)
entries: {key u64, val u32}[cap]  (16 B with padding)
h = k * 0x9E3779B97F4A7C15;  h ^= h >> 32;  slot = h & mask
```

Probe compares the tag first; the entry is read only on a tag match. The
duplicate-id check on every `new` (usually absent) touches only the dense
tag array. `removes` counts deletions; a value reference from `get` stays
valid until the next removal (insertion never moves existing entries), so
`replace` writes the new loc through its earlier reference when the
intervening cross removed nothing, instead of re-probing.

## 4. Batch entry point + prefetch pipeline

`apply_batch(cmds)` ≡ `for c in cmds: apply(c)` for events and state. When
`store.live ≥ 65536` (book no longer cache-resident) it software-prefetches
ahead of execution, reading possibly-stale state and never writing:

| distance | New (limit) | Cancel / Replace |
|---|---|---|
| i + 16 | map tag + entry for id | map tag + entry for id |
| i + 8 | ladder level at price | `get(id)` → chunk line |
| i + 4 | level → tail chunk | chunk → own level at chunk.price (+ level at new price for replace) |

Below the threshold it is a plain loop (prefetch probes cost more than they
save on a resident book). Languages with no prefetch intrinsic (Java, TS,
Go) may implement the pipeline with ordinary loads into a sink variable
where that measurably helps, or skip it; report which. **Java skips it by
default**: its plain loads stall retirement and halve W4 throughput
(RESULTS.md, 2026-10-28). **Go** keeps the pipeline but starts it at 2^18 live orders: at
~100k it lost 30% on W4 and only the 1M-order book gains. **TS** does the same with a threshold of 2^19: at ~100k live orders the
pipeline halved W4.

## 5. Build

- C++: `-O3 -march=native -flto`; optional PGO (`-DMATCHER_PGO_PROFILE`).
- Rust: `lto="fat"`, `codegen-units=1`, `panic="abort"` for bench bins,
  `-C target-cpu=native`; `#![forbid(unsafe_code)]` stays — use safe
  indexing patterns the optimiser can prove in-bounds.
- Go / Java / TS: default release toolchains; note GC settings.
