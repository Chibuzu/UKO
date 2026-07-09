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

	public void LoadCalibration()
	{
		var cf = new ConfigFile();
		Eval.CAL_A = cf.Load("user://calibration.cfg") == Error.Ok
			? (double)cf.GetValue("cal", "a", 0.0) : 0.0;
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
		return new GC.Dictionary { { "cands", cands }, { "mix", mix } };
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
			outp.Add(new PlanAction(id, tile, facing));
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
