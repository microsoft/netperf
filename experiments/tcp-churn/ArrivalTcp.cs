// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading;
using System.Threading.Tasks;
using System.Runtime.InteropServices;

public static class ArrivalTcp
{
    [DllImport("iphlpapi.dll")]
    private static extern uint GetExtendedTcpTable(IntPtr table,ref uint bytes,bool order,int family,int tableClass,uint reserved);
    public static bool IsListenerReady(int processId,int port)
    {
        if(processId<1 || port<1 || port>65535)throw new ArgumentException("Valid listener process and port are required.");
        uint bytes=0;
        uint status=GetExtendedTcpTable(IntPtr.Zero,ref bytes,false,2,3,0);
        if(status!=122 || bytes<4 || bytes>1048576)throw new InvalidOperationException("Cannot size the owned-listener table.");
        IntPtr table=Marshal.AllocHGlobal((int)bytes);
        try {
            status=GetExtendedTcpTable(table,ref bytes,false,2,3,0);
            if(status!=0)throw new InvalidOperationException("Cannot read the owned-listener table.");
            int count=Marshal.ReadInt32(table);
            if(count<0 || count>(bytes-4)/24)throw new InvalidOperationException("Invalid listener-table bounds.");
            for(int i=0;i<count;i++) {
                IntPtr row=IntPtr.Add(table,4+i*24);
                uint encoded=(uint)Marshal.ReadInt32(row,8);
                int localPort=(int)(((encoded&255)<<8)|((encoded>>8)&255));
                if(localPort==port && Marshal.ReadInt32(row,20)==processId)return true;
            }
            return false;
        } finally {Marshal.FreeHGlobal(table);}
    }

    private static long latencyTicks,maximumLatencyTicks;
    private static long bindTicks,connectTicks,responseTicks,eofTicks;
    private static long dispatchTicks,maximumDispatchTicks;
    private static bool noDelay;
    private static int inFlight,peakInFlight,completed,started;
    private static async Task SendWithSlot(SemaphoreSlim capacity,string source,IPAddress peer,int port,byte[] data,byte[] expectedResponse,long queuedAt=0)
    {
        long start=Stopwatch.GetTimestamp();
        if(queuedAt!=0) {
            long delay=start-queuedAt,prior;
            Interlocked.Add(ref dispatchTicks,delay);
            do {prior=Interlocked.Read(ref maximumDispatchTicks);if(delay<=prior)break;}
                while(Interlocked.CompareExchange(ref maximumDispatchTicks,delay,prior)!=prior);
        }
        int active=Interlocked.Increment(ref inFlight);
        Interlocked.Increment(ref started);
        int previous;
        do {previous=peakInFlight;if(active<=previous)break;} while(Interlocked.CompareExchange(ref peakInFlight,active,previous)!=previous);
        try {
            await Send(source,peer,port,data,expectedResponse).ConfigureAwait(false);
            Interlocked.Increment(ref completed);
        }
        finally {
            long elapsed=Stopwatch.GetTimestamp()-start,old;
            Interlocked.Add(ref latencyTicks,elapsed);
            do {old=Interlocked.Read(ref maximumLatencyTicks);if(elapsed<=old)break;}
                while(Interlocked.CompareExchange(ref maximumLatencyTicks,elapsed,old)!=old);
            Interlocked.Decrement(ref inFlight);capacity.Release();
        }
    }
    private static async Task ReadAll(NetworkStream stream,byte[] buffer)
    {
        int offset=0;
        while(offset<buffer.Length) {
            int n=await stream.ReadAsync(buffer,offset,buffer.Length-offset).ConfigureAwait(false);
            if(n==0)throw new IOException("Unexpected EOF.");
            offset+=n;
        }
    }
    private static async Task Serve(TcpClient socket,int size,byte[] response)
    {
        using(socket) {
            socket.NoDelay=noDelay;
            var stream=socket.GetStream();
            byte[] data=new byte[size];
            await ReadAll(stream,data).ConfigureAwait(false);
            for(int i=0;i<data.Length;i++)if(data[i]!=(byte)(i%251))throw new IOException("Data mismatch.");
            await stream.WriteAsync(response,0,response.Length).ConfigureAwait(false);
            socket.Client.Shutdown(SocketShutdown.Send);
            if(await stream.ReadAsync(new byte[1],0,1).ConfigureAwait(false)!=0)
                throw new IOException("Unexpected request data after completion.");
        }
    }
    private static async Task Send(string source,IPAddress peer,int port,byte[] data,byte[] expectedResponse)
    {
        long start=Stopwatch.GetTimestamp();
        using(var socket=new TcpClient(new IPEndPoint(IPAddress.Parse(source),0))) {
            long bound=Stopwatch.GetTimestamp();Interlocked.Add(ref bindTicks,bound-start);
            socket.NoDelay=noDelay;
            await socket.ConnectAsync(peer,port).ConfigureAwait(false);
            long connected=Stopwatch.GetTimestamp();Interlocked.Add(ref connectTicks,connected-bound);
            await socket.GetStream().WriteAsync(data,0,data.Length).ConfigureAwait(false);
            var reply=new byte[expectedResponse.Length];
            await ReadAll(socket.GetStream(),reply).ConfigureAwait(false);
            for(int i=0;i<reply.Length;i++)if(reply[i]!=expectedResponse[i])throw new IOException("Reply mismatch.");
            long received=Stopwatch.GetTimestamp();Interlocked.Add(ref responseTicks,received-connected);
            if(await socket.GetStream().ReadAsync(new byte[1],0,1).ConfigureAwait(false)!=0)
                throw new IOException("Unexpected response data after completion.");
            Interlocked.Add(ref eofTicks,Stopwatch.GetTimestamp()-received);
        }
    }
    private static async Task Run(string[] args)
    {
        string[] sources=args[0].Split(',');
        string[] peerTexts=args[1].Split(',');
        var peers=new IPAddress[peerTexts.Length];
        for(int i=0;i<peers.Length;i++)peers[i]=IPAddress.Parse(peerTexts[i]);
        var peer=peers[0];
        string role=args.Length>=8?args[7]:"local";
        if(role!="local" && role!="client" && role!="server")throw new ArgumentException("Unknown workload role.");
        if(peers.Length>8 || (peers.Length>1 && (role!="client" || peers.Length!=sources.Length)))
            throw new ArgumentException("Multiple peers require client role and one aligned source address per peer.");
        int port=int.Parse(args[2]),count=int.Parse(args[3]),rate=int.Parse(args[4]),size=int.Parse(args[5]);
        int responseSize=args.Length>=9?int.Parse(args[8]):1;
        int seed=args.Length>=10?int.Parse(args[9]):14529;
        int concurrency=args.Length>=11?int.Parse(args[10]):256;
        if(args.Length>=12 && args[11]!="nodelay" && args[11]!="nagle")throw new ArgumentException("Unknown socket pacing.");
        noDelay=args.Length>=12 && args[11]=="nodelay";
        if(count<1||count>8192||rate<1||rate>10000||size<1||size>1048576||responseSize<1||responseSize>1048576||port<1024||port>65535||
            sources.Length<1||sources.Length>8||(double)count/rate>120||concurrency<1||concurrency>1024)
            throw new ArgumentException("Invalid bounded arrival workload.");
        int gcHeapMiB=0,gcMinimumLaunch=0;
        if(args.Length==13) {
            string[] gc=args[12].Split(':');
            if(gc.Length!=3 || gc[0]!="gc" || role!="client" ||
                !int.TryParse(gc[1],out gcHeapMiB) || !int.TryParse(gc[2],out gcMinimumLaunch) ||
                gcHeapMiB<16 || gcHeapMiB>1024 || gcMinimumLaunch<1 || gcMinimumLaunch>=count)
                throw new ArgumentException("GC mode requires client role and gc:heap-MiB:minimum-launched, with 16-1024 MiB and a trigger before the final request.");
        }
        if(File.Exists(args[6]))throw new IOException("Use a new result file.");
        TcpListener listener=null;
        try {
            byte[] response=new byte[responseSize];
            for(int i=0;i<response.Length;i++)response[i]=(byte)(i%251);
            if(responseSize==1)response[0]=0x5a;
            Task receiver=null;
            if(role!="client") {
                listener=new TcpListener(peer,port);listener.Start(8192);
                receiver=Task.Run(async delegate {
                    var accepted=new List<Task>();
                    for(int i=0;i<count;i++)accepted.Add(Serve(await listener.AcceptTcpClientAsync().ConfigureAwait(false),size,response));
                    await Task.WhenAll(accepted).ConfigureAwait(false);
                });
            }
            if(role=="server") {
                if(File.Exists(args[6]+".ready"))throw new IOException("Use a new ready file.");
                File.WriteAllText(args[6]+".ready","listening");
                await receiver.ConfigureAwait(false);
                File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"role\":\"server\",\"connections\":"+count+
                    ",\"bytesReceived\":"+((long)count*size)+",\"bytesSent\":"+((long)count*responseSize)+
                    ",\"networkErrors\":0,\"protocolErrors\":0,\"barrier\":false}");
                return;
            }
            byte[][] pressureHeap=null;
            if(gcHeapMiB>0) {
                pressureHeap=new byte[gcHeapMiB*1024][];
                for(int i=0;i<pressureHeap.Length;i++)pressureHeap[i]=new byte[1024];
                GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
                for(int i=0;i<pressureHeap.Length;i+=2)pressureHeap[i]=null;
            }
            byte[] data=new byte[size];for(int i=0;i<size;i++)data[i]=(byte)(i%251);
            if(gcHeapMiB>0)File.WriteAllText(args[6]+".traffic-ready",DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture));
            var senders=new List<Task>();var random=new Random(seed);var clock=Stopwatch.StartNew();
            double next=0,maxLag=0,totalLag=0,lastLaunch=0;
            bool gcTriggered=false;int gcLaunched=0,gcStarted=0,gcCompleted=0,gcPending=0,gcBefore=0,gcAfter=0;
            double gcMilliseconds=0;string gcStart="",gcEnd="";
            using(var capacity=new SemaphoreSlim(concurrency)) {
            for(int i=0;i<count;i++) {
                int delay=(int)Math.Ceiling(next-clock.Elapsed.TotalMilliseconds);
                if(delay>0)await Task.Delay(delay).ConfigureAwait(false);
                await capacity.WaitAsync().ConfigureAwait(false);
                double lag=Math.Max(0,clock.Elapsed.TotalMilliseconds-next);
                maxLag=Math.Max(maxLag,lag);totalLag+=lag;lastLaunch=clock.Elapsed.TotalMilliseconds;
                string requestSource=sources[i%sources.Length];IPAddress targetPeer=peers[i%peers.Length];
                if(gcHeapMiB>0) {
                    long queuedAt=Stopwatch.GetTimestamp();
                    senders.Add(Task.Run(()=>SendWithSlot(capacity,requestSource,targetPeer,port,data,response,queuedAt)));
                } else {
                    senders.Add(SendWithSlot(capacity,requestSource,targetPeer,port,data,response));
                }
                if(gcHeapMiB>0 && !gcTriggered && i+1>=gcMinimumLaunch) {
                    int completedNow=Volatile.Read(ref completed),pendingNow=Volatile.Read(ref inFlight);
                    if(completedNow>0 && pendingNow>0) {
                        gcLaunched=i+1;gcStarted=Volatile.Read(ref started);gcCompleted=completedNow;gcPending=pendingNow;
                        gcBefore=GC.CollectionCount(GC.MaxGeneration);
                        gcStart=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
                        var collection=Stopwatch.StartNew();
                        GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
                        collection.Stop();gcMilliseconds=collection.Elapsed.TotalMilliseconds;
                        gcEnd=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
                        gcAfter=GC.CollectionCount(GC.MaxGeneration);gcTriggered=true;
                    }
                }
                next+=-Math.Log(1.0-random.NextDouble())*1000.0/rate;
            }
            await Task.WhenAll(senders).ConfigureAwait(false);
            }
            if(receiver!=null)await receiver.ConfigureAwait(false);
            clock.Stop();
            GC.KeepAlive(pressureHeap);
            if(gcHeapMiB>0 && (!gcTriggered || gcAfter<=gcBefore))
                throw new InvalidOperationException("The requested full GC did not overlap completed and in-flight requests.");
            string gcJson="{\"enabled\":"+(gcTriggered?"true":"false")+
                ",\"heapMiB\":"+gcHeapMiB+",\"launchedAtCollection\":"+gcLaunched+
                ",\"startedBeforeCollection\":"+gcStarted+",\"completedBeforeCollection\":"+gcCompleted+",\"inFlightBeforeCollection\":"+gcPending+
                ",\"gen2CollectionsBefore\":"+gcBefore+",\"gen2CollectionsAfter\":"+gcAfter+
                ",\"blockingCollectionMilliseconds\":"+gcMilliseconds.ToString("R",CultureInfo.InvariantCulture)+
                ",\"collectionStartUtc\":\""+gcStart+"\",\"collectionEndUtc\":\""+gcEnd+
                "\",\"serverGc\":"+(System.Runtime.GCSettings.IsServerGC?"true":"false")+"}";
            var targetJson=new List<string>();
            for(int i=0;i<peers.Length;i++) {
                int requests=count/peers.Length+(i<count%peers.Length?1:0);
                targetJson.Add("{\"index\":"+i+",\"loopback\":"+(IPAddress.IsLoopback(peers[i])?"true":"false")+
                    ",\"connections\":"+requests+",\"requestBytes\":"+((long)requests*size)+
                    ",\"responseBytes\":"+((long)requests*responseSize)+"}");
            }
            File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"connections\":"+count+
                ",\"bytesSent\":"+((long)count*size)+",\"networkErrors\":0,\"protocolErrors\":0,\"milliseconds\":"+clock.ElapsedMilliseconds+
                ",\"bytesReceived\":"+((long)count*responseSize)+
                ",\"arrivalRate\":"+rate+",\"seed\":"+seed+",\"barrier\":false"+
                ",\"arrivalDispatch\":\""+(gcHeapMiB>0?"thread-pool":"inline")+"\""+
                ",\"meanDispatchQueueMilliseconds\":"+(1000.0*dispatchTicks/Stopwatch.Frequency/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"maxDispatchQueueMilliseconds\":"+(1000.0*maximumDispatchTicks/Stopwatch.Frequency).ToString("R",CultureInfo.InvariantCulture)+
                ",\"maxLaunchLagMilliseconds\":"+maxLag.ToString("R",CultureInfo.InvariantCulture)+
                ",\"meanLaunchLagMilliseconds\":"+(totalLag/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"launchSpanMilliseconds\":"+lastLaunch.ToString("R",CultureInfo.InvariantCulture)+",\"role\":\""+role+"\",\"maximumInFlight\":"+concurrency+
                ",\"peakInFlight\":"+peakInFlight+
                ",\"meanRequestMilliseconds\":"+(1000.0*latencyTicks/Stopwatch.Frequency/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"meanBindMilliseconds\":"+(1000.0*bindTicks/Stopwatch.Frequency/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"meanConnectMilliseconds\":"+(1000.0*connectTicks/Stopwatch.Frequency/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"meanResponseMilliseconds\":"+(1000.0*responseTicks/Stopwatch.Frequency/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"meanEofMilliseconds\":"+(1000.0*eofTicks/Stopwatch.Frequency/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"noDelay\":"+(noDelay?"true":"false")+
                ",\"managedGc\":"+gcJson+
                ",\"targets\":["+string.Join(",",targetJson)+"]"+
                ",\"maximumRequestMilliseconds\":"+(1000.0*maximumLatencyTicks/Stopwatch.Frequency).ToString("R",CultureInfo.InvariantCulture)+"}");
        } finally {if(listener!=null)listener.Stop();}
    }
    private static int Main(string[] args)
    {
        try {
            if(args.Length<7 || args.Length>13) {
                Console.Error.WriteLine("Usage: ArrivalTcp sources peer port count rate request-bytes output.json [role [response-bytes [seed [maximum-in-flight [nodelay|nagle [gc:heap-MiB:minimum-launched]]]]]]");
                return 2;
            }
            if(!Run(args).Wait(TimeSpan.FromSeconds(150))){Console.Error.WriteLine("Arrival workload deadline exceeded.");return 3;}
            return 0;
        }catch(Exception error){Console.Error.WriteLine(error.GetBaseException().ToString());return 1;}
    }
}
