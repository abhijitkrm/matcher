#!/usr/bin/env bash
# verify.sh — run all golden-vector tests across implementation repos.
# Expects the impl repos as siblings: ../matcher-rust ../matcher-go
# ../matcher-cpp ../matcher-ts ../matcher-java
# (or set MATCHER_{RUST,GO,CPP,TS,JAVA}_DIR).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

RUST=${MATCHER_RUST_DIR:-$ROOT/../matcher-rust}
GO=${MATCHER_GO_DIR:-$ROOT/../matcher-go}
CPP=${MATCHER_CPP_DIR:-$ROOT/../matcher-cpp}
TS=${MATCHER_TS_DIR:-$ROOT/../matcher-ts}
JAVA=${MATCHER_JAVA_DIR:-$ROOT/../matcher-java}

echo "== matcher-rust ($RUST) =="
(cd "$RUST" && cargo test --quiet 2>&1 | grep -vE "^\s*$|Compiling|Finished|Running|Doc-tests|warning")

echo "== matcher-go ($GO) =="
(cd "$GO" && go test .)

echo "== matcher-cpp ($CPP) =="
(cd "$CPP" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build >/dev/null && ./build/golden_test vectors)

echo "== matcher-ts ($TS) =="
(cd "$TS" && tsc -p tsconfig.json && node dist/tests/golden.js)

echo "== matcher-java ($JAVA) =="
(cd "$JAVA" && mkdir -p out && javac -d out --release 17 src/main/java/io/github/abhijitkrm/matcher/*.java tests/Golden.java && java -cp out Golden vectors)

echo "all implementations verified"
