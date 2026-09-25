#!/usr/bin/env bash
# snapdiff — cross-language snapshot parity check (spec/JOURNAL.md).
# Applies the same command stream through all five implementations' snapdump
# tools and byte-compares the emitted snapshots.
#
#   scripts/snapdiff.sh [cmd.jsonl ...]
#
# Defaults: the engine vector + one generated fuzz stream.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

build() {
  (cd ../matcher-rust && cargo build --release --bin matchersnap >/dev/null 2>&1)
  (cd ../matcher-go && go build -o /tmp/matcher-snap-go ./cmd/matchersnap)
  (cd ../matcher-cpp && cmake -B build >/dev/null && cmake --build build --target matchersnap >/dev/null)
  (cd ../matcher-ts && npm run build >/dev/null 2>&1)
  (cd ../matcher-java && javac -d out --release 17 src/main/java/io/github/abhijitkrm/matcher/*.java tests/MatcherSnap.java)
}

inputs=("$@")
if [ ${#inputs[@]} -eq 0 ]; then
  (cd tools/fuzzgen && cargo build --release >/dev/null 2>&1)
  tools/fuzzgen/target/release/fuzzgen --seed 7 --n 8000 > /tmp/snapdiff-fuzz.cmd.jsonl
  inputs=(vectors/engine/001_multisymbol.cmd.jsonl /tmp/snapdiff-fuzz.cmd.jsonl)
fi

build

for f in "${inputs[@]}"; do
  echo "== $f"
  "$ROOT/../matcher-rust/target/release/matchersnap" "$f" > /tmp/snapdiff-rust.txt
  /tmp/matcher-snap-go "$f" > /tmp/snapdiff-go.txt
  "$ROOT/../matcher-cpp/build/matchersnap" "$f" > /tmp/snapdiff-cpp.txt
  node "$ROOT/../matcher-ts/dist/bench/matchersnap.js" "$f" > /tmp/snapdiff-ts.txt
  java -cp "$ROOT/../matcher-java/out" MatcherSnap "$f" > /tmp/snapdiff-java.txt
  for x in go cpp ts java; do
    if cmp -s /tmp/snapdiff-rust.txt /tmp/snapdiff-$x.txt; then
      echo "   $x: byte-identical"
    else
      echo "   $x: DIVERGED"
      diff /tmp/snapdiff-rust.txt /tmp/snapdiff-$x.txt | head -10
      exit 1
    fi
  done
done
echo "snapdiff: all implementations byte-identical"
