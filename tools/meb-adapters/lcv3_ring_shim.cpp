// lcv3_ring_shim.cpp — gives the unmodified lcv3 harness adapter the same
// batched report transport as matcher-cpp, so the "batched transport" column
// compares engines on equal footing. Built together with lcv3_adapter.cpp.
#include "ring_transport.hpp"

extern "C" const me_transport_t* engine_get_transport(void) { return &meb::kRingTransport; }
