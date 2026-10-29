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
    [DllImport("iphlpapi.dll")]
    private static extern uint GetIpPathTable(ushort family,out IntPtr table);
    [DllImport("iphlpapi.dll")]
    private static extern void FreeMibTable(IntPtr table);
    [StructLayout(LayoutKind.Explicit,Size=28)]
    private struct SockaddrInet
    {
        [FieldOffset(0)]public ushort Family;
        [FieldOffset(4)]public uint Ipv4;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IpPathRow
    {
        public SockaddrInet Source,Destination;
        public ulong InterfaceLuid;
        public uint InterfaceIndex;
        public SockaddrInet NextHop;
        public uint PathMtu,RttMean,RttDeviation,LastReachable;
        public byte IsReachable;
        public ulong TransmitSpeed,ReceiveSpeed;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IpPathTable
    {
        public uint Count;
        public IpPathRow FirstRow;
    }
    public static int CountIpv4Paths(int interfaceIndex,string sourceAddress)
    {
        double queryMilliseconds,scanMilliseconds;
        return CountIpv4Paths(interfaceIndex,sourceAddress,out queryMilliseconds,out scanMilliseconds);
    }
    public static int CountIpv4Paths(int interfaceIndex,string sourceAddress,out double queryMilliseconds,out double scanMilliseconds)
    {
        return CountIpv4PathsForSources(interfaceIndex,new[]{sourceAddress},out queryMilliseconds,out scanMilliseconds);
    }
    public static int CountIpv4PathsForSources(int interfaceIndex,string[] sourceAddresses,out double queryMilliseconds,out double scanMilliseconds)
    {
        queryMilliseconds=0;scanMilliseconds=0;
        if(interfaceIndex<1 || sourceAddresses==null || sourceAddresses.Length==0)
            throw new ArgumentException("IPv4 sources and an interface index are required.");
        var sourceValues=new HashSet<uint>();
        foreach(string address in sourceAddresses){
            IPAddress source;
            if(!IPAddress.TryParse(address,out source) || source.AddressFamily!=AddressFamily.InterNetwork ||
                !sourceValues.Add(BitConverter.ToUInt32(source.GetAddressBytes(),0)))
                throw new ArgumentException("Distinct IPv4 source addresses are required.");
        }
        IntPtr table;
        var clock=Stopwatch.StartNew();
        uint status=GetIpPathTable(2,out table);
        queryMilliseconds=clock.Elapsed.TotalMilliseconds;
        if(status!=0)throw new InvalidOperationException("Cannot read the IPv4 path table: "+status);
        if(table==IntPtr.Zero)throw new InvalidOperationException("The IPv4 path table is missing.");
        try {
            clock.Restart();
            int count=Marshal.ReadInt32(table);
            if(count<0 || count>1000000)throw new InvalidOperationException("Invalid IPv4 path-table bounds.");
            int stride=Marshal.SizeOf(typeof(IpPathRow));
            int offset=Marshal.OffsetOf(typeof(IpPathTable),"FirstRow").ToInt32();
            if(stride!=136 || offset!=8)throw new InvalidOperationException("The documented x64 IP-path layout did not verify.");
            int destinationOffset=Marshal.OffsetOf(typeof(IpPathRow),"Destination").ToInt32();
            int indexOffset=Marshal.OffsetOf(typeof(IpPathRow),"InterfaceIndex").ToInt32();
            int addressOffset=Marshal.OffsetOf(typeof(SockaddrInet),"Ipv4").ToInt32();
            int matched=0;
            for(int i=0;i<count;i++){
                IntPtr row=IntPtr.Add(table,offset+i*stride);
                if(Marshal.ReadInt16(row)!=2 || Marshal.ReadInt16(row,destinationOffset)!=2)
                    throw new InvalidOperationException("Unexpected address family in the IPv4 path table.");
                if(Marshal.ReadInt32(row,indexOffset)==interfaceIndex && sourceValues.Contains((uint)Marshal.ReadInt32(row,addressOffset)))matched++;
            }
            scanMilliseconds=clock.Elapsed.TotalMilliseconds;
            return matched;
        }finally{FreeMibTable(table);}
    }
    public static UdpClient[] CreateIdlePathSockets(string sourceAddress,int count,int[] occupiedPorts)
    {
        if((sourceAddress!="198.19.0.1" && sourceAddress!="198.19.0.2") ||
            (count!=1 && count!=1024 && count!=8192 && count!=24576) || occupiedPorts==null)
            throw new ArgumentException("Only a bounded owned path-retirement fixture is supported.");
        var source=IPAddress.Parse(sourceAddress);
        var occupied=new HashSet<int>(occupiedPorts);
        var sockets=new List<UdpClient>(count);
        int port=10000;
        try {
            for(int i=1;i<=count;i++){
                while(occupied.Contains(port))port++;
                if(port>65535)throw new InvalidOperationException("The explicit UDP-port budget was exhausted.");
                var socket=new UdpClient(new IPEndPoint(source,port++));
                sockets.Add(socket);
                var destination=new IPAddress(new byte[]{198,19,(byte)(31+i/256),(byte)(i%256)});
                socket.Connect(destination,9);
            }
            return sockets.ToArray();
        }catch{
            ReleaseIdlePathSockets(sockets);
            throw;
        }
    }
    public static void ReleaseIdlePathSockets(IEnumerable<UdpClient> sockets)
    {
        if(sockets==null)throw new ArgumentNullException("sockets");
        Parallel.ForEach(sockets,new ParallelOptions{MaxDegreeOfParallelism=Environment.ProcessorCount},socket=>socket.Dispose());
    }
    public static bool IsListenerReady(int processId,int port)
    {
        return CountOwnedTcpRows(processId,port,true)>0;
    }
    public static int CountEstablishedConnections(int processId,int port)
    {
        return CountOwnedTcpRows(processId,port,false);
    }
    private static int CountOwnedTcpRows(int processId,int port,bool listenerOnly)
    {
        if(processId<1 || port<1 || port>65535)throw new ArgumentException("Valid listener process and port are required.");
        uint bytes=0;
        int tableClass=listenerOnly?3:4;
        uint status=GetExtendedTcpTable(IntPtr.Zero,ref bytes,false,2,tableClass,0);
        if(status!=122 || bytes<4 || bytes>1048576)throw new InvalidOperationException("Cannot size the owned TCP table.");
        bytes=Math.Min(bytes+65536,1048576);
        IntPtr table=Marshal.AllocHGlobal((int)bytes);
        try {
            status=GetExtendedTcpTable(table,ref bytes,false,2,tableClass,0);
            if(status!=0)throw new InvalidOperationException("Cannot read the owned TCP table.");
            int count=Marshal.ReadInt32(table);
            if(count<0 || count>(bytes-4)/24)throw new InvalidOperationException("Invalid listener-table bounds.");
            int matched=0;
            for(int i=0;i<count;i++) {
                IntPtr row=IntPtr.Add(table,4+i*24);
                uint encoded=(uint)Marshal.ReadInt32(row,8);
                int localPort=(int)(((encoded&255)<<8)|((encoded>>8)&255));
                if(localPort==port && Marshal.ReadInt32(row,20)==processId &&
                    (listenerOnly || Marshal.ReadInt32(row)==5))matched++;
            }
            return matched;
        } finally {Marshal.FreeHGlobal(table);}
    }

    private static long latencyTicks,maximumLatencyTicks;
    private static long bindTicks,connectTicks,responseTicks,eofTicks;
    private static long dispatchTicks,maximumDispatchTicks;
    private static bool noDelay;
    private static int receiveBudgetBytes;
    private static int observedMaximumPostedReadBytes;
    private static int inFlight,peakInFlight,completed,started,connectedCount,acceptedCount;
    private static int serverInFlight,serverPeakInFlight,serverCompleted,serverStarted;
    private sealed class GcGraphNode
    {
        public GcGraphNode Next;
        public GcGraphNode Other;
    }
    private sealed class GcObservation
    {
        private readonly int heapMiB;
        private readonly string heapLayout;
        private readonly string observationFile;
        private int claim,launched,started,completed,pending,before,after;
        private double milliseconds;
        private string start="",end="";
        public GcObservation(int heap,string layout,string output) {heapMiB=heap;heapLayout=layout;observationFile=output;}
        public bool Triggered {get {return Volatile.Read(ref claim)==2;}}
        public void TryCollect(int minimum,int launchedNow,int startedNow,int completedNow,int pendingNow)
        {
            if(heapMiB==0 || launchedNow<minimum || completedNow<1 || pendingNow<1 ||
                Interlocked.CompareExchange(ref claim,1,0)!=0)return;
            launched=launchedNow;started=startedNow;completed=completedNow;pending=pendingNow;
            File.WriteAllText(observationFile+".begin","pre-collection-call");
            before=GC.CollectionCount(GC.MaxGeneration);
            start=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
            var clock=Stopwatch.StartNew();
            GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
            clock.Stop();milliseconds=clock.Elapsed.TotalMilliseconds;
            end=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
            after=GC.CollectionCount(GC.MaxGeneration);
            Volatile.Write(ref claim,2);
            File.WriteAllText(observationFile,Json());
        }
        public void Verify()
        {
            if(heapMiB>0 && (!Triggered || after<=before))
                throw new InvalidOperationException("The requested full GC did not overlap completed and in-flight requests.");
        }
        public string Json()
        {
            return "{\"enabled\":"+(Triggered?"true":"false")+",\"heapMiB\":"+heapMiB+",\"heapLayout\":\""+heapLayout+"\""+
                ",\"configuredReceiveBudgetBytes\":"+receiveBudgetBytes+",\"maximumPostedReadBytes\":"+receiveBudgetBytes+
                ",\"observedMaximumPostedReadBytes\":"+observedMaximumPostedReadBytes+
                ",\"requestedListenBacklogHint\":"+(receiveBudgetBytes>0?8192:0)+
                ",\"launchedAtCollection\":"+launched+",\"startedBeforeCollection\":"+started+
                ",\"completedBeforeCollection\":"+completed+",\"inFlightBeforeCollection\":"+pending+
                ",\"gen2CollectionsBefore\":"+before+",\"gen2CollectionsAfter\":"+after+
                ",\"blockingCollectionMilliseconds\":"+milliseconds.ToString("R",CultureInfo.InvariantCulture)+
                ",\"collectionStartUtc\":\""+start+"\",\"collectionEndUtc\":\""+end+
                "\",\"serverGc\":"+(System.Runtime.GCSettings.IsServerGC?"true":"false")+"}";
        }
    }
    private static object PrepareHeap(int heapMiB,string layout)
    {
        if(heapMiB==0)return null;
        if(layout=="graph") {
            // An x64 two-reference node plus its root slot nominally occupies 40 bytes.
            int count=(heapMiB*1024*1024/40)&~1;
            var nodes=new GcGraphNode[count];
            for(int i=0;i<count;i++)nodes[i]=new GcGraphNode();
            for(int i=0;i<count;i++) {
                nodes[i].Next=nodes[(i+2)%count];
                nodes[i].Other=nodes[(i+1024)%count];
            }
            GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
            for(int i=0;i<count;i+=2)nodes[i]=null;
            return nodes;
        }
        var heap=new byte[heapMiB*1024][];
        for(int i=0;i<heap.Length;i++)heap[i]=new byte[1024];
        GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
        for(int i=0;i<heap.Length;i+=2)heap[i]=null;
        return heap;
    }
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
            int remaining=buffer.Length-offset;
            int posted=receiveBudgetBytes>0?Math.Min(remaining,receiveBudgetBytes):remaining;
            if(receiveBudgetBytes>0) {
                int prior;
                do {prior=observedMaximumPostedReadBytes;if(posted<=prior)break;}
                    while(Interlocked.CompareExchange(ref observedMaximumPostedReadBytes,posted,prior)!=prior);
            }
            int n=await stream.ReadAsync(buffer,offset,posted).ConfigureAwait(false);
            if(n==0)throw new IOException("Unexpected EOF.");
            offset+=n;
        }
    }
    private static async Task Serve(Socket socket,int size,byte[] response)
    {
        using(socket) {
            socket.NoDelay=noDelay;
            if(receiveBudgetBytes>0) {
                socket.ReceiveBufferSize=receiveBudgetBytes;
                if(socket.ReceiveBufferSize!=receiveBudgetBytes)
                    throw new InvalidOperationException("The accepted socket receive budget did not read back exactly.");
            }
            using(var stream=new NetworkStream(socket,false)) {
            byte[] data=new byte[size];
            await ReadAll(stream,data).ConfigureAwait(false);
            for(int i=0;i<data.Length;i++)if(data[i]!=(byte)(i%251))throw new IOException("Data mismatch.");
            await stream.WriteAsync(response,0,response.Length).ConfigureAwait(false);
            socket.Shutdown(SocketShutdown.Send);
            if(await stream.ReadAsync(new byte[1],0,1).ConfigureAwait(false)!=0)
                throw new IOException("Unexpected request data after completion.");
            }
        }
    }
    private static async Task ServeTracked(Socket socket,int size,byte[] response)
    {
        int active=Interlocked.Increment(ref serverInFlight),prior;
        Interlocked.Increment(ref serverStarted);
        do {prior=serverPeakInFlight;if(active<=prior)break;}
            while(Interlocked.CompareExchange(ref serverPeakInFlight,active,prior)!=prior);
        try {
            await Serve(socket,size,response).ConfigureAwait(false);
            Interlocked.Increment(ref serverCompleted);
        } finally {Interlocked.Decrement(ref serverInFlight);}
    }
    private static async Task Send(string source,IPAddress peer,int port,byte[] data,byte[] expectedResponse)
    {
        long start=Stopwatch.GetTimestamp();
        using(var socket=new TcpClient(new IPEndPoint(IPAddress.Parse(source),0))) {
            long bound=Stopwatch.GetTimestamp();Interlocked.Add(ref bindTicks,bound-start);
            socket.NoDelay=noDelay;
            await socket.ConnectAsync(peer,port).ConfigureAwait(false);
            Interlocked.Increment(ref connectedCount);
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
        int gcHeapMiB=0,gcMinimumLaunch=0;bool poolDispatch=false;string heapLayout="arrays";
        if(args.Length==13) {
            string[] gc=args[12].Split(':');
            if(args[12]=="dispatch:pool" && role=="client")poolDispatch=true;
            else if((gc.Length!=3 && gc.Length!=4 && gc.Length!=5) || gc[0]!="gc" || (role!="client" && role!="server") ||
                !int.TryParse(gc[1],out gcHeapMiB) || !int.TryParse(gc[2],out gcMinimumLaunch) ||
                gcHeapMiB<16 || gcHeapMiB>1024 || gcMinimumLaunch<1 || gcMinimumLaunch>=count)
                throw new ArgumentException("GC mode requires client/server role and gc:heap-MiB:minimum-launched, with 16-1024 MiB and a trigger before the final request; dispatch:pool requires client role.");
            if(!poolDispatch && gc.Length>=4) {
                heapLayout=gc[3];
                if(heapLayout!="arrays" && heapLayout!="graph")throw new ArgumentException("Unknown GC heap layout.");
            }
            if(!poolDispatch && gc.Length==5 &&
                (role!="server" || !int.TryParse(gc[4],out receiveBudgetBytes) || receiveBudgetBytes!=16384))
                throw new ArgumentException("The bounded receive budget requires GC server role and an explicit 16384-byte budget.");
        }
        if(File.Exists(args[6]))throw new IOException("Use a new result file.");
        if(gcHeapMiB>0 && File.Exists(args[6]+".gc.json"))throw new IOException("Use a new GC observation file.");
        if(gcHeapMiB>0 && File.Exists(args[6]+".gc.json.begin"))throw new IOException("Use a new GC pre-call signal file.");
        Socket listener=null;
        try {
            byte[] response=new byte[responseSize];
            for(int i=0;i<response.Length;i++)response[i]=(byte)(i%251);
            if(responseSize==1)response[0]=0x5a;
            object pressureHeap=PrepareHeap(gcHeapMiB,heapLayout);
            var gcObservation=new GcObservation(gcHeapMiB,heapLayout,args[6]+".gc.json");
            Task receiver=null;
            if(role!="client") {
                listener=new Socket(peer.AddressFamily,SocketType.Stream,ProtocolType.Tcp);
                if(receiveBudgetBytes>0) {
                    listener.ReceiveBufferSize=receiveBudgetBytes;
                    if(listener.ReceiveBufferSize!=receiveBudgetBytes)
                        throw new InvalidOperationException("The listener receive budget did not read back exactly.");
                }
                listener.Bind(new IPEndPoint(peer,port));
                // Winsock SOMAXCONN_HINT(N) is -N; a positive backlog may be silently capped.
                listener.Listen(receiveBudgetBytes>0?-8192:8192);
                receiver=Task.Run(async delegate {
                    var accepted=new List<Task>();
                    using(var serverCapacity=new SemaphoreSlim(concurrency)) {
                    for(int i=0;i<count;i++) {
                        if(gcHeapMiB>0 && role=="server")await serverCapacity.WaitAsync().ConfigureAwait(false);
                        Socket connection=await listener.AcceptAsync().ConfigureAwait(false);
                        Interlocked.Increment(ref acceptedCount);
                        if(gcHeapMiB>0 && role=="server") {
                            accepted.Add(Task.Run(async delegate {
                                try {await ServeTracked(connection,size,response).ConfigureAwait(false);}
                                finally {serverCapacity.Release();}
                            }));
                            gcObservation.TryCollect(gcMinimumLaunch,Volatile.Read(ref acceptedCount),Volatile.Read(ref serverStarted),
                                Volatile.Read(ref serverCompleted),Volatile.Read(ref serverInFlight));
                        } else accepted.Add(Serve(connection,size,response));
                    }
                    await Task.WhenAll(accepted).ConfigureAwait(false);
                    }
                });
            }
            if(role=="server") {
                if(File.Exists(args[6]+".ready"))throw new IOException("Use a new ready file.");
                File.WriteAllText(args[6]+".ready","listening");
                await receiver.ConfigureAwait(false);
                GC.KeepAlive(pressureHeap);
                gcObservation.Verify();
                File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"role\":\"server\",\"connections\":"+count+
                    ",\"bytesReceived\":"+((long)count*size)+",\"bytesSent\":"+((long)count*responseSize)+
                    ",\"networkErrors\":0,\"protocolErrors\":0,\"barrier\":false,\"peakInFlight\":"+serverPeakInFlight+
                    ",\"requestDispatch\":\""+(gcHeapMiB>0?"thread-pool":"inline")+"\",\"managedGc\":"+gcObservation.Json()+"}");
                return;
            }
            byte[] data=new byte[size];for(int i=0;i<size;i++)data[i]=(byte)(i%251);
            if(gcHeapMiB>0)File.WriteAllText(args[6]+".traffic-ready",DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture));
            var senders=new List<Task>();var random=new Random(seed);var clock=Stopwatch.StartNew();
            double next=0,maxLag=0,totalLag=0,lastLaunch=0;
            using(var capacity=new SemaphoreSlim(concurrency)) {
            for(int i=0;i<count;i++) {
                int delay=(int)Math.Ceiling(next-clock.Elapsed.TotalMilliseconds);
                if(delay>0)await Task.Delay(delay).ConfigureAwait(false);
                await capacity.WaitAsync().ConfigureAwait(false);
                double lag=Math.Max(0,clock.Elapsed.TotalMilliseconds-next);
                maxLag=Math.Max(maxLag,lag);totalLag+=lag;lastLaunch=clock.Elapsed.TotalMilliseconds;
                string requestSource=sources[i%sources.Length];IPAddress targetPeer=peers[i%peers.Length];
                if(gcHeapMiB>0 || poolDispatch) {
                    long queuedAt=Stopwatch.GetTimestamp();
                    senders.Add(Task.Run(()=>SendWithSlot(capacity,requestSource,targetPeer,port,data,response,queuedAt)));
                } else {
                    senders.Add(SendWithSlot(capacity,requestSource,targetPeer,port,data,response));
                }
                gcObservation.TryCollect(gcMinimumLaunch,i+1,Volatile.Read(ref started),Volatile.Read(ref completed),Volatile.Read(ref inFlight));
                next+=-Math.Log(1.0-random.NextDouble())*1000.0/rate;
            }
            await Task.WhenAll(senders).ConfigureAwait(false);
            }
            if(receiver!=null)await receiver.ConfigureAwait(false);
            clock.Stop();
            GC.KeepAlive(pressureHeap);
            gcObservation.Verify();
            var targetJson=new List<string>();
            for(int i=0;i<peers.Length;i++) {
                int requests=count/peers.Length+(i<count%peers.Length?1:0);
                bool loopback=IPAddress.IsLoopback(peers[i]) || (sources.Length==1 && peers[i].Equals(IPAddress.Parse(sources[0])));
                targetJson.Add("{\"index\":"+i+",\"loopback\":"+(loopback?"true":"false")+
                    ",\"connections\":"+requests+",\"requestBytes\":"+((long)requests*size)+
                    ",\"responseBytes\":"+((long)requests*responseSize)+"}");
            }
            File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"connections\":"+count+
                ",\"bytesSent\":"+((long)count*size)+",\"networkErrors\":0,\"protocolErrors\":0,\"milliseconds\":"+clock.ElapsedMilliseconds+
                ",\"bytesReceived\":"+((long)count*responseSize)+
                ",\"arrivalRate\":"+rate+",\"seed\":"+seed+",\"barrier\":false"+
                ",\"arrivalDispatch\":\""+(gcHeapMiB>0||poolDispatch?"thread-pool":"inline")+"\""+
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
                ",\"managedGc\":"+gcObservation.Json()+
                ",\"targets\":["+string.Join(",",targetJson)+"]"+
                ",\"maximumRequestMilliseconds\":"+(1000.0*maximumLatencyTicks/Stopwatch.Frequency).ToString("R",CultureInfo.InvariantCulture)+"}");
        } finally {if(listener!=null)listener.Dispose();}
    }
    private static void WriteFailure(string[] args,Exception error)
    {
        if(args.Length<7 || (Volatile.Read(ref started)==0 && Volatile.Read(ref acceptedCount)==0))return;
        Exception cause=error;
        while(cause is AggregateException && ((AggregateException)cause).InnerExceptions.Count>0)
            cause=((AggregateException)cause).InnerExceptions[0];
        cause=cause.GetBaseException();
        SocketException socket=cause as SocketException;
        File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"failed\",\"connectionsStarted\":"+Volatile.Read(ref started)+
            ",\"connectionsConnected\":"+Volatile.Read(ref connectedCount)+",\"connectionsCompleted\":"+Volatile.Read(ref completed)+
            ",\"acceptedConnections\":"+Volatile.Read(ref acceptedCount)+",\"errorType\":\""+cause.GetType().FullName+
            "\",\"errorCode\":"+cause.HResult+",\"socketError\":"+(socket==null?"null":socket.NativeErrorCode.ToString(CultureInfo.InvariantCulture))+"}");
    }
    private static int Main(string[] args)
    {
        try {
            if(args.Length<7 || args.Length>13) {
                Console.Error.WriteLine("Usage: ArrivalTcp sources peer port count rate request-bytes output.json [role [response-bytes [seed [maximum-in-flight [nodelay|nagle [gc:heap-MiB:minimum-launched|dispatch:pool]]]]]]");
                return 2;
            }
            if(!Run(args).Wait(TimeSpan.FromSeconds(150))){
                WriteFailure(args,new TimeoutException("Arrival workload deadline exceeded."));
                Console.Error.WriteLine("Arrival workload deadline exceeded.");return 3;
            }
            return 0;
        }catch(Exception error){
            WriteFailure(args,error);
            Console.Error.WriteLine(error.GetBaseException().ToString());return 1;
        }
    }
}
