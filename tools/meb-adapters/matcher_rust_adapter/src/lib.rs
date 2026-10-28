//! matcher-rust adapter for the matching-engine-benchmark C ABI
//! (api/matching_engine_api.h). Same event -> report mapping as
//! matcher_cpp_adapter.cpp; see that file for the rules.
#![allow(static_mut_refs)]

use matcher::{BookConfig, CloseReason, Command, Event, IndexKind, OrderBook, Side, Sink, Tif};
use std::os::raw::c_void;

#[repr(C)]
pub struct NewOrder {
    order_id: u64,
    sequence_number: u64,
    price_ticks: i64,
    quantity: u32,
    side: u8,
    ioc: u8,
    _r: [u8; 2],
}

#[repr(C)]
pub struct Cancel {
    order_id: u64,
    sequence_number: u64,
}

#[repr(C)]
pub struct Modify {
    order_id: u64,
    sequence_number: u64,
    new_price_ticks: i64,
    new_quantity: u32,
    side: u8,
    _r: [u8; 3],
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Report {
    ty: u8,
    side: u8,
    _r: [u8; 6],
    seq: u64,
    order_id: u64,
    price: i64,
    qty: u32,
    _r2: u32,
    maker: u64,
    taker: u64,
    _r3: u64,
}

#[repr(C)]
pub struct Transport {
    create: Option<unsafe extern "C" fn()>,
    push: unsafe extern "C" fn(*mut c_void, *const Report) -> i32,
    drain: Option<unsafe extern "C" fn()>,
    flush: Option<unsafe extern "C" fn()>,
    destroy: Option<unsafe extern "C" fn()>,
}

const ORDER_ACK: u8 = 0;
const TRADE: u8 = 1;
const CANCEL_ACK: u8 = 2;
const MODIFY_ACK: u8 = 3;
const CANCEL_REJECT: u8 = 4;
const MODIFY_REJECT: u8 = 5;

#[derive(Clone, Copy, PartialEq)]
enum Mode {
    New,
    Cancel,
    Modify,
}

struct Ctx {
    tr: *const Transport,
    sink: *mut c_void,
    /// Per order id: (price << 1) | side. Prices are positive ticks < 2^30.
    ps: Vec<u32>,
    mode: Mode,
    seq: u64,
    id: u64,
    side: u8,
    price: i64,
    rejected: bool,
}

impl Ctx {
    #[inline(always)]
    fn push(&self, r: &Report) {
        unsafe {
            while ((*self.tr).push)(self.sink, r) == 0 {}
        }
    }

    #[inline(always)]
    fn report(&self, ty: u8, side: u8, id: u64, price: i64, qty: u32) {
        self.push(&Report {
            ty,
            side,
            _r: [0; 6],
            seq: self.seq,
            order_id: id,
            price,
            qty,
            _r2: 0,
            maker: 0,
            taker: 0,
            _r3: 0,
        });
    }

    #[inline(always)]
    fn ensure_id(&mut self, id: u64) {
        if id as usize >= self.ps.len() {
            self.ps.resize((id as usize + 1) * 2, 0);
        }
    }
}

impl Sink for Ctx {
    #[inline(always)]
    fn on_event(&mut self, _seq: u64, ev: &Event) {
        match *ev {
            Event::Trade {
                maker,
                taker,
                price,
                qty,
            } => self.push(&Report {
                ty: TRADE,
                side: 0,
                _r: [0; 6],
                seq: self.seq,
                order_id: taker,
                price,
                qty: qty as u32,
                _r2: 0,
                maker,
                taker,
                _r3: 0,
            }),
            Event::Closed { order_id, reason } => match reason {
                CloseReason::Cancelled => {
                    let ps = self.ps[order_id as usize];
                    self.report(CANCEL_ACK, (ps & 1) as u8, order_id, (ps >> 1) as i64, 0);
                }
                CloseReason::Expired => {
                    self.report(CANCEL_ACK, self.side, self.id, self.price, 0);
                }
                CloseReason::Filled => {}
            },
            Event::Rejected { .. } => {
                self.rejected = true;
                match self.mode {
                    Mode::Cancel => self.report(CANCEL_REJECT, 0, self.id, 0, 0),
                    Mode::Modify => self.report(MODIFY_REJECT, 0, self.id, 0, 0),
                    Mode::New => {}
                }
            }
            Event::Accepted { .. } | Event::Replaced { .. } => {}
        }
    }
}

static mut BOOK: Option<OrderBook> = None;
static mut CTX: Ctx = Ctx {
    tr: std::ptr::null(),
    sink: std::ptr::null_mut(),
    ps: Vec::new(),
    mode: Mode::New,
    seq: 0,
    id: 0,
    side: 0,
    price: 0,
    rejected: false,
};

#[inline(always)]
fn side_of(s: u8) -> Side {
    if s != 0 {
        Side::Ask
    } else {
        Side::Bid
    }
}

#[no_mangle]
pub unsafe extern "C" fn engine_init(_seed: u64, transport: *const Transport, report_sink: *mut c_void) {
    CTX.tr = transport;
    CTX.sink = report_sink;
    CTX.ps = vec![0; 1 << 21];
    let mut book = OrderBook::new(BookConfig {
        price_min: 0,
        price_max: (1 << 18) - 1,
        max_orders: 1 << 17,
        index: IndexKind::Ladder,
    });
    book.prefault();
    BOOK = Some(book);
}

#[no_mangle]
pub unsafe extern "C" fn engine_shutdown() {
    BOOK = None;
    CTX.ps = Vec::new();
}

#[no_mangle]
pub unsafe extern "C" fn engine_on_new_order(o: *const NewOrder) {
    let o = &*o;
    let ctx = &mut CTX;
    ctx.mode = Mode::New;
    ctx.seq = o.sequence_number;
    ctx.id = o.order_id;
    ctx.side = o.side;
    ctx.price = o.price_ticks;
    ctx.ensure_id(o.order_id);
    ctx.ps[o.order_id as usize] = ((o.price_ticks as u32) << 1) | o.side as u32;
    ctx.report(ORDER_ACK, o.side, o.order_id, o.price_ticks, o.quantity);
    let tif = if o.ioc != 0 { Tif::Ioc } else { Tif::Gtc };
    BOOK.as_mut().unwrap_unchecked().apply(
        Command::new(o.order_id, side_of(o.side), o.price_ticks, o.quantity as u64, tif),
        ctx,
    );
}

#[no_mangle]
pub unsafe extern "C" fn engine_on_cancel(c: *const Cancel) {
    let c = &*c;
    let ctx = &mut CTX;
    ctx.mode = Mode::Cancel;
    ctx.seq = c.sequence_number;
    ctx.id = c.order_id;
    ctx.ensure_id(c.order_id);
    BOOK.as_mut().unwrap_unchecked().apply(Command::Cancel { order_id: c.order_id }, ctx);
}

#[no_mangle]
pub unsafe extern "C" fn engine_on_modify(m: *const Modify) {
    let m = &*m;
    let ctx = &mut CTX;
    ctx.mode = Mode::Modify;
    ctx.seq = m.sequence_number;
    ctx.id = m.order_id;
    ctx.rejected = false;
    ctx.ensure_id(m.order_id);
    BOOK.as_mut().unwrap_unchecked().apply(
        Command::Replace {
            order_id: m.order_id,
            price: m.new_price_ticks,
            qty: m.new_quantity as u64,
        },
        ctx,
    );
    if !ctx.rejected {
        ctx.ps[m.order_id as usize] = ((m.new_price_ticks as u32) << 1) | m.side as u32;
        ctx.report(MODIFY_ACK, m.side, m.order_id, m.new_price_ticks, m.new_quantity);
    }
}

#[no_mangle]
pub extern "C" fn engine_flush() {}

#[no_mangle]
pub unsafe extern "C" fn engine_query_best_bid() -> i64 {
    BOOK.as_ref().unwrap_unchecked().best_bid().unwrap_or(i64::MIN)
}

#[no_mangle]
pub unsafe extern "C" fn engine_query_best_ask() -> i64 {
    BOOK.as_ref().unwrap_unchecked().best_ask().unwrap_or(i64::MAX)
}

#[no_mangle]
pub unsafe extern "C" fn engine_query_depth_at(price_ticks: i64, side: u8) -> u64 {
    BOOK.as_ref().unwrap_unchecked().level_total(side_of(side), price_ticks)
}
