## Performance Test Specification

- Netperf leverages the [Secnetperf](https://microsoft.github.io/msquic/msquicdocs/src/perf/readme.html?q=secnetperf) application to run multi-machine performance tests.
- Secnetperf leverages [MsQuic](https://github.com/microsoft/msquic) for it's QUIC/UDP
implementation, and a
["QUIC-like" application](https://github.com/microsoft/msquic/blob/release/2.5/src/perf/lib/Tcp.cpp) using the underlying OS's TCP implementation to provide an apples-to-apples comparison between QUIC and TCP. The main motiviation for this pseudo QUIC + TCP implementation is to introduce the concept of streams for TCP.
- All of Netperf's performance tests involve a client and server on separate machines.

## Test Scenarios

Secnetperf supports the following [test scenarios](https://github.com/microsoft/msquic/blob/release/2.5/src/perf/lib/PerfClient.cpp#L35-L73):

1. **Throughput Testing**
    - Upload
      - Client will try to send as much data as possible in **12 seconds** across **1 connection** and **1 stream** (there is no concept of "streams" in TCP, see the section above for how Secnetperf handles TCP testing).
    - Download
      - Client will request and receive as much data as possible in **12 seconds** across **1 connection** and **1 stream**.
2. **Latency Testing**
    - Observes the **0 - 99.99%** percentile RTT by opening / closing **1 connection** as many times as possible in **20 seconds**. We immediately close the connection upon a successful handshake.
3. **HPS Testing (handshakes per second)**
    - Counts how many successful RTTs completed per second in **12 seconds** by opening / closing **16 * (NUMBER OF CORES AVAILABLE) Connections** as many times as possible. We immediately close the connection upon a successful handshake.
4. **RPS Testing (requests per second)**
    - Counts how many successful RTTs completed per second in **20 seconds** by sending **512** bytes and receiving **4000** bytes of data for as many times as possible across **1 connection** and **100 streams**.
5. **Max RPS Testing**
    - Same as RPS but done with **16 * (NUMBER OF CORES AVAILABLE) Connections** and **100 streams.**




## Test Environment

Netperf is backed by a physical lab, as well as dedicated Azure VM pools with Network optimized VM SKUs.

### Lab

**Important Note:**
2 physical hosts are used for each scenario (client/server), but netperf will **NOT** run Secnetperf directly on the physical hosts. Instead, both the client/server have a single hyper-V VM to host the performance tests.

The idea is we make this hyper-v VM as close as possible to bare-metal performance, while still getting all the benefits of using VMs for testing. Additionally, 99% of customer scenarios will involve running workloads inside a VM.

- **Host Operating System**: Windows Server 2022
- **Test VM Operating System**: Windows Server 2022 / Ubuntu 24.04 / Custom Windows Branch+Build (WIP)
- **Host Specs**: 128GB RAM, 80 logical cores
- **Test VM Specs**: 100 GB RAM, 80 logical cores, SR-IOV enabled
- **Network Topology**: Each lab machine has a 200 Gbps Mellanox ConnectX-6 Dx NICs connected to a private switch to enable client/server testing.

### Azure VM Pool

2 VMs are used for each scenario (client/server)

- **Test VM Operating System**: Windows Server 2022 / Ubuntu 24.04 / Custom Windows Branch+Build
- **VM SKU**: Experimental_Boost4 (4 vCPUs, 8 GB RAM, MANA NICs)


