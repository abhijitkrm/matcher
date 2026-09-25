//! fuzzgen — seeded adversarial command-stream generator.
//!
//! Emits `engine:true` `.cmd.jsonl` (SCHEMA.md) to stdout: every command is
//! symbol-tagged, the order-id space is deliberately small (collisions),
//! and ~1-in-20 commands are malformed on purpose (qty=0, out-of-range
//! prices). Same seed => byte-identical corpus. All five implementations
//! must produce the identical canonical event stream — see scripts/diffuzz.sh.
//!
//!   fuzzgen --seed 1 --n 10000 --symbols 4 > /tmp/fuzz.cmd.jsonl

use std::io::Write as _;

/// xorshift64* — deterministic, dependency-free (same generator as vectorgen).
struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        let mut x = self.0;
        x ^= x >> 12;
        x ^= x << 25;
        x ^= x >> 27;
        self.0 = x;
        x.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    /// biased toward the edges of [lo,hi] — boundary values hit more often.
    fn range(&mut self, lo: i64, hi: i64) -> i64 {
        let w = hi - lo + 1;
        match self.below(8) {
            0 => lo,
            1 => hi,
            2 => lo + (w / 2), // midpoint
            _ => lo + self.below(w as u64) as i64,
        }
    }
}

fn main() {
    let mut seed = 1u64;
    let mut n = 10_000u64;
    let mut symbols = 4u64;
    let mut ids = 512u64;
    let mut pmin = 0i64;
    let mut pmax = 1_000i64;

    let mut args = std::env::args().skip(1);
    while let Some(a) = args.next() {
        let v = args.next().unwrap_or_else(|| panic!("{a} needs a value"));
        match a.as_str() {
            "--seed" => seed = v.parse().unwrap(),
            "--n" => n = v.parse().unwrap(),
            "--symbols" => symbols = v.parse().unwrap(),
            "--ids" => ids = v.parse().unwrap(),
            "--pmin" => pmin = v.parse().unwrap(),
            "--pmax" => pmax = v.parse().unwrap(),
            _ => panic!("unknown arg {a}"),
        }
    }

    let mut rng = Rng(seed.wrapping_mul(0x9E37_79B9_7F4A_7C15).wrapping_add(1));
    let mut out = String::with_capacity(1 << 22);
    let stdout = std::io::stdout();

    out.push_str(&format!(
        "{{\"format\":\"matcher-vector/1\",\"name\":\"fuzz_s{seed}\",\"engine\":true,\"pmin\":{pmin},\"pmax\":{pmax},\"max_orders\":4096,\"index\":\"both\"}}\n"
    ));

    const SIDES: [&str; 2] = ["bid", "ask"];
    const TIFS: [&str; 4] = ["gtc", "ioc", "fok", "post_only"];

    for _ in 0..n {
        let sym = rng.below(symbols);
        let id = rng.below(ids);
        match rng.below(100) {
            // ~50% new orders
            0..=49 => {
                let side = SIDES[rng.below(2) as usize];
                let market = rng.below(7) == 0;
                let tif = TIFS[rng.below(4) as usize];
                // ~5% malformed on purpose: qty=0 or price out of range
                let qty = if rng.below(33) == 0 { 0 } else { rng.below(1000) + 1 };
                let price = if market {
                    rng.below(2) as i64 // ignored; 0 or 1
                } else {
                    match rng.below(20) {
                        0 => pmin - rng.range(1, 3),               // below range
                        1 => pmax + rng.range(1, 3),               // above range
                        2 => rng.range(-2, 2),                     // <=0 territory
                        _ => rng.range(pmin + 1, pmax),
                    }
                };
                let otype = if market { "market" } else { "limit" };
                out.push_str(&format!(
                    "{{\"cmd\":\"new\",\"symbol\":{sym},\"order_id\":{id},\"side\":\"{side}\",\"otype\":\"{otype}\",\"price\":{price},\"qty\":{qty},\"tif\":\"{tif}\"}}\n"
                ));
            }
            // ~25% cancel — mostly unknown/closed ids on purpose
            50..=74 => {
                out.push_str(&format!(
                    "{{\"cmd\":\"cancel\",\"symbol\":{sym},\"order_id\":{id}}}\n"
                ));
            }
            // ~25% replace — new price/qty may be out of range or zero
            _ => {
                let price = match rng.below(12) {
                    0 => pmin - 1,
                    1 => pmax + 1,
                    _ => rng.range(pmin + 1, pmax),
                };
                let qty = if rng.below(40) == 0 { 0 } else { rng.below(1000) + 1 };
                out.push_str(&format!(
                    "{{\"cmd\":\"replace\",\"symbol\":{sym},\"order_id\":{id},\"price\":{price},\"qty\":{qty}}}\n"
                ));
            }
        }
        if out.len() > (1 << 20) {
            stdout.lock().write_all(out.as_bytes()).unwrap();
            out.clear();
        }
    }
    stdout.lock().write_all(out.as_bytes()).unwrap();
}
