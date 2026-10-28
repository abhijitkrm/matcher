// ring_transport.hpp — batched SPSC report transport for the harness
// (api/matching_engine_api.h, "engine_get_transport"). Shared by the matcher-cpp
// adapter and the lcv3 comparison shim so both use the identical ring.
#pragma once
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>

#include "matching_engine_api.h"

namespace meb {

// Batched single-producer/single-consumer ring (engine-supplied transport,
// api/matching_engine_api.h "engine_get_transport"). The producer writes
// reports into 64-byte slots and publishes its tail every kBatch reports (and
// in flush()), so the matcher and the drainer exchange a cache line once per
// batch instead of once per report. Reports reach the drainer a few messages
// late; the harness measures throughput only.
constexpr std::uint64_t kBatch = 32;

struct Ring {
    alignas(128) std::atomic<std::uint64_t> tail_pub{0};
    alignas(128) std::atomic<std::uint64_t> head_pub{0};
    alignas(128) std::uint64_t tail = 0, head_cache = 0;  // producer-private
    alignas(128) std::uint64_t head = 0, tail_cache = 0;  // consumer-private
    std::uint64_t mask = 0;
    me_report_t* slots = nullptr;
};

inline void* ring_create(std::uint32_t capacity) {
    std::uint64_t cap = 1024;
    while (cap < capacity) cap <<= 1;
    auto* r = new Ring();
    r->mask = cap - 1;
    r->slots = static_cast<me_report_t*>(std::aligned_alloc(128, cap * sizeof(me_report_t)));
    std::memset(r->slots, 0, cap * sizeof(me_report_t));  // prefault
    return r;
}

inline int ring_push(void* h, const me_report_t* rep) {
    auto* r = static_cast<Ring*>(h);
    if (r->tail - r->head_cache > r->mask) {
        r->tail_pub.store(r->tail, std::memory_order_release);  // let the drainer free space
        r->head_cache = r->head_pub.load(std::memory_order_acquire);
        if (r->tail - r->head_cache > r->mask) return 0;
    }
    r->slots[r->tail & r->mask] = *rep;
    ++r->tail;
    if ((r->tail & (kBatch - 1)) == 0) r->tail_pub.store(r->tail, std::memory_order_release);
    return 1;
}

inline std::uint32_t ring_drain(void* h, me_report_t* out, std::uint32_t max) {
    auto* r = static_cast<Ring*>(h);
    if (r->tail_cache == r->head) {
        r->tail_cache = r->tail_pub.load(std::memory_order_acquire);
        if (r->tail_cache == r->head) return 0;
    }
    std::uint64_t n = r->tail_cache - r->head;
    if (n > max) n = max;
    for (std::uint64_t i = 0; i < n; ++i) out[i] = r->slots[(r->head + i) & r->mask];
    r->head += n;
    r->head_pub.store(r->head, std::memory_order_release);
    return static_cast<std::uint32_t>(n);
}

inline void ring_flush(void* h) {
    auto* r = static_cast<Ring*>(h);
    r->tail_pub.store(r->tail, std::memory_order_release);
}

inline void ring_destroy(void* h) {
    auto* r = static_cast<Ring*>(h);
    std::free(r->slots);
    delete r;
}

inline const me_transport_t kRingTransport = {ring_create, ring_push, ring_drain, ring_flush, ring_destroy};

}  // namespace meb
