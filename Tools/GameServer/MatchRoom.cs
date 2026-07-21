// MatchRoom.cs -- one online match, run with real authority. The room is the
// MatchMediator made trustworthy: it holds each player's committed plan until
// BOTH are in (the simultaneity guarantee -- no client can peek), detects the
// contested-tile clash and runs the stance sub-round (the online half of round
// 11), resolves every turn with the server's own engine as the arbiter of
// record, enforces turn deadlines, awards forfeits on disconnect, and logs every
// completed match as training rows -- the learn-from-humans stream.
//
// Bots: a seat with no connection is played by the EXTREME brain. The brain's
// statics are single-threaded by design, so ALL brain work (plans and clash
// stances, across every room) serializes through one semaphore.
namespace UKO.Server;

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using UKO;

public sealed class Seat
{
    public string Slot;                 // "A" or "B"
    public WsConnection Conn;           // null = bot seat
    public string Name = "?";
    public List<string> Gear = new() { "", "", "", "" };
    public List<PlanAction> Plan;       // committed plan this turn (held until both)
    public string Stance;               // committed stance in a clash sub-round
    public bool IsBot => Conn == null;
}

public sealed class MatchRoom
{
    private static readonly SemaphoreSlim Brain = new(1, 1);   // ONE brain search at a time, server-wide
    private static readonly Random Rng = new();

    private readonly object _lock = new();
    private readonly Seat _a, _b;
    private readonly SimWorld.World _w;
    private Combatant _ca, _cb;
    private int _turn = 1;
    private enum Phase { Plans, Stances, Done }
    private Phase _phase = Phase.Plans;
    private Timer _deadline;
    private readonly int _deadlineSec;
    private readonly int _botBudget;
    private readonly string _logPath;
    private readonly long _matchId;
    private readonly List<(string line, bool seatA)> _rows = new();
    public bool Over { get; private set; }

    public MatchRoom(Seat a, Seat b, bool flatMap, int deadlineSec, int botBudget, string logPath)
    {
        _a = a; _b = b;
        _deadlineSec = deadlineSec;
        _botBudget = botBudget;
        _logPath = logPath;
        _matchId = Rng.NextInt64(3_000_000, 4_000_000);   // training-row id range: online era
        var rng = new Random(unchecked((int)_matchId));
        _w = flatMap ? FlatWorld() : SimWorld.Generate(rng);
        _ca = new Combatant("A", _w.SpawnA, (int)Config.Facing.EAST);
        _ca.Equip(a.Gear);
        _cb = new Combatant("B", _w.SpawnB, (int)Config.Facing.WEST);
        _cb.Equip(b.Gear);
    }

    private static SimWorld.World FlatWorld()
    {
        var w = new SimWorld.World
        {
            SpawnA = new Vec2I(Config.SPAWN_INSET, SimWorld.SIZE / 2),
            SpawnB = new Vec2I(SimWorld.SIZE - 1 - Config.SPAWN_INSET, SimWorld.SIZE / 2),
        };
        w.G.BaseBlocked = (bool[,])w.G.Blocked.Clone();
        w.BaseBlocked = (bool[,])w.G.Blocked.Clone();
        return w;
    }

    public async Task Start()
    {
        foreach (var s in new[] { _a, _b })
            if (!s.IsBot)
                await s.Conn.SendText(Wire.Msg("matched", o =>
                {
                    o["seat"] = s.Slot;
                    o["foe"] = (s == _a ? _b : _a).Name;
                    o["rows"] = Wire.RowsJson(_w.G.Blocked);
                    o["gear_a"] = Wire.GearJson(_a.Gear);
                    o["gear_b"] = Wire.GearJson(_b.Gear);
                    o["deadline"] = _deadlineSec;
                }));
        BeginTurn();
    }

    private void BeginTurn()
    {
        lock (_lock)
        {
            _phase = Phase.Plans;
            _a.Plan = null; _b.Plan = null;
            _a.Stance = null; _b.Stance = null;
            _rows.Add((TrainingCsv.Row(_matchId, _turn, "A", _ca, _cb, _w.G), true));
            _rows.Add((TrainingCsv.Row(_matchId, _turn, "B", _cb, _ca, _w.G), false));
            ArmDeadline(_deadlineSec, () => ForceMissingPlans());
        }
        foreach (var s in new[] { _a, _b })
            if (s.IsBot) _ = BotPlan(s);
    }

    public void SubmitPlan(Seat seat, List<PlanAction> seq)
    {
        lock (_lock)
        {
            if (_phase != Phase.Plans || Over || seat.Plan != null || seq == null) return;
            seat.Plan = seq;
            if (_a.Plan == null || _b.Plan == null) return;
            _deadline?.Dispose();
        }
        ProceedFromPlans();
    }

    private void ForceMissingPlans()
    {
        lock (_lock)
        {
            if (_phase != Phase.Plans || Over) return;
            _a.Plan ??= WaitPlan();
            _b.Plan ??= WaitPlan();
        }
        ProceedFromPlans();
    }

    private static List<PlanAction> WaitPlan()
        => new() { new PlanAction("wait"), new PlanAction("wait") };

    private void ProceedFromPlans()
    {
        bool clash;
        lock (_lock)
        {
            if (_phase != Phase.Plans || Over) return;
            // Dry run (the resolver is pure): does this turn contain a contested-tile
            // clash? If so, hold the reveal and ask both sides for a stance first.
            var dry = Resolver.Resolve(_w.G, _ca, _cb, _a.Plan, _b.Plan, _turn);
            clash = dry.Events.Any(e => e.Type == ResolverEvents.Clash);
            _phase = clash ? Phase.Stances : Phase.Done;
            if (clash)
                ArmDeadline(15, () => ForceMissingStances());
        }
        if (clash)
        {
            foreach (var s in new[] { _a, _b })
            {
                if (s.IsBot) _ = BotStance(s);
                else _ = s.Conn.SendText(Wire.Msg("clash", o => o["turn"] = _turn));
            }
            return;
        }
        ResolveTurn();
    }

    public void SubmitStance(Seat seat, string stance)
    {
        lock (_lock)
        {
            if (_phase != Phase.Stances || Over || seat.Stance != null) return;
            seat.Stance = stance;
            if (_a.Stance == null || _b.Stance == null) return;
            _deadline?.Dispose();
            StampStances();
            _phase = Phase.Done;
        }
        ResolveTurn();
    }

    private void ForceMissingStances()
    {
        lock (_lock)
        {
            if (_phase != Phase.Stances || Over) return;
            _a.Stance ??= "push";
            _b.Stance ??= "push";
            StampStances();
            _phase = Phase.Done;
        }
        ResolveTurn();
    }

    private void StampStances()
    {
        foreach (var (seat, plan) in new[] { (_a, _a.Plan), (_b, _b.Plan) })
            for (int i = 0; i < plan.Count; i++)
                if (plan[i].Id == "move")
                    plan[i] = new PlanAction("move", plan[i].Tile, plan[i].Facing, seat.Stance);
    }

    private void ResolveTurn()
    {
        List<PlanAction> pa, pb;
        string result;
        lock (_lock)
        {
            if (Over) return;
            pa = _a.Plan; pb = _b.Plan;
            var outp = Resolver.Resolve(_w.G, _ca, _cb, pa, pb, _turn);
            _ca = outp.A;
            _cb = outp.B;
            result = outp.Result;
        }
        foreach (var s in new[] { _a, _b })
            if (!s.IsBot)
                _ = s.Conn.SendText(Wire.Msg("reveal", o =>
                {
                    o["turn"] = _turn;
                    o["seq_a"] = Wire.SeqJson(pa);
                    o["seq_b"] = Wire.SeqJson(pb);
                }));
        if (result != "ongoing") { Finish(result); return; }
        lock (_lock)
        {
            if (_turn % Config.MAP_ROTATE_EVERY == 0)
            {
                var positions = new[] { _ca.Pos, _cb.Pos };
                var (crushed, newPos) = SimWorld.RotateBlockers(_w, positions);
                _ca.Pos = newPos[0];
                _cb.Pos = newPos[1];
                foreach (int idx in crushed)
                {
                    var who = idx == 0 ? _ca : _cb;
                    who.Hp = Math.Max(1, who.Hp - Config.MAP_CRUSH_DAMAGE);
                    who.RestReady = false;
                }
            }
            _turn++;
            if (_turn > 80) { /* stall cap, mirrors the harness draw rule */ }
        }
        if (_turn > 80) Finish("draw");
        else BeginTurn();
    }

    private void Finish(string result)
    {
        lock (_lock)
        {
            if (Over) return;
            Over = true;
            _deadline?.Dispose();
        }
        foreach (var s in new[] { _a, _b })
            if (!s.IsBot)
                _ = s.Conn.SendText(Wire.Msg("over", o => o["result"] = result));
        LogMatch(result);
    }

    // Disconnect / leave: the remaining player wins by forfeit. Abandoned matches
    // are NOT logged as training data (a ragequit outcome teaches the judge nothing).
    public void OnGone(Seat gone)
    {
        lock (_lock)
        {
            if (Over) return;
            Over = true;
            _deadline?.Dispose();
        }
        var other = gone == _a ? _b : _a;
        if (!other.IsBot)
        {
            _ = other.Conn.SendText(Wire.Msg("foe_left"));
            _ = other.Conn.SendText(Wire.Msg("over", o => o["result"] = "forfeit_win"));
        }
    }

    private void LogMatch(string result)
    {
        if (_logPath == "") return;
        try
        {
            lock (Brain)   // reuse as a cheap global file lock; writes are rare
            {
                if (!File.Exists(_logPath))
                    File.WriteAllText(_logPath, TrainingCsv.HEADER + "\n");
                using var f = new StreamWriter(_logPath, append: true);
                foreach (var (line, seatA) in _rows)
                    f.WriteLine($"{line},{TrainingCsv.Outcome(result, seatA)}");
            }
        }
        catch { /* a failed log line must never break a match */ }
    }

    private void ArmDeadline(int seconds, Action onFire)
    {
        _deadline?.Dispose();
        if (seconds <= 0) return;
        _deadline = new Timer(_ => onFire(), null, seconds * 1000, Timeout.Infinite);
    }

    // ── bot seats: the EXTREME brain, serialized server-wide ──
    private async Task BotPlan(Seat seat)
    {
        await Brain.WaitAsync();
        List<PlanAction> seq;
        try
        {
            ExtremeAI.BudgetOverrideMs = _botBudget;
            Eval.ClearCache();
            var (me, foe) = seat.Slot == "A" ? (_ca, _cb) : (_cb, _ca);
            seq = ExtremeAI.ChooseSequence(me, foe, _w.G, null);
        }
        catch { seq = WaitPlan(); }
        finally { Brain.Release(); }
        if (seq == null || seq.Count == 0) seq = WaitPlan();
        SubmitPlan(seat, seq);
    }

    // The bot's clash answer: solve the 3x3 stance game on the ACTUAL committed
    // plans (each cell = the real resolved outcome scored by the shared Eval),
    // mix with NashSolver, sample. Mirrors ClashOracle.gd.
    private async Task BotStance(Seat seat)
    {
        await Brain.WaitAsync();
        string pick;
        try
        {
            string[] stances = { "push", "pull", "feint" };
            var (me, foe) = seat.Slot == "A" ? (_ca, _cb) : (_cb, _ca);
            var (myPlan, foePlan) = seat.Slot == "A" ? (_a.Plan, _b.Plan) : (_b.Plan, _a.Plan);
            var m = new double[3][];
            for (int i = 0; i < 3; i++)
            {
                m[i] = new double[3];
                for (int j = 0; j < 3; j++)
                {
                    var mine = Stamped(myPlan, stances[i]);
                    var theirs = Stamped(foePlan, stances[j]);
                    Eval.ClearCache();
                    m[i][j] = Eval.ScoreRich(me, foe, _w.G, mine, theirs);
                }
            }
            var mix = NashSolver.Solve(m);
            double r = Rng.NextDouble(), acc = 0;
            pick = stances[0];
            for (int i = 0; i < 3; i++) { acc += mix[i]; if (r <= acc) { pick = stances[i]; break; } }
        }
        catch { pick = "push"; }
        finally { Brain.Release(); }
        SubmitStance(seat, pick);
    }

    private static List<PlanAction> Stamped(List<PlanAction> plan, string stance)
    {
        var outp = new List<PlanAction>();
        foreach (var a in plan)
            outp.Add(a.Id == "move" ? new PlanAction("move", a.Tile, a.Facing, stance) : a);
        return outp;
    }
}
