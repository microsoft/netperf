# ShadowSocketProxy iperf3 benchmark

The `shadowsocketproxy-iperf` workflow compares outbound TCP and UDP traffic
from WSL2 to a Windows peer with and without ShadowSocketProxy.

## Pair provisioning

The GitHub Actions runner must be a Windows 2022 self-hosted runner with the
existing `lab` and `x64` labels. Provision it before running the workflow:

- Install WSL2 and a pinned Linux distribution.
- Install Rust 1.96.1, `cargo`, `tc`, and `iperf3` inside WSL.
- Confirm the WSL kernel permits TC/BPF attachment.
- Install a pinned Windows `iperf3.exe` on the target peer.
- Enable PowerShell 7 remoting between the runner and target peer.

The target peer must allow TCP and UDP port 5201. The workflow creates
temporary firewall rules with the `netperf-iperf3-*` prefix and removes them
after the run.

The default target is `netperf-peer`. Its IPv4 address is resolved on the
runner, matching the existing eBPF performance workflows; an address can be
provided explicitly when DNS is unavailable.

The workflow uses the first installed WSL distribution when no distribution is
specified. Set the `distribution` input to pin a particular distribution.

## Measurements

Each run executes single-stream TCP, four-stream TCP, and UDP tests for every
configured UDP rate. The baseline runs before the proxy is started. The proxy
case starts the WSL control service and Windows host proxy, attaches the BPF
program, and repeats the same matrix.

JSON results and proxy logs are uploaded as the
`shadowsocketproxy-iperf-results` artifact. Use at least three repetitions and
compare throughput, UDP loss, jitter, and CPU or tracing data from the runner.

## Local smoke checks

The benchmark driver can be syntax-checked without a peer:

```powershell
[void][scriptblock]::Create((Get-Content -Raw .github\scripts\run-shadowsocketproxy-iperf.ps1))
```

A complete benchmark requires the paired Windows peer and cannot be completed
on a single workstation.
