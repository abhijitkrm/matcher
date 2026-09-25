#!/usr/bin/env bash
# diffuzz.sh — differential fuzzing across all five matcher implementations.
#
# For each seed: fuzzgen emits an adversarial engine-mode corpus; every impl's
# matcherfuzz harness prints its canonical event stream; all must be
# byte-identical to the Rust reference. Also asserts per-symbol seq density.
#
#   scripts/diffuzz.sh [seeds] [n-cmds]     # default: seeds 1..8, 20k cmds
#   SAN=1 scripts/diffuzz.sh                # build matcher-cpp with ASan+UBSan
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

RUST=${MATCHER_RUST_DIR:-$ROOT/../matcher-rust}
GO=${MATCHER_GO_DIR:-$ROOT/../matcher-go}
CPP=${MATCHER_CPP_DIR:-$ROOT/../matcher-cpp}
TS=${MATCHER_TS_DIR:-$ROOT/../matcher-ts}
JAVA=${MATCHER_JAVA_DIR:-$ROOT/../matcher-java}
SEEDS=${1:-8}
N=${2:-20000}
WORK=$(mktemp -d /tmp/diffuzz.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "== building harnesses =="
cargo build --release --manifest-path tools/fuzzgen/Cargo.toml --quiet
(cd "$RUST" && cargo build --bin matcherfuzz --quiet)
(cd "$GO" && go build -o "$WORK/matcherfuzz-go" ./cmd/matcherfuzz)
if [ "${SAN:-0}" = "1" ]; then
  echo "   (matcher-cpp: ASan+UBSan build)"
  (cd "$CPP" && cmake -S . -B "$WORK/build-san" -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DCMAKE_CXX_FLAGS="-fsanitize=address,undefined -fno-omit-frame-pointer" >/dev/null \
    && cmake --build "$WORK/build-san" --target matcherfuzz -j >/dev/null)
  CPPBIN="$WORK/build-san/matcherfuzz"
else
  (cd "$CPP" && cmake -S . -B build >/dev/null && cmake --build build --target matcherfuzz -j >/dev/null)
  CPPBIN="$CPP/build/matcherfuzz"
fi
(cd "$TS" && tsc -p tsconfig.json)
mkdir -p "$JAVA/out"
(cd "$JAVA" && javac -d out --release 17 src/main/java/io/github/abhijitkrm/matcher/*.java tests/MatcherFuzz.java)

FUZZGEN=tools/fuzzgen/target/release/fuzzgen
RUSTBIN=$RUST/target/debug/matcherfuzz   # debug: check_invariants() per cmd

# seq density check: per symbol, seq must be dense from 1 upward.
seqcheck() {
  awk -F'"' '
    match($0, /"seq":[0-9]+/) { seq = substr($0, RSTART+6, RLENGTH-6) }
    match($0, /"symbol":[0-9]+/) { sym = substr($0, RSTART+9, RLENGTH-9); nextseq[sym]++ ;
      if (seq != nextseq[sym]) { printf "seq gap: sym %s expected %d got %d\n", sym, nextseq[sym], seq; bad=1 } }
    END { exit bad }
  ' "$1"
}

fail=0
for seed in $(seq 1 "$SEEDS"); do
  corpus="$WORK/s$seed.cmd.jsonl"
  "$FUZZGEN" --seed "$seed" --n "$N" --symbols 8 --ids 512 > "$corpus"

  "$RUSTBIN" "$corpus" > "$WORK/s$seed.rust" 2>"$WORK/s$seed.rust.err" || { echo "seed $seed: rust crashed/invariant"; cat "$WORK/s$seed.rust.err" | head -5; fail=1; continue; }
  "$WORK/matcherfuzz-go" "$corpus" > "$WORK/s$seed.go"
  "$CPPBIN" "$corpus" > "$WORK/s$seed.cpp"
  node "$TS/dist/bench/matcherfuzz.js" "$corpus" > "$WORK/s$seed.ts"
  java -cp "$JAVA/out" MatcherFuzz "$corpus" > "$WORK/s$seed.java"

  ok=1
  for impl in go cpp ts java; do
    if ! cmp -s "$WORK/s$seed.rust" "$WORK/s$seed.$impl"; then
      echo "seed $seed: $impl DIVERGES from rust"
      diff "$WORK/s$seed.rust" "$WORK/s$seed.$impl" | head -8
      ok=0; fail=1
    fi
  done
  seqcheck "$WORK/s$seed.rust" || { echo "seed $seed: seq density violated"; ok=0; fail=1; }
  evs=$(wc -l < "$WORK/s$seed.rust" | tr -d ' ')
  [ "$ok" = 1 ] && echo "seed $seed: $evs events — 5-way identical ✓"
done

[ "$fail" = 0 ] && echo "diffuzz: all seeds clean" || { echo "diffuzz: FAILURES"; exit 1; }
