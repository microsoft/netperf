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

internal static class BarrierTcp
{
    private static async Task ReadExactly(NetworkStream stream, byte[] buffer)
    {
        int offset = 0;
        while (offset < buffer.Length)
        {
            int count = await stream.ReadAsync(buffer, offset, buffer.Length - offset).ConfigureAwait(false);
            if (count == 0) throw new IOException("Unexpected end of stream.");
            offset += count;
        }
    }

    private static async Task Receive(TcpClient socket, int bytes)
    {
        var buffer = new byte[bytes];
        await ReadExactly(socket.GetStream(), buffer).ConfigureAwait(false);
        for (int i = 0; i < buffer.Length; i++)
            if (buffer[i] != (byte)(i % 251)) throw new IOException("Payload verification failed.");
        await socket.GetStream().WriteAsync(new byte[] { 0x5a }, 0, 1).ConfigureAwait(false);
    }

    private static async Task Send(TcpClient socket, byte[] buffer, Task gate)
    {
        await gate.ConfigureAwait(false);
        await socket.GetStream().WriteAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
        var response = new byte[1];
        await ReadExactly(socket.GetStream(), response).ConfigureAwait(false);
        if (response[0] != 0x5a) throw new IOException("Completion verification failed.");
    }

    private static async Task Run(string[] args)
    {
        var sources = args[0].Split(',');
        var address = IPAddress.Parse(args[1]);
        int port = int.Parse(args[2], CultureInfo.InvariantCulture);
        int count = int.Parse(args[3], CultureInfo.InvariantCulture);
        int bytes = int.Parse(args[4], CultureInfo.InvariantCulture);
        string directory = Path.GetFullPath(args[5]);
        if (count < 1 || count > 8192 || bytes < 4096 || bytes > 1048576 ||
            port < 1024 || port > 65535 || sources.Length < 1 || sources.Length > 8)
            throw new ArgumentException("Invalid bounded workload.");
        foreach (string source in sources)
            if (IPAddress.Parse(source).AddressFamily != AddressFamily.InterNetwork || source == args[1])
                throw new ArgumentException("Distinct IPv4 source endpoints required.");
        if (address.AddressFamily != AddressFamily.InterNetwork) throw new ArgumentException("IPv4 peer required.");
        foreach (string file in new[] { "ready", "go", "done", "stop", "result.json" })
            if (File.Exists(Path.Combine(directory, file))) throw new IOException("Use fresh control files.");
        var sockets = new List<TcpClient>();
        var listener = new TcpListener(address, port);
        var gate = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        try
        {
            listener.Start(8192);
            var receivers = new List<Task>();
            var accept = Task.Run(async delegate {
                for (int i = 0; i < count; i++)
                {
                    var socket = await listener.AcceptTcpClientAsync().ConfigureAwait(false);
                    lock (sockets) sockets.Add(socket);
                    receivers.Add(Receive(socket, bytes));
                }
            });
            var buffer = new byte[bytes];
            for (int i = 0; i < bytes; i++) buffer[i] = (byte)(i % 251);
            var senders = new List<Task>();
            for (int i = 0; i < count; i++)
            {
                var socket = new TcpClient(new IPEndPoint(IPAddress.Parse(sources[i % sources.Length]), 0));
                lock (sockets) sockets.Add(socket);
                await socket.ConnectAsync(address, port).ConfigureAwait(false);
                senders.Add(Send(socket, buffer, gate.Task));
            }
            await accept.ConfigureAwait(false);
            listener.Stop();
            File.WriteAllText(Path.Combine(directory, "ready"), count.ToString(CultureInfo.InvariantCulture));
            while (!File.Exists(Path.Combine(directory, "go"))) await Task.Delay(10).ConfigureAwait(false);
            var clock = Stopwatch.StartNew();
            gate.SetResult(true);
            await Task.WhenAll(senders).ConfigureAwait(false);
            await Task.WhenAll(receivers).ConfigureAwait(false);
            clock.Stop();
            File.WriteAllText(Path.Combine(directory, "result.json"),
                "{\"schema\":1,\"outcome\":\"collected\",\"connections\":" + count +
                ",\"bytesSent\":" + ((long)count * bytes) + ",\"networkErrors\":0,\"protocolErrors\":0,\"payloadMilliseconds\":" +
                clock.ElapsedMilliseconds + "}");
            File.WriteAllText(Path.Combine(directory, "done"), "verified");
            while (!File.Exists(Path.Combine(directory, "stop"))) await Task.Delay(10).ConfigureAwait(false);
        }
        finally
        {
            listener.Stop();
            lock (sockets) foreach (var socket in sockets) socket.Close();
        }
    }

    private static int Main(string[] args)
    {
        if (args.Length != 6) { Console.Error.WriteLine("Expected sources, peer, port, connections, bytes and control directory."); return 2; }
        var task = Run(args);
        try
        {
            if (!task.Wait(TimeSpan.FromSeconds(180))) { Console.Error.WriteLine("Barrier workload deadline exceeded."); return 3; }
            return 0;
        }
        catch (Exception error) { Console.Error.WriteLine(error.GetBaseException().GetType().FullName); return 1; }
    }
}
