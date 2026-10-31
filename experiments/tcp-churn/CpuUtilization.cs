// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Runtime.InteropServices;

internal static class CpuUtilization
{
    [StructLayout(LayoutKind.Sequential)]
    private struct CounterValue { public uint Status; public double Value; }
    [StructLayout(LayoutKind.Sequential)]
    private struct CounterItem { public IntPtr Name; public CounterValue Value; }
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)]
    private static extern uint PdhOpenQueryW(string source,UIntPtr user,out IntPtr query);
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)]
    private static extern uint PdhAddEnglishCounterW(IntPtr query,string path,UIntPtr user,out IntPtr counter);
    [DllImport("pdh.dll",ExactSpelling=true)]
    private static extern uint PdhCollectQueryDataWithTime(IntPtr query,out long timestamp);
    [DllImport("pdh.dll",CharSet=CharSet.Unicode)]
    private static extern uint PdhGetFormattedCounterArrayW(IntPtr counter,uint format,ref uint bytes,out uint count,IntPtr items);
    [DllImport("pdh.dll",ExactSpelling=true)]
    private static extern uint PdhCloseQuery(IntPtr query);

    private static void Check(uint status)
    {
        if(status!=0)throw new InvalidOperationException("PDH status 0x"+status.ToString("X8",CultureInfo.InvariantCulture));
    }

    private static Dictionary<string,double> ReadValues(IntPtr counter)
    {
        uint bytes=0,count;
        uint status=PdhGetFormattedCounterArrayW(counter,0x200,ref bytes,out count,IntPtr.Zero);
        if(status!=0x800007d2 || bytes==0 || bytes>1048576)throw new InvalidOperationException("Invalid PDH array sizing.");
        IntPtr buffer=Marshal.AllocHGlobal((int)bytes);
        try {
            Check(PdhGetFormattedCounterArrayW(counter,0x200,ref bytes,out count,buffer));
            int stride=Marshal.SizeOf(typeof(CounterItem));
            if(count>bytes/(uint)stride)throw new InvalidOperationException("PDH item count exceeds the allocated array.");
            var values=new Dictionary<string,double>(StringComparer.Ordinal);
            for(uint i=0;i<count;i++) {
                var item=(CounterItem)Marshal.PtrToStructure(IntPtr.Add(buffer,checked((int)i*stride)),typeof(CounterItem));
                string name=Marshal.PtrToStringUni(item.Name);
                if(!Regex.IsMatch(name,@"^\d+,\d+$"))continue;
                if(item.Value.Status>1 || double.IsNaN(item.Value.Value) || double.IsInfinity(item.Value.Value))
                    throw new InvalidOperationException("Invalid formatted processor counter "+name+" status=0x"+
                        item.Value.Status.ToString("X8",CultureInfo.InvariantCulture)+" value="+item.Value.Value.ToString("R",CultureInfo.InvariantCulture));
                values.Add(name,item.Value.Value);
            }
            if(values.Count==0)throw new InvalidOperationException("No group-aware logical processor counters.");
            return values;
        } finally {Marshal.FreeHGlobal(buffer);}
    }

    private static int Main(string[] args)
    {
        IntPtr query=IntPtr.Zero;
        try {
            if(args.Length!=4 && args.Length!=5) {
                Console.Error.WriteLine("Usage: CpuUtilization output.json ready-file stop-file seconds [interval-ms]");
                return 2;
            }
            string output=args[0],ready=args[1],stop=args[2];
            int seconds=int.Parse(args[3],CultureInfo.InvariantCulture);
            int interval=args.Length==5?int.Parse(args[4],CultureInfo.InvariantCulture):1000;
            if(seconds<5||seconds>300||interval<1000||interval>10000||File.Exists(output)||File.Exists(ready)||File.Exists(stop))
                throw new ArgumentException("Fresh files and a bounded collection are required.");
            IntPtr counter;
            Check(PdhOpenQueryW(null,UIntPtr.Zero,out query));
            Check(PdhAddEnglishCounterW(query,@"\Processor Information(*)\% Processor Time",UIntPtr.Zero,out counter));
            long timestamp;
            // Keep provider timestamps opaque; bounded UTC brackets align the coherent query with ETW.
            DateTime queryStart=DateTime.UtcNow;
            Check(PdhCollectQueryDataWithTime(query,out timestamp));
            DateTime queryEnd=DateTime.UtcNow;
            double maximumQueryMilliseconds=0;
            string[] names=null;
            var rows=new List<string>();var clock=Stopwatch.StartNew();
            if(queryEnd<queryStart)throw new InvalidOperationException("UTC moved backwards during counter priming.");
            string previous=queryStart.AddTicks((queryEnd-queryStart).Ticks/2).ToString("o",CultureInfo.InvariantCulture);
            bool readyWritten=false;
            while(!File.Exists(stop) && clock.Elapsed.TotalSeconds<seconds) {
                Thread.Sleep(interval);
                queryStart=DateTime.UtcNow;
                Check(PdhCollectQueryDataWithTime(query,out timestamp));
                queryEnd=DateTime.UtcNow;
                double queryMilliseconds=(queryEnd-queryStart).TotalMilliseconds;
                if(queryEnd<queryStart || (readyWritten && queryMilliseconds>100))throw new InvalidOperationException("PDH timestamp bracket is too uncertain.");
                string end=queryStart.AddTicks((queryEnd-queryStart).Ticks/2).ToString("o",CultureInfo.InvariantCulture);
                var values=ReadValues(counter);
                var currentNames=values.Keys.OrderBy(name=>name,StringComparer.Ordinal).ToArray();
                if(names==null)names=currentNames;
                else if(!names.SequenceEqual(currentNames))throw new InvalidOperationException("Processor topology changed during collection.");
                if(!readyWritten) {
                    previous=end;File.WriteAllText(ready,"ready");readyWritten=true;continue;
                }
                maximumQueryMilliseconds=Math.Max(maximumQueryMilliseconds,queryMilliseconds);
                rows.Add("{\"startUtc\":\""+previous+"\",\"endUtc\":\""+end+
                    "\",\"queryStartUtc\":\""+queryStart.ToString("o",CultureInfo.InvariantCulture)+
                    "\",\"queryEndUtc\":\""+queryEnd.ToString("o",CultureInfo.InvariantCulture)+
                    "\",\"providerTimestampRaw\":\""+timestamp.ToString(CultureInfo.InvariantCulture)+"\",\"percentBusy\":["+
                    string.Join(",",names.Select(name=>values[name].ToString("R",CultureInfo.InvariantCulture)))+"]}");
                previous=end;
            }
            bool stopped=File.Exists(stop);
            if(names==null || rows.Count==0)throw new InvalidOperationException("No complete measured processor snapshot.");
            File.WriteAllText(output,"{\"schema\":1,\"outcome\":\""+(stopped?"collected":"deadline")+
                "\",\"counter\":\"Processor Information/% Processor Time\",\"snapshot\":\"coherent-pdh-query\",\"timestampSource\":\"Utc-bracketed-PdhCollectQueryDataWithTime\""+
                ",\"maximumQueryMilliseconds\":"+maximumQueryMilliseconds.ToString("R",CultureInfo.InvariantCulture)+
                ",\"requestedIntervalMilliseconds\":"+interval+",\"instances\":["+
                string.Join(",",names.Select(name=>"\""+name+"\""))+"],\"intervals\":["+string.Join(",",rows)+"]}");
            return stopped?0:3;
        }catch(Exception error){Console.Error.WriteLine(error.ToString());return 1;}
        finally {if(query!=IntPtr.Zero)PdhCloseQuery(query);}
    }
}
