// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Diagnostics.Symbols;
using Microsoft.Diagnostics.Tracing.Etlx;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using Microsoft.Diagnostics.Tracing.Session;
using System.Threading;

internal static class Program
{
    private static void Add(Dictionary<string, long> counts, string value)
    {
        counts.TryGetValue(value, out var count);
        counts[value] = count + 1;
    }

    private static bool IsNetwork(string name) =>
        string.Equals(name, "tcpip", StringComparison.OrdinalIgnoreCase) ||
        string.Equals(name, "tcpip.sys", StringComparison.OrdinalIgnoreCase);

    private static bool IsPathRefreshWait(IEnumerable<string> frames) =>
        frames.Any(frame => frame.EndsWith("!TcpUpdatePathInfoTcb", StringComparison.Ordinal)) &&
        frames.Any(frame => frame.IndexOf("!KxWaitForLockOwnerShip", StringComparison.OrdinalIgnoreCase) >= 0);

    private static bool IsTimerPathRefreshWait(IEnumerable<string> frames) =>
        IsPathRefreshWait(frames) &&
        frames.Any(frame => frame.EndsWith("!TcpTcbHeaderSend", StringComparison.Ordinal)) &&
        frames.Any(frame => frame.EndsWith("!TcpPeriodicTimeoutHandler", StringComparison.Ordinal));

    private static int PeakSampleCount(IReadOnlyList<long> sortedTicks, long windowTicks)
    {
        int left = 0, peak = 0;
        for (int right = 0; right < sortedTicks.Count; right++)
        {
            while (sortedTicks[right] - sortedTicks[left] >= windowTicks) left++;
            peak = Math.Max(peak, right - left + 1);
        }
        return peak;
    }

    private static int EventProcessFilter(string selector)
    {
        if (selector == "interval") return 0;
        if (!int.TryParse(selector, out int processId) || processId <= 0)
            throw new ArgumentException("Expected an interval selector or a positive process ID.");
        return processId;
    }

    private static object[] Top(Dictionary<string, long> counts, int limit) =>
        counts.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key)
            .Take(limit).Select(pair => (object)new { name = pair.Key, samples = pair.Value }).ToArray();

    private static int Main(string[] args)
    {
        if (args.Length == 5 && args[0] == "--spin-summary")
            return SpinLockEvidence.Run(args[1], args[2], args[3], args[4]);
        if (args.Length == 6 && args[0] == "--capture-probes")
        {
            string captureStage = "input";
            Action<string> progress = capturePhase => File.WriteAllText(args[3] + ".progress.json",
                JsonConvert.SerializeObject(new { schema = 1, outcome = "capture-starting", stage = capturePhase }));
            try
            {
                progress(captureStage);
                var state = JObject.Parse(File.ReadAllText(args[2]));
                var ids = state["publicProviderEvents"].Select(item => (int)item["Id"]).Distinct().ToList();
                if (ids.Count == 0 || ids.Count > 16) throw new InvalidOperationException("Invalid public probe list.");
                var provider = Guid.Parse((string)state["publicProviderGuid"]);
                var keywordText = (string)state["publicProviderKeywords"];
                ulong keywords = ulong.MaxValue;
                if (keywordText != null && (!keywordText.StartsWith("0x", StringComparison.Ordinal) ||
                    !ulong.TryParse(keywordText.Substring(2), System.Globalization.NumberStyles.HexNumber,
                        System.Globalization.CultureInfo.InvariantCulture, out keywords)))
                    throw new InvalidOperationException("Invalid explicit public provider keywords.");
                var duration = int.Parse(args[5]);
                if (duration < 15 || duration > 300) throw new InvalidOperationException("Invalid capture bound.");
                captureStage = "session-create";
                progress(captureStage);
                using (var capture = new TraceEventSession("TcpChurnExact-" + Guid.NewGuid().ToString("N"), args[1]))
                {
                    capture.StopOnDispose = true;
                    capture.BufferSizeMB = 64;
                    capture.CircularBufferMB = 64;
                    captureStage = "provider-enable";
                    progress(captureStage);
                    capture.EnableProvider(provider, TraceEventLevel.Verbose, keywords,
                        new TraceEventProviderOptions { EventIDsToEnable = ids });
                    captureStage = "ready";
                    File.WriteAllText(args[3], "ready");
                    var deadline = DateTime.UtcNow.AddSeconds(duration);
                    while (!File.Exists(args[4]))
                    {
                        if (DateTime.UtcNow >= deadline) return 4;
                        Thread.Sleep(100);
                    }
                }
                return 0;
            }
            catch (Exception error)
            {
                File.WriteAllText(args[3] + ".failure.json", JsonConvert.SerializeObject(new {
                    schema = 1, outcome = "capture-failed", stage = captureStage,
                    errorType = error.GetType().FullName, errorCode = error.HResult
                }));
                Console.Error.WriteLine("Exact public probe capture failed; inspect its numeric startup diagnostic.");
                return 1;
            }
        }
        if (args.Length == 7 && args[0] == "--events")
        {
            try
            {
                var state = JObject.Parse(File.ReadAllText(args[6]));
                int ownerProcessId = EventProcessFilter(args[3]);
                var provider = Guid.Parse((string)state["publicProviderGuid"]);
                var names = state["publicProviderEvents"].GroupBy(item => (int)item["Id"]).ToDictionary(
                    group => group.Key, group => (string)group.First()["Task"]);
                var counts = names.Values.Distinct().ToDictionary(name => name, name => 0L);
                var startTime = DateTime.Parse(args[4], null, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime();
                var endTime = DateTime.Parse(args[5], null, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime();
                long total = 0;
                using (var source = new ETWTraceEventSource(args[1]))
                {
                    source.AllEvents += record =>
                    {
                        if (record.ProviderGuid != provider) return;
                        if (ownerProcessId != 0 && record.ProcessID != ownerProcessId) return;
                        var time = record.TimeStamp.ToUniversalTime();
                        if (time < startTime || time > endTime) return;
                        total++;
                        if (names.TryGetValue((int)record.ID, out var name)) Add(counts, name);
                    };
                    source.Process();
                    File.WriteAllText(args[2], JsonConvert.SerializeObject(new {
                        schema = 1, outcome = "counted", providerEventsInInterval = total,
                        processFilterApplied = ownerProcessId != 0,
                        publicProbeCounts = counts, eventsLost = source.EventsLost,
                        conclusion = "events-do-not-prove-lock-waiting"
                    }, Formatting.Indented));
                }
                return 0;
            }
            catch { Console.Error.WriteLine("Public event analysis failed."); return 1; }
        }
        if (args.Length == 1 && args[0] == "--self-test")
        {
            if (!SpinLockEvidence.SelfTest()) return 1;
            var counts = new Dictionary<string, long>();
            Add(counts, "public"); Add(counts, "public");
            if (!IsNetwork("tcpip.sys") || IsNetwork("other.sys") || counts["public"] != 2)
                return 1;
            var delayedOutputWait = new[] { "nt!KeYieldProcessorEx", "nt!KxWaitForLockOwnerShipWithIrql",
                "nt!KiAcquireQueuedSpinLockInstrumented", "tcpip!TcpUpdatePathInfoTcb",
                "tcpip!TcpTcbHeaderSend", "tcpip!TcpPeriodicTimeoutHandler" };
            if (!IsPathRefreshWait(delayedOutputWait) || !IsTimerPathRefreshWait(delayedOutputWait) ||
                IsPathRefreshWait(new[] { "nt!KeAcquireInStackQueuedSpinLock", "tcpip!TcpUpdatePathInfoTcb" }) ||
                IsPathRefreshWait(new[] { "tcpip!TcpIsRttSampleInWaitInterval", "tcpip!TcpUpdatePathInfoTcb" }) ||
                IsTimerPathRefreshWait(new[] { "nt!KxWaitForLockOwnerShip", "tcpip!TcpUpdatePathInfoTcb" }))
                return 1;
            if (PeakSampleCount(new long[] { 0, 9, 10, 19 }, 10) != 2 ||
                PeakSampleCount(new long[] { 5, 5, 5 }, 10) != 3 ||
                PeakSampleCount(new long[0], 10) != 0)
                return 1;
            if (EventProcessFilter("interval") != 0 || EventProcessFilter("123") != 123) return 1;
            bool rejectedProcessFilter = false;
            try { EventProcessFilter("0"); } catch (ArgumentException) { rejectedProcessFilter = true; }
            if (!rejectedProcessFilter) return 1;
            Console.WriteLine("CPU analyzer contract checks passed.");
            return 0;
        }
        if (args.Length != 4)
        {
            Console.Error.WriteLine("Usage: CpuSamples trace.etl output.json startUtc endUtc");
            return 2;
        }
        string stage = "open";
        try
        {
            var start = DateTime.Parse(args[2], null, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime();
            var end = DateTime.Parse(args[3], null, System.Globalization.DateTimeStyles.RoundtripKind).ToUniversalTime();
            if (end <= start || File.Exists(args[1])) throw new InvalidOperationException("Invalid interval/output.");
            var folder = Path.GetDirectoryName(Path.GetFullPath(args[0]));
            var cache = Path.Combine(folder, "public-symbols");
            Directory.CreateDirectory(cache);
            using (var diagnostics = File.CreateText(Path.Combine(folder, "symbol-analysis.log")))
            using (var log = TraceLog.OpenOrConvert(args[0], new TraceLogOptions { ConversionLog = diagnostics }))
            using (var symbols = new SymbolReader(diagnostics, "srv*" + cache + "*https://msdl.microsoft.com/download/symbols"))
            {
                // Never consult a private symbol server, symbol path environment, or source server.
                symbols.Options = SymbolReaderOptions.NoNGenSymbolCreation;
                stage = "symbols";
                foreach (var module in log.ModuleFiles)
                {
                    var name = module.Name ?? "";
                    if (IsNetwork(name) || name.Equals("ntoskrnl", StringComparison.OrdinalIgnoreCase) ||
                        name.Equals("ntoskrnl.exe", StringComparison.OrdinalIgnoreCase))
                        log.CodeAddresses.LookupSymbolsForModule(symbols, module);
                }
                var networkFrames = new Dictionary<string, long>();
                var networkStacks = new Dictionary<string, long>();
                var networkLeaves = new Dictionary<string, long>();
                var processors = new HashSet<int>();
                var networkProcessors = new Dictionary<string, long>();
                var timerProcessors = new Dictionary<string, long>();
                var callers = new Dictionary<string, Dictionary<string, long>>();
                stage = "samples";
                long samples = 0, withStack = 0, network = 0, unresolved = 0;
                long pathRefreshWait = 0, timerPathRefreshWait = 0, hypervisorNotifiedPathRefreshWait = 0;
                var timerWaitTicks = new List<long>();
                var pathWaitTicks = new List<long>();
                foreach (var record in log.Events)
                {
                    var sample = record as SampledProfileTraceData;
                    if (sample == null) continue;
                    var utc = sample.TimeStamp.ToUniversalTime();
                    if (utc < start || utc > end) continue;
                    samples++;
                    processors.Add(sample.ProcessorNumber);
                    var stack = sample.CallStack();
                    if (stack == null) continue;
                    withStack++;
                    var frames = new List<string>();
                    var seen = new HashSet<string>();
                    bool hit = false;
                    string leaf = null;
                    for (int depth = 0; stack != null && depth < 128; depth++, stack = stack.Caller)
                    {
                        var address = stack.CodeAddress;
                        var module = address.ModuleFile;
                        var moduleName = module == null ? "" : module.Name ?? "";
                        var method = address.FullMethodName ?? "";
                        bool tcp = IsNetwork(moduleName);
                        if (tcp) hit = true;
                        // Export only names from the two explicitly public-symbol-resolved system modules.
                        bool kernel = moduleName.Equals("ntoskrnl", StringComparison.OrdinalIgnoreCase) ||
                                      moduleName.Equals("ntoskrnl.exe", StringComparison.OrdinalIgnoreCase);
                        if (!tcp && !kernel) continue;
                        if (method.Length == 0 || method.Contains("0x") || method.Contains("\\") || method.Contains("/"))
                        {
                            if (tcp) unresolved++;
                            continue;
                        }
                        var label = (tcp ? "tcpip!" : "nt!") + method;
                        if (depth == 0) leaf = label;
                        frames.Add(label);
                        if (tcp) seen.Add(label);
                    }
                    if (!hit) continue;
                    network++;
                    if (frames.Any(frame => frame.EndsWith("TcpPeriodicTimeoutHandler", StringComparison.Ordinal)))
                        Add(timerProcessors, sample.ProcessorNumber.ToString());
                    Add(networkProcessors, sample.ProcessorNumber.ToString());
                    var publicStack = string.Join(" <- ", frames.Take(24));
                    foreach (var frame in seen)
                    {
                        Add(networkFrames, frame);
                        if (!callers.TryGetValue(frame, out var frameStacks))
                        {
                            frameStacks = new Dictionary<string, long>();
                            callers[frame] = frameStacks;
                        }
                        Add(frameStacks, publicStack);
                    }
                    if (IsPathRefreshWait(frames))
                    {
                        pathRefreshWait++;
                        pathWaitTicks.Add((utc - start).Ticks);
                        if (IsTimerPathRefreshWait(frames))
                        {
                            timerPathRefreshWait++;
                            timerWaitTicks.Add((utc - start).Ticks);
                        }
                        if (frames.Any(frame => frame.EndsWith("!HvlNotifyLongSpinWait", StringComparison.Ordinal)))
                            hypervisorNotifiedPathRefreshWait++;
                    }
                    if (leaf != null) Add(networkLeaves, leaf);
                    if (frames.Count > 0) Add(networkStacks, string.Join(" <- ", frames.Take(24)));
                }
                double profileIntervalMs = log.SampleProfileInterval.TotalMilliseconds;
                if (profileIntervalMs <= 0) throw new InvalidOperationException("A positive profile sampling interval is required.");
                timerWaitTicks.Sort();
                pathWaitTicks.Sort();
                File.WriteAllText(args[1], JsonConvert.SerializeObject(new
                {
                    schema = 1, outcome = samples > 0 ? "sampled" : "no-samples",
                    intervalSeconds = (end - start).TotalSeconds,
                    cpuSamples = samples, samplesWithStacks = withStack,
                    networkModuleSamples = network, unresolvedNetworkFrames = unresolved,
                    publicPathRefreshWaitSamples = pathRefreshWait,
                    publicTimerPathRefreshWaitSamples = timerPathRefreshWait,
                    publicHypervisorNotifiedPathRefreshWaitSamples = hypervisorNotifiedPathRefreshWait,
                    profileIntervalMilliseconds = profileIntervalMs,
                    pathRefreshWaitPeaks = new[] { 10.0, 100.0, 500.0, 620.0 }.Select(window =>
                    {
                        int peak = PeakSampleCount(pathWaitTicks, TimeSpan.FromMilliseconds(window).Ticks);
                        return new { windowMilliseconds = window, samples = peak,
                            sampledWaitingCpuEquivalents = peak * profileIntervalMs / window };
                    }).ToArray(),
                    timerPathRefreshWaitPeaks = new[] { 10.0, 100.0, 500.0, 620.0 }.Select(window =>
                    {
                        int peak = PeakSampleCount(timerWaitTicks, TimeSpan.FromMilliseconds(window).Ticks);
                        return new { windowMilliseconds = window, samples = peak,
                            sampledWaitingCpuEquivalents = peak * profileIntervalMs / window };
                    }).ToArray(),
                    timerWaitPeakConclusion = "sample-density-not-simultaneous-lock-waiter-proof",
                    pathRefreshWaitConclusion = "caller-signature-only-not-lock-address-or-owner-proof",
                    observedProcessorNumbers = processors.OrderBy(value => value).ToArray(),
                    networkSamplesByProcessor = Top(networkProcessors, 4096),
                    timerSamplesByProcessor = Top(timerProcessors, 4096),
                    timerProcessorConclusion = "distinct-across-interval-not-simultaneous-timer-cpus",
                    traceProcessorCount = log.NumberOfProcessors, eventsLost = log.EventsLost,
                    publicNetworkFrames = Top(networkFrames, 4096),
                    publicNetworkStackLeaves = Top(networkLeaves, 50),
                    publicNetworkStacks = Top(networkStacks, 256),
                    publicNetworkSpinStacks = Top(networkStacks.Where(pair =>
                        pair.Key.StartsWith("nt!", StringComparison.Ordinal) &&
                        pair.Key.Split(new[] { " <- " }, StringSplitOptions.None)[0].IndexOf("spin", StringComparison.OrdinalIgnoreCase) >= 0)
                        .ToDictionary(pair => pair.Key, pair => pair.Value), 512),
                    publicNetworkFunctionCallers = callers.OrderBy(pair => pair.Key).Take(4096)
                        .Select(pair => new { function = pair.Key, stacks = Top(pair.Value, 8) }).ToArray(),
                    conclusion = "sample-evidence-only"
                }, Formatting.Indented));
                return samples > 0 ? 0 : 3;
            }
        }
        catch (Exception error)
        {
            File.WriteAllText(args[1], JsonConvert.SerializeObject(new {
                schema = 1, outcome = "analysis-failed", stage,
                errorType = error.GetType().FullName, errorCode = error.HResult,
                errorSite = error.TargetSite == null ? "" : error.TargetSite.DeclaringType.FullName + "." + error.TargetSite.Name
            }));
            // ETL paths/host/process details belong in guest-local diagnostics, not public logs.
            Console.Error.WriteLine("CPU analysis failed; inspect guest-local symbol-analysis.log.");
            return 1;
        }
    }
}
