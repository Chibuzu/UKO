// BrainBridge.cs -- ONE-CALL-PER-DECISION adapter for the C# EXTREME brain.
// This is the architecture the boundary measurement demanded: GDScript marshals the
// state across ONCE, the entire search loop (candidates -> matrix -> deepening ->
// Nash -> exploit) runs in C#, and only the chosen sequence crosses back.
//
// Also exposes the agreement-harness probes (CandidatesOf / ScoreRich / ScoreDeep /
// SolveMatrix / ChooseMixDet): the pipeline is deterministic up to the final sample,
// so the harness compares NUMBERS, not statistics.
//
// The OpponentModel lives HERE (C# state on this RefCounted): GDScript calls
// ObserveFoe() after each turn and Save/LoadModel for persistence.
namespace UKO;

using Godot;
using System.Collections.Generic;
using GC = Godot.Collections;

[GlobalClass]
public partial class BrainBridge : RefCounted
{
	private readonly OpponentModel _model = new();

	// ── setup ────────────────────────────────────────────────────────────────
	public void SetProfile(string name) => ExtremeAI.SetProfile(name);

	public void SetDepth(int d) => Eval.LOOKAHEAD_DEPTH = d;

	// Force the calibration knob (agreement harness pins BOTH sides to 0 so raw
	// margins are compared; SetProfile auto-loads a fitted calibration otherwise).
	public void SetCal(double a) => Eval.CAL_A = a;

	public void SetBudget(int ms) => ExtremeAI.BudgetOverrideMs = ms;   // -1 = profile default

	public void LoadCalibration()
	{
		var cf = new ConfigFile();
		Eval.CAL_A = LoadWithFallback(cf, "calibration.cfg")
			? (double)cf.GetValue("cal", "a", 0.0) : 0.0;
	}

	// ROUND 17: user:// first (refits win), else the SHIPPED res://Data/ copy --
	// fresh installs start with an empty user:// and would silently lose the
	// fitted judge/calibration. Mirror of Eval.gd._cfg_load (GD twin).
	private static bool LoadWithFallback(ConfigFile cf, string name)
		=> cf.Load("user://" + name) == Error.Ok || cf.Load("res://Data/" + name) == Error.Ok;

	// ── learned value function (fitted by FitValue.gd -> user://value_fn.cfg) ──
	public void SetValueEnabled(bool on) => Eval.VALUE_ON = on;

	// One parsed weight set. v3 cfgs may carry CROSSES (feature-pair products
	// appended after the 28 base features); a cfg without them is a v1 (K = 0).
	private sealed class ValueSet
	{
		public double[] W, Mean, Std;
		public int[][] Cross;
	}
	private readonly ValueSet[] _valueSlots = new ValueSet[2];

	private static ValueSet ParseValueCfg(string path)
	{
		var cf = new ConfigFile();
		if (cf.Load(path) != Error.Ok) return null;
		var vs = new ValueSet
		{
			W = ToDoubles(cf.GetValue("value", "w", new GC.Array()).AsGodotArray()),
			Mean = ToDoubles(cf.GetValue("value", "mean", new GC.Array()).AsGodotArray()),
			Std = ToDoubles(cf.GetValue("value", "std", new GC.Array()).AsGodotArray()),
		};
		var cr = cf.GetValue("value", "crosses", new GC.Array()).AsGodotArray();
		vs.Cross = new int[cr.Count][];
		for (int k = 0; k < cr.Count; k++)
		{
			var pair = cr[k].AsGodotArray();
			if (pair.Count != 2) return null;
			vs.Cross[k] = new[] { pair[0].AsInt32(), pair[1].AsInt32() };
		}
		int n = 28 + vs.Cross.Length;
		bool ok = vs.W.Length == n + 1 && vs.Mean.Length == n && vs.Std.Length == n;
		return ok ? vs : null;
	}

	private static void ApplyValueSet(ValueSet vs)
	{
		Eval.VW = vs.W;
		Eval.VMEAN = vs.Mean;
		Eval.VSTD = vs.Std;
		Eval.VCROSS = vs.Cross;
	}

	public bool LoadValueFn()
	{
		var vs = ParseValueCfg("user://value_fn.cfg")
			?? ParseValueCfg("res://Data/value_fn.cfg");   // shipped copy (round 17)
		if (vs == null) return false;
		ApplyValueSet(vs);
		return true;
	}

	// Champion-vs-challenger support (ValueArena v2): parse two cfgs once, swap
	// per decision by reference (no per-decision disk IO).
	public bool LoadValueSlot(int slot, string path)
	{
		if (slot < 0 || slot >= _valueSlots.Length) return false;
		_valueSlots[slot] = ParseValueCfg(path);
		return _valueSlots[slot] != null;
	}

	public void UseValueSlot(int slot)
	{
		var vs = _valueSlots[slot];
		if (vs == null) return;
		ApplyValueSet(vs);
		Eval.VALUE_ON = true;
	}

	private static double[] ToDoubles(GC.Array a)
	{
		var outp = new double[a.Count];
		for (int i = 0; i < a.Count; i++) outp[i] = a[i].AsDouble();
		return outp;
	}

	// ── the one call per decision ────────────────────────────────────────────
	public GC.Array ChooseSequence(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary me, GC.Dictionary foe, bool useModel)
	{
		var grid = MakeGrid(gridRows, baseRows, rotStep, shrinkLevel);
		var cme = FromDict(me);
		var cfoe = FromDict(foe);
		var seq = ExtremeAI.ChooseSequence(cme, cfoe, grid, useModel ? _model : null);
		return SeqOut(seq);
	}

	// ── background thinking (ROUND 10: 3s+ budgets must not freeze the UI) ──
	// StartChoose marshals ON the calling thread (Godot objects never cross
	// threads), then searches on a worker. GD polls ChooseDone each frame and
	// collects with TakeChosen -- which returns the marshaled result, again on
	// the calling thread. ONE search at a time (the turn loop is serial); the
	// harness probes and the arena never use this path.
	private System.Threading.Tasks.Task<List<PlanAction>> _job;

	public void StartChoose(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary me, GC.Dictionary foe, bool useModel)
	{
		var grid = MakeGrid(gridRows, baseRows, rotStep, shrinkLevel);
		var cme = FromDict(me);
		var cfoe = FromDict(foe);
		var model = useModel ? _model : null;
		_job = System.Threading.Tasks.Task.Run(() => ExtremeAI.ChooseSequence(cme, cfoe, grid, model));
	}

	public bool ChooseDone() => _job == null || _job.IsCompleted;

	public GC.Array TakeChosen()
	{
		if (_job == null) return new GC.Array();
		try
		{
			var seq = _job.Result;
			return SeqOut(seq);
		}
		catch (System.Exception e)
		{
			GD.PushWarning($"[BrainBridge] background search failed: {e.Message} -- falling back to wait.");
			return new GC.Array();
		}
		finally
		{
			_job = null;
		}
	}

	// ── opponent model ───────────────────────────────────────────────────────
	public void ObserveFoe(GC.Array seq, string sit) => _model.Observe(SeqIn(seq), sit);

	public string SituationOf(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary actor, GC.Dictionary other)
		=> OpponentModel.SituationOf(FromDict(actor), FromDict(other),
			MakeGrid(gridRows, baseRows, rotStep, shrinkLevel));

	public void SaveModel()
	{
		var cf = new ConfigFile();
		var w = new GC.Dictionary();
		foreach (var kv in _model.W) w[kv.Key] = kv.Value;
		cf.SetValue("global", "w", w);
		cf.SetValue("global", "total", _model.Total);
		foreach (var kv in _model.Buckets)
		{
			var bw = new GC.Dictionary();
			foreach (var e in kv.Value.W) bw[e.Key] = e.Value;
			cf.SetValue("buckets", kv.Key, new GC.Dictionary { { "w", bw }, { "total", kv.Value.Total } });
		}
		cf.Save("user://uko_opp_model.cfg");
	}

	public void LoadModel()
	{
		var cf = new ConfigFile();
		if (cf.Load("user://uko_opp_model.cfg") != Error.Ok) return;
		_model.W.Clear();
		var w = cf.GetValue("global", "w", new GC.Dictionary()).AsGodotDictionary();
		foreach (var k in w.Keys) _model.W[k.AsString()] = w[k].AsDouble();
		_model.Total = (double)cf.GetValue("global", "total", 0.0);
		_model.Buckets.Clear();
		if (!cf.HasSection("buckets")) return;
		foreach (var sit in cf.GetSectionKeys("buckets"))
		{
			var bd = cf.GetValue("buckets", sit, new GC.Dictionary()).AsGodotDictionary();
			var b = new OpponentModel.Bucket { Total = bd["total"].AsDouble() };
			var bw = bd["w"].AsGodotDictionary();
			foreach (var k in bw.Keys) b.W[k.AsString()] = bw[k].AsDouble();
			_model.Buckets[sit] = b;
		}
	}

	// ── agreement-harness probes (deterministic) ────────────────────────────
	public string[] CandidatesOf(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary me, GC.Dictionary foe)
	{
		var grid = MakeGrid(gridRows, baseRows, rotStep, shrinkLevel);
		var cands = AIToolkit.Candidates(FromDict(me), FromDict(foe), grid);
		var outp = new string[cands.Count];
		for (int i = 0; i < cands.Count; i++) outp[i] = SeqStr(cands[i]);
		return outp;
	}

	public double ScoreRich(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary me, GC.Dictionary foe, GC.Array mySeq, GC.Array foeSeq)
	{
		var grid = MakeGrid(gridRows, baseRows, rotStep, shrinkLevel);
		return Eval.ScoreRich(FromDict(me), FromDict(foe), grid, SeqIn(mySeq), SeqIn(foeSeq));
	}

	public double ScoreDeep(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary me, GC.Dictionary foe, GC.Array mySeq, GC.Array foeSeq, int depth)
	{
		var grid = MakeGrid(gridRows, baseRows, rotStep, shrinkLevel);
		Eval.ClearCache();
		return Eval.ScoreDeep(FromDict(me), FromDict(foe), grid, SeqIn(mySeq), SeqIn(foeSeq), depth);
	}

	public double[] SolveMatrix(GC.Array m, int iters)
	{
		var M = new double[m.Count][];
		for (int i = 0; i < m.Count; i++)
		{
			var row = m[i].AsGodotArray();
			M[i] = new double[row.Count];
			for (int j = 0; j < row.Count; j++) M[i][j] = row[j].AsDouble();
		}
		return iters > 0 ? NashSolver.SolveIters(M, iters) : NashSolver.Solve(M);
	}

	// Deterministic pipeline for the harness: budget 0 = BASELINE selective deepening
	// only (the budgeted extension and depth-3 refine are time-gated and skip at 0),
	// so both sides compare the identical deterministic subset -- fast AND exact.
	public GC.Dictionary ChooseMixDet(string[] gridRows, string[] baseRows, int rotStep, int shrinkLevel,
			GC.Dictionary me, GC.Dictionary foe)
	{
		var grid = MakeGrid(gridRows, baseRows, rotStep, shrinkLevel);
		var r = ExtremeAI.ChooseMix(FromDict(me), FromDict(foe), grid, null, budgetOverrideMs: 0);
		var cands = new GC.Array();
		foreach (var c in r.Cands) cands.Add(SeqStr(c));
		var mix = new GC.Array();
		foreach (var p in r.Mix) mix.Add(p);
		return new GC.Dictionary { { "cands", cands }, { "mix", mix }, { "value", r.GuaranteedValue } };
	}

	// ── marshaling (same contract as ResolverBridge) ─────────────────────────
	private static Grid MakeGrid(string[] rows, string[] baseRows, int rotStep, int shrinkLevel)
	{
		var g = Grid.FromRows(rows);
		var gb = Grid.FromRows(baseRows);
		g.BaseBlocked = gb.Blocked;
		g.RotStep = rotStep;
		g.ShrinkLevel = shrinkLevel;
		return g;
	}

	private static Combatant FromDict(GC.Dictionary d)
	{
		var c = new Combatant(d["id"].AsString(), new Vec2I(d["x"].AsInt32(), d["y"].AsInt32()), d["facing"].AsInt32());
		c.Hp = d["hp"].AsInt32();
		c.Mp = d["mp"].AsInt32();
		c.Energy = d["energy"].AsInt32();
		c.ActionCount = d["action_count"].AsInt32();
		c.RestReady = d["rest_ready"].AsBool();
		c.SpeedBoost = d["speed_boost"].AsBool();
		var cds = d["cooldowns"].AsGodotDictionary();
		foreach (var k in cds.Keys) c.Cooldowns[k.AsString()] = cds[k].AsInt32();
		var sts = d["statuses"].AsGodotDictionary();
		foreach (var k in sts.Keys) c.Statuses[k.AsString()] = sts[k].AsInt32();
		var sps = d["spent_once"].AsGodotDictionary();
		foreach (var k in sps.Keys) c.SpentOnce[k.AsString()] = sps[k].AsBool();
		var gear = new List<string>();
		foreach (var g in d["gear"].AsGodotArray()) gear.Add(g.AsString());
		c.Equip(gear);
		return c;
	}

	private static List<PlanAction> SeqIn(GC.Array seq)
	{
		var outp = new List<PlanAction>();
		foreach (var v in seq)
		{
			var d = v.AsGodotDictionary();
			string id = d["id"].AsString();
			Vec2I? tile = null;
			int? facing = null;
			if (d.ContainsKey("tile")) { var t = d["tile"].AsVector2I(); tile = new Vec2I(t.X, t.Y); }
			if (d.ContainsKey("facing")) facing = d["facing"].AsInt32();
			string stance = d.ContainsKey("stance") ? d["stance"].AsString() : "push";
			outp.Add(new PlanAction(id, tile, facing, stance));
		}
		return outp;
	}

	private static GC.Array SeqOut(List<PlanAction> seq)
	{
		var outp = new GC.Array();
		foreach (var a in seq)
		{
			var d = new GC.Dictionary { { "id", a.Id } };
			if (a.HasTile) d["tile"] = new Vector2I(a.Tile.Value.X, a.Tile.Value.Y);
			if (a.HasFacing) d["facing"] = a.Facing.Value;
			if (a.Stance != null && a.Stance != "push") d["stance"] = a.Stance;
			outp.Add(d);
		}
		return outp;
	}

	// Canonical sequence string shared with the harness: id@x.y^f joined by '+'.
	private static string SeqStr(List<PlanAction> seq)
	{
		var parts = new List<string>();
		foreach (var a in seq)
		{
			string s = a.Id;
			if (a.HasTile) s += $"@{a.Tile.Value.X}.{a.Tile.Value.Y}";
			if (a.HasFacing) s += $"^{a.Facing.Value}";
			parts.Add(s);
		}
		return string.Join("+", parts);
	}
}
