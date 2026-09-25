#!/usr/bin/env bash
# e2e — end-to-end recovery proof across all five implementations.
#
# Per impl:  run cmds → full.evt
#            run prefix → snap + prefix.evt
#            recover snap + journal tail → recov.evt
#            assert prefix.evt + recov.evt == full.evt   (byte-identical)
# Cross-impl: every impl restores every other impl's snapshot — the
#             matcher-snap/1 format is portable by design.
# Adversarial: empty tail, snapshot at seq 0, truncated journal line
#             (recover must exit nonzero, not diverge silently).
#
#   scripts/e2e.sh [cmd.jsonl]
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
WORK=/tmp/matcher-e2e
rm -rf "$WORK"; mkdir -p "$WORK"

CMDS=${1:-$ROOT/vectors/engine/001_multisymbol.cmd.jsonl}
TOTAL=$(wc -l < "$CMDS" | tr -d ' ')
SPLIT=$((TOTAL / 2))
head -n "$SPLIT" "$CMDS" > "$WORK/prefix.cmd"
tail -n +$((SPLIT + 1)) "$CMDS" > "$WORK/tail.cmd"

# ---- build all impls --------------------------------------------------------
(cd ../matcher-rust && cargo build --release --bin matcherrun --bin matcherrecover >/dev/null 2>&1)
(cd ../matcher-go && go build -o /tmp/matcher-e2e/go-run ./cmd/matcherrun \
                 && go build -o /tmp/matcher-e2e/go-recover ./cmd/matcherrecover)
(cd ../matcher-cpp && cmake -B build >/dev/null && cmake --build build --target matcherrun matcherrecover >/dev/null)
(cd ../matcher-ts && npm run build >/dev/null 2>&1)
(cd ../matcher-java && javac -d out --release 17 \
    src/main/java/io/github/abhijitkrm/matcher/*.java \
    tests/MatcherRun.java tests/MatcherRecover.java)

run_rust()  { "$ROOT/../matcher-rust/target/release/matcherrun" "$@"; }
run_go()    { /tmp/matcher-e2e/go-run "$@"; }
run_cpp()   { "$ROOT/../matcher-cpp/build/matcherrun" "$@"; }
run_ts()    { node "$ROOT/../matcher-ts/dist/bench/matcherrun.js" "$@"; }
run_java()  { java -cp "$ROOT/../matcher-java/out" MatcherRun "$@"; }

rec_rust()  { "$ROOT/../matcher-rust/target/release/matcherrecover" "$@"; }
rec_go()    { /tmp/matcher-e2e/go-recover "$@"; }
rec_cpp()   { "$ROOT/../matcher-cpp/build/matcherrecover" "$@"; }
rec_ts()    { node "$ROOT/../matcher-ts/dist/bench/matcherrecover.js" "$@"; }
rec_java()  { java -cp "$ROOT/../matcher-java/out" MatcherRecover "$@"; }

IMPLS="rust go cpp ts java"

# ---- per-impl e2e ------------------------------------------------------------
for i in $IMPLS; do
  run_$i "$CMDS" > "$WORK/$i-full.evt"
  run_$i "$WORK/prefix.cmd" --snap "$WORK/$i.snap" > "$WORK/$i-prefix.evt"
  rec_$i "$WORK/$i.snap" "$WORK/tail.cmd" > "$WORK/$i-recov.evt"
  cat "$WORK/$i-prefix.evt" "$WORK/$i-recov.evt" > "$WORK/$i-joined.evt"
  cmp -s "$WORK/$i-joined.evt" "$WORK/$i-full.evt" \
    && echo "$i: e2e identical" \
    || { echo "$i: E2E DIVERGED"; diff "$WORK/$i-joined.evt" "$WORK/$i-full.evt" | head -8; exit 1; }
  cmp -s "$WORK/$i-full.evt" "$WORK/rust-full.evt" \
    && echo "$i: evt == rust evt" \
    || { echo "$i: evt stream diverges from rust"; exit 1; }
done

# ---- cross-impl restore matrix ------------------------------------------------
# Every impl recovers every impl's snapshot; all must emit the identical tail.
rec_ts "$WORK/rust.snap" "$WORK/tail.cmd" > "$WORK/ref-tail.evt"
for snap_impl in $IMPLS; do
  for rec_impl in $IMPLS; do
    rec_$rec_impl "$WORK/$snap_impl.snap" "$WORK/tail.cmd" > "$WORK/x-$snap_impl-$rec_impl.evt"
    cmp -s "$WORK/x-$snap_impl-$rec_impl.evt" "$WORK/ref-tail.evt" \
      || { echo "cross-restore $snap_impl→$rec_impl DIVERGED"; exit 1; }
  done
done
echo "cross-impl restore: 25 combinations byte-identical"

# ---- adversarial --------------------------------------------------------------
# empty tail: recover emits nothing, exits 0
: > "$WORK/empty.cmd"
rec_rust "$WORK/rust.snap" "$WORK/empty.cmd" > "$WORK/empty.evt"
[ ! -s "$WORK/empty.evt" ] && echo "empty tail: clean" || { echo "empty tail FAILED"; exit 1; }

# snapshot at seq 0: empty snap + full journal = full run
head -1 "$CMDS" > "$WORK/only-header.cmd"
run_rust "$WORK/only-header.cmd" --snap "$WORK/zero.snap" > /dev/null
cat "$WORK/prefix.cmd" "$WORK/tail.cmd" > "$WORK/all.cmd"
{ head -1 "$CMDS"; grep -v '"format"' "$WORK/all.cmd"; } > "$WORK/all-hdr.cmd"
rec_rust "$WORK/zero.snap" "$WORK/all-hdr.cmd" > "$WORK/zero.evt"
cmp -s "$WORK/zero.evt" "$WORK/rust-full.evt" \
  && echo "seq-0 snapshot + full replay: identical" \
  || { echo "seq-0 replay FAILED"; exit 1; }

# truncated journal tail: recover must exit nonzero
{ head -5 "$WORK/tail.cmd"; head -1 "$WORK/tail.cmd" | cut -c1-30; } > "$WORK/trunc.cmd"
if rec_rust "$WORK/rust.snap" "$WORK/trunc.cmd" > /dev/null 2>&1; then
  echo "truncated tail: NOT DETECTED"; exit 1
else
  echo "truncated tail: detected (nonzero exit)"
fi

echo "e2e: all checks passed"
