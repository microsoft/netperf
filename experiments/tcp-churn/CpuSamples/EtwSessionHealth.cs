// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Microsoft.Diagnostics.Tracing.Session;
using Newtonsoft.Json;

internal static class EtwSessionHealth
{
    internal static int Run(string output)
    {
        try
        {
            if (File.Exists(output)) throw new IOException("Use a fresh collector health output.");
            var collectors = new List<object>();
            foreach (string name in TraceEventSession.GetActiveSessionNames()
                .Where(value => value.StartsWith("WPR_initiated_", StringComparison.OrdinalIgnoreCase)))
            {
                var session = TraceEventSession.GetActiveSession(name);
                if (session == null) throw new InvalidOperationException("An active WPR collector disappeared.");
                session.StopOnDispose = false;
                try
                {
                    int lost = session.EventsLost;
                    if (lost < 0) throw new InvalidOperationException("A collector returned an invalid loss counter.");
                    string label = name.Replace('_', ' ').ToLowerInvariant();
                    string kind = label.Contains("tcpchurn gc events") ? "exact-tcp-clr" :
                        label.Contains("system collector") ? "sampled-system" : "other-wpr";
                    collectors.Add(new { collectorOrdinal = collectors.Count + 1, kind, eventsLost = lost });
                }
                finally { session.Dispose(); }
            }
            if (collectors.Count == 0) throw new InvalidOperationException("No active WPR collectors were found.");
            File.WriteAllText(output, JsonConvert.SerializeObject(new {
                schema = 1, outcome = "queried", readOnly = true, collectors,
                sessionNamesExported = false, conclusion = "active-collector-loss-before-stop"
            }, Formatting.Indented));
            return 0;
        }
        catch (Exception error)
        {
            if (!File.Exists(output))
                File.WriteAllText(output, JsonConvert.SerializeObject(new {
                    schema = 1, outcome = "failed", failureType = error.GetType().FullName,
                    failureCode = error.HResult, sessionNamesExported = false
                }, Formatting.Indented));
            return 1;
        }
    }
}
