// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Diagnostics.Symbols;
using Microsoft.Diagnostics.Tracing.Etlx;
using Microsoft.Diagnostics.Tracing.Parsers.Kernel;
using Newtonsoft.Json;

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

    private static object[] Top(Dictionary<string, long> counts, int limit) =>
        counts.OrderByDescending(pair => pair.Value).ThenBy(pair => pair.Key)
            .Take(limit).Select(pair => (object)new { name = pair.Key, samples = pair.Value }).ToArray();

    private static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--self-test")
        {
            var counts = new Dictionary<string, long>();
            Add(counts, "public"); Add(counts, "public");
            if (!IsNetwork("tcpip.sys") || IsNetwork("other.sys") || counts["public"] != 2)
                return 1;
            Console.WriteLine("CPU analyzer contract checks passed.");
            return 0;
        }
        if (args.Length != 4)
        {
            Console.Error.WriteLine("Usage: CpuSamples trace.etl output.json startUtc endUtc");
            return 2;
        }
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
                long samples = 0, withStack = 0, network = 0, unresolved = 0;
                foreach (var sample in log.Events.OfType<SampledProfileTraceData>())
                {
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
                    foreach (var frame in seen) Add(networkFrames, frame);
                    if (leaf != null) Add(networkLeaves, leaf);
                    if (frames.Count > 0) Add(networkStacks, string.Join(" <- ", frames.Take(24)));
                }
                File.WriteAllText(args[1], JsonConvert.SerializeObject(new
                {
                    schema = 1, outcome = samples > 0 ? "sampled" : "no-samples",
                    intervalSeconds = (end - start).TotalSeconds,
                    cpuSamples = samples, samplesWithStacks = withStack,
                    networkModuleSamples = network, unresolvedNetworkFrames = unresolved,
                    observedProcessorNumbers = processors.OrderBy(value => value).ToArray(),
                    traceProcessorCount = log.NumberOfProcessors, eventsLost = log.EventsLost,
                    publicNetworkFrames = Top(networkFrames, 100),
                    publicNetworkStackLeaves = Top(networkLeaves, 50),
                    publicNetworkStacks = Top(networkStacks, 50),
                    conclusion = "sample-evidence-only"
                }, Formatting.Indented));
                return samples > 0 ? 0 : 3;
            }
        }
        catch
        {
            // ETL paths/host/process details belong in guest-local diagnostics, not public logs.
            Console.Error.WriteLine("CPU analysis failed; inspect guest-local symbol-analysis.log.");
            return 1;
        }
    }
}
