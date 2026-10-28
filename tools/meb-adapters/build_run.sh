#!/usr/bin/env bash
# Runs inside the meb-linux container (see README.md) with the harness checkout at
# /work/harness, this directory at /work/adapters, matcher-cpp at /work/matcher-cpp
# and matcher-rust at /work/matcher-rust.
#   build_run.sh cpp|cpp-ring|cpp-discard|rust <scenario> [extra harness args]
set -euo pipefail
which=$1; scen=${2:-normal}; shift 2 || true
cd /work/harness
case $which in
  cpp|cpp-ring|cpp-discard)
    flags=""; so=matcher_cpp_adapter.so
    [ "$which" = cpp-ring ] && { flags="-DCUSTOM_TRANSPORT"; so=matcher_cpp_ring_adapter.so; }
    [ "$which" = cpp-discard ] && { flags="-DCUSTOM_TRANSPORT -DDISCARD_REPORTS"; so=matcher_cpp_discard_adapter.so; }
    g++ -std=c++20 -O3 -march=native -fPIC -shared $flags -I api -I /work/matcher-cpp/include \
        /work/adapters/matcher_cpp_adapter.cpp -o $so
    ./harness --engine ./$so --scenario "$scen" --mode perf "$@" 2>&1 | grep -vE "^$"
    ;;
  rust)
    (cd /work/adapters/matcher_rust_adapter && RUSTFLAGS="-C target-cpu=native" \
        CARGO_TARGET_DIR=/work/harness/rust_target cargo build --release 2>&1 | tail -3)
    cp /work/harness/rust_target/release/libmatcher_rust_adapter.so /work/harness/matcher_rust_adapter.so
    ./harness --engine ./matcher_rust_adapter.so --scenario "$scen" --mode perf "$@" 2>&1 | grep -vE "^$"
    ;;
esac
