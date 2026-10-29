// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using Microsoft.Diagnostics.Symbols;
using Microsoft.Diagnostics.Tracing;
using Microsoft.Diagnostics.Tracing.Etlx;
using Newtonsoft.Json;

internal static class SpinLockEvidence
{
    private sealed class Record
    {
        internal ulong Address, Caller, Acquire, Release;
        internal uint Wait, Spins, Interrupts;
        internal int Cpu;
        internal byte Irql;
    }

    // The installed public Thread_V2/SpinLock MOF schema: opcode 41, x64 payload 56 bytes.
    private static Record Decode(byte[] data, int cpu)
    {
        if (data.Length != 56) throw new InvalidOperationException("Unexpected x64 spinlock payload size.");
        var value = new Record {
            Address = BitConverter.ToUInt64(data, 0), Caller = BitConverter.ToUInt64(data, 8),
            Acquire = BitConverter.ToUInt64(data, 16), Release = BitConverter.ToUInt64(data, 24),
            Wait = BitConverter.ToUInt32(data, 32), Spins = BitConverter.ToUInt32(data, 36),
            Interrupts = BitConverter.ToUInt32(data, 44), Irql = data[48], Cpu = cpu
        };
        if (value.Address == 0 || value.Release < value.Acquire || value.Acquire < value.Wait)
            throw new InvalidOperationException("Invalid spinlock timing or address.");
        return value;
    }

    private static int Peak(IEnumerable<Record> records, bool uninterrupted)
    {
        var points = new List<Tuple<ulong, int, int>>();
        foreach (var value in records)
        {
            if (value.Wait == 0 || (uninterrupted && (value.Interrupts != 0 || value.Irql < 2 || value.Spins == 0)))
                continue;
            points.Add(Tuple.Create(value.Acquire - value.Wait, value.Cpu, 1));
            points.Add(Tuple.Create(value.Acquire, value.Cpu, -1));
        }
        var active = new Dictionary<int, int>();
        int peak = 0;
        foreach (var point in points.OrderBy(value => value.Item1).ThenBy(value => value.Item3))
        {
            active.TryGetValue(point.Item2, out int count);
            count += point.Item3;
            if (count < 0) throw new InvalidOperationException("Unbalanced spinlock intervals.");
            if (count == 0) active.Remove(point.Item2); else active[point.Item2] = count;
            peak = Math.Max(peak, active.Count);
        }
        return peak;
    }

    internal static bool SelfTest()
    {
        var data = new byte[56];
        Buffer.BlockCopy(BitConverter.GetBytes(0x1234UL), 0, data, 0, 8);
        Buffer.BlockCopy(BitConverter.GetBytes(0x5678UL), 0, data, 8, 8);
        Buffer.BlockCopy(BitConverter.GetBytes(1000UL), 0, data, 16, 8);
        Buffer.BlockCopy(BitConverter.GetBytes(1100UL), 0, data, 24, 8);
        Buffer.BlockCopy(BitConverter.GetBytes(50U), 0, data, 32, 4);
        Buffer.BlockCopy(BitConverter.GetBytes(2U), 0, data, 36, 4);
        data[48] = 2;
        var first = Decode(data, 0);
        var second = Decode(data, 1);
        second.Acquire = 1020;
        var sameCpu = Decode(data, 0);
        var interrupted = Decode(data, 2);
        interrupted.Interrupts = 1;
        return first.Wait == 50 && first.Caller == 0x5678 && first.Irql == 2 &&
            Peak(new[] { first, second, sameCpu, interrupted }, false) == 3 &&
            Peak(new[] { first, second, sameCpu, interrupted }, true) == 2;
    }

    internal static int Run(string traceFile, string output, string startText, string endText)
    {
        string stage = "input";
        int observedVersion = -1, observedPointerSize = 0, observedPayloadBytes = 0;
        try
        {
            if (File.Exists(output)) throw new IOException("Use a fresh spinlock summary.");
            var start = DateTime.Parse(startText, null, DateTimeStyles.RoundtripKind).ToUniversalTime();
            var end = DateTime.Parse(endText, null, DateTimeStyles.RoundtripKind).ToUniversalTime();
            if (end <= start) throw new ArgumentException("A positive workload interval is required.");
            var directory = Path.GetDirectoryName(Path.GetFullPath(traceFile));
            var cache = Path.Combine(directory, "public-symbols");
            using (var diagnostics = File.CreateText(Path.Combine(directory, "spinlock-symbols.log")))
            using (var trace = TraceLog.OpenOrConvert(traceFile, new TraceLogOptions { ConversionLog = diagnostics }))
            using (var reader = new SymbolReader(diagnostics, "srv*" + cache + "*https://msdl.microsoft.com/download/symbols"))
            {
                reader.Options = SymbolReaderOptions.NoNGenSymbolCreation;
                var module = trace.ModuleFiles.First(value =>
                    value.Name.Equals("tcpip", StringComparison.OrdinalIgnoreCase) ||
                    value.Name.Equals("tcpip.sys", StringComparison.OrdinalIgnoreCase));
                trace.CodeAddresses.LookupSymbolsForModule(reader, module);
                var pdbName = Path.GetFileName(module.PdbName);
                var pdb = Path.Combine(cache, pdbName,
                    module.PdbSignature.ToString("N").ToUpperInvariant() + module.PdbAge.ToString(CultureInfo.InvariantCulture), pdbName);
                using (var symbols = reader.OpenSymbolFile(pdb) as NativeSymbolModule)
                {
                    if (symbols == null || symbols.PdbGuid != module.PdbSignature || symbols.PdbAge != module.PdbAge)
                        throw new InvalidOperationException("Exact public TCP PDB identity did not verify.");
                    var records = new List<Record>();
                    long spinEvents = 0, losses;
                    var threadGuid = Guid.Parse("3d6fa8d1-fe05-11d0-9dda-00c04fd7ba7c");
                    stage = "raw-spinlock-events";
                    using (var source = new ETWTraceEventSource(traceFile))
                    {
                        source.AllEvents += item =>
                        {
                            if ((int)item.Opcode != 41 || (item.ProviderGuid != threadGuid && item.TaskGuid != threadGuid))
                                return;
                            var utc = item.TimeStamp.ToUniversalTime();
                            if (utc < start || utc > end) return;
                            spinEvents++;
                            observedVersion = item.Version; observedPointerSize = item.PointerSize; observedPayloadBytes = item.EventDataLength;
                            if (item.PointerSize != 8 || item.Version != 2)
                                throw new InvalidOperationException("Unexpected spinlock pointer size or MOF version.");
                            var value = Decode(item.EventData(), item.ProcessorNumber);
                            if (value.Caller < module.ImageBase || value.Caller >= module.ImageEnd) return;
                            if (records.Count >= 2000000) throw new InvalidOperationException("TCP spinlock record bound exceeded.");
                            records.Add(value);
                        };
                        source.Process();
                        losses = source.EventsLost;
                    }
                    if (losses != 0 || trace.EventsLost != 0)
                        throw new InvalidOperationException("Lossless kernel lock evidence is required.");
                    var names = new Dictionary<ulong, string>();
                    foreach (var caller in records.Select(value => value.Caller).Distinct())
                    {
                        uint symbolRva = 0;
                        var name = symbols.FindNameForRva(checked((uint)(caller - module.ImageBase)), ref symbolRva);
                        if (string.IsNullOrEmpty(name) || name.Contains("\\") || name.Contains("/") || name.Contains("0x"))
                            throw new InvalidOperationException("A TCP release site did not resolve to a public symbol.");
                        names.Add(caller, name);
                    }
                    int ordinal = 0;
                    var locks = records.GroupBy(value => value.Address).OrderByDescending(group => group.Sum(value => (double)value.Wait))
                        .Take(32).Select(group =>
                        {
                            var sites = group.GroupBy(value => names[value.Caller]).Select(site =>
                                new { function = site.Key, events = site.Count(), maximumHoldCycles = site.Max(value => value.Release - value.Acquire) }).ToArray();
                            bool readerSite = sites.Any(site => site.function.Contains("IppGetNextHopFromPath") ||
                                site.function.Contains("TcpUpdatePathInfoTcb") || site.function.Contains("IppValidatePath"));
                            bool writerSite = sites.Any(site => site.function.Contains("IppGarbageCollectPaths"));
                            return new { lockOrdinal = ++ordinal, events = group.Count(), positiveWaits = group.Count(value => value.Wait > 0),
                                peakRecordedWaitingCpus = Peak(group, false),
                                peakUninterruptedDispatchLevelWaitingCpus = Peak(group, true),
                                pathRefreshAndGarbageCollectorShareLock = readerSite && writerSite, publicReleaseSites = sites };
                        }).ToArray();
                    File.WriteAllText(output, JsonConvert.SerializeObject(new {
                        schema = 1, outcome = spinEvents > 0 ? "decoded" : "no-spinlock-records",
                        eventsLost = losses, rawSpinlockEvents = spinEvents, tcpReleaseSiteEvents = records.Count, locks,
                        addressExported = false, symbolSource = "exact-public-tcp-pdb",
                        conclusion = "same-address-raw-cycle-overlap-not-scheduled-cpu-time"
                    }, Formatting.Indented));
                    return spinEvents > 0 ? 0 : 3;
                }
            }
        }
        catch (Exception error)
        {
            File.WriteAllText(output, JsonConvert.SerializeObject(new {
                schema = 1, outcome = "analysis-failed", stage, observedVersion, observedPointerSize, observedPayloadBytes,
                errorType = error.GetType().FullName, errorCode = error.HResult
            }));
            return 1;
        }
    }
}
