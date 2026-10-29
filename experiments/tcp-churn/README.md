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

### Healthy traffic without an injected outage

The CPU campaign can also collect a bounded success-only scenario, with
`SynDrop` omitted. Success means every CTS client summary has zero network
and protocol errors and the selected NIC byte deltas account for its payload.
It does **not** mean every packet avoided retransmission or that background
system-wide TCP activity was absent.

On already prepared, dedicated local adapters:

```powershell
./Invoke-CpuCampaign.ps1 -Tools C:\PublicTools -Diagnostics C:\Runs\new\diagnostics `
  -PublishDirectory C:\Runs\new\publish -AnalyzerDirectory C:\PublicAnalyzer `
  -Seconds 90 -Connections 1024 -MaximumBatches 1 -ClientWorkers 8 `
  -BaseServerPort 20000 -BytesPerConnection 65536 `
  -ClientInterface owned-client -PeerInterface owned-server `
  -ClientAddresses 192.0.2.21,192.0.2.22,192.0.2.23,192.0.2.24,192.0.2.25,192.0.2.26,192.0.2.27,192.0.2.28 `
  -PeerAddress 192.0.2.12
```

Create the new diagnostics/publication directories first, provision the owned
addresses/routes and scoped inbound allow rule, and verify RSS and address
readiness. This entrypoint does not provision adapters or inject a fault.
Choose listener ports outside the machine's ephemeral port range and check
for collisions. Explicit interface arguments are honored for local traffic.

Parallel mode starts all listeners before launching clients, uses distinct
source addresses, bounds aggregate attempts to **8,192** rather than 8,192 per
worker, verifies every client summary, accounts for shared NIC counters once,
and cleans up all owned processes, including partial startup. Parallel mode
is deliberately limited to one local healthy batch. `MaximumBatches=1` is
also useful for a finite single-client control; larger payloads are explicit
through `BytesPerConnection`.

The published workload totals describe the campaign wall interval, including
listener setup, not an isolated throughput benchmark. Raw client summaries
remain in diagnostics. `healthy-evidence.json` classifies explicit sampled
kernel wait loops separately as path-info ACK tracking, shutdown/RTT updates,
connection-failure updates, path lookup/validation, WFP, endpoint allocation,
or other. It de-duplicates the same stack appearing under several functions.
Acquisition-function samples alone and full-size-ACK events do not satisfy
a wait criterion. Counts are bounded-stack lower bounds, not lock-address
identification or weighted CPU percentages.

Measured on a dedicated physical 80-logical-processor machine with a
40-RSS-processor/queue local pair:

| Successful workload | Connections | CPU samples | Full-size-ACK events | WFP wait samples, lower bound | Healthy path-info explicit waits |
| --- | ---: | ---: | ---: | ---: | ---: |
| One client, 256 concurrent | 8,192 | 50,423 | 99 | 36 | 0 |
| Eight clients, 1,024 concurrent each | 8,192 | 127,575 | 353 | 14,811 | 0 |
| Eight-client repeat | 8,192 | 182,050 | 127 | 14,358 | 0 |

These runs completed all attempts with zero CTS errors and zero CPU/probe event
loss. No fault rules or TCP global changes were applied. No timeout or BH-entry
events were counted. Nevertheless, provider-wide retransmission-round counts
were 229, 88 and 8,017 respectively. The repeat also contained one sampled
connection-failure path-info wait despite eventual application success. It must
not be reclassified as a clean ACK-path contention reproduction.

The current finding is **healthy application traffic can reproduce substantial
network lock waiting, but the observed dominant waits are WFP/port-allocation,
not the targeted ACK/BH path-cache update**. Shutdown/RTT acquisition samples
were seen but are not explicit wait-loop proof. Lack of a finite sample does
not prove absence of short path-cache waits. No before/after improvement is
claimed. Earlier listener-readiness and port-exhaustion failures were excluded,
not counted as successful runs.

The tested lab image required matching private symbols and a current DIA reader.
That reanalysis and its raw traces/symbols stay private and are **not Actions
artifacts**; only the numeric findings above are recorded here. The default
public analyzer/workflow still uses the Microsoft public symbol server. An
explicit `AnalysisSymbolScope=private-lab-only` labels private/manual evidence
but does not fetch private symbols. Never upload that analysis directory.
The portable PowerShell runtime used on the manual host was acquired from
the official release and hash-verified; no machine-wide runtime installation
was required. Fixture cleanup restored disabled adapters and removed owned
addresses/routes/firewall rules; driver/trust/physical-network settings were
unchanged.

### Isolating the first-data confirmation from ALE

Two additional traffic modes remove connection establishment and teardown from
the analyzed CPU/event window. Neither disables WFP or changes TCP global policy.
Use the prepared local-adapter invocation above with one worker and
`MaximumBatches=1`:

- `EstablishedOnly` establishes every CTS connection, warms up for three seconds,
  then measures `Seconds` of paced data. `RateLimitBytesPerSecond` defaults to
  1 MiB/s per connection. All connections must still be established at the end,
  both selected NICs must show progress, and every CTS connection must eventually
  finish without errors. `steady-state.json` records window boundaries, counts
  and byte deltas. Overall result bytes/time still cover the whole workload,
  not just the steady window.
- `BarrierExecutable` runs the small, public-source `BarrierTcp.cs` helper.
  It establishes and accepts every connection **without sending application
  payload**, signals `ready`, then waits for a `go` file. The campaign checks the
  established count, starts the analyzed interval and releases the first payloads.
  The helper verifies every payload byte and completion response, signals `done`,
  and keeps sockets open until the campaign ends the interval and signals `stop`.
  This excludes connect/accept and close activity while exercising first-data ACK
  processing. `first-data.json` records verified totals and the pre-established
  count. Helper, readiness, measurement and shutdown waits are bounded.

Build the new helper from this public source using the existing .NET Framework
compiler; no OS source or existing native driver binary is involved:

```powershell
& "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo `
  /target:exe /platform:x64 /out:C:\PublicTools\BarrierTcp.exe .\BarrierTcp.cs
# In the prepared-adapter CPU campaign, add:
# -BarrierExecutable C:\PublicTools\BarrierTcp.exe -MaximumBatches 1 `
# -ClientWorkers 1 -Connections 8192 -BytesPerConnection 65536
```

The helper supports 1-8 explicitly supplied source addresses and up to 8,192
connections. No replacement connections are created. It is an experiment
workload, not a production server. The first-data mode requires 64 KiB-1 MiB
payloads through the campaign. Do not select `SynDrop`, a remote peer session,
parallel-worker mode or `EstablishedOnly` at the same time.

Measured results on the dedicated 80-logical-processor machine, with 40 RSS
queues/processors:

| Mode | Pre-established connections | Analyzed seconds | CPU samples | Full-size-ACK events | Confirmation-path samples, lower bound | Explicit target wait samples |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Paced steady data | 64 | 20.007 | 11,902 | 0 | 0 | 0 |
| First-data release, one link engine | 1,024 | 1.170 | 4,860 | 330 | 0 | 0 |
| First-data release, one link engine | 8,192 | 2.526 | 37,658 | 6,468 | 5 | 0 |
| First-data release, four link engines | 8,192 | 1.599 | 19,440 | 2,977 | 1 | 0 |
| Four link engines, one source address | 8,192 | 1.642 | 22,878 | 2,964 | 4 | 0 |

Every listed window had zero recorded SYN-send, retransmission-round, timeout
and BH-entry events, zero sampled WFP/port-allocation waits, zero unresolved
TCPIP frames and zero CPU/probe event loss. All payloads completed and fixture
cleanup passed. The 8,192-connection barrier transfers verified 512 MiB each.
Private symbol-based analysis remains private; only numeric observations are
published here. A failed high-concurrency paced transfer was excluded.

**Finding:** ordinary steady traffic removed ALE contention but did not exercise
the first-data confirmation during its measured window. The synchronized
first-data release does exercise that confirmation path without ALE churn or
recorded retransmission events. Increasing link-engine concurrency and
concentrating on one source/destination path retained that coverage. This is a
better isolated strategy, **not yet a sampled target-lock-wait reproduction**:
acquisition/release frames establish execution, not waiting. Bounded stack
retention and finite sampling can miss brief waits. A positive contention claim
still requires an explicit wait stack or lock-address/timing evidence, not just
more ACK events. Provider counts remain system-wide rather than flow-correlated.

### Independent-arrival workload and actual lock-collision evidence

The barrier is a diagnostic control, not a realistic service arrival model.
`ArrivalTcp.cs` provides an alternative: each client connection starts on an
independently scheduled exponential interarrival time, connects, immediately
sends a request payload, verifies the server's acknowledgement, then closes.
There is no preconnection phase or shared release barrier. The server verifies
every payload byte. A fixed seed makes the offered arrival sequence reproducible.
Actual launch lag and total duration are reported rather than treating an offered
rate as achieved throughput.

Build it with the same existing .NET Framework compiler used for `BarrierTcp.cs`,
substituting `ArrivalTcp.cs` and the desired output executable path. On dedicated,
already prepared interfaces:

```powershell
# sources, peer, listener port, total requests, offered requests/sec,
# payload bytes/request, new result file
C:\PublicTools\ArrivalTcp.exe 192.0.2.21 192.0.2.12 20000 8192 2000 65536 C:\Runs\new\arrival.json
```

The helper is bounded to 8,192 requests, 1 MiB per payload, and a 150-second
process deadline; invalid configurations fail explicitly. It is a synthetic
request/reply service workload, not a replay of a specific customer application.
It does not provision adapters, firewall rules, traces or trust policy.

For two prepared physical machines, select separate roles. Run the server on
the machine owning the peer address, then run the client on the other machine:

```powershell
# Server: sources, peer/listen address, port, count, rate, request bytes, output,
# role, response bytes, seed, client concurrency bound, socket pacing
C:\PublicTools\ArrivalTcp.exe 192.0.2.21 192.0.2.12 20000 256 128 1024 C:\Runs\new\server.json server 65536 14529 128 nodelay

# Client: same protocol dimensions; its source address must be locally assigned.
C:\PublicTools\ArrivalTcp.exe 192.0.2.21 192.0.2.12 20000 256 128 1024 C:\Runs\new\client.json client 65536 14529 128 nodelay
```

The optional arguments default to `local`, one response byte, seed 14529,
256 maximum in-flight client requests, and `nagle`. Client concurrency is now
bounded (1-1,024), so offered rate can exceed achieved rate. Each response is
verified byte-for-byte; the server half-closes first and the client verifies EOF
before closing. Output includes peak concurrency, seed, launch lag and
bind/connect/response/EOF timing. Parallel workers should use different seeds
(for example, `14529 + 7919 * workerIndex`), not identical arrival schedules.
Server readiness is a listener-owned ready file, not a first-payload barrier;
`IsListenerReady` checks the listener's process ownership without a probe connection.

#### Managed-GC and mixed-target diagnostic

The client or receiving server can optionally perform one real blocking, compacting generation-2
collection during ongoing verified I/O. Append `gc:heap-MiB:minimum-launched`
after the socket-pacing argument. The bounded heap must be 16-1,024 MiB.
The trigger waits until at least the requested number of requests have launched
(or connections have been accepted by the receiver),
at least one request has completed, and at least one remains in flight. If that
overlap never occurs, the run fails rather than claiming GC-path coverage.

The heap is allocated, promoted and given alternating unreachable objects before
the arrival clock starts. The blocking collection runs at the I/O-overlap trigger.
There is no preconnection phase, first-payload gate, sleep-based pause or shared
release barrier. Normal asynchronous completions and the existing arrival
schedule catch up after the actual runtime collection.
For a receiving process, accepted requests are dispatched through a bounded
worker pool, and independent client processes continue running during its GC.
An independent client can explicitly select `dispatch:pool` instead of a GC
descriptor to use bounded dispatch without triggering a collection.
An optional fourth GC-descriptor element selects `arrays` (default) or `graph`,
for example `gc:1024:2048:graph`. The graph uses a nominally equivalent x64 heap
budget with two-reference nodes and parity-separated links; discarding alternate
roots leaves real unreachable object graphs to mark and compact. It does not
add a sleep or suspension primitive. `managed_gc_heap_layout=graph` selects this
contrast in the guest workflow. Heap policy and observed collection time are
reported separately; changing layout does not guarantee a longer pause.
The completed collection also writes an owned `.gc.json` observation immediately,
independently of final request-budget completion. A failed transfer can therefore
retain the actual collection envelope and quality-checked post-GC CPU window
without being relabelled as successful.

To opt into server GC and all-processor-group runtime support, copy
`ArrivalTcp.ServerGc.config` beside the compiled executable as
`ArrivalTcp.exe.config`. The template is not activated automatically.

For mixed traffic in one client process, use up to eight comma-separated peers
and an equally sized, positionally aligned source-address list. Selection is
round-robin. Server and `local` roles still require one peer/listen address.
For example, prepare one server on the remote peer and another on the client
machine's loopback interface, each expecting half of 8,192 requests:

```powershell
# On the physical peer:
C:\PublicTools\ArrivalTcp.exe 192.0.2.21 192.0.2.12 20000 4096 1000 65536 C:\Runs\new\remote.json server 65536 14529 256 nodelay
# On the client machine, in a separate process:
C:\PublicTools\ArrivalTcp.exe 127.0.0.1 127.0.0.2 20000 4096 1000 65536 C:\Runs\new\loopback.json server 65536 14529 256 nodelay
# On the client machine, after both listeners are ready:
C:\PublicTools\ArrivalTcp.exe '192.0.2.21,127.0.0.1' '192.0.2.12,127.0.0.2' 20000 8192 2000 65536 C:\Runs\new\mixed.json client 65536 14529 256 nodelay gc:512:2048
```

Client output records per-target index, loopback classification, successful
connection counts and directional payload bytes, without exporting addresses.
Only non-loopback target bytes should be compared with physical-NIC counters;
aggregate mixed payload is not physical-wire accounting.

`managedGc` records the generation-2 counter increment, completed/in-flight
request counts, server-GC mode and UTC collection-call envelope. Its elapsed
time is **not** an ETW-verified exact managed-thread suspension duration. Use CLR
suspension/restart events when establishing pause timing, and correlate the
post-resume kernel wait stacks. GC's own CPU consumption is not TCP/IP contention.
UTC envelope timestamps can be equal for short collections; the high-resolution
stopwatch and generation counter establish that the collection actually ran.
This is an explicitly forced-GC diagnostic, not natural-allocation/customer
replay or proof of the target lock's CPU severity.

The existing management-guest workflow also accepts
`profile_cpu=true, managed_gc_mixed=true`. It uses the two **already running,
idle Windows Server guests**, compiles only these public sources, and adds a
separate loopback server in the client guest. It does not provision/reset a VM,
install a driver, alter a feature, or change global networking/offload policy.
`connections` is the bounded client in-flight limit; 8,192 total requests are
offered over the nominal `seconds` interval. Heap pressure is bounded to 1024 MiB
and requires at least four times that much free guest memory before allocation.
This increases only heap pressure from the initial 512 MiB diagnostic; a longer
pause must be observed, not assumed. `managed_gc_payload_bytes` selects
1460-byte, 2 KiB, 64 KiB (default), or 1 MiB requests and responses for controlled comparisons
without changing offloads, arrival scheduling, GC pressure or the in-flight limit.
Client byte accounting includes both targets; only half travels on the remote
path. Results record the payload size and the client data-interface MTU.
The 1460-byte choice is an MTU-1500/MSS diagnostic control, not a claim about
negotiated TCP options or a customer-equivalent application message size.
Managed-GC mode alone permits `seconds=1` for a denser independently scheduled
arrival stream; other guest campaigns retain their five-second minimum.
This changes offered rate, not a shared connection or first-data release barrier.
GC mode dispatches each due request onto the runtime thread pool after reserving
its shared in-flight slot, rather than serializing synchronous socket setup on
the arrival scheduler. Ordinary non-GC arrivals retain inline dispatch. Launch
lag and dispatch-queue delay are separate measurements; reports include actual
started requests at collection, peak in-flight work and achieved launch span.
Queued work is not proof of wire-level arrival or target-lock CPU utilization.

This mode captures kernel CPU samples, exact TCP probes and CLR GC events.
It publishes only allowlisted numeric/fixed-label results, public-symbol CPU
aggregates and owned-client CLR event counts. Raw traces, addresses, credentials
and process identities stay in guest diagnostics. `cpu-after-gc.json` starts at
the end of the collection-call envelope without discarding the initial catch-up
milliseconds, and covers up to two seconds; CLR event coverage does not
by itself establish exact pause correlation. It is labelled virtualized and
diagnostic, not physical-equivalent or proof of 30 target-lock CPUs.
Failures report a bounded phase, exception type and numeric error code; child
startup failures also include a filtered error identifier and source line.
Exception messages and raw child logs are not published.

Healthy mixed-GC guest controls completed 8,192 requests each, split equally
between remote and loopback targets, with lossless probe coverage:

| Request/reply size | Full-size ACK events | Public run |
|---|---:|---|
| 64 KiB | 10 | [40640981126](https://github.com/microsoft/netperf/actions/runs/40640981126) |
| 1 MiB | 57 | [40641594223](https://github.com/microsoft/netperf/actions/runs/40641594223) |
| 2 KiB | 0 | [40642676715](https://github.com/microsoft/netperf/actions/runs/40642676715) |
| 1460 bytes | 4096 | [40643240259](https://github.com/microsoft/netperf/actions/runs/40643240259) |

These are coverage contrasts, not evidence that larger messages cause more
confirmations. The 1460-byte control exercised a confirmation for every remote
request without changing offloads; it did not reproduce a cache-lock hotspot.
No BH-entry or retransmission events occurred.

The [parallel-dispatch control](https://github.com/microsoft/netperf/actions/runs/40644395035)
observed 71 requests in flight at a 51 ms collection and a peak of 419, but
still had only 11 setter-frame occurrences in 371,052 whole-window CPU samples.
The [1 GiB heap contrast](https://github.com/microsoft/netperf/actions/runs/40645010719)
observed a 99 ms collection, all 4,096 remote full-size ACK confirmations, and
only three setter-frame occurrences in 148,630 samples over 9.48 seconds.
Both verified endpoint accounting and cleanup. An offered 8,192 requests/second
did not establish that achieved rate: the latter workload took 5.064 seconds.
Acquisition/release frames are not proof of spinning on a particular lock.
These virtualized healthy-GC trials do **not** establish target-lock saturation.

For an explicitly separate recovery contrast, also select
`managed_gc_peer_recovery=true`. This requires an existing dynamic on-link peer
neighbor, verified against the owned peer adapter, and disabled client forwarding.
After the client has finished heap preparation and ordinary traffic reaches at
least eight established remote connections plus 64 KiB of adapter sends, an
independent local agent substitutes the **owned client adapter's MAC** for that
one peer for the selected `managed_gc_recovery_ms` hold interval (3, 5 or 8
seconds; default 8). Apply/restore operations are separately timestamped and can
extend the overall interruption beyond that hold. Requests are never held at a connection/data barrier.
This models a temporary stale L2 mapping, not a size-selective MTU black hole.

The agent restores the verified peer MAC and original dynamic-neighbor policy
in `finally`; the controller also performs an ownership-checked restoration pass.
The pulse itself changes no route, link, firewall profile, offload or trust setting.
The peer's in-band management session may also pause, so algorithm coverage is
counted only for TCB lifetimes correlated to the owned client's completion
and close events, excluding management traffic and invalidating reused TCB identities.
Owned close-event coverage must also match the completed workload. Failed BH
attempts are counted separately from probe entry; a numeric count of failure
messages mentioning an `ACK` token and generic unacked/max/hop tokens is reported
without exporting message text. These lexical counts may overlap and are not by
themselves a complete reason classification.
The contrast is accepted only with complete verified transfers, data
retransmission **and actual BH entry** on those client connections, lossless
traces and verified cleanup. It adds `cpu-after-recovery.json` for the immediate
post-restoration window. Algorithm coverage still does not establish a cache-lock
wait, target CPU saturation, or equivalence to a physical deployment.
Post-restoration CPU diagnostics are retained even when the final BH-entry gate
rejects the run. Fixed DHCP-state flags document the admission constraints for
possible future data/management isolation; this pulse never changes DHCP.

The separate healthy receiver control selects `managed_gc_process_role=server`
with isolated data enabled and the neighbor pulse disabled. The profiled guest
runs one GC receiver, a distinct local producer connects to that guest's own data
address, and the peer runs another independent producer. Both producers use
different arrival seeds and no forced GC; only the receiver pauses. Each sends
half the verified request budget. This is ordinary listener readiness followed
by independent requests, not a preconnected cohort or shared first-data release.
The CLR process filter and TCP ownership correlation move to the receiver;
passive TCBs are attributed using public accept-completion plus close events.
The result records the profiled process role. The maximum independent-producer
launch span is not a shared wire-arrival clock; workload duration covers both
producers and the receiver. Ordinary client-GC mode remains the default.

The opt-in `managed_gc_receive_budget_bytes=16384` receiver control sets and
verifies a 16-KiB socket receive buffer on the listener and every accepted
socket, and caps each posted request read at 16 KiB. Both limits matter:
an already-posted full-request read can otherwise absorb data while the
application is collecting. The default `0` leaves socket and posted-read
behavior unchanged; the GC result records both configured limits (`0` means
the default, not a zero-length receive). This is a backpressure experiment,
not proof that TCP advertised a zero window or sent a probe. No producer
barrier, application sleep, neighbor pulse or route mutation is added.
This option also requires and captures the public zero-window probing
begin/end events. Whole-machine event counts remain distinct from
ownership-correlated events and from sampled lock-wait evidence.
The bounded control uses Winsock `SOMAXCONN_HINT(8192)` for its listener,
rather than assuming a positive backlog argument requests that queue size.
The requested hint is recorded; Windows provides no query for the actual
backlog. This is ordinary accept-queue capacity, not a preconnected/data-release
barrier. See the [Winsock listen contract](https://learn.microsoft.com/windows/win32/api/winsock2/nf-winsock2-listen).

The separate `managed_gc_cache_retire_paths=1|1024|8192|24576|49152` mechanism control
requires the ordinary receiver setup described above.
The explicit `managed_gc_mixed=persistent64` variant keeps each independently
arriving TCP connection for64 validated1460-byte request/response exchanges.
There is no preconnection phase or data-release barrier. Both endpoints report
the applied exchange count and exact total bytes; connection lifetime accounting
remains separate from message count. The ordinary `true` mode still performs one
exchange. Persistent mode is restricted to receiver GC and1460-byte payloads,
and bounds TCP ownership-event analysis separately for the larger ACK workload.
Persistent captures export the installed CPU profile with 256 MiB of system
buffers and omit high-volume context-switch/ready-thread tracing, retaining
sampled CPU stacks, process/thread lifetime and image metadata. Optional
spinlock events remain a separate explicit choice. The report states that
scheduling events were omitted; these captures must not be used to infer
off-CPU owner intervals. TCP/CLR filters and zero-loss acceptance are unchanged.

The idle-cache mechanism control
requires isolated receiver GC and excludes neighbor pulses.
It populates measured idle UDP paths using only the extra source
`198.19.0.1/17`, sends no UDP payloads, and retires that secondary address after
the real-GC signal while ordinary TCP continues on `198.19.240.1`.
It rejects overlapping routes/addresses, measures cached paths both before
and after closing the fixture sockets, and requires a live TCP cohort before
retirement. Management/data addresses, static IPv4 policy and default routes
must remain unchanged. The measured population and actual API timing are
reported separately from sampled lock waits. This deliberately tests address
retirement/cache maintenance; it is not evidence that an unobserved application
pause causes address changes or that this trigger occurred elsewhere.
No VM CPU settings or host scheduling policies are changed.
Explicitly selecting both cache retirement and route refresh runs an
interaction control: one owned next-hop change makes cached TCP path
information stale while the separate owned-source retirement exercises
cache maintenance. Each agent has its own lifecycle, snapshot and report,
and both restorations must pass. Selecting either control alone retains its
original behavior.
The optional `managed_gc_peer_pressure=true` contrast adds an independent
managed loopback service to the owned peer. It uses the same bounded real
graph-GC workload, ordinary Poisson requests and verified bytes, not a CPU
burner or data-release barrier. Both heaps must fit admission limits.
The additional service uses a 4,096-request workload offered at 2,048 requests/s with at most
256 concurrent requests; the result records the applied offered rate. Both
loopback endpoints must finish, and their measured generation-2 collection
must overlap the profiled collection. This tests concurrent managed-service
CPU pressure without changing VM processor allocation or host scheduling.
With the disposable-interface variant, the companion's ordinary accepted-flow
threshold is later (1,536 rather than 1,024), and its measured collection must
instead overlap the interface-cleanup API. This targets lock-holder scheduling
during maintenance, not merely two collections that end before maintenance.
The explicit `managed_gc_unused_interface=true` variant creates one
disposable synthetic NIC on the owned generation-2 VM. It is first added
disconnected, configured without DHCP, and only then attached to the VM's
existing data switch, matched by the guest's peer-route source MAC. The idle cache uses this NIC; productive TCP and management
continue on the original NIC. This variant releases its idle UDP sockets before
traffic readiness and verifies the cached population and TCP cohort after GC
begins. Those snapshots must finish during the actual collection. It then waits
for GC completion and detaches the disposable NIC's IPv4 binding without another
expensive table query in that critical window. Snapshot timestamps and the
`establishedAtSnapshot` count describe the measured state, not an instantaneous
count at the later detach call.
This keeps cache-size comparisons from also shifting the maintenance trigger
by their different socket-close costs. The source-address-only control retains
its GC-start-then-release timing; the result records the trigger phase.
Its identity-checked binding/address restore
and host-side removal must both verify. Original VM NICs and switch
configuration are never changed. This is an interface-retirement mechanism
control, not a claim that the trigger happened in a customer workload.
A unique skip-as-source `/32` bootstrap address is assigned while disconnected
to prevent automatic link-local configuration; it has no gateway and is
removed with the disposable interface.
Binding restoration waits for the identity-matched IPv4 interface to return
before restoring its static configuration. A cleanup failure always rejects
the benchmark; an available capture may still be analyzed as explicitly
rejected diagnostic evidence, never promoted to a successful workload.
Path-population snapshots use the documented IP Helper path table, filtered
by the owned interface and source, rather than launching a command-line
enumerator in the GC-triggered interval. The native structure layout and
ordinary loopback path enumeration are validated by the source tests.
Counting reads only the required native row fields instead of boxing every
complete row. Trigger diagnostics separate the native query, row scan and TCP
cohort snapshot costs, since observation latency can move maintenance away
from the intended GC phase.
Socket population uses a bounded compiled loop and reports its duration;
the requested count still must match measured cached paths, rather than
assuming that successful socket creation pins every path.
Fixture socket release is also a measured compiled loop, avoiding
interpreter overhead and, in the unused-interface variant, finishing before traffic.
Its maximum parallelism is the process's available CPU count, reported in
the control result; only the separately owned idle UDP fixture is released.
No productive TCP connection is preconnected or released by this operation.
The 49,152-path scale variant uses two owned sources, `198.19.0.1` and
`198.19.0.2`, within the same exclusive `/17`, with 24,576 destinations per
source. It counts their union in one native snapshot and reports the source
count. All source identities are checked before removing either address,
including rollback after partial setup. This varies both total paths and
source count; it is not presented as a pure single-source cardinality control.

CPU summaries separately count queued lock-owner waits under path refresh
and the narrower timer/header-send/path-refresh signature, including a
separate count for hypervisor long-spin notification stacks. Acquisition
frames alone and ordinary RTT wait-interval checks do not qualify. These
are caller signatures, not proof of a particular lock address or owner;
a periodic timer frame does not by itself establish retransmission or
black-hole probing.
The timer-wait summary also reports peak sample density over sliding 10-, 100-,
500- and 620-ms windows using the trace's recorded positive sampling interval.
These CPU-equivalent estimates are not proof of simultaneous waiters on one
identified lock.

The read-only `probe_peer` mode also rejects remaining owned GC processes,
data aliases, firewall rules or permanent fixture neighbors, and publishes only
numeric residual counts. It never removes resources or changes guest policy.
It also reports the read-only WPR status exit code and recognized CPU-profile
or not-recording flags. Unrecognized status is not evidence that recording is
idle; the probe never cancels or stops a capture.
The read-only probe also counts exact-probe ETW loggers independently of WPR;
an idle WPR status does not establish that these separate loggers are absent.
It reports the peer-route data adapter's RSS queue/processor bounds separately
from VM logical-CPU count. CPU summaries also expose timer samples by
processor; distinct processors over a whole interval are not claimed as
simultaneous timer execution.
`managed_gc_rss_processors=32|40|64|80` is an explicit temporary receive-scaling
control on the verified guest data adapter. It snapshots all RSS settings,
requests queues/processors without restarting the adapter, exposes the full
range of actual active processor groups so SMT exclusion does not halve a
range truncated to the requested RSS count, and requires the requested queue
and processor budget plus an eligible RSS array covering that budget.
Settings remain exact except that preparation may normalize the upper bound
to the final processor in the returned eligible RSS array, within the requested
range. This handles an excluded final SMT sibling without accepting a queue or
processor-budget clamp; a different narrowed endpoint remains a rejection.
Original RSS fields, active
array size, data-adapter IPv4 addresses and default routes must restore.
The host NIC, VM CPU allocation and switch configuration are not changed.
If the existing adapter cannot activate the requested queues without a
restart, the control is rejected and restored. The explicit
`managed_gc_owned_data_interface=true` alternative instead creates a separate
identity-checked, no-gateway `NetperfData-*` NIC. Only that disposable NIC may
restart for RSS activation; the original management/data adapters are never
restarted. Experimental aliases/traffic move to the new NIC and the VM's
original hardware layout is restored by identity-checked removal.
Failed TCP/CLR collector startup reports a fixed capture stage, exception
type and numeric error code. Provider discovery, TCP startup and CLR startup
remain separate adapter phases; private exception messages and raw ETLs are
not copied into the numeric result.
The explicit `managed_gc_wpr_probes=true` alternative uses WPR to enable the
same exact public TCP/CLR event-ID filters alongside CPU profiling. It does
not silently fall back from another controller. The providers are strict,
the generated profile is schema-validated, and CPU/TCP/CLR analysis reads the
single merged ETL while preserving the existing integrity, symbol and loss
gates. Default controller selection is unchanged.
Managed-GC capture explicitly requests the TCP diagnosis/send/connect/TCB
keywords needed by the selected events and the CLR GC keyword, rather than
all provider keywords. The TCP selection is checked against the installed
manifest. Event-ID filtering alone does not constrain provider-enable
callbacks or unrelated rundown/control operations.
The kernel TCP provider explicitly requests nonpaged event buffers; the
dedicated hosted activation test checks TCP and CLR individually as well as
the combined CPU/event recording.
The WPR alternative skips dynamic managed-PDB generation, which is not used
by the public TCP/kernel symbol analysis or CLR event correlation.
CLR correlation uses the same provider-GUID-aware ETW reader as event counting,
with an explicit profiled-process and time-interval filter. It does not depend
on a registry-backed event-log query being able to select CLR records from a
merged kernel/user ETL.
`managed_gc_spinlocks=true` additionally exports the installed CPU profile,
adds its strict kernel spinlock keyword, and increases the owned system
collector's buffers. It requires the explicit WPR backend. Raw addresses and
ETLs remain guest-local; the public sampled CPU densities are still not
presented as same-lock simultaneous-waiter proof.
The spinlock summary decodes the installed public x64 Thread/SpinLock schema,
groups records by their actual address privately, and resolves TCP release
sites against the capture's exact public PDB identity. Only per-capture lock
ordinals, public function names and aggregate counts leave the guest.
Same-lock maintenance attribution accepts the exact public `IppValidatePaths`,
`IppGarbageCollectPaths` or `IppFlushPaths` writer together with the unambiguous
`IppGetNextHopFromPath` reader site. `TcpUpdatePathInfoTcb` alone is not reader
proof because it can contain inlined on-demand write validation.
It retains separate garbage-collector-only and
any-maintenance-writer flags; a validation writer by itself is not a reader.
Recorded cycle-interval overlap and the no-interrupt DISPATCH-level subset
remain separate from sampled CPU density; no raw address is exported.
It also reports numeric free-space admission information for the guest temporary
drives; busy or residual-resource failures retain fixed failure categories rather
than exporting process names, paths or exception messages.

The separate manual `tcp-churn-retention.yml` workflow inspects regenerable
ETLX indexes for an explicit list of exact synthetic GC-start UTC .NET ticks.
It requires idle workload/analyzer processes and idle WPR, and validates every
collection match before changing anything. Its opt-in prune removes only
ordinary `.etlx` files with corresponding nonempty original ETLs, verifying
original ETL hashes and rejecting changed files or reparse-point directories.
Raw ETLs, numeric summaries and symbols remain guest-local. No trace path or
raw capture is published; inspection is the default.

The explicit `managed_gc_route_refresh=true` plus
`managed_gc_route_variant=destination-flush` alternative tests on-demand
validation after atomic path invalidation, without interface deletion or a
large idle-cache fixture. It snapshots a live cohort during the actual GC,
waits for collection completion, and invokes the documented destination-cache
delete for only `198.19.240.1` and `198.19.240.6`, always with the verified
owned interface specified. Management destinations and whole-cache flushes
are excluded. Both operations, original addresses/default routes/static IPv4
policy, peer identity and timing must verify. This mode rejects cache
retirement and companion-pressure combinations.
The `onlink-after-gc` variant instead uses the original equivalent on-link
host-route worker, changing only its trigger from the pre-call signal to the
actual GC-completion file. It still adds/removes exactly one owned peer route,
keeps interface and next hop unchanged, and verifies that the route API starts
after collection. It rejects the same mixed maintenance/pressure modes.

The `onlink` and `peer-gateway` route-refresh variants require isolated
receiver GC and no neighbor pulse. An independent agent observes a pre-call GC
signal and adds exactly one host route to the owned benchmark peer, retaining
the connected prefix's interface and on-link next hop. The more-specific entry
is ActiveStore only; existing host routes reject admission, default routes are
verified unchanged, and both agent `finally` and an ownership-checked controller
pass remove the entry. The read-only residual check also rejects a remaining
control route. Workload CPU windows exclude route-removal cleanup.
This tests cached-path invalidation separately from ordinary receive pressure;
it is not a claim that the route update exactly overlaps CLR suspension, causes
a cache epoch change by itself, or represents a customer network event.
`managed_gc_route_variant=peer-gateway` adds a second owned peer alias and uses
it as a logical next hop for that host route. The agent verifies that it resolves
to the same owned peer NIC/MAC and retains the interface, while reporting that
the logical next hop changed. The packet destination remains the peer's own
data address; this is not an independent physical gateway or a DGD-transition
claim. Both peer aliases and the host route are ownership-checked and removed.
The default `onlink` variant retains the original on-link next-hop semantics.
The `applyStartUtc`/`applyEndUtc` envelope brackets the route-addition API call;
`addedUtc` follows independent route verification. Neither timestamp is an exact
kernel cache-invalidation time. A verification timestamp after GC does not by
itself establish that the route was applied after GC.

[Run 40671784588](https://github.com/microsoft/netperf/actions/runs/40671784588)
completed all 8,192 transactions with 1 MiB requests and responses, a 754 ms
graph-heap collection, and verified cleanup. The logical-next-hop addition API
returned 53 ms before the collection ended. At the lower offered arrival rate
(1,640/s), the earlier connection refusals did not recur; this contrast does not
identify their kernel cause. There were 11 active receiver operations at GC
entry and a peak of 741 over the workload. The two-second post-GC window had
135,619 CPU samples, including 19 path-update and 3 path-setter frame occurrences,
with zero lost events or unresolved network frames. These are frame counts,
not global path-cache-lock wait counts or evidence of target-lock saturation.
The route API timing also does not prove a particular cached-path epoch changed.

`managed_gc_isolated_data=true` is a separate, explicit opt-in for fresh data
paths. It requires both existing guest interfaces to already have DHCP disabled.
It transactionally adds four client aliases and one peer alias, all ActiveStore
and SkipAsSource, within a dedicated benchmark /29. Existing address or route
overlaps reject admission; management addresses, DHCP state and default routes
are snapshotted and verified unchanged. Cleanup removes only the owned aliases
and their connected prefix, then verifies exact original management policy.
It does not create an adapter, VM or host switch. Four remote source/target
pairs plus four loopback pairs retain the same aggregate endpoint and wire-byte
checks. WinRM continues to use the original addresses rather than priming the
TCP data paths before the experiment. These temporary guest address/connected-route
changes occur only in this opt-in fixture, not in ordinary healthy or recovery runs.
Runtime socket failures now produce an explicitly failed result with framework
exception type, numeric error/socket codes and started/connected/completed
counts, while retaining a nonzero process exit. No exception message, endpoint
address or stack is exported. A rejected transfer can retain quality-checked
whole-window CPU/TCP diagnostics after verified cleanup; this never changes its
failed outcome or makes it an accepted recovery/severity result.

The manual lab investigation supplemented CPU sampling with the existing Windows
Performance Toolkit **SPINLOCK collision events**, rather than assuming that a
function-entry sample proves contention. Private analysis matched the exact
running binary, distinguished the compartment path-cache lock from per-path
RTT locks, and grouped events by the actual lock address. Only uninterrupted
events with a **positive recorded spin count** were accepted as collision proof.
Addresses, disassembly, private symbols, raw trace records and the build-specific
attribution tooling remain private; this public helper contains none of those.

Measured on the dedicated 80-logical-processor machine with a 40-RSS pair:

| Offered arrivals/sec | Completed requests | Actual requests/sec including drain | Positive-spin events on the identified path-cache lock | Lost events/buffers |
| --- | ---: | ---: | ---: | ---: |
| 2,000 | 8,192 | 1,967 | 32 | 0 / 0 |
| 2,000, repeat | 8,192 | 1,966 | 32 | 0 / 0 |
| 2,000, with TCP probes | 8,192 | 1,965 | 31 | 0 / 0 |
| 2,000, end-to-end assertion repeat | 8,192 | 1,964 | 27 | 0 / 0 |
| 10,000 | 8,192 | 2,185 | 774 | 0 / 0 |

All rows verified 512 MiB of payload with zero application network/protocol
errors and no injected fault. The high offered rate was **not achieved** and
must not be described as a 10,000-connection/sec benchmark. The instrumented
2,000/sec repeat also verified matching selected NIC byte deltas; mean launch
lag was 6.65 ms, maximum 50.16 ms, and launch span 4,163.57 ms. These are ordinary
independent arrivals subject to scheduling delay, not simultaneous payload release.

The TCP-probed run counted zero final timeout/BH-entry events, but 742
provider-wide retransmission-round events, with zero probe loss. Thus all
requests succeeded, but **zero packet loss/retransmission is not claimed**,
and those events are not flow-correlated. No outage or firewall block was injected.

**Finding:** actual contention on the identified compartment path-cache lock
is reproducible with a plausible independently arriving request/reply workload.
This is stronger than generic TCP wait stacks or barrier-only mechanism coverage.
It does **not** establish customer-scale severity, that the BH-confirmation writer
dominates the workload, or an optimization benefit. The observed collision
durations at the moderate rate are small. The fixture still has both endpoints
on one machine and an emulated link; a two-physical-host comparison remains
necessary before treating it as representative of a remote customer's topology.
Kernel collision tracing itself adds overhead and is diagnostic evidence, not
an uninstrumented performance measurement.

### Coherent per-processor CPU measurements

Compile `CpuUtilization.cs` with the same x64 .NET Framework compiler, then run:

```powershell
C:\PublicTools\CpuUtilization.exe C:\Runs\new\cpu.json C:\Runs\new\cpu.ready C:\Runs\new\cpu.stop 240 1000
# Wait for cpu.ready, run the workload, and create cpu.stop for owned shutdown.
# A deadline without the stop file is a failed/incomplete collection.
```

This uses one group-aware wildcard PDH query per snapshot, not sequential
per-CPU reads. Collection is bounded to 5-300 seconds and 1,000-10,000 ms
intervals; 100 ms polling produced invalid idle-CPU statuses and is not supported.
Warm-up precedes readiness. Invalid counters or topology changes fail explicitly.
Provider timestamps are retained as opaque values: observed provider clocks
were not UTC. Each query is instead bracketed by UTC reads, aligned to their
midpoint, and rejected if its measured bracket exceeds 100 ms.

`CpuUtilization.psm1` integrates interval-average utilization over explicit UTC
workload bounds. It rejects legacy sequential snapshots, unverified clock
alignment, overlapping/malformed intervals and less than 90% interval coverage.
It reports time-weighted busy-CPU equivalents and logical processors at least
90% busy, plus per-processor averages/peaks. Peaks are counter-interval averages,
not instantaneous readings. When invoking a native analyzer from PowerShell,
format UTC bounds explicitly with `ToUniversalTime().ToString('o')`; implicit
DateTime argument conversion loses timezone/subsecond information.

These are **total CPU** measurements, not attribution to a lock. Earlier local
reports without the coherent-query/UTC-alignment quality tags are provisional
and must not be used as evidence of customer-scale CPU saturation.

### Two-physical-host investigation: severity gate still open

Manual SSH measurements now use two dedicated physical 80-logical-processor
servers, a 200-Gbps hardware link, MTU 1,500 and 40 verified RSS targets per host.
They are not executions of the GitHub hardware workflow and do not use DuoNIC.
Host access, isolated benchmark addressing, fault control, private symbols and
raw traces remain outside this public repository.

Successful native CTS controls transferred 16 GiB over 16,384 connections.
The LSO-disabled CPU-plus-collision run averaged 23.18 busy CPU equivalents on
the server and peaked at 43 logical processors at least 90% busy. A CPU-only
repeat (no collision instrumentation) averaged 18.94 busy CPU equivalents and
peaked at 60 logical processors at least 90% busy. Exact private analysis of
that repeat found TCP send/completion lock waits, **not a path-cache hotspot**.
LSO was restored to its original enabled state after those diagnostics.

Offload settings affect mechanism coverage, but do not universally suppress it:
the LSO-enabled native control still recorded 7,740 server full-size-ACK events,
versus 16,384 in the LSO-disabled CPU-only repeat. Provider counts are system-wide,
not flow-correlated. Do not equate ACK-event counts with actual BH probing or
lock waiting, or assume a customer's offload configuration.

A subsequent established-flow recovery trial requested a 500 ms stale neighbor
mapping, changed only the isolated peer's data-plane mapping, then restored
dynamic resolution. The verified-mapping-to-restoration interval was 662 ms;
it was not an exact 500 ms physical outage. All 8,192 connections completed
64 GiB with native expected-connection-byte-count verification, not per-byte
pattern verification. Server averages were 12.29 busy CPU equivalents, peak
40.46 busy CPU equivalents and 20 logical processors at least 90% busy.
There were retransmissions and BH-confirmation events, but zero BH-entry events.
Exact private CPU attribution found only six candidate-setter frame occurrences
across both hosts, with no CPU/probe event loss or unresolved TCPIP frames.
This remains a negative severity result, not a customer reproduction.

A larger eight-second fault restored successfully but produced connection
resets/deadlines; it is excluded from successful-transfer results. On-link
traffic also does not exercise route-level DGD failover. More CPU load or more
retransmissions alone cannot close either mechanism or severity gate.

The next matched pair used 32 routed service addresses on the same isolated
physical link. Both the no-fault and requested 1,500 ms recovery runs completed
8,192 connections and 64 GiB. Client CPU averaged 31.07 and 30.32 busy equivalents,
respectively, but exact profiles attributed substantial waits to receive/buffer
management rather than the target cache. No BH-entry event was recorded.

A separate cache-cardinality diagnostic connected and closed 7,872 UDP sockets
without sending payloads, increasing the measured server data-interface cache
from 71 to 7,941 entries. This is **lookup-conditioned state, not 7,872 active
peers or a customer traffic replay**. The resulting matched control and recovery
both completed 8,192 connections and 64 GiB. Server averages were 9.65 and 7.45
busy CPU equivalents, respectively. Explicit DGD state-change events were
captured (2,362 control / 1,836 recovery, provider-wide); these counts do not
alone establish distinct state transitions, causality or lock waiting.
The recovery still recorded zero BH-entry events, with zero CPU/probe loss and
zero unresolved TCPIP frames. Its candidate setter and path-suspicion functions
remained sparsely sampled. Cache conditioning did **not** close the severity gate.

A sender-side diagnostic then used a logical standby next hop on the same
physical receiver. An eight-second-requested stale primary mapping was restored,
and all 8,192 connections / 64 GiB completed. Unlike the earlier ACK-direction
faults, this recorded **347 actual BH-entry events** and 316 BH-exit events.
It is a heuristic BH-probing reproduction, not proof of size-selective MTU loss.
Server CPU averaged 10.57 busy equivalents; exact sampling still found only
sparse target-path candidates, with zero CPU/probe loss or unresolved TCPIP
frames. DGD event payloads in the measured window were unchanged-state
notifications, so event totals are not claimed as gateway-state transitions.
Logical next hops sharing a physical receiver are not independent gateway
hardware. This closes a mechanism-coverage gap, **not the target-lock severity gate**.

Short outbound sends then placed connection creation and BH confirmations on
the same host: 8,192 connections transferred 512 MiB. The initial LSO-enabled
run recorded 455 full-size-ACK events. A no-restart LSO configuration request
did not demonstrate increased coverage and is not used as a verified LSO-off
comparison. After applying the setting with a guarded data-adapter restart
and restoring the benchmark addresses/route, the LSO-off run recorded all
8,192 full-size ACKs. Client CPU averaged 15.87 busy equivalents, peaked at
19.15 and had zero logical processors at least 90% busy. Exact analysis found
eight candidate-setter frame occurrences among 80,433 CPU samples, with zero
CPU/probe loss or unresolved TCPIP frames. A restarted, original-LSO-restored
control completed the same transfer and recorded 613 full-size ACKs.

A larger 65,536-connection outbound attempt encountered port-allocation errors
and is excluded; no global port-range/reuse policy was changed to hide them.
Both original offload configurations and RSS40 were verified after restoration.
Temporary service addresses, primary/standby test routes, owned collectors and
scoped firewall rules were removed; the original isolated physical fixture was
retained for further work. These experiments still do not reproduce the
customer-scale target-lock hotspot.

A bounded scaling follow-up used status/error-only CTS console logging. Its
8,192-connection control passed with all full-size ACKs and peaked at 16.56
busy client CPU equivalents. The 65,536-connection case enabled CTS
`PortScalability` and verified that name in its effective options, but still
encountered port-allocation errors and was rejected. Existing TCP templates had
no auto-reuse range, so CTS did not select `ReuseUnicastPort`; global TCP policy
was intentionally left unchanged. This capacity limit applies to that candidate
workload, not as an explanation of the customer's contention. Further high-count
runs now require a validated existing reuse prerequisite before workloads start.
The later fan-out trial was not started after this failure, and restoration/
owned-fixture cleanup still completed.

**Acceptance remains open:** plausible traffic must show the identified
path-cache lock consuming roughly 30 CPUs, with contemporaneous per-CPU
measurements and exact stack/instruction or lock-identity attribution. Neither
generic saturation nor small positive-spin collision counts satisfy that gate.

```powershell
./Test-TcpChurn.ps1
./Test-HyperVTopologyProbe.ps1
./Test-RssControl.ps1
./Test-HealthyParallel.ps1
./Test-HealthyEvidence.ps1
./Test-EstablishedTransfer.ps1
./Test-BarrierTcp.ps1
./Test-ArrivalTcp.ps1
./Test-GcArrivalTcp.ps1
./Test-GcGuestAdapter.ps1
./Test-CpuUtilization.ps1
./Test-CpuCollector.ps1
```

Tests use a memory adapter, a bounded owned PowerShell child, mocked Hyper-V
lifecycle operations, synthetic RSS snapshots, loopback request/reply endpoints
and a bounded real PDH collector. They do not install a driver, operate real VMs
or pretend to establish kernel-lock performance coverage.
