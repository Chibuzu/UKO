// WebSocketServer.cs -- a small, dependency-free RFC 6455 WebSocket server on
// raw TcpListener. Hand-rolled ON PURPOSE: HttpListener's websocket support is
// platform-spotty, and the game's frames are tiny JSON messages -- a complete,
// predictable implementation here beats a leaky abstraction. Supports text
// frames (with continuation), close, ping/pong; enforces client masking and a
// frame-size cap. One receive loop per connection; sends serialized per-connection.
namespace UKO.Server;

using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class WsConnection
{
    public readonly string Id = Guid.NewGuid().ToString("N")[..8];
    private readonly TcpClient _tcp;
    private readonly NetworkStream _stream;
    private readonly SemaphoreSlim _sendLock = new(1, 1);
    public volatile bool Closed;
    public object Tag;   // the server's per-connection state (player)

    public WsConnection(TcpClient tcp, NetworkStream stream)
    {
        _tcp = tcp;
        _stream = stream;
    }

    public async Task SendText(string text)
    {
        if (Closed) return;
        byte[] payload = Encoding.UTF8.GetBytes(text);
        byte[] header;
        if (payload.Length < 126)
            header = new byte[] { 0x81, (byte)payload.Length };
        else if (payload.Length <= ushort.MaxValue)
            header = new byte[] { 0x81, 126, (byte)(payload.Length >> 8), (byte)payload.Length };
        else
            throw new InvalidOperationException("frame too large");
        await _sendLock.WaitAsync();
        try
        {
            if (Closed) return;
            await _stream.WriteAsync(header);
            await _stream.WriteAsync(payload);
        }
        catch { Close(); }
        finally { _sendLock.Release(); }
    }

    public void Close()
    {
        if (Closed) return;
        Closed = true;
        try { _tcp.Close(); } catch { /* already down */ }
    }

    // ── receive loop: yields complete text messages until the socket ends ──
    public async Task ReceiveLoop(int maxFrame, Func<string, Task> onText)
    {
        var accum = new List<byte>();
        var buf8 = new byte[8];
        try
        {
            while (!Closed)
            {
                int b0 = await ReadByte();
                int b1 = await ReadByte();
                if (b0 < 0 || b1 < 0) break;
                bool fin = (b0 & 0x80) != 0;
                int opcode = b0 & 0x0F;
                bool masked = (b1 & 0x80) != 0;
                long len = b1 & 0x7F;
                if (len == 126)
                {
                    await ReadExactly(buf8, 2);
                    len = (buf8[0] << 8) | buf8[1];
                }
                else if (len == 127)
                {
                    await ReadExactly(buf8, 8);
                    len = 0;
                    for (int i = 0; i < 8; i++) len = (len << 8) | buf8[i];
                }
                if (!masked || len > maxFrame) break;   // clients MUST mask; oversize = drop
                var mask = new byte[4];
                await ReadExactly(mask, 4);
                var payload = new byte[len];
                await ReadExactly(payload, (int)len);
                for (int i = 0; i < payload.Length; i++) payload[i] ^= mask[i & 3];

                switch (opcode)
                {
                    case 0x1:            // text
                    case 0x0:            // continuation
                        accum.AddRange(payload);
                        if (accum.Count > maxFrame) { Close(); return; }
                        if (fin)
                        {
                            string text = Encoding.UTF8.GetString(accum.ToArray());
                            accum.Clear();
                            await onText(text);
                        }
                        break;
                    case 0x8:            // close
                        Close();
                        return;
                    case 0x9:            // ping -> pong
                        await SendControl(0xA, payload);
                        break;
                    case 0xA:            // pong: ignore
                        break;
                    default:             // binary etc.: not part of the protocol
                        Close();
                        return;
                }
            }
        }
        catch (Exception e)
        {
            if (Environment.GetEnvironmentVariable("UKO_WS_DEBUG") == "1")
                Console.WriteLine($"[ws-debug] {Id} receive loop: {e.GetType().Name}: {e.Message}");
        }
        Close();
    }

    private async Task SendControl(int opcode, byte[] payload)
    {
        if (payload.Length > 125) payload = Array.Empty<byte>();
        await _sendLock.WaitAsync();
        try
        {
            if (Closed) return;
            await _stream.WriteAsync(new[] { (byte)(0x80 | opcode), (byte)payload.Length });
            if (payload.Length > 0) await _stream.WriteAsync(payload);
        }
        catch { Close(); }
        finally { _sendLock.Release(); }
    }

    private async Task<int> ReadByte()
    {
        var one = new byte[1];
        int n = await _stream.ReadAsync(one.AsMemory(0, 1));
        return n == 1 ? one[0] : -1;
    }

    private async Task ReadExactly(byte[] buf, int count)
    {
        int off = 0;
        while (off < count)
        {
            int n = await _stream.ReadAsync(buf.AsMemory(off, count - off));
            if (n <= 0) throw new IOException("socket closed mid-frame");
            off += n;
        }
    }
}

public static class WebSocketServer
{
    private const string MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    // Accept loop. Round 17: this port now speaks BOTH dialects -- an Upgrade
    // request becomes a game WebSocket (handed to `onOpen`), any other GET is
    // served as a STATIC FILE from the web/ folder. One port, one bat: the
    // same server hosts the website build AND the matches it connects to.
    public static async Task Listen(int port, Func<WsConnection, Task> onOpen, CancellationToken ct)
    {
        var listener = new TcpListener(IPAddress.Any, port);
        listener.Start();
        Console.WriteLine($"[server] listening on port {port} (game + website)");
        ct.Register(() => { try { listener.Stop(); } catch { } });
        while (!ct.IsCancellationRequested)
        {
            TcpClient tcp;
            try { tcp = await listener.AcceptTcpClientAsync(ct); }
            catch { break; }
            _ = Task.Run(async () =>
            {
                try
                {
                    tcp.NoDelay = true;
                    var stream = tcp.GetStream();
                    var (path, key, upgrade) = await ReadRequest(stream);
                    if (!upgrade)
                    {
                        if (path != null) await ServeStatic(stream, path);
                        tcp.Close();
                        return;
                    }
                    string accept = Convert.ToBase64String(
                        SHA1.HashData(Encoding.ASCII.GetBytes(key + MAGIC)));
                    string resp = "HTTP/1.1 101 Switching Protocols\r\n" +
                                  "Upgrade: websocket\r\nConnection: Upgrade\r\n" +
                                  $"Sec-WebSocket-Accept: {accept}\r\n\r\n";
                    await stream.WriteAsync(Encoding.ASCII.GetBytes(resp));
                    await onOpen(new WsConnection(tcp, stream));
                }
                catch { try { tcp.Close(); } catch { } }
            }, ct);
        }
    }

    // Minimal, forgiving HTTP request reader: request path + websocket intent.
    private static async Task<(string path, string key, bool upgrade)> ReadRequest(NetworkStream stream)
    {
        var sb = new StringBuilder();
        var one = new byte[1];
        while (sb.Length < 16384)
        {
            int n = await stream.ReadAsync(one.AsMemory(0, 1));
            if (n <= 0) return (null, null, false);
            sb.Append((char)one[0]);
            if (sb.Length > 4 && sb[^1] == '\n' && sb[^2] == '\r' && sb[^3] == '\n' && sb[^4] == '\r')
                break;
        }
        string[] lines = sb.ToString().Split("\r\n");
        string path = null;
        string[] req = lines[0].Split(' ');
        if (req.Length >= 2 && (req[0] == "GET" || req[0] == "HEAD")) path = req[1];
        string key = null;
        bool upgrade = false;
        foreach (string line in lines)
        {
            int c = line.IndexOf(':');
            if (c < 0) continue;
            string h = line[..c].Trim().ToLowerInvariant();
            string v = line[(c + 1)..].Trim();
            if (h == "sec-websocket-key") key = v;
            if (h == "upgrade" && v.ToLowerInvariant().Contains("websocket")) upgrade = true;
        }
        return (path, key, upgrade && key != null);
    }

    // ── static hosting for the website build (round 17) ─────────────────────
    private static readonly Dictionary<string, string> MIME = new()
    {
        [".html"] = "text/html; charset=utf-8",
        [".js"] = "text/javascript",
        [".wasm"] = "application/wasm",          // required for streaming compile
        [".pck"] = "application/octet-stream",
        [".png"] = "image/png",
        [".ico"] = "image/x-icon",
        [".svg"] = "image/svg+xml",
        [".css"] = "text/css",
        [".json"] = "application/json",
    };

    // Wherever the server was launched from, find the exported build: repo root
    // (run_server.bat), Tools/GameServer itself, or next to the built exe.
    private static IEnumerable<string> WebRoots()
    {
        yield return Path.Combine("Tools", "GameServer", "web");
        yield return "web";
        yield return Path.Combine(AppContext.BaseDirectory, "web");
    }

    private static async Task ServeStatic(NetworkStream stream, string rawPath)
    {
        string path = Uri.UnescapeDataString(rawPath.Split('?')[0].Split('#')[0]);
        if (path is "/" or "") path = "/index.html";
        string file = null;
        foreach (string root in WebRoots())
        {
            string full = Path.GetFullPath(root);
            string cand = Path.GetFullPath(Path.Combine(full, path.TrimStart('/')));
            if (!cand.StartsWith(full, StringComparison.Ordinal)) continue;   // no ../ escapes
            if (File.Exists(cand)) { file = cand; break; }
        }
        if (file == null)
        {
            byte[] miss = Encoding.UTF8.GetBytes(
                "<html><body style=\"font-family:sans-serif\"><h2>UKO server is running.</h2>" +
                "<p>No website build here yet: export the Web preset into " +
                "<code>Tools/GameServer/web</code> (see DEPLOY_WEB.md), then refresh.</p></body></html>");
            await Respond(stream, "404 Not Found", "text/html; charset=utf-8", miss);
            return;
        }
        byte[] body = await File.ReadAllBytesAsync(file);
        string mime = MIME.GetValueOrDefault(Path.GetExtension(file).ToLowerInvariant(),
            "application/octet-stream");
        await Respond(stream, "200 OK", mime, body);
    }

    // Cross-origin-isolation headers ride on every response so a threads-ON
    // web export (SharedArrayBuffer) works from this server too; same-origin
    // assets satisfy COEP automatically. no-cache: re-exports show up on F5.
    private static async Task Respond(NetworkStream stream, string status, string mime, byte[] body)
    {
        string head = $"HTTP/1.1 {status}\r\n" +
                      $"Content-Type: {mime}\r\n" +
                      $"Content-Length: {body.Length}\r\n" +
                      "Cache-Control: no-cache\r\n" +
                      "Cross-Origin-Opener-Policy: same-origin\r\n" +
                      "Cross-Origin-Embedder-Policy: require-corp\r\n" +
                      "Cross-Origin-Resource-Policy: same-origin\r\n" +
                      "Connection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.ASCII.GetBytes(head));
        await stream.WriteAsync(body);
        await stream.FlushAsync();
    }
}
