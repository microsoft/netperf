# Questions

The high-level reason for this project is to answer questions that various internal and external groups have about the performance of networking across various different scenarios.
The final output of this project is a dashboard that is meant to answer these questions.
Below is a list of all the questions we could come up with that might be interesting to answer.
Eventually, a subset of these questions will be prioritized and answered by the dashboard.

> **Note** - It should be noted that even the definition of **performance** is subjective, and highly dependent on the scenario and the user. In the questions below, we try to not use this word, but instead be specific about the metric of interest (e.g. throughput, latency, CPU utilization, etc.).

## Transports

> **Note** - Considering modern day network usage is almost always secured, we measure the performance of the secure variants of the protocols (e.g. TCP/TLS, QUIC, etc.) instead of the insecure variants (e.g. TCP, UDP, etc.).

- What is the **throughput** of a given protocol on Windows and Linux?
    - For single connection/stream scenarios?
    - For multi-connection/stream scenarios?
        - At large scale?
    - Upload? Download?

- What is the **latency** of a given protocol for a request/response type exchange on Windows and Linux?
    - For single connection/stream scenarios?
    - For multi-connection/stream scenarios?
        - At large scale?
    - For multiple request/response IO sizes?
    - What do the percentile curves look like?
        - What percentiles do we care about most?
- What is the **jitter** detected across the measured latency in request/respose protocol exchanges on Windows and Linux?
- What is the total **transactions** over a period of time for a given protocol + workload on Windows and Linux?
    - "transaction" defined as the application's work, from creating the socket to closing the socket
    - Could also be defined at the protocol's definition of 'start' and 'end' (protocol being one above TCP or UDP)
- What is the **maximum requests/sec** of a given protocol for a request/response type exchange on Windows and Linux?
- What is the **maximum handshakes/sec** of a given protocol for a request/response type exchange on Windows and Linux?

## XDP

- How does AF_XDP {bulk, small} **throughput** compare to alternatives*?
- How does AF_XDP {bulk, small, bursty} **latency** compare to alternatives*?
- How does AF_XDP **throughput/latency** scale across RSS/CPUs compared to alternatives*?
- How much does offload X improve performance? **TODO: Define metric**
- What is the overhead of XDP inspection (e.g. always return PASS) compared to a plain stack? **TODO: Define metric**
- How many **packets/sec** can XDP inspect and drop for DDoS, and how does it compare to alternatives**?
- How many **packets/sec** can XDP inspect and forward, and how does it compare to alternatives**?

**AF_XDP Alternatives**
- Windows sockets w/ IOCP
- Windows RIO w/ IOCP and polling
- Windows sockets w/ notifications instead of async/IOCP (ProcessSocketNotifications, WSAPoll)
- Windows blocking vs Linux blocking
- Windows TransmitFile vs. a Linux similar API (an API that doesn't need to roundtrip to usermode)
- Linux traditional sockets (Epoll? blocking calls?)
- Linux io_uring
- Linux XDP (native (w/ and w/o zerocopy) vs generic)
- DPDK?

**XDP+eBPF Alternatives**
- Linux XDP (native (w/ and w/o zerocopy) vs generic)
- DPDK?

## eBPF

TODO
