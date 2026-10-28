// matcher_cpp_adapter.cpp — matching-engine-benchmark ABI adapter for matcher-cpp.
//
// Maps matcher-cpp's event stream onto the harness's six report types. The
// engine is used unmodified (one public query, OrderBook::level_total, was
// added for engine_query_depth_at). Mapping, from the harness contract:
//
//   new order   OrderAck first (the order's own price/qty), then one Trade per
//               fill; an IOC residual (our closed{expired}) -> CancelAck.
//   cancel      closed{cancelled} -> CancelAck (stored side + resting price);
//               rejected{unknown_order_id} -> CancelReject.
//   modify      cancel+reinsert is exactly our replace for a quantity increase;
//               one ModifyAck (requested price/qty) whether or not the
//               reinsert fully filled (our closed{filled}); unknown id ->
//               ModifyReject.
//
// Order ids are dense (OUCH-style), so the side and resting price needed for
// CancelAck are kept in a flat id-indexed array, as the reference adapters do.

#include <matcher/matcher.hpp>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
#include <memory>
#include <vector>

#include "matching_engine_api.h"
#ifdef CUSTOM_TRANSPORT
#include "ring_transport.hpp"
#endif

namespace {

using namespace matcher;

const me_transport_t* g_tr = nullptr;
void* g_sink = nullptr;
std::unique_ptr<OrderBook> g_book;

// Per order id: (price << 1) | side. Prices are positive ticks < 2^30.
std::vector<std::uint32_t> g_ps;

// The message being processed.
enum Mode : std::uint8_t { kNew, kCancel, kModify };
Mode g_mode = kNew;
std::uint64_t g_seq = 0;
std::uint64_t g_id = 0;
std::uint8_t g_side = 0;
std::int64_t g_price = 0;

#ifdef CUSTOM_TRANSPORT
using meb::ring_push;
using meb::ring_flush;
using meb::kRingTransport;
#endif

inline void push(const me_report_t& r) {
#ifdef DISCARD_REPORTS
    // Measurement only: drops every report to expose the matcher-side floor.
    // The correctness hash FAILs by construction; never report this build.
    asm volatile("" : : "r"(&r) : "memory");
    return;
#endif
#ifdef CUSTOM_TRANSPORT
    while (!ring_push(g_sink, &r)) {
    }
#else
    while (!g_tr->push(g_sink, &r)) {
        // queue full: spin until the drainer catches up
    }
#endif
}

inline void report(std::uint8_t type, std::uint8_t side, std::uint64_t id,
                   std::int64_t price, std::uint32_t qty) {
    me_report_t r;
    std::memset(&r, 0, sizeof r);
    r.type = type;
    r.side = side;
    r.sequence_number = g_seq;
    r.order_id = id;
    r.price_ticks = price;
    r.quantity = qty;
    push(r);
}

struct ReportSink {
    inline void on_event(std::uint64_t, const Event& ev) {
        switch (ev.kind) {
            case Event::Kind::Trade: {
                me_report_t r;
                std::memset(&r, 0, sizeof r);
                r.type = ME_TRADE;
                r.sequence_number = g_seq;
                r.order_id = ev.taker;
                r.price_ticks = ev.price;
                r.quantity = static_cast<std::uint32_t>(ev.qty);
                r.maker_order_id = ev.maker;
                r.taker_order_id = ev.taker;
                push(r);
                break;
            }
            case Event::Kind::Closed:
                if (ev.reason == std::uint8_t(CloseReason::Cancelled)) {
                    const std::uint32_t ps = g_ps[ev.order_id];
                    report(ME_CANCEL_ACK, ps & 1, ev.order_id, ps >> 1, 0);
                } else if (ev.reason == std::uint8_t(CloseReason::Expired)) {
                    // IOC residual of the order being processed.
                    report(ME_CANCEL_ACK, g_side, g_id, g_price, 0);
                }
                break;  // closed{filled}: a maker (or taker) leaving; not reported
            case Event::Kind::Rejected:
                if (g_mode == kCancel) report(ME_CANCEL_REJECT, 0, g_id, 0, 0);
                else if (g_mode == kModify) report(ME_MODIFY_REJECT, 0, g_id, 0, 0);
                break;
            default:  // Accepted / Replaced: covered by the OrderAck / ModifyAck below
                break;
        }
    }
};

ReportSink g_rs;

inline void ensure_id(std::uint64_t id) {
    if (id >= g_ps.size()) g_ps.resize((id + 1) * 2, 0);
}

}  // namespace

extern "C" {

void engine_init(std::uint64_t, const me_transport_t* transport, void* report_sink) {
    g_tr = transport;
    g_sink = report_sink;
    BookConfig cfg;
    cfg.price_min = 0;
    cfg.price_max = (1 << 18) - 1;  // 262,144 ticks, as the QuantCup baseline
    cfg.max_orders = 1 << 17;       // standing book peaks ~42k orders (static)
    cfg.index = IndexKind::Ladder;
    g_book = std::make_unique<OrderBook>(cfg);
    g_book->prefault();
    g_ps.assign(1 << 21, 0);
}

void engine_shutdown(void) {
    g_book.reset();
    std::vector<std::uint32_t>().swap(g_ps);
}

void engine_on_new_order(const new_order_t* o) {
    g_mode = kNew;
    g_seq = o->sequence_number;
    g_id = o->order_id;
    g_side = o->side;
    g_price = o->price_ticks;
    ensure_id(g_id);
    g_ps[g_id] = (static_cast<std::uint32_t>(g_price) << 1) | g_side;
    report(ME_ORDER_ACK, g_side, g_id, g_price, o->quantity);
    g_book->apply(Command::new_limit(g_id, o->side ? Side::Ask : Side::Bid, g_price,
                                     o->quantity, o->ioc ? Tif::Ioc : Tif::Gtc),
                  g_rs);
}

void engine_on_cancel(const cancel_t* c) {
    g_mode = kCancel;
    g_seq = c->sequence_number;
    g_id = c->order_id;
    ensure_id(g_id);
    g_book->apply(Command::cancel(g_id), g_rs);
}

void engine_on_modify(const modify_t* m) {
    g_mode = kModify;
    g_seq = m->sequence_number;
    g_id = m->order_id;
    ensure_id(g_id);
    // A rejected replace (unknown id) emits rejected -> ModifyReject; otherwise
    // the reinsert may trade, then exactly one ModifyAck follows.
    struct Probe {
        ReportSink* rs;
        bool rejected = false;
        inline void on_event(std::uint64_t s, const Event& ev) {
            if (ev.kind == Event::Kind::Rejected) rejected = true;
            rs->on_event(s, ev);
        }
    } probe{&g_rs};
    g_book->apply(Command::replace(g_id, m->new_price_ticks, m->new_quantity), probe);
    if (!probe.rejected) {
        g_ps[g_id] = (static_cast<std::uint32_t>(m->new_price_ticks) << 1) | m->side;
        report(ME_MODIFY_ACK, m->side, g_id, m->new_price_ticks, m->new_quantity);
    }
}

void engine_flush(void) {
#ifdef CUSTOM_TRANSPORT
    ring_flush(g_sink);
#endif
}

#ifdef CUSTOM_TRANSPORT
const me_transport_t* engine_get_transport(void) { return &kRingTransport; }
#endif

std::int64_t engine_query_best_bid(void) {
    Price p;
    return g_book->best_bid(p) ? p : std::numeric_limits<std::int64_t>::min();
}

std::int64_t engine_query_best_ask(void) {
    Price p;
    return g_book->best_ask(p) ? p : std::numeric_limits<std::int64_t>::max();
}

std::uint64_t engine_query_depth_at(std::int64_t price_ticks, std::uint8_t side) {
    return g_book->level_total(side ? Side::Ask : Side::Bid, price_ticks);
}

}  // extern "C"
