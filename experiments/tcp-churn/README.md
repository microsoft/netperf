# Portable TCP churn experiment

This initial experiment is **collection-only**, not proof of a kernel optimization,
black-hole probing, dead-gateway failover, or use of every processor.

## Public inputs only

All implementation here is public test code. Do not add private OS source, private
helpers, internal identifiers, unpublished binaries, signing keys, or private build
references. Basic traffic needs no new binary. Optional CPU analysis builds its
small helper from this public source and public NuGet packages.

`dependencies.json` pins existing public CTS and DuoNIC assets by full commit and
SHA256. They are downloaded into runner-local scratch, **not committed, cached as
Actions artifacts, or re-uploaded**. The DuoNIC acquisition precedent is
[eBPF's public helper](https://github.com/microsoft/ebpf-for-windows/blob/fb94520bfdd7ddf048e2f7561a65392988d4fca1/scripts/common.psm1);
netperf already runs CTS in its `cts_traffic.yml` workflow.

Only explicitly allowlisted JSON files from a separate publication directory are
uploaded. Traffic results contain numeric measurements and fixed status labels;
CPU results additionally contain bounded public-system-symbol aggregates.
Raw stdout, addresses, host inventory, traces and existing tool/driver binaries
are not artifacts. The separately built public-source analyzer is the exception.
Do not broaden uploads to the scratch/workspace directory.

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
`environment=netperf-windows-lab` explicitly permits any dedicated Windows x64
lab runner, removing only the Windows-2022 image constraint. It still requires
both `self-hosted` and `lab`; inspect the actual job's runner assignment and OS
before comparing results across machines/images. This is not a hosted fallback.
An explicit `environment=hosted-smoke` option runs the same actual DuoNIC fixture
on a fresh GitHub-hosted Windows machine if lab capacity is unavailable. This is
deployment/traffic compatibility validation only, not an 80-processor lab result.
The public driver is Microsoft-signed; no trust policy is changed. A hosted run
does not schedule a reset of the unrelated netperf lab.

The lab adapter refuses existing DuoNIC devices, colliding aliases or an assigned
fixture subnet before installing one public pair,
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

## Management-host fallback

`tcp-churn-guest.yml` uses the documented management slot from netperf's
targeted-reset workflow to execute **inside its existing lab VM**, not on the
Hyper-V host. This manual fallback uses configured VM credentials through
PowerShell Direct, refuses active Actions workers/CTS in the guest, and leaves
runner registration and host networking unchanged. It copies only this public
experiment's text sources; tools are downloaded in the guest. Authentication
failure is not a reason to change credentials or host policy. Raw diagnostics
remain in guest scratch; only numeric result JSON is copied back.

This is not a reservation system: use it only for an idle dedicated guest.
Normal guest-runner scheduling is preferred. It does not reset the guest or
terminate another experiment to obtain access.
The existing management host uses Windows PowerShell 5.1; only this thin
PowerShell Direct wrapper supports that version. The actual experiment runs
under PowerShell 7 in the VM. No PowerShell installation or runner-registration
change is needed on the host.

Verified actual netperf execution:
[run 40371149553](https://github.com/microsoft/netperf/actions/runs/40371149553).
The management job ran on `RR1-Netperf-25`, executing within the documented
`netperf-windows-2022-client` guest. It completed 512 connections and 32 MiB of
payload; selected DuoNIC transmit and receive byte deltas both accounted for
the transfer. Owned fixture cleanup succeeded, and the artifact contained only
the allowlisted numeric result. The CTS interval was 85 ms: deployment/traffic
proof, **not** a sustained-throughput or 80-CPU performance result.

Recent eBPF runs used the same Windows-2022 lab labels as the original direct
dispatch, so those labels were not inferred to be incorrect. The direct queue
remained unassigned even after a successful targeted reset; the management
slot provided the proven path into the actual lab VM without changing runner
registration. Keep these two execution paths distinct when reporting outcomes.

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

### CPU sampling campaign

The management-guest workflow now accepts `profile_cpu=true`, `seconds` and
`connections`. It builds the new `CpuSamples` helper entirely from this public
source and public NuGet dependencies. Unlike existing CTS/driver/OS binaries,
this new source-built test helper is an explicitly separate build artifact;
no private binary is involved.

Inside the guest, the campaign starts the built-in WPR CPU profile without
cancelling or taking over a pre-existing recording. It records an idle window,
then repeated finite connection batches on distinct server ports, with the
documented CTS port-scalability socket option. No global TCP reuse or timeout
setting is changed. A time ceiling/batch cap bounds the campaign; resource
failures remain failures, not successful measurements.

WPR is stopped before analysis, and raw ETL/ETLX plus diagnostic logs remain
in guest-local scratch. The helper consults only Microsoft's public symbol
server, never an environment/private symbol path or source server. Published
JSON includes interval sample counts, lost events, observed processor numbers,
and bounded resolved frames/stacks from `tcpip` and `ntoskrnl` only. No process
names/command lines, addresses, module paths or raw traces are published.

Partial captures may be analyzed even if a later traffic batch fails. Always
read `result.json` and `cpu-progress.json` together with the sample aggregates.
Sampled branch entry is not evidence of exclusive-lock waiting; a spin/lock
frame must occur on the relevant network stack to support a contention claim.
Absence in a finite sample is not proof that a short function never executed.
Unresolved symbols or lost events must be reported, not converted to zeros.

The analyzer uses .NET Framework already available on the Windows guest. Its
public package references and native symbol dependencies are built on hosted
Windows CI; no runtime is installed on the management host.

Use an optimized, unchanged public baseline for this smoke. This project does not
deploy private OS bits or know private feature identifiers. Build labels, if added
later, are not feature-state evidence.

DuoNIC link engines, RSS placement and processor groups can limit concurrency.
Actual CPU execution must be measured before claiming 80-processor coverage. An
ordinary loopback benchmark is rejected, and byte counters are not evidence that a
particular kernel algorithm ran. Large transfers exercise ordinary TCP data, not
necessarily a black hole.

### Real-peer outage reproduction

Dispatch `tcp-churn-guest.yml` on this branch with `profile_cpu=true`,
`peer_measurement=true`, `syn_drop=true`, `seconds=60`, and `connections=1024`.
The management adapter reaches the existing idle peer using configured credentials;
the workload still uses the portable CTS adapter interface. A scoped peer firewall
block silently drops the test connection attempts. This is a SYN-loss experiment,
**not** selective PMTU loss or established-flow black-hole probing.

The peer adapter snapshots all firewall profile Enabled states, installs a
client-scoped remoting allow rule before enabling disabled profiles, and creates
test-port rules scoped to the actual endpoint addresses. Cleanup restores and
re-reads the original profile states before deleting its rules. Restoration failure
is an error and retains the recovery rules, not a successful experiment. No global
TCP setting or OS binary is changed.

The exact-ID event collector discovers the public TCPIP provider metadata on the
running image and uses an owned, bounded session. Read lost-event counters: the
earlier broad-keyword collection was lossy and is not valid counting evidence.
Counts are provider-wide, not correlated to individual test connections.

Verified on the actual 80-logical-processor netperf guest:

- [Healthy run 40380401452](https://github.com/microsoft/netperf/actions/runs/40380401452):
  24,576 connections over 54.19 seconds; 153,852 CPU samples, including 44,820
  with TCPIP on the stack; 149 full-size-ACK tracking events; zero CPU or probe
  events lost. No BH entry/exit/failure events. Path-info waits seen principally
  under connection shutdown must not be called BH-confirmation contention.
- [Outage run 40385886331](https://github.com/microsoft/netperf/actions/runs/40385886331):
  1,024 failed connections, 1,024 retransmission timeouts and 4,096 retransmission
  rounds; 3,757 CPU samples, including 815 with TCPIP on the stack; zero CPU or
  probe events lost. The retained public stacks include **20 queued-wait samples**
  under the connection-failure path-info update:

  ```text
  nt!KxWaitForLockOwnerShip
    <- nt!KeAcquireInStackQueuedSpinLock
    <- tcpip!IpNlpSetPathInfo
    <- tcpip!InetSetPathConnectionFailedAf
    <- tcpip!TcpNotifyTcbDelay
  ```

- [Repeat 40387003564](https://github.com/microsoft/netperf/actions/runs/40387003564):
    the exact-ancestry assertion passed with **32 target wait samples**, 1,024
    retransmission timeouts and 4,096 retransmission rounds; zero CPU or probe
    events lost. CPU sampling covered 44.56 seconds, with 4,158 samples including
    814 with TCPIP on the stack. The 1,024 blocked attempts took 42.105 seconds.
    Post-restore firewall profile verification passed.
- [Timing-verified repeat 40387935712](https://github.com/microsoft/netperf/actions/runs/40387935712):
    **39 target wait samples**, 1,024 retransmission timeouts and 4,096 retransmission
    rounds; zero CPU or probe events lost. CPU sampling covered 44.366 seconds,
    with 4,336 samples including 952 with TCPIP on the stack. The corrected result
    separates 42.130 seconds of client traffic, 44.366 seconds of load-phase wall
    time, and 58.605 seconds including capture processing. Timing invariants,
    exact-ancestry assertion and cleanup verification passed.

`CpuEvidence.psm1` requires lossless collection and that exact public-symbol caller
ancestry, rejecting unrelated shutdown waits. `lock-evidence.json` reports a
lower-bound wait-sample count because caller stacks are bounded. A real-peer
SYN-drop campaign fails its reproduction assertion if the fault or target wait
is absent; absence in one finite sample is not proof the path never runs.
For SYN-drop results, `seconds` is the load-phase wall time, `clientSeconds` is
the CTS-reported traffic duration, and `loadAndAnalysisSeconds` includes subsequent
capture processing. In the first two outage runs above, the old `result.seconds`
included processing; use `cpu-load.intervalSeconds` and
`cpu-progress.synOutcomes.Milliseconds` for those runs instead.

These are different workloads, not before/after optimization measurements.
The outage demonstrates connection-failure update contention, **not BH probing**
(BH entry was zero), DGD, or contention magnitude across all 80 CPUs. CPU sample
counts are not weighted whole-system CPU percentages. The public DuoNIC package
supports at most 16 RSS queues/processors; the local fixture opts into that supported
spread and records placement rather than claiming 80-way receive concurrency.

Still missing: selective PMTU filtering, routed DGD topology, kernel lock-site
counters, and a before/after statistical comparison. Add those as public-source
adapters/evidence, not copies of private implementations. Keep recovery/progress
tests alongside performance work. Raw captures remain guest-local and consume
substantial disk space; do not publish them.

### 128-processor functional gate

CPU oversubscription, if the hypervisor permits the requested topology, can test
control-path correctness without providing performance evidence. Do not infer
single-VM startup support from aggregate vCPU overcommit or from an accepted
processor-count configuration.

The management workflow has a separate `probe_128_topology=true` mode.
`topology_vcpus` defaults to 128; use 80 for a control on the current host.
The probe creates a GUID-owned, generation-2 diskless VM with disconnected
networking, 2 GiB startup memory and one virtual thread per core. It starts,
stops and removes only that VM, including partial-create recovery. It does not
change the existing guests, install a driver, weaken trust, or boot a guest OS.
Only numeric/fixed-status `topology-check.json` is published; native errors stay
in management-host scratch. Processor-configuration rejection and startup
rejection are recorded separately from cleanup failure.

[Initial actual-host probe 40390355259](https://github.com/microsoft/netperf/actions/runs/40390355259)
found 40 host-OS-reported cores, 80 host logical processors and an existing 80-vCPU
guest. Configuring 128 vCPUs succeeded, but startup failed; owned-VM removal
was verified. That initial probe used 512 MiB; subsequent control/target probes
use the same 2 GiB allocation. A diskless boot success would establish only
Hyper-V startup capacity, not Windows guest enumeration or RSS coverage.

The same-memory controls confirmed the distinction:
[80-vCPU control 40391042784](https://github.com/microsoft/netperf/actions/runs/40391042784)
started successfully;
[128-vCPU target 40391047006](https://github.com/microsoft/netperf/actions/runs/40391047006)
accepted configuration but failed startup. Both used one virtual thread per
core, and both verified owned-VM removal. The current host therefore has not
provided a usable 128-vCPU guest. Do not treat accepted configuration or a
successful negative-capacity workflow as a 128-CPU RSS validation pass.

The management host is itself a VM, so its reported core count describes virtual
topology, not the underlying physical hardware. These results do not establish
the same startup behavior on bare-metal Hyper-V. Schema 2 therefore uses
`hostReportedCores`, not schema 1's misleading `hostPhysicalCores` field, and
records Hyper-V's `LogicalProcessorCount` separately from the host OS's processor
count. Interpret the old artifact's core field as host-OS-reported topology only.

`Invoke-RssControlCheck.ps1` is a separate **read-only**, fail-closed check for
an already configured adapter on a suitable Windows guest. Use only approved
installed drivers and dedicate the adapter before changing its configuration.
For a suitable 128-processor topology and a driver supporting 128 queues, the
configuration can be applied locally, outside this read-only checker:

```powershell
Set-NetAdapterRss -Name owned-duonic -Profile NUMAStatic `
  -BaseProcessorGroup 0 -BaseProcessorNumber 0 `
  -MaxProcessorGroup 1 -MaxProcessorNumber 63 `
  -MaxProcessors 128 -NumberOfReceiveQueues 128
./Invoke-RssControlCheck.ps1 -AdapterName owned-duonic -PublishFile C:\Runs\rss-control.json
```

The checker reads the effective state twice, requiring enabled RSS, 128 queues,
128 maximum processors, 128 distinct RSS processor-array entries, consistent
array metadata, and an indirection table covering every one of those 128 targets.
It validates group-relative coordinates and rejects duplicates, missing targets,
out-of-set targets, unknown representations and changed/invalid second reads.
The parser supports public CIM processor objects and group:number[/preference]
strings; it does not turn unknown data into defaults.

This distinguishes a configured queue limit from actual reported assignment.
It leaves all adapter settings unchanged. Re-run after an approved adapter
restart to check persistence; the checker itself does not restart networking.
Its result explicitly leaves runtime DPC coverage and performance **unverified**.
Those require traffic/capture evidence, not just RSS settings. The current public
DuoNIC package remains limited to 16, so these scripts do not claim a live
128-queue driver test. No unpublished OS/driver binaries are acquired or uploaded.
RSS excludes SMT siblings; verify the guest's eligible processor set rather than
equating 128 vCPUs with 128 eligible targets.

### Arbitrary RSS counts on an approved dedicated adapter

The read-only checker accepts every integer from 1 through 128 independently
for `ExpectedQueues` and `ExpectedProcessors`, including 40. It runs under
Windows PowerShell 5.1 as well as PowerShell 7:

```powershell
./Invoke-RssControlCheck.ps1 -AdapterName owned-duonic `
  -ExpectedProcessors 40 -ExpectedQueues 40 -PublishFile C:\Runs\rss40.json
```

The installed driver must independently support the requested values; changing
the checker's arguments does not add capability to the pinned public driver.
RSS processor/queue counts need not be powers of two. The indirection table and
packet-ring lengths can remain powers of two independently of those counts.

An approved, separately supplied driver was exercised on a dedicated physical
80-logical-processor lab host with **40 queues and 40 RSS processors** on both
ends of a pair. Two independent reads and a subsequent adapter restart retained
40 distinct indirection targets across processor groups 0 and 1 in 128-entry
tables. CTS completed 8,192 connections and 512 MiB of payload with zero network
or protocol errors; selected transmit/receive byte deltas both measured
540,114,834 bytes. This is functional/control-path and traffic proof, **not**
a sustained performance comparison or per-processor runtime DPC coverage.
No native driver, catalog, private source, certificate or raw lab diagnostics
are published by this experiment. Approved driver provisioning remains external
to the public workload.

```powershell
./Test-TcpChurn.ps1
./Test-HyperVTopologyProbe.ps1
./Test-RssControl.ps1
```

Tests use a memory adapter, a bounded owned PowerShell child, mocked Hyper-V
lifecycle operations and synthetic RSS snapshots. They do not install a driver,
operate real VMs or pretend to be runtime/performance coverage.
