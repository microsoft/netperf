# Linux UDP Echo Performance Diagnosis

## Problem Statement
The Linux echo server achieves only ~277K RPS with 92% CPU idle on an 80-core machine, significantly lower than Windows performance.

## Root Cause Analysis

### Issue Found
**The server creates duplicate socket workers for both IPv4 and IPv6 on every CPU core**, but the test only sends IPv4 traffic. This causes:

1. **Worker Contention**: With 80 cores, the server creates **160 worker threads** (2 per core)
2. **Socket Affinity Conflict**: Both IPv4 and IPv6 workers compete for CPU affinity to the same core
3. **Idle Cores**: Only IPv4 sockets receive traffic, leaving IPv6 workers idle
4. **Inefficient Scheduling**: The kernel scheduler must manage 160 threads competing for 80 cores

### Evidence from Diagnostics

**mpstat data shows:**
- **Total CPU usage: ~7.5%** (should be much higher with proper scaling)
- Breakdown: 6.5% sys + 1% soft IRQ + 0.2% user
- **92% idle**: Massive underutilization
- Consistent ~277K RPS ceiling despite available capacity

**Code location** ([src/server/main.cpp](https://github.com/Alan-Jowett/LinuxUDPShardedEcho/blob/41e6431a40d2beaaf494dae42461b37985736ced/src/server/main.cpp#L360-L365)):
```cpp
for (uint32_t i = 0; i < num_workers; ++i) {
    // Start one worker per address family per CPU
    workers.push_back(create_worker(i, AF_INET));      // IPv4 socket
    workers.push_back(create_worker(i, AF_INET6));     // IPv6 socket (unused!)
}
```

## Recommended Fixes

### Option 1: Add `--ipv4-only` Flag (Recommended)
Modify the server to accept an `--ipv4-only` flag that only creates IPv4 sockets when the test doesn't need IPv6 support.

**Changes needed in LinuxUDPShardedEcho:**
1. Add `--ipv4-only` argument parser option
2. Conditionally create IPv4/IPv6 based on flag
3. Update help text

**Changes needed in netperf test script:**
1. Add `--ipv4-only` to receiver options in `run-echo-test-linux.ps1`

### Option 2: Dynamic Socket Count
Only create sockets for protocols needed based on client configuration.

### Option 3: Fix Socket Affinity
Distribute sockets across cores differently to avoid the all-or-nothing affinity model.

## Expected Improvement
With only 80 IPv4 worker threads (one per core):
- Proper CPU core utilization
- Each core handles its own socket without contention
- Should achieve significant RPS improvement (likely 800K+ RPS based on available CPU capacity)

## Next Steps
1. Implement `--ipv4-only` flag in [LinuxUDPShardedEcho](https://github.com/Alan-Jowett/LinuxUDPShardedEcho)
2. Update test script to pass this flag for IPv4-only tests
3. Re-run performance test to validate improvement
4. Consider making dual-stack IPv4/IPv6 optional in general

## Performance Test Data
- **Server**: 80-core Linux (Ubuntu 24.04) on Azure
- **Previous RPS**: ~277K req/s
- **Worker Count**: 160 threads (80 cores × 2 address families)
- **CPU Idle**: 92%
- **Network**: No packet loss at application level, but some dropped at kernel level due to slow processing
