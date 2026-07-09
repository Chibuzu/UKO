// Eval.cs -- C# BRAIN PORT. Faithful port of Scripts/AI/Eval.gd: the shared per-pair
// scorer + situation evaluator + selective-depth subgame values.
// Framework-free: CAL_A is SET by the bridge (which reads user://calibration.cfg);
// the incoming-walls cache keys on (grid ref, rot, shrink) instead of instance id.
namespace UKO;

using System;
using System.Collections.Generic;

public static class Eval
{
	// ── Transition weights ────────────────────────────────────────────────────
	public static double W_DEAL = 1.0;
	public static double W_TAKE = 1.25;
	public const double W_WIN = 1000.0;

	// ── Situational weights ───────────────────────────────────────────────────
	public static double W_ENERGY = 0.08;
	public static double W_MP = 0.05;
	public static double W_LOCK = 0.25;
	public const int LOCK_THRESH = 30;
	public static double W_DANGER_MELEE = 0.5;
	public static double W_DANGER_SPELL = 0.6;
	public static double W_PRESSURE = 0.45;
	public static double W_ATTRITION = 8.0;
	public static double W_TEMPO = 0.3;
	public static double W_MOBILITY = 1.5;
	public static double W_PRESS = 0.2;
	public static double W_INCOMING = 6.0;
	public static double W_CENTER = 0.5;
	public static double W_ITEM = 2.0;
	public static double W_LETHAL = 2.5;

	// ── Lookahead ─────────────────────────────────────────────────────────────
	public const int LOOKAHEAD_DEPTH = 2;
	public const int DEEP_CANDS = 3;
	public const int DEEP_ITERS = 64;
	public static double DISCOUNT = 0.9;

	// ── Calibration (set by the bridge from user://calibration.cfg) ──────────
	public static double CAL_A = 0.0;
	public static double ToWinprob(double score) => 1.0 / (1.0 + Math.Exp(-CAL_A * score));

	// Snapshot of hand defaults so profiles can restore at runtime (mirrors DEFAULTS).
	public static readonly Dictionary<string, double> Defaults = GetWeights();

	public static Dictionary<string, double> GetWeights() => new()
	{
		["W_DEAL"] = W_DEAL, ["W_TAKE"] = W_TAKE, ["W_ENERGY"] = W_ENERGY, ["W_MP"] = W_MP,
		["W_LOCK"] = W_LOCK, ["W_DANGER_MELEE"] = W_DANGER_MELEE, ["W_DANGER_SPELL"] = W_DANGER_SPELL,
		["W_PRESSURE"] = W_PRESSURE, ["W_ATTRITION"] = W_ATTRITION, ["W_TEMPO"] = W_TEMPO,
		["W_MOBILITY"] = W_MOBILITY, ["W_PRESS"] = W_PRESS, ["W_INCOMING"] = W_INCOMING,
		["W_CENTER"] = W_CENTER, ["W_ITEM"] = W_ITEM, ["W_LETHAL"] = W_LETHAL, ["DISCOUNT"] = DISCOUNT,
	};

	public static void SetWeights(Dictionary<string, double> w)
	{
		foreach (var kv in w)
		{
			double v = kv.Value;
			switch (kv.Key)
			{
				case "W_DEAL": W_DEAL = v; break;
				case "W_TAKE": W_TAKE = v; break;
				case "W_ENERGY": W_ENERGY = v; break;
				case "W_MP": W_MP = v; break;
				case "W_LOCK": W_LOCK = v; break;
				case "W_DANGER_MELEE": W_DANGER_MELEE = v; break;
				case "W_DANGER_SPELL": W_DANGER_SPELL = v; break;
				case "W_PRESSURE": W_PRESSURE = v; break;
				case "W_ATTRITION": W_ATTRITION = v; break;
				case "W_TEMPO": W_TEMPO = v; break;
				case "W_MOBILITY": W_MOBILITY = v; break;
				case "W_PRESS": W_PRESS = v; break;
				case "W_INCOMING": W_INCOMING = v; break;
				case "W_CENTER": W_CENTER = v; break;
				case "W_ITEM": W_ITEM = v; break;
				case "W_LETHAL": W_LETHAL = v; break;
				case "DISCOUNT": DISCOUNT = v; break;
			}
		}
	}

	// Per-decision transposition cache for solved subgame values.
	private static readonly Dictionary<string, double> SubCache = new();
	public static void ClearCache() => SubCache.Clear();

	public static double ScoreRich(Combatant me, Combatant foe, Grid grid,
			List<PlanAction> mySeq, List<PlanAction> foeSeq)
		=> ScoreDeep(me, foe, grid, mySeq, foeSeq, 0);

	// Seat-correct forward model (same seats as reality) + depth-aware leaf.
	public static double ScoreDeep(Combatant me, Combatant foe, Grid grid,
			List<PlanAction> mySeq, List<PlanAction> foeSeq, int depth)
	{
		ResolveResult outp;
		if (me.Id == "A")
			outp = Resolver.Resolve(grid, me, foe, mySeq, foeSeq, 0);
		else
			outp = Resolver.Resolve(grid, foe, me, foeSeq, mySeq, 0);
		bool meA = me.Id == "A";
		Combatant foeAfter = meA ? outp.B : outp.A;
		Combatant meAfter = meA ? outp.A : outp.B;
		double dealt = foe.Hp - foeAfter.Hp;
		double taken = me.Hp - meAfter.Hp;
		double s = dealt * W_DEAL - taken * W_TAKE;
		string res = outp.Result;
		string myWin = meA ? "a_wins" : "b_wins";
		if (res == myWin) s += W_WIN;
		else if (res == "a_wins" || res == "b_wins") s -= W_WIN;
		if (depth <= 0 || res == "a_wins" || res == "b_wins")
			return s + EvalSituation(meAfter, foeAfter, grid);
		return s + DISCOUNT * SubgameValue(meAfter, foeAfter, grid, depth);
	}

	private static double SubgameValue(Combatant me, Combatant foe, Grid grid, int depth)
	{
		string key = StateKey(me, foe, grid, depth);
		if (SubCache.TryGetValue(key, out double cached)) return cached;
		double v = SubgameValueRaw(me, foe, grid, depth);
		SubCache[key] = v;
		return v;
	}

	private static double SubgameValueRaw(Combatant me, Combatant foe, Grid grid, int depth)
	{
		var myC = CappedCands(me, foe, grid);
		if (myC.Count == 0) return EvalSituation(me, foe, grid);
		var foeC = CappedCands(foe, me, grid);
		if (foeC.Count == 0)
			foeC = new List<List<PlanAction>> { new() { new PlanAction("rest") } };
		var M = new double[myC.Count][];
		for (int i = 0; i < myC.Count; i++)
		{
			M[i] = new double[foeC.Count];
			for (int j = 0; j < foeC.Count; j++)
				M[i][j] = ScoreDeep(me, foe, grid, myC[i], foeC[j], depth - 1);
		}
		var mix = NashSolver.SolveIters(M, DEEP_ITERS);
		return NashSolver.ValueOf(M, mix);
	}

	private static List<List<PlanAction>> CappedCands(Combatant me, Combatant foe, Grid grid)
	{
		var clean = new List<List<PlanAction>>();
		foreach (var c in AIToolkit.Candidates(me, foe, grid))
			if (c.Count > 0) clean.Add(c);
		if (clean.Count <= DEEP_CANDS) return clean;
		var ranked = new List<(List<PlanAction> Seq, double V)>();
		foreach (var c in clean)
			ranked.Add((c, CheapRank(me, foe, grid, c)));
		// Godot's sort_custom is UNSTABLE; the GDScript side now uses an explicit
		// value-then-index tie-break to match this stable top-k (defined behavior).
		return StableTop(ranked, DEEP_CANDS);
	}

	// Stable descending top-k (preserves original order on ties, like GDScript's insertion sort).
	private static List<List<PlanAction>> StableTop(List<(List<PlanAction> Seq, double V)> ranked, int k)
	{
		var idx = new List<int>();
		for (int i = 0; i < ranked.Count; i++) idx.Add(i);
		idx.Sort((a, b) =>
		{
			int c = ranked[b].V.CompareTo(ranked[a].V);
			return c != 0 ? c : a.CompareTo(b);
		});
		var outp = new List<List<PlanAction>>();
		for (int n = 0; n < Math.Min(k, idx.Count); n++)
			outp.Add(ranked[idx[n]].Seq);
		return outp;
	}

	private static double CheapRank(Combatant me, Combatant foe, Grid grid, List<PlanAction> seq)
	{
		var m = me.Clone();
		foreach (var a in seq) AIToolkit.ApplyProjection(m, a);
		return ThreatModel.WorstDamage(m, foe, grid) * W_DEAL - ThreatModel.WorstDamage(foe, m, grid) * W_TAKE;
	}

	// ── Situation value (the strategist's heart; mirrors _eval_situation) ────
	public static double EvalSituation(Combatant me, Combatant foe, Grid grid)
	{
		double v = 0.0;

		v += W_ENERGY * (me.Energy - foe.Energy);
		v += W_MP * (me.Mp - foe.Mp);
		v -= W_LOCK * Math.Max(0, LOCK_THRESH - me.Energy) * PulseRelief(me);
		v += W_LOCK * Math.Max(0, LOCK_THRESH - foe.Energy) * PulseRelief(foe);

		var danger = ThreatModel.Incoming(foe, me, grid);
		var mine = ThreatModel.Incoming(me, foe, grid);
		int dtot = danger.Blockable + danger.Unblockable;
		double lethalMult = (dtot >= me.Hp && me.Hp > 0) ? W_LETHAL : 1.0;
		double fear = 1.0 + 1.2 * (1.0 - (double)me.Hp / Config.MAX_HP);
		v -= ((W_DANGER_MELEE * danger.Blockable + W_DANGER_SPELL * danger.Unblockable) * lethalMult) * fear;
		v += W_PRESSURE * (mine.Blockable + mine.Unblockable);

		bool foeStarved = foe.Energy < Config.COST_ATTACK;
		bool meStarved = me.Energy < Config.COST_ATTACK;
		if (foeStarved && !meStarved) v += W_ATTRITION;
		else if (meStarved && !foeStarved) v -= W_ATTRITION;

		var iw = IncomingSet(grid);
		if (iw.Contains(me.Pos)) v -= W_INCOMING;
		if (iw.Contains(foe.Pos)) v += W_INCOMING;
		if (grid.ShrinkLevel > 0)
			v += W_CENTER * grid.ShrinkLevel * (EdgeDepth(me.Pos) - EdgeDepth(foe.Pos));

		double meG = me.SpentOnce.ContainsKey("grenade") ? 0.0 : 1.0;
		double foeG = foe.SpentOnce.ContainsKey("grenade") ? 0.0 : 1.0;
		v += W_ITEM * (meG - foeG);

		double hpAdv = me.Hp - foe.Hp;
		if (hpAdv > 0.0)
		{
			double prox = 1.0 / (1 + Grid.Dist(me.Pos, foe.Pos));
			v += W_PRESS * hpAdv * prox;
		}

		if (me.SpeedBoost && !foe.SpeedBoost) v += W_TEMPO;
		else if (foe.SpeedBoost && !me.SpeedBoost) v -= W_TEMPO;
		v += W_MOBILITY * (Mobility(me, foe, grid) - Mobility(foe, me, grid));
		return v;
	}

	private static int Mobility(Combatant c, Combatant other, Grid grid)
	{
		int n = 0;
		foreach (var d in Grid.DIRS)
		{
			Vec2I p = c.Pos + d;
			if (grid.InBounds(p) && !grid.IsBlocked(p) && other.Pos != p) n++;
		}
		return n;
	}

	private static double PulseRelief(Combatant c)
	{
		int toPulse = Config.ENERGY_PULSE_ACTIONS - (c.ActionCount % Config.ENERGY_PULSE_ACTIONS);
		if (toPulse <= 1) return 0.45;
		if (toPulse <= 2) return 0.7;
		return 1.0;
	}

	// Incoming-walls cache: constant while one turn is being chosen; keyed by
	// (grid reference, rot, shrink) instead of GDScript's instance id.
	private static Grid _iwGrid = null;
	private static int _iwRot = -1, _iwShrink = -1;
	private static HashSet<Vec2I> _iwSet = new();
	private static HashSet<Vec2I> IncomingSet(Grid grid)
	{
		if (!ReferenceEquals(grid, _iwGrid) || grid.RotStep != _iwRot || grid.ShrinkLevel != _iwShrink)
		{
			_iwGrid = grid;
			_iwRot = grid.RotStep;
			_iwShrink = grid.ShrinkLevel;
			_iwSet = new HashSet<Vec2I>(grid.IncomingWalls());
		}
		return _iwSet;
	}

	private static int EdgeDepth(Vec2I p)
		=> Math.Min(Math.Min(p.X, p.Y), Math.Min(Grid.SIZE - 1 - p.X, Grid.SIZE - 1 - p.Y));

	private static string StateKey(Combatant me, Combatant foe, Grid grid, int depth)
		=> $"{depth}|{grid.RotStep}|{grid.ShrinkLevel}|{CKey(me)}|{CKey(foe)}";

	private static string CKey(Combatant c)
	{
		var cd = new List<string>(c.Cooldowns.Keys); cd.Sort();
		var st = new List<string>(c.Statuses.Keys); st.Sort();
		var sp = new List<string>(c.SpentOnce.Keys); sp.Sort();
		var cds = string.Join(",", cd.ConvertAll(k => $"{k}={c.Cooldowns[k]}"));
		var sts = string.Join(",", st.ConvertAll(k => $"{k}={c.Statuses[k]}"));
		var sps = string.Join(",", sp.ConvertAll(k => $"{k}={c.SpentOnce[k]}"));
		return $"{c.Pos.X},{c.Pos.Y},{c.Facing},{c.Hp},{c.Mp},{c.Energy},{c.ActionCount},{(c.RestReady ? 1 : 0)},{(c.SpeedBoost ? 1 : 0)},{{{cds}}},{{{sts}}},{{{sps}}}";
	}
}
