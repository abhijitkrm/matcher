#!/usr/bin/env bash
# Runs inside the meb-linux container (see README.md) with the harness checkout at
# /work/harness, this directory at /work/adapters, matcher-cpp at /work/matcher-cpp
# and matcher-rust at /work/matcher-rust.
#   build_run.sh cpp|cpp-ring|cpp-discard|rust|rust-ring|lcv3|lcv3-ring <scenario> [extra harness args]
set -euo pipefail
which=$1; scen=${2:-normal}; shift 2 || true
cd /work/harness
case $which in
  cpp|cpp-ring|cpp-discard)
    flags=""; so=matcher_cpp_adapter.so
    [ "$which" = cpp-ring ] && { flags="-DCUSTOM_TRANSPORT"; so=matcher_cpp_ring_adapter.so; }
    [ "$which" = cpp-discard ] && { flags="-DCUSTOM_TRANSPORT -DDISCARD_REPORTS"; so=matcher_cpp_discard_adapter.so; }
    g++ -std=c++20 -O3 -march=native -fPIC -shared $flags -I api -I /work/adapters -I /work/matcher-cpp/include \
        /work/adapters/matcher_cpp_adapter.cpp -o $so
    ./harness --engine ./$so --scenario "$scen" --mode perf "$@" 2>&1 | grep -vE "^$"
    ;;
  lcv3|lcv3-ring)
    extra=""; so=lcv3_adapter.so
    [ "$which" = lcv3-ring ] && { extra="/work/adapters/lcv3_ring_shim.cpp"; so=lcv3_ring_adapter.so; }
    g++ -std=c++20 -O3 -march=native -fPIC -shared -fexceptions -frtti -I api -I /work/adapters \
        -I /work/adapters/stubs -I third_party/lcv3 additional_references/lcv3_adapter/lcv3_adapter.cpp \
        $extra -o $so
    ./harness --engine ./$so --scenario "$scen" --mode perf "$@" 2>&1 | grep -vE "^$"
    ;;
  rust|rust-ring)
    feat=""; so=matcher_rust_adapter.so; tgt=rust_target
    [ "$which" = rust-ring ] && { feat="--features ring"; so=matcher_rust_ring_adapter.so; tgt=rust_target_ring; }
    (cd /work/adapters/matcher_rust_adapter && RUSTFLAGS="-C target-cpu=native" \
        CARGO_TARGET_DIR=/work/harness/$tgt cargo build --release $feat 2>&1 | grep -E "^error|warning: unused|Finished" | head -5)
    cp /work/harness/$tgt/release/libmatcher_rust_adapter.so /work/harness/$so
    ./harness --engine ./$so --scenario "$scen" --mode perf "$@" 2>&1 | grep -vE "^$"
    ;;
esac
