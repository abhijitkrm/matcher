#!/usr/bin/env bash
# exhaustive.sh — bounded exhaustive verification on the real shipped code.
#
# fuzzgen --exhaustive D emits EVERY sequence of D commands over an 8-command
# alphabet (resting both sides, crossing, IOC/FOK/PostOnly, dup/unknown ids,
# cancel, replace) alternating two symbols. Every impl runs every sequence;
# all five event streams must be byte-identical.
#
# This is not sampling: within the bounded domain it is a proof that the
# implementations are equivalent.
#
#   scripts/exhaustive.sh [depth]     # default depth 3 → 512 sequences × 5 impls
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

RUST=${MATCHER_RUST_DIR:-$ROOT/../matcher-rust}
GO=${MATCHER_GO_DIR:-$ROOT/../matcher-go}
CPP=${MATCHER_CPP_DIR:-$ROOT/../matcher-cpp}
TS=${MATCHER_TS_DIR:-$ROOT/../matcher-ts}
JAVA=${MATCHER_JAVA_DIR:-$ROOT/../matcher-java}
DEPTH=${1:-3}
WORK=$(mktemp -d /tmp/exhaustive.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

echo "== building harnesses =="
cargo build --release --manifest-path tools/fuzzgen/Cargo.toml --quiet
(cd "$RUST" && cargo build --bin matcherfuzz --quiet)
(cd "$GO" && go build -o "$WORK/matcherfuzz-go" ./cmd/matcherfuzz)
(cd "$CPP" && cmake -S . -B build >/dev/null && cmake --build build --target matcherfuzz -j >/dev/null)
(cd "$TS" && tsc -p tsconfig.json)
mkdir -p "$JAVA/out"
(cd "$JAVA" && javac -d out --release 17 src/main/java/io/github/abhijitkrm/matcher/*.java tests/MatcherFuzz.java)

tools/fuzzgen/target/release/fuzzgen --exhaustive "$DEPTH" --out "$WORK/seqs"

RUSTBIN=$RUST/target/debug/matcherfuzz   # debug: check_invariants() per cmd
fail=0
checked=0
for f in "$WORK"/seqs/*.cmd.jsonl; do
  "$RUSTBIN" "$f" > "$WORK/ref.out" 2>"$WORK/ref.err" \
    || { echo "$(basename "$f"): rust crashed/invariant"; head -3 "$WORK/ref.err"; fail=1; continue; }
  "$WORK/matcherfuzz-go" "$f" > "$WORK/go.out"
  "$CPP/build/matcherfuzz" "$f" > "$WORK/cpp.out"
  node "$TS/dist/bench/matcherfuzz.js" "$f" > "$WORK/ts.out"
  java -cp "$JAVA/out" MatcherFuzz "$f" > "$WORK/java.out"
  for impl in go cpp ts java; do
    cmp -s "$WORK/ref.out" "$WORK/$impl.out" \
      || { echo "$(basename "$f"): $impl DIVERGES"; fail=1; }
  done
  checked=$((checked + 1))
done

if [ "$fail" = 0 ]; then
  echo "exhaustive: $checked sequences (depth $DEPTH) — 5-way identical ✓"
else
  echo "exhaustive: FAILURES"
  exit 1
fi
