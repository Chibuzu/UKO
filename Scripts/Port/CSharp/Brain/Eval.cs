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
	public static double W_DOORSTEP = 2.0;
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
	public static double W_SURE_PRESS = 0.35;
	public static double W_REST_PATH = 6.0;
	public static double W_TEMPO = 0.3;
	public static double W_MOBILITY = 1.5;
	public static double W_PRESS = 0.2;
	public static double W_INCOMING = 6.0;
	public static double W_CENTER = 0.5;
	public static double W_ITEM = 2.0;
	public static double W_LETHAL = 2.5;

	// ── Lookahead ─────────────────────────────────────────────────────────────
	public static int LOOKAHEAD_DEPTH = 2;   // settable (BrainBridge.SetDepth): the overnight depth dial
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
		["W_CENTER"] = W_CENTER, ["W_ITEM"] = W_ITEM, ["W_LETHAL"] = W_LETHAL,
		["W_SURE_PRESS"] = W_SURE_PRESS, ["W_REST_PATH"] = W_REST_PATH,
		["W_DOORSTEP"] = W_DOORSTEP, ["DISCOUNT"] = DISCOUNT,
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
				case "W_SURE_PRESS": W_SURE_PRESS = v; break;
				case "W_REST_PATH": W_REST_PATH = v; break;
				case "W_DOORSTEP": W_DOORSTEP = v; break;
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
			return s + Leaf(meAfter, foeAfter, grid);
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
		if (myC.Count == 0) return Leaf(me, foe, grid);
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
		var top = StableTop(ranked, DEEP_CANDS);
		// NEVER a suicidal self-model: the aggro-flavored rank above must not strip
		// the recover line from my own reply set -- a subgame whose every reply
		// stands and trades reads survivable spots as death (and vice versa). If
		// [rest] was offered at all, it stays in the cap (replacing the last pick).
		bool hasRest = false;
		foreach (var s in top) if (s.Count == 1 && s[0].Id == "rest") { hasRest = true; break; }
		if (!hasRest)
			foreach (var c in clean)
				if (c.Count == 1 && c[0].Id == "rest") { top[top.Count - 1] = c; break; }
		return top;
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
		// Damage the sequence itself COMMITS (nominal), not just the threat left after
		// it. Without this, spending actions ranked LOW (projection drains energy ->
		// post-state threat ~0) and hoarding ranked HIGH -- so capped subgames dropped
		// the foe's actual punishes and deep values went blind exactly at knife-edges.
		double committed = 0.0;
		foreach (var a in seq)
		{
			if (a.Id == "attack") committed += Config.ATTACK_DAMAGE;
			else
			{
				var d = Config.Def(a.Id);
				if (d != null && d.Effect != null && d.Effect.Type == "damage")
					committed += d.Effect.Amount ?? 0;
			}
			AIToolkit.ApplyProjection(m, a);
		}
		// WIN-RELEVANT units, not raw points: damage beyond a fighter's remaining hp
		// is worthless, and LETHAL reach is worth a whole health bar. Without this a
		// foe's killing swing ranked BELOW a sidestep (15 dmg "worth" less than the
		// counter-threat), so capped subgames modeled the foe as politely walking away.
		double deal = committed + ThreatModel.WorstDamage(m, foe, grid);
		double take = ThreatModel.WorstDamage(foe, m, grid);
		double r = Math.Min(deal, foe.Hp) * W_DEAL - Math.Min(take, m.Hp) * W_TAKE;
		if (deal >= foe.Hp) r += Config.MAX_HP;   // I can end it: worth a full bar
		if (take >= m.Hp) r -= Config.MAX_HP;     // it can end me: costs a full bar
		return r;
	}

	// ── Situation value (the strategist's heart; mirrors _eval_situation) ────
	// ── LEARNED VALUE (mirror of Eval.gd's block; agreement harness runs with it OFF) ──
	public static bool VALUE_ON = false;
	public static double[] VW = System.Array.Empty<double>();     // (28+K) weights + bias last
	public static double[] VMEAN = System.Array.Empty<double>();
	public static double[] VSTD = System.Array.Empty<double>();
	// v3: K crossed features (products of base-feature pairs) appended after the
	// 28 base columns. The PAIR LIST travels in the cfg -- the fitter owns it;
	// inference just replays it. Empty = a v1 cfg (pure linear, K = 0).
	public static int[][] VCROSS = System.Array.Empty<int[]>();
	public const double VALUE_SCALE = 100.0;

	// The leaf judge: hand eval, or the learned value when armed. ONE dispatch point.
	private static double Leaf(Combatant me, Combatant foe, Grid grid)
	{
		if (VALUE_ON && VW.Length >= 29)
			return VALUE_SCALE * (2.0 * LearnedP(me, foe, grid) - 1.0);
		return EvalSituation(me, foe, grid);
	}

	public static double LearnedP(Combatant me, Combatant foe, Grid grid)
	{
		var f = ValueFeatures(me, foe, grid);
		int nBase = f.Length;                       // 28
		int n = nBase + VCROSS.Length;              // + crossed features
		double z = VW[n];                           // bias is last
		for (int i = 0; i < n; i++)
		{
			double x = i < nBase ? f[i] : f[VCROSS[i - nBase][0]] * f[VCROSS[i - nBase][1]];
			double sd = VSTD[i];
			z += VW[i] * ((x - VMEAN[i]) / (sd > 0.0 ? sd : 1.0));
		}
		return 1.0 / (1.0 + Math.Exp(-z));
	}

	// THE v2 feature vector -- 28 values, EXACTLY the selfplay_v2.csv columns.
	// Fit (FitValue.gd), harvest (OvernightSweep) and inference must always agree.
	public static double[] ValueFeatures(Combatant me, Combatant foe, Grid grid)
	{
		int Tier(string r) => r == "front" ? 0 : r == "side" ? 1 : 2;
		int epa = Config.ENERGY_PULSE_ACTIONS;
		return new double[]
		{
			me.Hp, me.Mp, me.Energy, foe.Hp, foe.Mp, foe.Energy,
			Grid.Dist(me.Pos, foe.Pos), grid.ShrinkLevel,
			me.ActionCount, foe.ActionCount,
			me.SpentOnce.ContainsKey("grenade") ? 0.0 : 1.0,
			foe.SpentOnce.ContainsKey("grenade") ? 0.0 : 1.0,
			Tier(Config.RelOf(foe.Facing, foe.Pos, me.Pos)),
			Tier(Config.RelOf(me.Facing, me.Pos, foe.Pos)),
			epa - (me.ActionCount % epa), epa - (foe.ActionCount % epa),
			me.Energy < Config.COST_ATTACK ? 1.0 : 0.0,
			foe.Energy < Config.COST_ATTACK ? 1.0 : 0.0,
			me.Energy < Config.COST_GUARD ? 1.0 : 0.0,
			foe.Energy < Config.COST_GUARD ? 1.0 : 0.0,
			me.RestReady ? 1.0 : 0.0, foe.RestReady ? 1.0 : 0.0,
			me.Cooldowns.GetValueOrDefault("aoe_burst", 0), me.Cooldowns.GetValueOrDefault("dark_bolt", 0),
			foe.Cooldowns.GetValueOrDefault("aoe_burst", 0), foe.Cooldowns.GetValueOrDefault("dark_bolt", 0),
			me.Statuses.ContainsKey("rooted") || me.Statuses.ContainsKey("staggered") ? 1.0 : 0.0,
			foe.Statuses.ContainsKey("rooted") || foe.Statuses.ContainsKey("staggered") ? 1.0 : 0.0,
		};
	}

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

		// DEATH'S DOOR (hp convexity): inside one full-power foe turn (two swings) of
		// dying, each hp point IS the match -- a 10-point heal at 15 hp doubles the
		// swings needed to kill me; 10 damage on a 100-hp foe changes little. The
		// linear dealt/taken terms can't see that, so aggro always outbid the heal at
		// death's door (gate 4 red). Priced at the LEAF so every line, at every depth,
		// feels staying in (or pushing the foe into) one-turn-kill range. Symmetric.
		double doorstep = 2.0 * Config.ATTACK_DAMAGE;
		if (me.Hp < doorstep) v -= W_DOORSTEP * (doorstep - me.Hp);
		if (foe.Hp < doorstep) v += W_DOORSTEP * (doorstep - foe.Hp);

		// Foe cannot afford GUARD: my blockable melee threat is UNANSWERABLE.
		if (foe.Energy < Config.COST_GUARD && mine.Blockable > 0)
			v += W_SURE_PRESS * mine.Blockable;
		if (me.Energy < Config.COST_GUARD && danger.Blockable > 0)
			v -= W_SURE_PRESS * danger.Blockable;

		// The rest doorway (Fra): wounded + ending the turn where resting is SAFE.
		double myDeficit = (Config.MAX_HP - me.Hp) + (Config.MAX_MP - me.Mp);
		if (myDeficit >= 25 && me.RestReady && ThreatModel.RestSafe(foe, me, grid))
			v += W_REST_PATH * Math.Min(1.0, myDeficit / 60.0);
		double foeDeficit = (Config.MAX_HP - foe.Hp) + (Config.MAX_MP - foe.Mp);
		if (foeDeficit >= 25 && foe.RestReady && ThreatModel.RestSafe(me, foe, grid))
			v -= W_REST_PATH * Math.Min(1.0, foeDeficit / 60.0);

		bool foeStarved = foe.Energy < Config.COST_ATTACK;
		bool meStarved = me.Energy < Config.COST_ATTACK;
		if (foeStarved && !meStarved)
		{
			// LOCKOUT CLOCK: further from their +30 pulse = longer lock = worth more.
			int foeToPulse = Config.ENERGY_PULSE_ACTIONS - (foe.ActionCount % Config.ENERGY_PULSE_ACTIONS);
			v += W_ATTRITION * (0.6 + 0.4 * (double)foeToPulse / Config.ENERGY_PULSE_ACTIONS);
		}
		else if (meStarved && !foeStarved)
		{
			int meToPulse = Config.ENERGY_PULSE_ACTIONS - (me.ActionCount % Config.ENERGY_PULSE_ACTIONS);
			v -= W_ATTRITION * (0.6 + 0.4 * (double)meToPulse / Config.ENERGY_PULSE_ACTIONS);
		}

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
