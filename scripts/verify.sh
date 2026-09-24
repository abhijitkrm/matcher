#!/usr/bin/env bash
# verify.sh — run all golden-vector tests across implementations.
# Exit non-zero if any implementation diverges from the corpus.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== matcher-rust =="
(cd matcher-rust && cargo test --quiet 2>&1 | grep -vE "^\s*$|Compiling|Finished|Running|Doc-tests|warning")

echo "== matcher-go =="
(cd matcher-go && go test ./matcher/)

echo "== matcher-cpp =="
(cd matcher-cpp && cmake -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build >/dev/null && ./build/golden_test ../vectors)

echo "all implementations verified"
