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
    [StructLayout(LayoutKind.Sequential)]
    private struct MemoryStatus
    {
        public uint Length,MemoryLoad;
        public ulong TotalPhysical,AvailablePhysical,TotalPageFile,AvailablePageFile,TotalVirtual,AvailableVirtual,AvailableExtendedVirtual;
    }
    [DllImport("kernel32.dll",SetLastError=true)]
    private static extern bool GlobalMemoryStatusEx(ref MemoryStatus status);
    [DllImport("iphlpapi.dll")]
    private static extern uint GetExtendedTcpTable(IntPtr table,ref uint bytes,bool order,int family,int tableClass,uint reserved);
    [DllImport("iphlpapi.dll")]
    private static extern uint GetIpPathTable(ushort family,out IntPtr table);
    [StructLayout(LayoutKind.Explicit,Size=104)]
    private struct BestRouteRow
    {
        [FieldOffset(0)]public ulong InterfaceLuid;
        [FieldOffset(8)]public uint InterfaceIndex;
    }
    [DllImport("iphlpapi.dll")]
    private static extern uint GetBestRoute2(IntPtr interfaceLuid,uint interfaceIndex,ref SockaddrInet source,
        ref SockaddrInet destination,uint options,out BestRouteRow route,out SockaddrInet bestSource);
    [DllImport("iphlpapi.dll")]
    private static extern void FreeMibTable(IntPtr table);
    [DllImport("iphlpapi.dll")]
    private static extern void InitializeIpForwardEntry(IntPtr row);
    [DllImport("iphlpapi.dll")]
    private static extern uint CreateIpForwardEntry2(IntPtr row);
    [DllImport("iphlpapi.dll")]
    private static extern uint DeleteIpForwardEntry2(IntPtr row);
    // MIB_IPFORWARD_ROW2 (x64): InterfaceIndex@8, DestinationPrefix@12 (address@16, length@40), NextHop@44, ValidLifetime@76, Metric@84.
    private const int ForwardRowBytes=104;
    private static IntPtr NewOnLinkRouteRow(int interfaceIndex,uint prefixAddress,byte prefixLength)
    {
        IntPtr row=Marshal.AllocHGlobal(ForwardRowBytes);
        for(int i=0;i<ForwardRowBytes;i++)Marshal.WriteByte(row,i,0);
        InitializeIpForwardEntry(row);
        if((uint)Marshal.ReadInt32(row,76)!=uint.MaxValue){
            Marshal.FreeHGlobal(row);
            throw new InvalidOperationException("The documented forward-row layout did not verify.");
        }
        Marshal.WriteInt32(row,8,interfaceIndex);
        Marshal.WriteInt16(row,12,2);
        Marshal.WriteInt32(row,16,(int)prefixAddress);
        Marshal.WriteByte(row,40,prefixLength);
        Marshal.WriteInt16(row,44,2);
        Marshal.WriteInt32(row,48,0);
        Marshal.WriteInt32(row,84,256);
        return row;
    }
    public static bool VerifyForwardRowLayout()
    {
        IntPtr row=NewOnLinkRouteRow(1,0x00F813C6u,24);
        try{return Marshal.ReadInt32(row,8)==1 && Marshal.ReadInt16(row,12)==2 && Marshal.ReadByte(row,40)==24 &&
            (uint)Marshal.ReadInt32(row,16)==0x00F813C6u;}
        finally{Marshal.FreeHGlobal(row);}
    }
    // Adds and removes one owned on-link /24 so each operation bumps the compartment routing epoch.
    private static int RunRouteEpochDial(string[] args)
    {
        int interfaceIndex=int.Parse(args[1]),delay=int.Parse(args[2]),duration=int.Parse(args[3]),interval=int.Parse(args[4]);
        if(interfaceIndex<1 || delay<0 || delay>30000 || duration<100 || duration>10000 || interval<1 || interval>1000)
            throw new ArgumentException("The route-epoch dial requires bounded delay, duration and interval.");
        if(File.Exists(args[7]))throw new IOException("Use a fresh dial report.");
        string startAfterFile=args.Length==9?args[8]:null;
        IntPtr row=NewOnLinkRouteRow(interfaceIndex,0x00F813C6u,24);
        long operations=0,failures=0;bool present=false;string start="",end="";uint lastError=0;
        try{
            File.WriteAllText(args[5],"ready");
            if(startAfterFile!=null){
                var trigger=Stopwatch.StartNew();
                while(!File.Exists(startAfterFile) && !File.Exists(args[6])){
                    if(trigger.Elapsed.TotalSeconds>120)throw new TimeoutException("The dial start trigger did not appear.");
                    Thread.Sleep(1);
                }
            }
            var clock=Stopwatch.StartNew();
            while(clock.ElapsedMilliseconds<delay){if(File.Exists(args[6]))break;Thread.Sleep(5);}
            if(!File.Exists(args[6])){
                start=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
                var window=Stopwatch.StartNew();long next=0;
                while(window.ElapsedMilliseconds<duration && !File.Exists(args[6])){
                    uint status=present?DeleteIpForwardEntry2(row):CreateIpForwardEntry2(row);
                    if(status==0){present=!present;operations++;}else{failures++;lastError=status;if(failures>16)break;}
                    next+=interval;
                    long wait=next-window.ElapsedMilliseconds;
                    // Sleep only for long gaps; spin one thread for short ones instead of raising global timer resolution.
                    if(wait>=20)Thread.Sleep((int)wait-16);
                    while(next>window.ElapsedMilliseconds && !File.Exists(args[6]))Thread.SpinWait(200);
                }
                end=DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture);
            }
        }finally{
            if(present){
                uint status=DeleteIpForwardEntry2(row);
                if(status==0){present=false;operations++;}else{lastError=status;}
            }
            Marshal.FreeHGlobal(row);
            File.WriteAllText(args[7],"{\"schema\":1,\"prefix\":\"198.19.248.0/24\",\"intervalMilliseconds\":"+interval+
                ",\"durationMilliseconds\":"+duration+",\"routeOperations\":"+operations+",\"failures\":"+failures+
                ",\"lastError\":"+lastError+",\"routeRemoved\":"+(present?"false":"true")+
                ",\"startAfterGc\":"+(startAfterFile!=null?"true":"false")+",\"pacing\":\"sleep-long-spin-short\""+
                ",\"startUtc\":\""+start+"\",\"endUtc\":\""+end+"\"}");
        }
        return (failures>0 || present)?1:0;
    }
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
        var snapshot=ReadPathPopulation(interfaceIndex,sourceAddresses,0,0);
        queryMilliseconds=snapshot.QueryMilliseconds;scanMilliseconds=snapshot.ScanMilliseconds;
        return snapshot.DatagramPaths;
    }
    public static int CountReferencedLoopbackPaths(int interfaceIndex,out double queryMilliseconds,out double scanMilliseconds)
    {
        var snapshot=ReadPathPopulation(interfaceIndex,new[]{"127.0.0.1"},interfaceIndex,4194303);
        queryMilliseconds=snapshot.QueryMilliseconds;scanMilliseconds=snapshot.ScanMilliseconds;
        return snapshot.ReferencedTcpPaths;
    }
    public sealed class PathPopulationSnapshot
    {
        public int DatagramPaths,ReferencedTcpPaths,TotalIpv4Rows;
        public double QueryMilliseconds,ScanMilliseconds;
    }
    public static PathPopulationSnapshot ReadPathPopulation(int interfaceIndex,string[] sourceAddresses,int loopbackInterfaceIndex,int referencedPaths)
    {
        var snapshot=new PathPopulationSnapshot();
        if(interfaceIndex<1 || sourceAddresses==null || sourceAddresses.Length==0)
            throw new ArgumentException("IPv4 sources and an interface index are required.");
        if(referencedPaths<0 || referencedPaths>4194303 || (referencedPaths>0 && loopbackInterfaceIndex<1))
            throw new ArgumentException("The referenced path census requires its bounded loopback scope.");
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
        snapshot.QueryMilliseconds=clock.Elapsed.TotalMilliseconds;
        if(status!=0)throw new InvalidOperationException("Cannot read the IPv4 path table: "+status);
        if(table==IntPtr.Zero)throw new InvalidOperationException("The IPv4 path table is missing.");
        try {
            clock.Restart();
            int count=Marshal.ReadInt32(table);
            if(count<0 || count>1000000)throw new InvalidOperationException("Invalid IPv4 path-table bounds.");
            snapshot.TotalIpv4Rows=count;
            int stride=Marshal.SizeOf(typeof(IpPathRow));
            int offset=Marshal.OffsetOf(typeof(IpPathTable),"FirstRow").ToInt32();
            if(stride!=136 || offset!=8)throw new InvalidOperationException("The documented x64 IP-path layout did not verify.");
            int destinationOffset=Marshal.OffsetOf(typeof(IpPathRow),"Destination").ToInt32();
            int indexOffset=Marshal.OffsetOf(typeof(IpPathRow),"InterfaceIndex").ToInt32();
            int addressOffset=Marshal.OffsetOf(typeof(SockaddrInet),"Ipv4").ToInt32();
            for(int i=0;i<count;i++){
                IntPtr row=IntPtr.Add(table,offset+i*stride);
                if(Marshal.ReadInt16(row)!=2 || Marshal.ReadInt16(row,destinationOffset)!=2)
                    throw new InvalidOperationException("Unexpected address family in the IPv4 path table.");
                int rowInterface=Marshal.ReadInt32(row,indexOffset);
                uint source=(uint)Marshal.ReadInt32(row,addressOffset);
                uint destination=(uint)Marshal.ReadInt32(row,destinationOffset+addressOffset);
                if(rowInterface==interfaceIndex && sourceValues.Contains(source))snapshot.DatagramPaths++;
                // Match 127.64.0.0/10 in the little-endian IPv4 field.
                if(referencedPaths>0 && rowInterface==loopbackInterfaceIndex && source==0x0100007Fu &&
                    (destination&0xC0FFu)==0x407Fu){
                    int ordinal=(((int)(destination>>8)&255)-64)*65536+((int)(destination>>16)&255)*256+(int)(destination>>24);
                    if(ordinal>=1 && ordinal<=referencedPaths)snapshot.ReferencedTcpPaths++;
                }
            }
            snapshot.ScanMilliseconds=clock.Elapsed.TotalMilliseconds;
            return snapshot;
        }finally{FreeMibTable(table);}
    }
    private static IPAddress ParseIdlePathSource(string sourceAddress)
    {
        IPAddress source;
        if(!IPAddress.TryParse(sourceAddress,out source) || source.AddressFamily!=AddressFamily.InterNetwork)
            throw new ArgumentException("Only a bounded owned IPv4 source is supported.");
        byte[] sourceBytes=source.GetAddressBytes();
        if(sourceBytes[0]!=198 || sourceBytes[1]!=19 || sourceBytes[2]!=0 || sourceBytes[3]<1 || sourceBytes[3]>12)
            throw new ArgumentException("Only a bounded owned path-retirement source is supported.");
        return source;
    }
    public static UdpClient[] CreateIdlePathSocketPopulation(string[] sourceAddresses,int totalCount,int[] occupiedPorts)
    {
        if(sourceAddresses==null || sourceAddresses.Length<1 || sourceAddresses.Length>12 ||
            totalCount<1 || totalCount%sourceAddresses.Length!=0 || occupiedPorts==null)
            throw new ArgumentException("Distinct bounded sources and an exact path population are required.");
        int perSource=totalCount/sourceAddresses.Length;
        if(perSource!=1 && perSource!=1024 && perSource!=8192 && perSource!=24576)
            throw new ArgumentException("The per-source path population is outside its explicit bounds.");
        var addresses=new HashSet<IPAddress>();
        foreach(string source in sourceAddresses)
            if(!addresses.Add(ParseIdlePathSource(source)))throw new ArgumentException("Idle path sources must be distinct.");
        var groups=new System.Collections.Concurrent.ConcurrentBag<UdpClient[]>();
        try {
            Parallel.ForEach(sourceAddresses,new ParallelOptions{
                MaxDegreeOfParallelism=Math.Min(sourceAddresses.Length,Environment.ProcessorCount)
            },source=>groups.Add(CreateIdlePathSockets(source,perSource,occupiedPorts)));
        }catch(Exception failure){
            var completed=new List<UdpClient>();
            foreach(var group in groups)completed.AddRange(group);
            try {ReleaseIdlePathSockets(completed);}
            catch(Exception cleanup){throw new AggregateException("Idle path population and required cleanup failed.",failure,cleanup);}
            throw;
        }
        var result=new List<UdpClient>(totalCount);
        foreach(var group in groups)result.AddRange(group);
        return result.ToArray();
    }
    public static UdpClient[] CreateIdlePathSockets(string sourceAddress,int count,int[] occupiedPorts)
    {
        var source=ParseIdlePathSource(sourceAddress);
        if((count!=1 && count!=1024 && count!=8192 && count!=24576) || occupiedPorts==null)
            throw new ArgumentException("Only a bounded owned path-retirement fixture is supported.");
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
        }catch(Exception failure){
            try {ReleaseIdlePathSockets(sockets);}
            catch(Exception cleanup){throw new AggregateException("Idle path creation and required cleanup failed.",failure,cleanup);}
            throw;
        }
    }
    public static void ReleaseIdlePathSockets(IEnumerable<UdpClient> sockets)
    {
        if(sockets==null)throw new ArgumentNullException("sockets");
        Parallel.ForEach(sockets,new ParallelOptions{MaxDegreeOfParallelism=Environment.ProcessorCount},socket=>socket.Dispose());
    }
    public sealed class ReferencedTcpPathFixture:IDisposable
    {
        public const int ConnectBatchLimit=256;
        public const int SourcePortReservationLimit=4096;
        private readonly Socket[] clients,servers,portReservations;
        private int disposed;
        public int Count {get;private set;}
        public int Port {get;private set;}
        public ulong AvailablePhysicalBytesAtCreate {get;private set;}
        public double CreationMilliseconds {get;private set;}
        public int PreparationQueries {get;private set;}
        public double PreparationMilliseconds {get;private set;}
        public int MaximumBindParallelism {get{return Math.Min(Count,Math.Min(32,Environment.ProcessorCount));}}
        public int ReservedSourcePorts {get{return portReservations.Length;}}
        private ReferencedTcpPathFixture(int count)
        {
            Count=count;clients=new Socket[count];servers=new Socket[count];portReservations=new Socket[Math.Min(SourcePortReservationLimit,count)];
        }
        private static IPAddress SourceFor(int ordinal)
        {
            return new IPAddress(new byte[]{127,(byte)(64+(ordinal>>16)),(byte)((ordinal>>8)&255),(byte)(ordinal&255)});
        }
        public static ReferencedTcpPathFixture Create(int count)
        {
            if(count!=1 && count!=128 && count!=1024 && count!=4096 && count!=8192 && count!=49152 && count!=98304 && count!=196608 && count!=294912)
                throw new ArgumentException("Only bounded referenced loopback TCP fixtures are supported.");
            var memory=new MemoryStatus{Length=(uint)Marshal.SizeOf(typeof(MemoryStatus))};
            if(!GlobalMemoryStatusEx(ref memory))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            if(memory.AvailablePhysical<(ulong)count*65536+268435456)
                throw new InvalidOperationException("Insufficient free physical memory for the bounded referenced TCP fixture.");
            var fixture=new ReferencedTcpPathFixture(count);
            fixture.AvailablePhysicalBytesAtCreate=memory.AvailablePhysical;
            using(var listener=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp)){
                try{
                    listener.ExclusiveAddressUse=true;
                    listener.Bind(new IPEndPoint(IPAddress.Loopback,0));
                    listener.Listen(-8192);
                    fixture.Port=((IPEndPoint)listener.LocalEndPoint).Port;
                    var clock=Stopwatch.StartNew();
                    for(int i=0;i<fixture.portReservations.Length;i++){
                        var reservation=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp);
                        fixture.portReservations[i]=reservation;
                        reservation.ExclusiveAddressUse=true;
                        reservation.Bind(new IPEndPoint(IPAddress.Loopback,0));
                    }
                    for(int offset=0;offset<count;offset+=ConnectBatchLimit){
                        if(clock.Elapsed.TotalSeconds>120)throw new TimeoutException("Referenced TCP fixture creation exceeded its deadline.");
                        int batch=Math.Min(ConnectBatchLimit,count-offset);
                        var connects=new Task[batch];
                        Parallel.For(0,batch,new ParallelOptions{MaxDegreeOfParallelism=Math.Min(batch,fixture.MaximumBindParallelism)},i=>{
                            var client=new Socket(AddressFamily.InterNetwork,SocketType.Stream,ProtocolType.Tcp);
                            fixture.clients[offset+i]=client;
                            client.ExclusiveAddressUse=true;
                            int sourcePort=((IPEndPoint)fixture.portReservations[(offset+i)%fixture.portReservations.Length].LocalEndPoint).Port;
                            client.Bind(new IPEndPoint(SourceFor(offset+i+1),sourcePort));
                            connects[i]=client.ConnectAsync(IPAddress.Loopback,fixture.Port);
                        });
                        if(!Task.WaitAll(connects,5000))throw new TimeoutException("A referenced loopback connection exceeded its deadline.");
                        for(int i=0;i<batch;i++){
                            var server=listener.Accept();
                            var remote=(IPEndPoint)server.RemoteEndPoint;
                            byte[] bytes=remote.Address.GetAddressBytes();
                            int ordinal=(bytes[1]-64)*65536+bytes[2]*256+bytes[3];
                            if(bytes[0]!=127 || ordinal<1 || ordinal>count || fixture.clients[ordinal-1]==null ||
                                fixture.servers[ordinal-1]!=null ||
                                remote.Port!=((IPEndPoint)fixture.clients[ordinal-1].LocalEndPoint).Port){
                                server.Dispose();
                                throw new InvalidOperationException("The private loopback listener accepted an unexpected source.");
                            }
                            fixture.servers[ordinal-1]=server;
                        }
                    }
                    fixture.VerifyHeld();
                    fixture.CreationMilliseconds=clock.Elapsed.TotalMilliseconds;
                    return fixture;
                }catch(Exception failure){
                    int created=0,connected=0;
                    foreach(var socket in fixture.clients)if(socket!=null)created++;
                    foreach(var socket in fixture.servers)if(socket!=null)connected++;
                    failure.Data["FixtureCreatedClients"]=created;
                    failure.Data["FixtureConnectedPairs"]=connected;
                    try{fixture.Dispose();}
                    catch(Exception cleanup){throw new AggregateException("Referenced TCP fixture creation and cleanup failed.",failure,cleanup);}
                    throw;
                }
            }
        }
        public void VerifyHeld()
        {
            if(Volatile.Read(ref disposed)!=0)throw new ObjectDisposedException("ReferencedTcpPathFixture");
            for(int i=0;i<Count;i++){
                if(clients[i]==null || servers[i]==null || !clients[i].Connected || !servers[i].Connected ||
                    !((IPEndPoint)clients[i].LocalEndPoint).Address.Equals(SourceFor(i+1)) ||
                    !((IPEndPoint)clients[i].RemoteEndPoint).Address.Equals(IPAddress.Loopback) ||
                    ((IPEndPoint)clients[i].LocalEndPoint).Port<1 ||
                    ((IPEndPoint)clients[i].LocalEndPoint).Port!=((IPEndPoint)portReservations[i%portReservations.Length].LocalEndPoint).Port ||
                    ((IPEndPoint)clients[i].RemoteEndPoint).Port!=Port ||
                    ((IPEndPoint)servers[i].LocalEndPoint).Port!=Port ||
                    ((IPEndPoint)servers[i].RemoteEndPoint).Port!=((IPEndPoint)clients[i].LocalEndPoint).Port)
                    throw new InvalidOperationException("A referenced TCP fixture connection changed.");
            }
        }
        public void PreparePaths(int loopbackInterfaceIndex)
        {
            VerifyHeld();
            if(loopbackInterfaceIndex<1)throw new ArgumentException("A verified loopback interface is required.");
            var clock=Stopwatch.StartNew();
            var source=new SockaddrInet{Family=2,Ipv4=0x0100007F};
            for(int i=1;i<=Count;i++){
                var destination=new SockaddrInet{Family=2,Ipv4=BitConverter.ToUInt32(SourceFor(i).GetAddressBytes(),0)};
                BestRouteRow route;SockaddrInet bestSource;
                uint status=GetBestRoute2(IntPtr.Zero,(uint)loopbackInterfaceIndex,ref source,ref destination,0,out route,out bestSource);
                if(status!=0)throw new System.ComponentModel.Win32Exception((int)status);
                if(route.InterfaceIndex!=(uint)loopbackInterfaceIndex || bestSource.Family!=2 || bestSource.Ipv4!=source.Ipv4)
                    throw new InvalidOperationException("A referenced-path route query escaped its verified loopback scope.");
                PreparationQueries++;
            }
            PreparationMilliseconds=clock.Elapsed.TotalMilliseconds;
        }
        public void Dispose()
        {
            if(Interlocked.Exchange(ref disposed,1)!=0)return;
            var errors=new List<Exception>();
            foreach(var group in new[]{clients,servers,portReservations}){
                foreach(var socket in group){
                    if(socket==null)continue;
                    try{socket.LingerState=new LingerOption(true,0);}catch(Exception error){errors.Add(error);}
                    try{socket.Dispose();}catch(Exception error){errors.Add(error);}
                }
            }
            if(errors.Count>0)throw new AggregateException("Required referenced TCP fixture cleanup failed.",errors);
        }
    }
    public static bool IsListenerReady(int processId,int port)
    {
        return CountOwnedTcpRows(processId,port,true)>0;
    }
    public static int CountEstablishedConnections(int processId,int port)
    {
        return CountOwnedTcpRows(processId,port,false);
    }
    public static int CountEstablishedConnectionsInLargeTable(int processId,int port)
    {
        return CountOwnedTcpRows(processId,port,false,67108864);
    }
    public static int CountEstablishedLoopbackFixtureServers(int processId,int port)
    {
        return CountOwnedTcpRows(processId,port,false,67108864,0x0100007F);
    }
    private static int CountOwnedTcpRows(int processId,int port,bool listenerOnly,uint maximumBytes=1048576,uint localAddress=0)
    {
        if(processId<1 || port<1 || port>65535)throw new ArgumentException("Valid listener process and port are required.");
        uint bytes=0;
        int tableClass=listenerOnly?3:4;
        uint status=GetExtendedTcpTable(IntPtr.Zero,ref bytes,false,2,tableClass,0);
        if(status!=122 || bytes<4 || bytes>maximumBytes)throw new InvalidOperationException("Cannot size the owned TCP table.");
        bytes=Math.Min(bytes+65536,maximumBytes);
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
                    (localAddress==0 || (uint)Marshal.ReadInt32(row,4)==localAddress) &&
                    (listenerOnly || Marshal.ReadInt32(row)==5))matched++;
            }
            return matched;
        } finally {Marshal.FreeHGlobal(table);}
    }

    private static long latencyTicks,maximumLatencyTicks;
    private static long bindTicks,connectTicks,responseTicks,eofTicks;
    private static long dispatchTicks,maximumDispatchTicks;
    private static bool noDelay;
    private static HashSet<string> clusterSourceSet;
    private static int clusterPortCursor=-1;
    private static int receiveBudgetBytes;
    private static int exchangesPerConnection=1;
    private static bool framedWrites;
    private static bool idleKeepalive;
    private static int keepaliveConfiguredSockets;
    private static int serverResponsesCompleted;
    private static bool serviceWait;
    private static int serviceRequestOrdinal,serviceWaitsCompleted;
    private static bool serviceRequestPipelining;
    private static int serviceDelayMinimumMilliseconds=250;
    private static string firstErrorJson;
    private static string RemoteText(Socket socket)
    {
        try {return socket.RemoteEndPoint is IPEndPoint ? ((IPEndPoint)socket.RemoteEndPoint).Address.ToString() : "";}
        catch(Exception) {return "";}
    }
    private static void RecordFirstError(Exception error,string phase,string remote)
    {
        Exception cause=error.GetBaseException();
        SocketException socket=cause as SocketException;
        // Only the earliest failing connection is kept, so the server and producer reports can be ordered in time.
        Interlocked.CompareExchange(ref firstErrorJson,"{\"utc\":\""+DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture)+
            "\",\"phase\":\""+phase+"\",\"remoteAddress\":\""+remote+"\",\"errorType\":\""+cause.GetType().FullName+
            "\",\"socketError\":"+(socket==null?"null":socket.NativeErrorCode.ToString(CultureInfo.InvariantCulture))+"}",null);
    }
    private static int serviceDelaySpanMilliseconds=501;
    private static int clientPacingWaitsCompleted;
    private static int preparedGraphNodeCount;
    private static long preparedManagedHeapBytes;
    private static ulong largeHeapFreePhysicalBytesBeforePreparation;
    private static int observedMaximumPostedReadBytes;
    private static int maximumPerConnectionReadBufferBytes;
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
        private readonly string readinessFile;
        private int claim,launched,started,completed,pending,before,after;
        private double milliseconds;
        private string start="",end="",trigger="",completedUnit="connections";
        public GcObservation(int heap,string layout,string output,string ready=null) {heapMiB=heap;heapLayout=layout;observationFile=output;readinessFile=ready;}
        public bool Triggered {get {return Volatile.Read(ref claim)==2;}}
        public void TryCollect(int minimum,int launchedNow,int startedNow,int completedNow,int pendingNow,string triggerEdge="launch",string completionUnit="connections")
        {
            if(heapMiB==0 || Volatile.Read(ref claim)!=0 || launchedNow<minimum || completedNow<1 || pendingNow<1 ||
                (readinessFile!=null && !File.Exists(readinessFile)) ||
                Interlocked.CompareExchange(ref claim,1,0)!=0)return;
            launched=launchedNow;started=startedNow;completed=completedNow;pending=pendingNow;
            trigger=triggerEdge;
            completedUnit=completionUnit;
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
                ",\"readinessGateRequired\":"+(readinessFile!=null?"true":"false")+
                ",\"readinessGateSatisfied\":"+(readinessFile!=null && Triggered?"true":"false")+
                ",\"preparedGraphNodeCount\":"+preparedGraphNodeCount+",\"preparedManagedHeapBytes\":"+preparedManagedHeapBytes+
                ",\"largeHeapFreePhysicalBytesBeforePreparation\":"+largeHeapFreePhysicalBytesBeforePreparation+
                ",\"configuredReceiveBudgetBytes\":"+receiveBudgetBytes+",\"maximumPostedReadBytes\":"+receiveBudgetBytes+
                ",\"observedMaximumPostedReadBytes\":"+observedMaximumPostedReadBytes+
                ",\"requestedListenBacklogHint\":"+(receiveBudgetBytes>0?8192:0)+
                ",\"launchedAtCollection\":"+launched+",\"startedBeforeCollection\":"+started+
                ",\"completedBeforeCollection\":"+completed+",\"inFlightBeforeCollection\":"+pending+
                ",\"gen2CollectionsBefore\":"+before+",\"gen2CollectionsAfter\":"+after+
                ",\"triggerObservation\":\""+trigger+"\""+
                ",\"completedUnit\":\""+completedUnit+"\""+
                ",\"blockingCollectionMilliseconds\":"+milliseconds.ToString("R",CultureInfo.InvariantCulture)+
                ",\"collectionStartUtc\":\""+start+"\",\"collectionEndUtc\":\""+end+
                "\",\"serverGc\":"+(System.Runtime.GCSettings.IsServerGC?"true":"false")+"}";
        }
    }
    private static int GraphNodeCount(int heapMiB)
    {
        return checked((int)(((long)heapMiB*1024*1024/40)&~1L));
    }
    private static object PrepareHeap(int heapMiB,string layout)
    {
        if(heapMiB==0)return null;
        if(heapMiB>1024){
            var status=new MemoryStatus{Length=(uint)Marshal.SizeOf(typeof(MemoryStatus))};
            if(!GlobalMemoryStatusEx(ref status))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            largeHeapFreePhysicalBytesBeforePreparation=status.AvailablePhysical;
            if(status.AvailablePhysical<(ulong)heapMiB*4*1024*1024)
                throw new InvalidOperationException("Insufficient free physical memory for the larger graph receiver.");
        }
        if(layout=="graph") {
            // An x64 two-reference node plus its root slot nominally occupies 40 bytes.
            int count=GraphNodeCount(heapMiB);
            preparedGraphNodeCount=count;
            var nodes=new GcGraphNode[count];
            for(int i=0;i<count;i++)nodes[i]=new GcGraphNode();
            for(int i=0;i<count;i++) {
                nodes[i].Next=nodes[(i+2)%count];
                nodes[i].Other=nodes[(i+1024)%count];
            }
            GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
            for(int i=0;i<count;i+=2)nodes[i]=null;
            preparedManagedHeapBytes=GC.GetTotalMemory(false);
            return nodes;
        }
        var heap=new byte[heapMiB*1024][];
        for(int i=0;i<heap.Length;i++)heap[i]=new byte[1024];
        GC.Collect(GC.MaxGeneration,GCCollectionMode.Forced,true,true);
        for(int i=0;i<heap.Length;i+=2)heap[i]=null;
        preparedManagedHeapBytes=GC.GetTotalMemory(false);
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
    private static byte[] CreateValidationBuffer(int length)
    {
        var buffer=new byte[Math.Min(length,65536)];
        int prior;
        do {prior=maximumPerConnectionReadBufferBytes;if(buffer.Length<=prior)break;}
            while(Interlocked.CompareExchange(ref maximumPerConnectionReadBufferBytes,buffer.Length,prior)!=prior);
        return buffer;
    }
    private static async Task ReadAll(NetworkStream stream,byte[] buffer,int count)
    {
        int offset=0;
        while(offset<count) {
            int remaining=count-offset;
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
    private static async Task ReadPattern(NetworkStream stream,byte[] buffer,int length,byte[] expected)
    {
        for(int offset=0;offset<length;){
            int count=Math.Min(buffer.Length,length-offset);
            await ReadAll(stream,buffer,count).ConfigureAwait(false);
            for(int i=0;i<count;i++){
                byte value=expected==null?(byte)((offset+i)%251):expected[offset+i];
                if(buffer[i]!=value)throw new IOException(expected==null?"Data mismatch.":"Reply mismatch.");
            }
            offset+=count;
        }
    }
    private static Task WriteMessage(NetworkStream stream,byte[] data)
    {
        return framedWrites?WriteFramedMessage(stream,data):stream.WriteAsync(data,0,data.Length);
    }
    private static void ConfigureKeepalive(Socket socket)
    {
        var values=new byte[12];
        Buffer.BlockCopy(BitConverter.GetBytes((uint)1),0,values,0,4);
        Buffer.BlockCopy(BitConverter.GetBytes((uint)1000),0,values,4,4);
        Buffer.BlockCopy(BitConverter.GetBytes((uint)1000),0,values,8,4);
        if(socket.IOControl(IOControlCode.KeepAliveValues,values,null)!=0 ||
            Convert.ToInt32(socket.GetSocketOption(SocketOptionLevel.Socket,SocketOptionName.KeepAlive))!=1)
            throw new InvalidOperationException("The requested keepalive setting did not verify.");
        Interlocked.Increment(ref keepaliveConfiguredSockets);
    }
    private static async Task WriteFramedMessage(NetworkStream stream,byte[] data)
    {
        await stream.WriteAsync(data,0,4).ConfigureAwait(false);
        await stream.WriteAsync(data,4,data.Length-4).ConfigureAwait(false);
    }
    private static async Task WritePacedServiceRequests(NetworkStream stream,byte[] data,int connectionOrdinal)
    {
        for(int exchange=0;exchange<exchangesPerConnection;exchange++){
            await WriteMessage(stream,data).ConfigureAwait(false);
            if(exchange+1<exchangesPerConnection){
                await Task.Delay(serviceDelayMinimumMilliseconds+(int)(((long)connectionOrdinal*1103515245+(long)exchange*104729)%serviceDelaySpanMilliseconds)).ConfigureAwait(false);
                Interlocked.Increment(ref clientPacingWaitsCompleted);
            }
        }
    }
    private static async Task ReadServiceResponses(NetworkStream stream,byte[] reply,byte[] expectedResponse)
    {
        for(int exchange=0;exchange<exchangesPerConnection;exchange++)
            await ReadPattern(stream,reply,expectedResponse.Length,expectedResponse).ConfigureAwait(false);
    }
    private static async Task Serve(Socket socket,int size,byte[] response,GcObservation gcObservation=null,int gcMinimumLaunch=0)
    {
        using(socket) {
            socket.NoDelay=noDelay;
            if(framedWrites && socket.NoDelay)throw new InvalidOperationException("The requested Nagle setting did not verify.");
            if(idleKeepalive)ConfigureKeepalive(socket);
            if(receiveBudgetBytes>0) {
                socket.ReceiveBufferSize=receiveBudgetBytes;
                if(socket.ReceiveBufferSize!=receiveBudgetBytes)
                    throw new InvalidOperationException("The accepted socket receive budget did not read back exactly.");
            }
            using(var stream=new NetworkStream(socket,false)) {
            byte[] data=CreateValidationBuffer(size);
            for(int exchange=0;exchange<exchangesPerConnection;exchange++){
                await ReadPattern(stream,data,size,null).ConfigureAwait(false);
                if(serviceWait){
                    int ordinal=Interlocked.Increment(ref serviceRequestOrdinal);
                    await Task.Delay(serviceDelayMinimumMilliseconds+(int)(((long)ordinal*104729)%serviceDelaySpanMilliseconds)).ConfigureAwait(false);
                    Interlocked.Increment(ref serviceWaitsCompleted);
                }
                await WriteMessage(stream,response).ConfigureAwait(false);
                if(idleKeepalive || serviceWait){
                    Interlocked.Increment(ref serverResponsesCompleted);
                    if(gcObservation!=null)gcObservation.TryCollect(gcMinimumLaunch,Volatile.Read(ref acceptedCount),
                        Volatile.Read(ref serverStarted),Volatile.Read(ref serverResponsesCompleted),
                        Volatile.Read(ref serverInFlight),"response","application-responses");
                }
            }
            if(!idleKeepalive)socket.Shutdown(SocketShutdown.Send);
            if(await stream.ReadAsync(new byte[1],0,1).ConfigureAwait(false)!=0)
                throw new IOException("Unexpected request data after completion.");
            if(idleKeepalive)socket.Shutdown(SocketShutdown.Send);
            }
        }
    }
    private static async Task ServeTracked(Socket socket,int size,byte[] response,GcObservation gcObservation,int gcMinimumLaunch)
    {
        int active=Interlocked.Increment(ref serverInFlight),prior;
        Interlocked.Increment(ref serverStarted);
        do {prior=serverPeakInFlight;if(active<=prior)break;}
            while(Interlocked.CompareExchange(ref serverPeakInFlight,active,prior)!=prior);
        string remote=RemoteText(socket);
        try {
            await Serve(socket,size,response,gcObservation,gcMinimumLaunch).ConfigureAwait(false);
            Interlocked.Increment(ref serverCompleted);
        } catch(Exception error) {RecordFirstError(error,"serve",remote);throw;}
        finally {Interlocked.Decrement(ref serverInFlight);}
        gcObservation.TryCollect(gcMinimumLaunch,Volatile.Read(ref acceptedCount),Volatile.Read(ref serverStarted),
            (idleKeepalive || serviceWait)?Volatile.Read(ref serverResponsesCompleted):Volatile.Read(ref serverCompleted),
            Volatile.Read(ref serverInFlight),"completion",(idleKeepalive || serviceWait)?"application-responses":"connections");
    }
    private static async Task Send(string source,IPAddress peer,int port,byte[] data,byte[] expectedResponse)
    {
        string phase="connect";
        try {await SendCore(source,peer,port,data,expectedResponse,value=>phase=value).ConfigureAwait(false);}
        catch(Exception error) {RecordFirstError(error,"client-"+phase,peer.ToString());throw;}
    }
    // A port-0 bind to an explicit address draws a globally unique port from the shared dynamic range, which caps
    // a many-address producer near 16k concurrent connections. Cluster sources instead bind explicit ports below
    // the dynamic range from one global cursor over a span coprime to the source count: each port number then
    // carries only a few endpoints (explicit-bind cost grows with endpoints sharing a port), and the same
    // address:port pair does not recur within a run.
    private const int ClusterPortBase=20000,ClusterPortSpan=28999;
    private static void BindSource(Socket socket,string source)
    {
        if(clusterSourceSet==null || !clusterSourceSet.Contains(source)){
            socket.Bind(new IPEndPoint(IPAddress.Parse(source),0));
            return;
        }
        var address=IPAddress.Parse(source);
        for(int attempt=0;;attempt++){
            int port=ClusterPortBase+(int)((uint)Interlocked.Increment(ref clusterPortCursor)%ClusterPortSpan);
            try {socket.Bind(new IPEndPoint(address,port));return;}
            catch(SocketException error) {
                // Administratively excluded ports (for example 47001) report access denied.
                if((error.SocketErrorCode!=SocketError.AddressAlreadyInUse && error.SocketErrorCode!=SocketError.AccessDenied) || attempt>=64)throw;
            }
        }
    }
    private static async Task SendCore(string source,IPAddress peer,int port,byte[] data,byte[] expectedResponse,Action<string> setPhase)
    {
        long start=Stopwatch.GetTimestamp();
        using(var socket=new TcpClient(AddressFamily.InterNetwork)) {
            BindSource(socket.Client,source);
            long bound=Stopwatch.GetTimestamp();Interlocked.Add(ref bindTicks,bound-start);
            socket.NoDelay=noDelay;
            if(framedWrites && socket.NoDelay)throw new InvalidOperationException("The requested Nagle setting did not verify.");
            await socket.ConnectAsync(peer,port).ConfigureAwait(false);
            int connectionOrdinal=Interlocked.Increment(ref connectedCount);
            if(idleKeepalive)ConfigureKeepalive(socket.Client);
            long connected=Stopwatch.GetTimestamp();Interlocked.Add(ref connectTicks,connected-bound);
            var stream=socket.GetStream();
            var reply=CreateValidationBuffer(expectedResponse.Length);
            setPhase("exchange");
            if(serviceRequestPipelining){
                await Task.WhenAll(WritePacedServiceRequests(stream,data,connectionOrdinal),
                    ReadServiceResponses(stream,reply,expectedResponse)).ConfigureAwait(false);
            }else{
                for(int exchange=0;exchange<exchangesPerConnection;exchange++){
                    await WriteMessage(stream,data).ConfigureAwait(false);
                    await ReadPattern(stream,reply,expectedResponse.Length,expectedResponse).ConfigureAwait(false);
                }
            }
            long received=Stopwatch.GetTimestamp();Interlocked.Add(ref responseTicks,received-connected);
            if(idleKeepalive){
                int holdSeconds=8+(int)(((long)connectionOrdinal*1103515245)%23);
                await Task.Delay(TimeSpan.FromSeconds(holdSeconds)).ConfigureAwait(false);
                socket.Client.Shutdown(SocketShutdown.Send);
            }
            setPhase("eof");
            if(await stream.ReadAsync(new byte[1],0,1).ConfigureAwait(false)!=0)
                throw new IOException("Unexpected response data after completion.");
            Interlocked.Add(ref eofTicks,Stopwatch.GetTimestamp()-received);
        }
    }
    private static async Task Run(string[] args)
    {
        // '@file' supplies a comma-separated source list too long for one command line (thousands of cluster peers).
        string[] sources=(args[0].StartsWith("@",StringComparison.Ordinal)?File.ReadAllText(args[0].Substring(1)).Trim():args[0]).Split(',');
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
        bool clusterSources=sources.Length>8;
        if(clusterSources){
            clusterSourceSet=new HashSet<string>(sources,StringComparer.Ordinal);
            if(sources.Length%47==0 || sources.Length%617==0)throw new ArgumentException("The cluster source count must be coprime to the explicit port span.");
        }
        if(clusterSources){
            // Many sources are permitted only from the owned 198.19.64.0/19 cluster fixture.
            var distinct=new HashSet<string>(StringComparer.Ordinal);
            foreach(string source in sources){
                IPAddress parsed;
                if(!IPAddress.TryParse(source,out parsed) || parsed.AddressFamily!=AddressFamily.InterNetwork ||
                    !distinct.Add(source))throw new ArgumentException("Cluster sources must be distinct IPv4 addresses.");
                byte[] bytes=parsed.GetAddressBytes();
                if(bytes[0]!=198 || bytes[1]!=19 || bytes[2]<64 || bytes[2]>95)
                    throw new ArgumentException("Cluster sources must stay inside the owned 198.19.64.0/19 fixture.");
            }
            if(role!="client" || peers.Length!=1 || sources.Length>8192)
                throw new ArgumentException("Cluster sources require one target peer, client role and at most 8192 addresses.");
        }
        // Hot service mode models a large node and may carry up to eight times the ordinary connection bounds.
        bool hotScale=args.Length>=14 && args[13].StartsWith("servicehot256",StringComparison.Ordinal);
        // Held mode keeps a large, mostly idle population of long-lived connections established at once.
        bool heldPopulation=args.Length>=14 && args[13]=="servicehold40:pipelined";
        int countLimit=heldPopulation?262144:hotScale?65536:8192,concurrencyLimit=heldPopulation?262144:hotScale?32768:4096;
        if(count<1||count>countLimit||rate<1||rate>10000||size<1||size>1048576||responseSize<1||responseSize>1048576||port<1024||port>65535||
            sources.Length<1||(!clusterSources && sources.Length>8)||(double)count/rate>120||concurrency<1||concurrency>concurrencyLimit)
            throw new ArgumentException("Invalid bounded arrival workload.");
        int gcHeapMiB=0,gcMinimumLaunch=0;bool poolDispatch=false;string heapLayout="arrays";
        if(args.Length>=13) {
            string[] gc=args[12].Split(':');
            if(args[12]=="dispatch:pool" && role=="client")poolDispatch=true;
            else if((gc.Length!=3 && gc.Length!=4 && gc.Length!=5) || gc[0]!="gc" || (role!="client" && role!="server") ||
                !int.TryParse(gc[1],out gcHeapMiB) || !int.TryParse(gc[2],out gcMinimumLaunch) ||
                gcHeapMiB<16 || gcHeapMiB>2048 || gcMinimumLaunch<1 || gcMinimumLaunch>=count)
                throw new ArgumentException("GC mode requires client/server role and gc:heap-MiB:minimum-launched, with 16-2048 MiB and a trigger before the final request; dispatch:pool requires client role.");
            if(!poolDispatch && gc.Length>=4) {
                heapLayout=gc[3];
                if(heapLayout!="arrays" && heapLayout!="graph")throw new ArgumentException("Unknown GC heap layout.");
            }
            if(!poolDispatch && gc.Length==5 &&
                (role!="server" || !int.TryParse(gc[4],out receiveBudgetBytes) || receiveBudgetBytes!=16384))
                throw new ArgumentException("The bounded receive budget requires GC server role and an explicit 16384-byte budget.");
            if(gcHeapMiB>1024 && (role!="server" || heapLayout!="graph"))
                throw new ArgumentException("The larger GC budget requires the graph receiver layout.");
        }
        exchangesPerConnection=1;
        framedWrites=false;
        idleKeepalive=false;
        serviceWait=false;
        serviceRequestPipelining=false;
        if(args.Length>=14){
            if(args[13]=="servicehold40:pipelined"){
                // Long-lived pooled connections: one small request per 1-2 s for about a minute each.
                if(size!=512 || (responseSize!=1460 && responseSize!=16384) || role=="local")
                    throw new ArgumentException("Held service mode requires 512-byte requests and 1460- or 16384-byte pipelined responses.");
                serviceWait=true;serviceRequestPipelining=true;exchangesPerConnection=40;
                serviceDelayMinimumMilliseconds=1000;serviceDelaySpanMilliseconds=1001;
                if(!noDelay)throw new ArgumentException("Pipelined service requests require explicit nodelay pacing.");
            }else if(args[13]=="servicehot256:pipelined"){
                // One MSS-sized response keeps the guest data path at a high exchange rate; 16 KiB responses suit hosts with
                // high-bandwidth private links.
                if(size!=512 || (responseSize!=1460 && responseSize!=16384) || role=="local")
                    throw new ArgumentException("Hot service mode requires 512-byte requests and 1460- or 16384-byte pipelined responses.");
                serviceWait=true;serviceRequestPipelining=true;exchangesPerConnection=256;
                serviceDelayMinimumMilliseconds=50;serviceDelaySpanMilliseconds=81;
                if(!noDelay)throw new ArgumentException("Pipelined service requests require explicit nodelay pacing.");
            }else if(args[13]=="servicewait64" || args[13]=="servicewait64:pipelined"){
                if(size!=512 || (responseSize!=512 && responseSize!=16384) || role=="local" ||
                    (responseSize==16384 && args[13]!="servicewait64:pipelined"))
                    throw new ArgumentException("Service wait mode requires 512-byte requests and 512-byte responses, or 16384-byte pipelined responses.");
                serviceWait=true;exchangesPerConnection=64;
                serviceRequestPipelining=args[13]=="servicewait64:pipelined";
                if(serviceRequestPipelining && !noDelay)
                    throw new ArgumentException("Pipelined service requests require explicit nodelay pacing.");
            }else if(args[13]=="idlekeepalive"){
                if(size!=1460 || responseSize!=1460 || role=="local")
                    throw new ArgumentException("Idle keepalive mode requires bounded client/server 1460-byte messages.");
                idleKeepalive=true;
            }else{
            string[] exchangeOption=args[13].Split(':');
            if((exchangeOption.Length!=2 && exchangeOption.Length!=3) || exchangeOption[0]!="exchanges" ||
                !int.TryParse(exchangeOption[1],out exchangesPerConnection) || exchangesPerConnection!=64 ||
                size!=1460 || responseSize!=1460)
                throw new ArgumentException("Persistent mode requires exchanges:64 and 1460-byte requests and responses.");
            framedWrites=exchangeOption.Length==3;
            if(framedWrites && (exchangeOption[2]!="framed" || noDelay))
                throw new ArgumentException("Framed exchanges require exchanges:64:framed with Nagle enabled.");
            }
        }
        string gcReadinessFile=null;
        if(args.Length==15){
            if(role!="server" || gcHeapMiB==0 || !serviceRequestPipelining)
                throw new ArgumentException("Fixture readiness gates require the pipelined GC receiver.");
            gcReadinessFile=Path.GetFullPath(args[14]);
            if(!string.Equals(Path.GetDirectoryName(gcReadinessFile),Path.GetDirectoryName(Path.GetFullPath(args[6])),StringComparison.OrdinalIgnoreCase) ||
                Path.GetFileName(gcReadinessFile)!="route-control.ready" || File.Exists(gcReadinessFile))
                throw new ArgumentException("Use a fresh owned fixture readiness file beside the receiver output.");
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
            var gcObservation=new GcObservation(gcHeapMiB,heapLayout,args[6]+".gc.json",gcReadinessFile);
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
                listener.Listen(receiveBudgetBytes>0?-Math.Max(8192,concurrency):8192);
                receiver=Task.Run(async delegate {
                    var accepted=new List<Task>();
                    using(var serverCapacity=new SemaphoreSlim(concurrency)) {
                    for(int i=0;i<count;i++) {
                        if(gcHeapMiB>0 && role=="server")await serverCapacity.WaitAsync().ConfigureAwait(false);
                        Socket connection=await listener.AcceptAsync().ConfigureAwait(false);
                        Interlocked.Increment(ref acceptedCount);
                        if(gcHeapMiB>0 && role=="server") {
                            accepted.Add(Task.Run(async delegate {
                                try {await ServeTracked(connection,size,response,gcObservation,gcMinimumLaunch).ConfigureAwait(false);}
                                finally {serverCapacity.Release();}
                            }));
                            gcObservation.TryCollect(gcMinimumLaunch,Volatile.Read(ref acceptedCount),Volatile.Read(ref serverStarted),
                                (idleKeepalive || serviceWait)?Volatile.Read(ref serverResponsesCompleted):Volatile.Read(ref serverCompleted),
                                Volatile.Read(ref serverInFlight),"accept",(idleKeepalive || serviceWait)?"application-responses":"connections");
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
                    ",\"bytesReceived\":"+((long)count*size*exchangesPerConnection)+",\"bytesSent\":"+((long)count*responseSize*exchangesPerConnection)+
                    ",\"exchangesPerConnection\":"+exchangesPerConnection+
                    ",\"framedWrites\":"+(framedWrites?"true":"false")+",\"noDelay\":"+(noDelay?"true":"false")+
                    ",\"managedCoreLibrary\":\""+typeof(object).Assembly.GetName().Name+"\",\"managedRuntimeVersion\":\""+Environment.Version+"\""+
                    ",\"idleKeepalive\":"+(idleKeepalive?"true":"false")+",\"keepaliveConfiguredSockets\":"+keepaliveConfiguredSockets+
                    ",\"serviceWait\":"+(serviceWait?"true":"false")+",\"serviceWaitsCompleted\":"+serviceWaitsCompleted+
                    ",\"serviceRequestPipelining\":"+(serviceRequestPipelining?"true":"false")+",\"clientPacingWaitsCompleted\":"+clientPacingWaitsCompleted+
                    ",\"clientPacingMinimumMilliseconds\":"+(serviceRequestPipelining?serviceDelayMinimumMilliseconds:0)+",\"clientPacingMaximumMilliseconds\":"+(serviceRequestPipelining?serviceDelayMinimumMilliseconds+serviceDelaySpanMilliseconds-1:0)+
                    ",\"serviceWaitMinimumMilliseconds\":"+(serviceWait?serviceDelayMinimumMilliseconds:0)+",\"serviceWaitMaximumMilliseconds\":"+(serviceWait?serviceDelayMinimumMilliseconds+serviceDelaySpanMilliseconds-1:0)+
                    ",\"keepaliveIdleMillisecondsRequested\":"+(idleKeepalive?1000:0)+",\"keepaliveIntervalMillisecondsRequested\":"+(idleKeepalive?1000:0)+
                    ",\"maximumPerConnectionReadBufferBytes\":"+maximumPerConnectionReadBufferBytes+
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
                    ",\"connections\":"+requests+",\"requestBytes\":"+((long)requests*size*exchangesPerConnection)+
                    ",\"responseBytes\":"+((long)requests*responseSize*exchangesPerConnection)+"}");
            }
            File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"connections\":"+count+
                ",\"bytesSent\":"+((long)count*size*exchangesPerConnection)+",\"networkErrors\":0,\"protocolErrors\":0,\"milliseconds\":"+clock.ElapsedMilliseconds+
                ",\"bytesReceived\":"+((long)count*responseSize*exchangesPerConnection)+
                ",\"exchangesPerConnection\":"+exchangesPerConnection+
                ",\"framedWrites\":"+(framedWrites?"true":"false")+
                ",\"managedCoreLibrary\":\""+typeof(object).Assembly.GetName().Name+"\",\"managedRuntimeVersion\":\""+Environment.Version+"\""+
                ",\"idleKeepalive\":"+(idleKeepalive?"true":"false")+",\"keepaliveConfiguredSockets\":"+keepaliveConfiguredSockets+
                ",\"serviceWait\":"+(serviceWait?"true":"false")+",\"serviceWaitsCompleted\":"+serviceWaitsCompleted+
                ",\"serviceRequestPipelining\":"+(serviceRequestPipelining?"true":"false")+",\"clientPacingWaitsCompleted\":"+clientPacingWaitsCompleted+
                ",\"clientPacingMinimumMilliseconds\":"+(serviceRequestPipelining?serviceDelayMinimumMilliseconds:0)+",\"clientPacingMaximumMilliseconds\":"+(serviceRequestPipelining?serviceDelayMinimumMilliseconds+serviceDelaySpanMilliseconds-1:0)+
                ",\"serviceWaitMinimumMilliseconds\":"+(serviceWait?serviceDelayMinimumMilliseconds:0)+",\"serviceWaitMaximumMilliseconds\":"+(serviceWait?serviceDelayMinimumMilliseconds+serviceDelaySpanMilliseconds-1:0)+
                ",\"keepaliveIdleMillisecondsRequested\":"+(idleKeepalive?1000:0)+",\"keepaliveIntervalMillisecondsRequested\":"+(idleKeepalive?1000:0)+
                ",\"idleHoldMinimumMilliseconds\":"+(idleKeepalive?8000:0)+",\"idleHoldMaximumMilliseconds\":"+(idleKeepalive?30000:0)+
                ",\"maximumPerConnectionReadBufferBytes\":"+maximumPerConnectionReadBufferBytes+
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
            "\",\"errorCode\":"+cause.HResult+",\"socketError\":"+(socket==null?"null":socket.NativeErrorCode.ToString(CultureInfo.InvariantCulture))+
            ",\"failureUtc\":\""+DateTime.UtcNow.ToString("o",CultureInfo.InvariantCulture)+"\",\"firstError\":"+(Volatile.Read(ref firstErrorJson)??"null")+"}");
    }
    private static int Main(string[] args)
    {
        try {
            if((args.Length==8 || args.Length==9) && args[0]=="--route-epoch-dial")return RunRouteEpochDial(args);
            if(args.Length<7 || args.Length>15) {
                Console.Error.WriteLine("Usage: ArrivalTcp sources peer port count rate request-bytes output.json [role [response-bytes [seed [maximum-in-flight [nodelay|nagle [gc:heap-MiB:minimum-launched|dispatch:pool [exchanges:64[:framed]|idlekeepalive|servicewait64[:pipelined]|servicehot256:pipelined|servicehold40:pipelined [fixture-ready-file]]]]]]]]");
                return 2;
            }
            // Hot-scale nodes carry up to 8x the connections, so they get a longer bounded deadline.
            bool hotService=args.Length>=14 && (args[13].StartsWith("servicehot256",StringComparison.Ordinal) || args[13]=="servicehold40:pipelined");
            if(!Run(args).Wait(TimeSpan.FromSeconds(hotService?330:150))){
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
