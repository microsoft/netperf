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
    private static bool noDelay;
    private static int inFlight,peakInFlight;
    private static async Task SendWithSlot(SemaphoreSlim capacity,string source,IPAddress peer,int port,byte[] data,byte[] expectedResponse)
    {
        int active=Interlocked.Increment(ref inFlight);
        int previous;
        do {previous=peakInFlight;if(active<=previous)break;} while(Interlocked.CompareExchange(ref peakInFlight,active,previous)!=previous);
        long start=Stopwatch.GetTimestamp();
        try {await Send(source,peer,port,data,expectedResponse).ConfigureAwait(false);}
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
        var peer=IPAddress.Parse(args[1]);
        string role=args.Length>=8?args[7]:"local";
        if(role!="local" && role!="client" && role!="server")throw new ArgumentException("Unknown workload role.");
        int port=int.Parse(args[2]),count=int.Parse(args[3]),rate=int.Parse(args[4]),size=int.Parse(args[5]);
        int responseSize=args.Length>=9?int.Parse(args[8]):1;
        int seed=args.Length>=10?int.Parse(args[9]):14529;
        int concurrency=args.Length>=11?int.Parse(args[10]):256;
        if(args.Length==12 && args[11]!="nodelay" && args[11]!="nagle")throw new ArgumentException("Unknown socket pacing.");
        noDelay=args.Length==12 && args[11]=="nodelay";
        if(count<1||count>8192||rate<1||rate>10000||size<1||size>1048576||responseSize<1||responseSize>1048576||port<1024||port>65535||
            sources.Length<1||sources.Length>8||(double)count/rate>120||concurrency<1||concurrency>1024)
            throw new ArgumentException("Invalid bounded arrival workload.");
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
            byte[] data=new byte[size];for(int i=0;i<size;i++)data[i]=(byte)(i%251);
            var senders=new List<Task>();var random=new Random(seed);var clock=Stopwatch.StartNew();
            double next=0,maxLag=0,totalLag=0,lastLaunch=0;
            using(var capacity=new SemaphoreSlim(concurrency)) {
            for(int i=0;i<count;i++) {
                int delay=(int)Math.Ceiling(next-clock.Elapsed.TotalMilliseconds);
                if(delay>0)await Task.Delay(delay).ConfigureAwait(false);
                await capacity.WaitAsync().ConfigureAwait(false);
                double lag=Math.Max(0,clock.Elapsed.TotalMilliseconds-next);
                maxLag=Math.Max(maxLag,lag);totalLag+=lag;lastLaunch=clock.Elapsed.TotalMilliseconds;
                senders.Add(SendWithSlot(capacity,sources[i%sources.Length],peer,port,data,response));
                next+=-Math.Log(1.0-random.NextDouble())*1000.0/rate;
            }
            await Task.WhenAll(senders).ConfigureAwait(false);
            }
            if(receiver!=null)await receiver.ConfigureAwait(false);
            clock.Stop();
            File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"connections\":"+count+
                ",\"bytesSent\":"+((long)count*size)+",\"networkErrors\":0,\"protocolErrors\":0,\"milliseconds\":"+clock.ElapsedMilliseconds+
                ",\"bytesReceived\":"+((long)count*responseSize)+
                ",\"arrivalRate\":"+rate+",\"seed\":"+seed+",\"barrier\":false"+
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
                ",\"maximumRequestMilliseconds\":"+(1000.0*maximumLatencyTicks/Stopwatch.Frequency).ToString("R",CultureInfo.InvariantCulture)+"}");
        } finally {if(listener!=null)listener.Stop();}
    }
    private static int Main(string[] args)
    {
        try {
            if(args.Length<7 || args.Length>12) {
                Console.Error.WriteLine("Usage: ArrivalTcp sources peer port count rate request-bytes output.json [role [response-bytes [seed [maximum-in-flight [nodelay|nagle]]]]]");
                return 2;
            }
            if(!Run(args).Wait(TimeSpan.FromSeconds(150))){Console.Error.WriteLine("Arrival workload deadline exceeded.");return 3;}
            return 0;
        }catch(Exception error){Console.Error.WriteLine(error.GetBaseException().ToString());return 1;}
    }
}
