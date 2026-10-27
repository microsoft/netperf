// Copyright (c) Microsoft Corporation.
// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Threading.Tasks;

internal static class ArrivalTcp
{
    private static async Task ReadAll(NetworkStream stream,byte[] buffer)
    {
        int offset=0;
        while(offset<buffer.Length) {
            int n=await stream.ReadAsync(buffer,offset,buffer.Length-offset).ConfigureAwait(false);
            if(n==0)throw new IOException("Unexpected EOF.");
            offset+=n;
        }
    }
    private static async Task Serve(TcpClient socket,int size)
    {
        using(socket) {
            byte[] data=new byte[size];
            await ReadAll(socket.GetStream(),data).ConfigureAwait(false);
            for(int i=0;i<data.Length;i++)if(data[i]!=(byte)(i%251))throw new IOException("Data mismatch.");
            await socket.GetStream().WriteAsync(new byte[]{0x5a},0,1).ConfigureAwait(false);
        }
    }
    private static async Task Send(string source,IPAddress peer,int port,byte[] data)
    {
        using(var socket=new TcpClient(new IPEndPoint(IPAddress.Parse(source),0))) {
            await socket.ConnectAsync(peer,port).ConfigureAwait(false);
            await socket.GetStream().WriteAsync(data,0,data.Length).ConfigureAwait(false);
            var reply=new byte[1];
            await ReadAll(socket.GetStream(),reply).ConfigureAwait(false);
            if(reply[0]!=0x5a)throw new IOException("Reply mismatch.");
        }
    }
    private static async Task Run(string[] args)
    {
        string[] sources=args[0].Split(',');
        var peer=IPAddress.Parse(args[1]);
        int port=int.Parse(args[2]),count=int.Parse(args[3]),rate=int.Parse(args[4]),size=int.Parse(args[5]);
        if(count<1||count>8192||rate<1||rate>10000||size<4096||size>1048576||port<1024||port>65535||
            sources.Length<1||sources.Length>8||(double)count/rate>120)
            throw new ArgumentException("Invalid bounded arrival workload.");
        if(File.Exists(args[6]))throw new IOException("Use a new result file.");
        var listener=new TcpListener(peer,port);listener.Start(8192);
        try {
            var receiver=Task.Run(async delegate {
                var accepted=new List<Task>();
                for(int i=0;i<count;i++)accepted.Add(Serve(await listener.AcceptTcpClientAsync().ConfigureAwait(false),size));
                await Task.WhenAll(accepted).ConfigureAwait(false);
            });
            byte[] data=new byte[size];for(int i=0;i<size;i++)data[i]=(byte)(i%251);
            var senders=new List<Task>();var random=new Random(14529);var clock=Stopwatch.StartNew();
            double next=0,maxLag=0,totalLag=0,lastLaunch=0;
            for(int i=0;i<count;i++) {
                int delay=(int)Math.Ceiling(next-clock.Elapsed.TotalMilliseconds);
                if(delay>0)await Task.Delay(delay).ConfigureAwait(false);
                double lag=Math.Max(0,clock.Elapsed.TotalMilliseconds-next);
                maxLag=Math.Max(maxLag,lag);totalLag+=lag;lastLaunch=clock.Elapsed.TotalMilliseconds;
                senders.Add(Send(sources[i%sources.Length],peer,port,data));
                next+=-Math.Log(1.0-random.NextDouble())*1000.0/rate;
            }
            await Task.WhenAll(senders).ConfigureAwait(false);
            await receiver.ConfigureAwait(false);clock.Stop();
            File.WriteAllText(args[6],"{\"schema\":1,\"outcome\":\"collected\",\"connections\":"+count+
                ",\"bytesSent\":"+((long)count*size)+",\"networkErrors\":0,\"protocolErrors\":0,\"milliseconds\":"+clock.ElapsedMilliseconds+
                ",\"arrivalRate\":"+rate+",\"seed\":14529,\"barrier\":false"+
                ",\"maxLaunchLagMilliseconds\":"+maxLag.ToString("R",CultureInfo.InvariantCulture)+
                ",\"meanLaunchLagMilliseconds\":"+(totalLag/count).ToString("R",CultureInfo.InvariantCulture)+
                ",\"launchSpanMilliseconds\":"+lastLaunch.ToString("R",CultureInfo.InvariantCulture)+"}");
        } finally {listener.Stop();}
    }
    private static int Main(string[] args)
    {
        try {
            if(args.Length!=7)return 2;
            if(!Run(args).Wait(TimeSpan.FromSeconds(150))){Console.Error.WriteLine("Arrival workload deadline exceeded.");return 3;}
            return 0;
        }catch(Exception error){Console.Error.WriteLine(error.GetBaseException().ToString());return 1;}
    }
}
