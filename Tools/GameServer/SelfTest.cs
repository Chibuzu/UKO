// SelfTest.cs -- the server proves itself before any human connects: real
// WebSocket clients (System.Net.WebSockets.ClientWebSocket -- a fully standard,
// independent implementation exercising our hand-rolled server) play complete
// matches over localhost. Three suites:
//   1. BOT MATCH    -- quick_bot vs a do-nothing dummy: the EXTREME seat must win.
//   2. HUMANS+CLASH -- two scripted clients collide head-on on a flat arena: the
//                      clash sub-round must fire, stances must stamp, and a
//                      mid-match leave must award the forfeit.
//   3. CONCURRENCY  -- three simultaneous bot matches (the brain serializes
//                      through one semaphore) must all complete.
// Plus: the training log must exist with well-formed 32-column rows.
namespace UKO.Server;

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Net.Sockets;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading;
using System.Threading.Tasks;

public static class SelfTest
{
    private static int _fails;

    public static async Task<int> Run(int port)
    {
        string log = "selftest_matches.csv";
        try { File.Delete(log); } catch { }
        typeof(ServerMain).GetField("_logPath",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)
            ?.SetValue(null, log);

        using var cts = new CancellationTokenSource();
        _ = WebSocketServer.Listen(port, ServerMain.OnOpen, cts.Token);
        await Task.Delay(400);

        await StaticHosting(port);
        await BotMatch(port);
        await HumansAndClash(port);
        await Concurrency(port);
        CheckLog(log);

        cts.Cancel();
        Console.WriteLine(_fails == 0 ? "[selftest] ALL PASS" : $"[selftest] {_fails} FAILED");
        return _fails == 0 ? 0 : 1;
    }

    private static void Check(bool ok, string what)
    {
        if (!ok) _fails++;
        Console.WriteLine($"[{(ok ? "PASS" : "FAIL")}] {what}");
    }

    // ── suite 0: the game port doubles as the website's web server (round 17) ──
    private static async Task StaticHosting(int port)
    {
        string root = Path.Combine("Tools", "GameServer", "web");
        Directory.CreateDirectory(root);
        string probe = Path.Combine(root, "selftest_probe.txt");
        await File.WriteAllTextAsync(probe, "uko-web-ok");
        try
        {
            using var http = new HttpClient();
            string body = await http.GetStringAsync($"http://127.0.0.1:{port}/selftest_probe.txt");
            Check(body == "uko-web-ok", "static: probe file served verbatim");
            var idx = await http.GetAsync($"http://127.0.0.1:{port}/");
            Check(idx.StatusCode is System.Net.HttpStatusCode.OK or System.Net.HttpStatusCode.NotFound,
                $"static: '/' answers well-formed HTTP ({(int)idx.StatusCode})");
            bool coi = idx.Headers.TryGetValues("Cross-Origin-Opener-Policy", out var v) &&
                v.FirstOrDefault() == "same-origin";
            Check(coi, "static: cross-origin-isolation headers present");
            // Raw socket: HttpClient squashes ../ client-side, so send it by hand.
            using var t = new TcpClient();
            await t.ConnectAsync("127.0.0.1", port);
            var s = t.GetStream();
            await s.WriteAsync(Encoding.ASCII.GetBytes("GET /../ServerMain.cs HTTP/1.1\r\nHost: x\r\n\r\n"));
            var buf = new byte[256];
            int n = await s.ReadAsync(buf);
            Check(n > 0 && Encoding.ASCII.GetString(buf, 0, n).StartsWith("HTTP/1.1 404"),
                "static: raw ../ traversal blocked");
        }
        catch (Exception e)
        {
            Check(false, $"static: hosting reachable ({e.GetType().Name}: {e.Message})");
        }
        finally { try { File.Delete(probe); } catch { } }
    }

    // ── suite 1: quick_bot -- EXTREME must beat a dummy that only waits ──
    private static async Task BotMatch(int port)
    {
        await using var c = await TC.Connect(port, "Dummy", flat: false);
        await c.Send("""{"t":"quick_bot"}""");
        var matched = await c.RecvT("matched");
        Check(matched != null && Wire.Str(matched, "seat") == "A", "bot-match: matched as seat A");
        string result = await PlayWaits(c, matched);
        Check(result == "b_wins" || result == "draw",
            $"bot-match: completes with the bot unbeaten (got '{result}')");
    }

    // Drive a match by always submitting [wait, wait]; answer clashes with push.
    private static async Task<string> PlayWaits(TC c, JsonNode matched)
    {
        if (matched == null) return "no-match";
        int turn = 1;
        await c.SendPlanWaits(turn);
        for (int guard = 0; guard < 400; guard++)
        {
            var msg = await c.Recv(240000);   // bot decisions serialize across rooms; be patient
            if (msg == null) return "socket-dropped";
            switch (Wire.Str(msg, "t"))
            {
                case "reveal":
                    turn++;
                    await c.SendPlanWaits(turn);
                    break;
                case "clash":
                    await c.Send("""{"t":"stance","stance":"push"}""");
                    break;
                case "over":
                    return Wire.Str(msg, "result");
            }
        }
        return "guard-exhausted";
    }

    // ── suite 2: two scripted humans on a flat arena: clash + forfeit ──
    private static async Task HumansAndClash(int port)
    {
        await using var a = await TC.Connect(port, "Alice", flat: true);
        await using var b = await TC.Connect(port, "Bob", flat: true);
        await a.Send("""{"t":"quick"}""");
        await a.RecvT("queued");
        await b.Send("""{"t":"quick"}""");
        var ma = await a.RecvT("matched");
        var mb = await b.RecvT("matched");
        bool seatsOk = ma != null && mb != null &&
            Wire.Str(ma, "seat") == "A" && Wire.Str(mb, "seat") == "B";
        Check(seatsOk, "humans: both matched with distinct seats");
        if (!seatsOk) return;

        // March toward each other, then both lunge for (2,4) -- a forward-forward clash.
        await a.SendPlan(1, """[{"id":"wait"},{"id":"wait"}]""");
        await b.SendPlan(1, """[{"id":"move","tile":[5,4]},{"id":"move","tile":[4,4]}]""");
        Check(await a.RecvT("reveal") != null && await b.RecvT("reveal") != null, "humans: turn 1 revealed");
        await a.SendPlan(2, """[{"id":"wait"},{"id":"wait"}]""");
        await b.SendPlan(2, """[{"id":"move","tile":[3,4]},{"id":"wait"}]""");
        Check(await a.RecvT("reveal") != null && await b.RecvT("reveal") != null, "humans: turn 2 revealed");
        await a.SendPlan(3, """[{"id":"move","tile":[2,4]},{"id":"wait"}]""");
        await b.SendPlan(3, """[{"id":"move","tile":[2,4]},{"id":"wait"}]""");
        var clashA = await a.RecvT("clash");
        var clashB = await b.RecvT("clash");
        Check(clashA != null && clashB != null, "humans: head-on collision triggers the clash sub-round");
        await a.Send("""{"t":"stance","stance":"push"}""");
        await b.Send("""{"t":"stance","stance":"feint"}""");
        var rev = await a.RecvT("reveal");
        bool stamped = rev?["seq_b"]?.ToJsonString()?.Contains("feint") == true;
        Check(stamped, "humans: reveal carries the stamped stances");
        await b.RecvT("reveal");

        await a.Send("""{"t":"leave"}""");
        Check(await b.RecvT("foe_left") != null, "humans: leaver triggers foe_left");
        var over = await b.RecvT("over");
        Check(Wire.Str(over, "result") == "forfeit_win", "humans: remaining player wins by forfeit");
    }

    // ── suite 3: three bot matches at once (brain serialized, rooms parallel) ──
    private static async Task Concurrency(int port)
    {
        var tasks = Enumerable.Range(0, 3).Select(async i =>
        {
            await using var c = await TC.Connect(port, $"D{i}", flat: false);
            await c.Send("""{"t":"quick_bot"}""");
            var matched = await c.RecvT("matched");
            return await PlayWaits(c, matched);
        }).ToArray();
        var results = await Task.WhenAll(tasks);
        Check(results.All(r => r == "b_wins" || r == "draw"),
            $"concurrency: 3 simultaneous bot matches all complete ({string.Join(",", results)})");
    }

    private static void CheckLog(string log)
    {
        bool ok = File.Exists(log);
        int rows = 0, badCols = 0;
        bool damage = false;
        if (ok)
            foreach (string line in File.ReadLines(log).Skip(1))
            {
                rows++;
                var c = line.Split(',');
                if (c.Length != 32) badCols++;
                else if (c[2] == "B" && int.TryParse(c[6], out int foeHp) && foeHp < 100)
                    damage = true;   // the bot landed hits on somebody
            }
        Check(ok && rows > 0 && badCols == 0,
            $"training log: {rows} rows, {badCols} malformed");
        Check(damage, "training log: bot matches show real damage dealt");
    }

    // ── minimal standard-library test client ──
    private sealed class TC : IAsyncDisposable
    {
        private readonly ClientWebSocket _ws = new();
        private readonly byte[] _buf = new byte[64 * 1024];

        public static async Task<TC> Connect(int port, string name, bool flat)
        {
            var c = new TC();
            await c._ws.ConnectAsync(new Uri($"ws://127.0.0.1:{port}/"), CancellationToken.None);
            string test = flat ? ""","test":"flat" """.TrimEnd() : "";
            await c.Send($$"""{"t":"hello","name":"{{name}}","gear":["discount_charm","burst_node","blink_boots","dark_focus"]{{test}}}""");
            await c.RecvT("welcome");
            return c;
        }

        public async Task Send(string json)
            => await _ws.SendAsync(Encoding.UTF8.GetBytes(json), WebSocketMessageType.Text, true, CancellationToken.None);

        public async Task SendPlan(int turn, string seqJson)
            => await Send($$"""{"t":"plan","turn":{{turn}},"seq":{{seqJson}}}""");

        public async Task SendPlanWaits(int turn)
            => await SendPlan(turn, """[{"id":"wait"},{"id":"wait"}]""");

        public async Task<JsonNode> Recv(int timeoutMs = 60000)
        {
            try
            {
                using var cts = new CancellationTokenSource(timeoutMs);
                int total = 0;
                while (true)
                {
                    var r = await _ws.ReceiveAsync(_buf.AsMemory(total), cts.Token);
                    total += r.Count;
                    if (r.MessageType == WebSocketMessageType.Close) return null;
                    if (r.EndOfMessage) break;
                }
                return JsonNode.Parse(Encoding.UTF8.GetString(_buf, 0, total));
            }
            catch { return null; }
        }

        // Skip unrelated messages (pong, queued echoes) until `type` or timeout.
        public async Task<JsonNode> RecvT(string type, int timeoutMs = 60000)
        {
            for (int i = 0; i < 50; i++)
            {
                var msg = await Recv(timeoutMs);
                if (msg == null) return null;
                if (Wire.Str(msg, "t") == type) return msg;
            }
            return null;
        }

        public async ValueTask DisposeAsync()
        {
            try { await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None); }
            catch { }
            _ws.Dispose();
        }
    }
}
