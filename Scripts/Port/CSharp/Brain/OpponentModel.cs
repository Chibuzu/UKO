// OpponentModel.cs -- C# BRAIN PORT. Faithful port of Scripts/AI/OpponentModel.gd:
// situation-bucketed tendency tracking with decay + a global fallback.
// Framework-free: persistence is done by the bridge (Export/Import plain state).
namespace UKO;

using System;
using System.Collections.Generic;

public sealed class OpponentModel
{
	public const double DECAY = 0.6;
	public const double WARM_BUCKET = 3.0;

	public Dictionary<string, double> W = new();                     // global: category -> decayed weight
	public double Total = 0.0;
	public sealed class Bucket { public Dictionary<string, double> W = new(); public double Total = 0.0; }
	public Dictionary<string, Bucket> Buckets = new();               // situation -> bucket

	public void Observe(List<PlanAction> seq, string sit = "")
	{
		foreach (var k in new List<string>(W.Keys)) W[k] *= DECAY;
		Total *= DECAY;
		Bucket bk = null;
		if (sit != "")
		{
			if (!Buckets.TryGetValue(sit, out bk))
			{
				bk = new Bucket();
				Buckets[sit] = bk;
			}
			foreach (var k in new List<string>(bk.W.Keys)) bk.W[k] *= DECAY;
			bk.Total *= DECAY;
		}
		foreach (var action in seq)
		{
			string cat = CategoryOf(action);
			if (cat == "") continue;
			W[cat] = W.GetValueOrDefault(cat, 0.0) + 1.0;
			Total += 1.0;
			if (bk != null)
			{
				bk.W[cat] = bk.W.GetValueOrDefault(cat, 0.0) + 1.0;
				bk.Total += 1.0;
			}
		}
	}

	public double Freq(string category, string sit = "")
	{
		if (sit != "" && Buckets.TryGetValue(sit, out var bk) && bk.Total >= WARM_BUCKET)
			return bk.W.GetValueOrDefault(category, 0.0) / bk.Total;
		if (Total <= 0.0) return 0.0;
		return W.GetValueOrDefault(category, 0.0) / Total;
	}

	public bool IsWarm() => Total >= 1.0;

	public double Confidence() => Math.Min(1.0, Total / 12.0);

	public static string CategoryOf(PlanAction action)
	{
		string id = action.Id ?? "";
		if (id == "" || id == "_noop") return "";
		if (Config.IsSpell(id)) return "spell";
		return Config.Def(id).Category;
	}

	public static string SituationOf(Combatant actor, Combatant other, Grid grid)
	{
		string hp = actor.Hp < 40 ? "L" : (actor.Hp > 70 ? "H" : "M");
		string en = actor.Energy < 30 ? "L" : (actor.Energy >= 70 ? "H" : "M");
		int dist = Grid.Dist(actor.Pos, other.Pos);
		string d = dist <= 1 ? "adj" : (dist <= 2 ? "near" : "far");
		string f = Config.FlankTier(actor.Facing, actor.Pos, other.Pos);
		int hurt = actor.RestReady ? 0 : 1;
		return $"h{hp}|e{en}|d{d}|f{f}|w{hurt}";
	}

	public double WeightOf(List<PlanAction> seq, string sit = "")
	{
		if (!IsWarm()) return 1.0;
		double sum = 0.0;
		int n = 0;
		foreach (var action in seq)
		{
			string cat = CategoryOf(action);
			if (cat == "") continue;
			sum += Freq(cat, sit) + 0.05;
			n++;
		}
		if (n == 0) return 0.05;
		return sum / n;
	}
}
