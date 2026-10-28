# Adapters for the Flash One matching-engine benchmark

C-ABI adapters that run matcher-cpp and matcher-rust through
[flash1-dev/matching-engine-benchmark](https://github.com/flash1-dev/matching-engine-benchmark)
(MIT). The harness needs Linux, GCC 14+ and Boost; on macOS use the container.
Results and caveats: `docs/RESULTS.md`, section "Third-party harness".

```sh
git clone https://github.com/flash1-dev/matching-engine-benchmark harness
docker build -t meb-linux tools/meb-adapters
docker run --rm -v $PWD/harness:/work/harness -w /work/harness meb-linux \
    bash -c 'make && scripts/build_baselines.sh liquibook quantcup'
docker run --rm --cpus=4 \
    -v $PWD/harness:/work/harness -v $PWD/tools/meb-adapters:/work/adapters \
    -v $PWD/../matcher-cpp:/work/matcher-cpp:ro -v $PWD/../matcher-rust:/work/matcher-rust:ro \
    -w /work/harness meb-linux /work/adapters/build_run.sh cpp normal      # one run
# full challenge (10 perf runs + audit per scenario), after building the .so files:
#   python3 scripts/run_challenge.py --compare ./matcher_cpp_adapter.so ./matcher_cpp_ring_adapter.so
```

- `matcher_cpp_adapter.cpp`: default harness transport; `-DCUSTOM_TRANSPORT`
  adds an engine-supplied batched SPSC ring (`engine_get_transport`, publishes
  every 32 reports and in `flush()`); `-DDISCARD_REPORTS` is a measurement-only
  build that drops reports to expose the matcher-side floor (its hash FAILs).
- `matcher_rust_adapter/`: cdylib, default transport only.
- `stubs/immintrin.h`: empty stand-in so the x86-only lcv3 engine builds on ARM.
- Event mapping (our events to their six report types) is documented at the top
  of `matcher_cpp_adapter.cpp`. Both adapters reproduce the consensus hash on all
  five scenarios and pass the audit.
