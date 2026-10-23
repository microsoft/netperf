# Portable TCP churn experiment

This initial experiment is **collection-only**, not proof of a kernel optimization,
black-hole probing, dead-gateway failover, or use of every processor.

## Public inputs only

All implementation here is public test code. Do not add private OS source, private
helpers, internal identifiers, unpublished binaries, signing keys, or private build
references. No new binary is required by this implementation.

`dependencies.json` pins existing public CTS and DuoNIC assets by full commit and
SHA256. They are downloaded into runner-local scratch, **not committed, cached as
Actions artifacts, or re-uploaded**. The DuoNIC acquisition precedent is
[eBPF's public helper](https://github.com/microsoft/ebpf-for-windows/blob/fb94520bfdd7ddf048e2f7561a65392988d4fca1/scripts/common.psm1);
netperf already runs CTS in its `cts_traffic.yml` workflow.

Only `result.json` from a separate publication directory is uploaded. The publisher
reconstructs a field allowlist containing numeric measurements and fixed status
labels. Raw stdout, addresses, host inventory, traces, binaries and adapter state
are not artifacts. Do not broaden that upload to the scratch/workspace directory.

## Interface and adapters

`TcpChurn.psm1` owns the plan, public CTS summary decoding, lifecycle, progress and
wire-accounting checks. It has no GitHub, credential, driver-installation, remote
execution, feature-control, private-provider or artifact-storage dependency.

`Invoke-TcpChurnExperiment` accepts an adapter with `State` and five scriptblocks:

| Method | Contract |
| --- | --- |
| `StartPeer(state, plan)` | Own any peer resources; cleanup must handle partial start. |
| `PeerReady(state, plan)` | Observe readiness without generating a warm-up connection. |
| `ReadCounters(state, plan)` | Return cumulative `Transmitted` and `Received` bytes for the selected path. |
| `RunClient(state, plan)` | Return `ExitCode` and local `Text`; bound execution. |
| `Close(state, plan)` | Release owned resources; failures are errors, not successful measurements. |

The Windows CTS adapter implements processes, listener observation, NIC counters
and local diagnostics. The netperf adapter separately owns public dependency
acquisition, an isolated fixture, and publication. A manual machine can use the
Windows adapter with preconfigured interfaces; another lab can implement this same
small interface with its own remote execution and evidence storage.

## Netperf smoke

The workflow first runs source-only tests on a GitHub-hosted Windows runner.
Privileged lab execution is **manual dispatch only**, on the existing
`self-hosted, lab, os-windows-2022, x64` labels. It is not a pull-request-triggered
self-hosted job. Use `execute_lab=true` after reviewing the branch.

The lab adapter refuses any existing DuoNIC devices, installs one public pair,
uses explicit CTS bind/listen addresses and the public setup's host routes, and
requires data to be accounted for by both adapters. It does not claim that mere
local traffic is a valid path test. It removes its own processes, named firewall
rule and software-device instances; netperf's standard lab reset is also scheduled.
The client has a time ceiling and a connection-attempt cap (at most 32 iterations
per concurrent connection, and 8192 attempts in total). It may finish before the
time ceiling. This avoids silently exhausting the ordinary ephemeral-port range
in a deployment smoke; it is not a sustained-load measurement. A longer campaign
needs an explicit reuse/port budget and resource checks rather than OS tuning
hidden in the workload.

No Secure Boot/test-signing/trust/Defender setting is weakened. If the existing lab
image cannot load the public driver, preparation fails; use an approved image
rather than installing a private signing key. The driver package may remain in the
disposable image's driver store until reset.

## Manual machine

Prepare and dedicate two interfaces with an actual path between them, using only
approved public tooling. Keep native tools outside source checkouts.

```powershell
./Invoke-TcpChurn.ps1 -TrafficExecutable C:\PublicTools\ctsTraffic.exe `
  -ClientAddress 192.168.1.11 -ServerAddress 192.168.1.12 `
  -ClientInterface duo1 -ServerInterface duo2 `
  -WorkDirectory C:\Runs\new-run -DedicatedAdapters
```

No provisioning or upload occurs in this entrypoint. The same core can be invoked
by an internal runner without adopting GitHub's execution or artifact model.
The new work directory holds local diagnostics; only explicitly publish the
allowlisted result if those measurements are intended to be public.

## Limits and next experiments

Use an optimized, unchanged public baseline for this smoke. This project does not
deploy private OS bits or know private feature identifiers. Build labels, if added
later, are not feature-state evidence.

DuoNIC link engines, RSS placement and processor groups can limit concurrency.
Actual CPU execution must be measured before claiming 80-processor coverage. An
ordinary loopback benchmark is rejected, and byte counters are not evidence that a
particular kernel algorithm ran. Large transfers exercise ordinary TCP data, not
necessarily a black hole.

This first cut has no loss injection, selective PMTU filter, routed DGD topology,
kernel lock-site counters, CPU stacks, or before/after statistical claim. Add those
as public-source adapters/evidence, not copies of private implementations. Keep
required recovery/progress tests alongside performance work.

```powershell
./Test-TcpChurn.ps1
```

Tests use a memory adapter and a bounded owned PowerShell child. They do not
install a driver or pretend to be a real network performance run.
