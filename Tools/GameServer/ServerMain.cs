// ServerMain.cs -- the UKO game server: lobby + rooms over the hand-rolled
// WebSocket layer. Day-one feature set, deliberately account-free:
//   hello {name, gear}         -> welcome
//   host {}                    -> hosted {code}     (4-letter room code)
//   join {code}                -> both get matched {...}
//   quick {}                   -> paired with the next quick player, or queued
//   quick_bot {}               -> instant match vs the server-side EXTREME brain
//   plan {turn, seq} / stance {stance} / leave {} / ping {} -> pong
// Every completed match appends training rows to --log (the learn-from-humans
// stream). Run via run_server.bat locally, or deployed per DEPLOY_SERVER.md.
namespace UKO.Server;

using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using UKO;

public sealed class Player
{
    public WsConnection Conn;
    public string Name = "player";
    public List<string> Gear = new() { "", "", "", "" };
    public bool TestFlat;          // honored only with --allow-test (the selftest hook)
    public MatchRoom Room;
    public Seat Seat;
}

public static class ServerMain
{
    private static readonly object Lobby = new();
    private static readonly Dictionary<string, Player> HostCodes = new();
    private static Player _quickWaiting;
    private static int _deadlineSec = 90;
    private static int _botBudget = 1500;
    private static string _logPath = "server_matches.csv";
    private static bool _allowTest;

    public static async Task<int> Main(string[] args)
    {
        var a = ParseArgs(args);
        int port = GetInt(a, "port", 8765);
        _deadlineSec = GetInt(a, "deadline", 90);
        _botBudget = GetInt(a, "bot-budget", 1500);
        _logPath = a.GetValueOrDefault("log", "server_matches.csv");
        _allowTest = a.ContainsKey("allow-test");

        ExtremeAI.SetProfile("extreme");
        Eval.LOOKAHEAD_DEPTH = 3;
        string valueCfg = a.GetValueOrDefault("value-cfg", "");
        bool armed = valueCfg != "" && ValueCfg.TryArm(valueCfg);
        Console.WriteLine($"[server] UKO game server | port {port} | deadline {_deadlineSec}s | " +
                          $"bot budget {_botBudget}ms | judge {(armed ? "ARMED" : "hand eval")} | log {_logPath}");

        if (a.ContainsKey("selftest"))
            return await SelfTest.Run(port);

        using var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; cts.Cancel(); };
        await WebSocketServer.Listen(port, OnOpen, cts.Token);
        return 0;
    }

    public static async Task OnOpen(WsConnection conn)
    {
        var player = new Player { Conn = conn };
        conn.Tag = player;
        Console.WriteLine($"[server] + {conn.Id}");
        await conn.ReceiveLoop(16 * 1024, text => Dispatch(player, text));
        Console.WriteLine($"[server] - {conn.Id} ({player.Name})");
        Cleanup(player);
    }

    private static void Cleanup(Player p)
    {
        lock (Lobby)
        {
            if (_quickWaiting == p) _quickWaiting = null;
            foreach (var kv in new List<KeyValuePair<string, Player>>(HostCodes))
                if (kv.Value == p) HostCodes.Remove(kv.Key);
        }
        p.Room?.OnGone(p.Seat);
        p.Room = null;
    }

    private static async Task Dispatch(Player p, string text)
    {
        var msg = Wire.Parse(text);
        if (msg == null) return;
        switch (Wire.Str(msg, "t"))
        {
            case "hello":
                p.Name = San(Wire.Str(msg, "name", "player"));
                p.Gear = Wire.ParseGear(msg["gear"]);
                p.TestFlat = _allowTest && Wire.Str(msg, "test") == "flat";
                await p.Conn.SendText(Wire.Msg("welcome", o => o["pid"] = p.Conn.Id));
                break;
            case "host":
            {
                string code = NewCode();
                lock (Lobby) HostCodes[code] = p;
                await p.Conn.SendText(Wire.Msg("hosted", o => o["code"] = code));
                break;
            }
            case "join":
            {
                Player host = null;
                string code = Wire.Str(msg, "code").ToUpperInvariant();
                lock (Lobby)
                {
                    if (HostCodes.TryGetValue(code, out host)) HostCodes.Remove(code);
                }
                if (host == null || host.Conn.Closed)
                    await p.Conn.SendText(Wire.Msg("err", o => o["msg"] = "no such room"));
                else
                    await StartMatch(host, p);
                break;
            }
            case "quick":
            {
                Player other = null;
                lock (Lobby)
                {
                    if (_quickWaiting != null && _quickWaiting != p && !_quickWaiting.Conn.Closed)
                    {
                        other = _quickWaiting;
                        _quickWaiting = null;
                    }
                    else
                    {
                        _quickWaiting = p;
                    }
                }
                if (other != null) await StartMatch(other, p);
                else await p.Conn.SendText(Wire.Msg("queued"));
                break;
            }
            case "quick_bot":
                await StartBotMatch(p);
                break;
            case "plan":
                p.Room?.SubmitPlan(p.Seat, Wire.ParseSeq(msg["seq"]));
                break;
            case "stance":
            {
                string s = Wire.Str(msg, "stance");
                if (s == "push" || s == "pull" || s == "feint")
                    p.Room?.SubmitStance(p.Seat, s);
                break;
            }
            case "leave":
                p.Room?.OnGone(p.Seat);
                p.Room = null;
                break;
            case "ping":
                await p.Conn.SendText(Wire.Msg("pong"));
                break;
        }
    }

    private static async Task StartMatch(Player pa, Player pb)
    {
        var sa = new Seat { Slot = "A", Conn = pa.Conn, Name = pa.Name, Gear = pa.Gear };
        var sb = new Seat { Slot = "B", Conn = pb.Conn, Name = pb.Name, Gear = pb.Gear };
        var room = new MatchRoom(sa, sb, pa.TestFlat && pb.TestFlat, _deadlineSec, _botBudget, _logPath);
        pa.Room = room; pa.Seat = sa;
        pb.Room = room; pb.Seat = sb;
        Console.WriteLine($"[server] match: {pa.Name} vs {pb.Name}");
        await room.Start();
    }

    private static async Task StartBotMatch(Player p)
    {
        var sa = new Seat { Slot = "A", Conn = p.Conn, Name = p.Name, Gear = p.Gear };
        var sb = new Seat
        {
            Slot = "B", Conn = null, Name = "EXTREME",
            Gear = new List<string> { "discount_charm", "burst_node", "blink_boots", "dark_focus" },
        };
        var room = new MatchRoom(sa, sb, p.TestFlat, _deadlineSec, _botBudget, _logPath);
        p.Room = room; p.Seat = sa;
        Console.WriteLine($"[server] match: {p.Name} vs EXTREME bot");
        await room.Start();
    }

    private static readonly Random CodeRng = new();
    private static string NewCode()
    {
        const string alpha = "ABCDEFGHJKMNPQRSTUVWXYZ";   // no I/L/O: unambiguous codes
        lock (Lobby)
        {
            while (true)
            {
                var chars = new char[4];
                for (int i = 0; i < 4; i++) chars[i] = alpha[CodeRng.Next(alpha.Length)];
                string code = new(chars);
                if (!HostCodes.ContainsKey(code)) return code;
            }
        }
    }

    private static string San(string s)
    {
        var sb = new System.Text.StringBuilder();
        foreach (char c in s)
            if (char.IsLetterOrDigit(c) || c == '_' || c == '-' || c == ' ')
                sb.Append(c);
        string outp = sb.ToString().Trim();
        return outp == "" ? "player" : outp[..Math.Min(20, outp.Length)];
    }

    private static Dictionary<string, string> ParseArgs(string[] raw)
    {
        var outp = new Dictionary<string, string>();
        for (int i = 0; i < raw.Length; i++)
            if (raw[i].StartsWith("--"))
                outp[raw[i][2..]] = (i + 1 < raw.Length && !raw[i + 1].StartsWith("--")) ? raw[++i] : "1";
        return outp;
    }

    private static int GetInt(Dictionary<string, string> a, string k, int dflt)
        => a.TryGetValue(k, out string v) && int.TryParse(v, out int n) ? n : dflt;
}
