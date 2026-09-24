#!/usr/bin/env bash
# verify.sh — run all golden-vector tests across implementation repos.
# Expects the impl repos as siblings: ../matcher-rust ../matcher-go ../matcher-cpp
# (or set MATCHER_RUST_DIR / MATCHER_GO_DIR / MATCHER_CPP_DIR).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)

RUST=${MATCHER_RUST_DIR:-$ROOT/../matcher-rust}
GO=${MATCHER_GO_DIR:-$ROOT/../matcher-go}
CPP=${MATCHER_CPP_DIR:-$ROOT/../matcher-cpp}

echo "== matcher-rust ($RUST) =="
(cd "$RUST" && cargo test --quiet 2>&1 | grep -vE "^\s*$|Compiling|Finished|Running|Doc-tests|warning")

echo "== matcher-go ($GO) =="
(cd "$GO" && go test .)

echo "== matcher-cpp ($CPP) =="
(cd "$CPP" && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build >/dev/null && ./build/golden_test vectors)

echo "all implementations verified"
