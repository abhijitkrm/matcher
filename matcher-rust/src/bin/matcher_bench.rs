//! matcher_bench — spec/BENCH.md measurement protocol.
//!
//!   matcher_bench <prefix> [--tag name]
//!
//! Loads `<prefix>.setup.cmd.jsonl` (untimed) + `<prefix>.run.cmd.jsonl`
//! (measured). Prints one RESULTS.md row. Parsing happens before timing;
//! all per-op latencies (ns) are stored, sorted, and reported exactly.

use std::time::Instant;

use matcher::jsonflat::{parse_command, parse_header};
use matcher::*;

fn load(path: &str) -> (BookConfig, Vec<Command>) {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{path}: {e}"));
    let mut lines = text.lines();
    let (pmin, pmax, max_orders, index) = parse_header(lines.next().unwrap_or(""));
    let cmds = lines
        .filter(|l| !l.trim().is_empty())
        .map(|l| parse_command(l).unwrap_or_else(|| panic!("bad command line: {l}")))
        .collect();
    (
        BookConfig {
            price_min: pmin,
            price_max: pmax,
            max_orders,
            index,
        },
        cmds,
    )
}

fn percentile(sorted: &[u64], p: f64) -> u64 {
    if sorted.is_empty() {
        return 0;
    }
    let i = ((sorted.len() as f64 - 1.0) * p).ceil() as usize;
    sorted[i.min(sorted.len() - 1)]
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: matcher_bench <corpus-prefix> [--tag name]");
        std::process::exit(2);
    }
    let prefix = &args[1];
    let tag = args
        .iter()
        .position(|a| a == "--tag")
        .and_then(|i| args.get(i + 1))
        .cloned()
        .unwrap_or_else(|| prefix.rsplit('/').next().unwrap().to_string());

    let (cfg, setup) = load(&format!("{prefix}.setup.cmd.jsonl"));
    let (_, run) = load(&format!("{prefix}.run.cmd.jsonl"));

    // Warmup: throwaway book, setup + first 10% of run.
    {
        let mut book = OrderBook::new(cfg);
        let mut sink = NullSink::new();
        for c in &setup {
            book.apply(*c, &mut sink);
        }
        for c in run.iter().take(run.len() / 10) {
            book.apply(*c, &mut sink);
        }
        std::hint::black_box(sink.acc);
    }

    // Timed: fresh book, untimed setup, per-op timing on run.
    let mut book = OrderBook::new(cfg);
    let mut sink = NullSink::new();
    for c in &setup {
        book.apply(*c, &mut sink);
    }
    let mut lat = Vec::with_capacity(run.len());
    let wall = Instant::now();
    for c in &run {
        let t0 = Instant::now();
        book.apply(*c, &mut sink);
        lat.push(t0.elapsed().as_nanos() as u64);
    }
    let wall_ns = wall.elapsed().as_nanos() as u64;
    std::hint::black_box(sink.acc);

    lat.sort_unstable();
    let ops = run.len();
    let ops_s = ops as f64 / (wall_ns as f64 / 1e9);
    let mean = lat.iter().map(|v| *v as u128).sum::<u128>() / ops.max(1) as u128;

    println!(
        "| {tag} | {ops} | {ops_s:.0} | {mean} | {} | {} | {} | {} | {} |",
        percentile(&lat, 0.50),
        percentile(&lat, 0.90),
        percentile(&lat, 0.99),
        percentile(&lat, 0.999),
        lat.last().copied().unwrap_or(0),
    );
    eprintln!("env: {} / {}", std::env::consts::ARCH, std::env::consts::OS);
}
