// ThreatModel.cs -- C# BRAIN PORT. Faithful port of Scripts/AI/ThreatModel.gd:
// what a fighter can ACTUALLY do to another this turn, grounded in resolver rules.
namespace UKO;

using System;
using System.Collections.Generic;

public static class ThreatModel
{
	private static int Rnd(double x) => (int)Math.Round(x, MidpointRounding.AwayFromZero);

	// Max basic-attack damage att can land on def this turn (reach<=2, energy, best flank).
	public static int MeleeDamage(Combatant att, Combatant def, Grid grid)
	{
		int best = 0;
		var blinkTiles = BlinkReach(att, def, grid);
		foreach (var dv in Grid.DIRS)
		{
			Vec2I t = def.Pos + dv;
			if (!grid.InBounds(t) || grid.IsBlocked(t)) continue;
			int cost;
			if (att.Pos == t)
				cost = Config.COST_ATTACK;
			else if (Grid.Dist(att.Pos, t) == 1)
				cost = Config.EffectiveMoveCost(att.Facing, att.Pos, t, att.Statuses) + Config.COST_ATTACK;
			else if (blinkTiles.Contains(t))
				cost = Config.COST_ATTACK;
			else
				continue;
			if (att.Energy < cost) continue;
			string rel = FlankOf(def, t);
			best = Math.Max(best, Rnd(Config.ATTACK_DAMAGE * Config.FLANK_MULT[rel]));
		}
		return best;
	}

	// Max damaging-spell damage att can land on def this turn (mp/cooldown/shape/LOS, one setup step).
	public static int SpellDamage(Combatant att, Combatant def, Grid grid)
	{
		int best = 0;
		foreach (var sid in att.SpellIds())
		{
			var d = Config.Def(sid);
			var eff = d.Effect;
			if (eff == null || eff.Type != "damage") continue;
			if (att.Cooldowns.GetValueOrDefault(sid, 0) > 0) continue;
			if (att.Mp < d.MpCost) continue;
			int amt = eff.Amount ?? 0;
			switch (d.Shape)
			{
				case "around":
					if (CanReachAdjacent(att, def, grid)) best = Math.Max(best, amt);
					break;
				case "line":
					if (CanLine(att, def, grid, d.Range ?? 1)) best = Math.Max(best, amt);
					break;
			}
		}
		return best;
	}

	public struct Incoming2 { public int Blockable; public int Unblockable; }
	public static Incoming2 Incoming(Combatant att, Combatant def, Grid grid)
		=> new() { Blockable = MeleeDamage(att, def, grid), Unblockable = SpellDamage(att, def, grid) };

	public static int WorstDamage(Combatant att, Combatant def, Grid grid)
		=> MeleeDamage(att, def, grid) + SpellDamage(att, def, grid);

	public static bool RestSafe(Combatant att, Combatant def, Grid grid)
		=> WorstDamage(att, def, grid) == 0;

	public static bool HasMeleeThreat(Combatant att, Combatant def, Grid grid)
		=> MeleeDamage(att, def, grid) > 0;

	public static string FlankOf(Combatant def, Vec2I at)
		=> Config.FlankTier(def.Facing, def.Pos, at);

	// Tiles att could blink onto this turn (ready blinks only).
	private static List<Vec2I> BlinkReach(Combatant att, Combatant foe, Grid grid)
	{
		var outp = new List<Vec2I>();
		foreach (var sid in att.SpellIds())
		{
			if (!Config.IsBlink(sid)) continue;
			if (att.Cooldowns.GetValueOrDefault(sid, 0) > 0 || att.Mp < Config.Def(sid).MpCost) continue;
			int rng = Config.Def(sid).Range ?? 2;
			foreach (var dv in Grid.DIRS)
			{
				var bl = Config.BlinkLanding(grid, att.Pos, dv, rng, foe.Pos);
				if (bl.HasValue) outp.Add(bl.Value);
			}
		}
		return outp;
	}

	private static int Cheb(Vec2I a, Vec2I b) => Vec2I.Cheb(a, b);

	// Within Chebyshev 1 of def this turn (already, or after one affordable step)?
	private static bool CanReachAdjacent(Combatant att, Combatant def, Grid grid)
	{
		if (Cheb(att.Pos, def.Pos) <= 1) return true;
		foreach (var dv in Grid.DIRS)
		{
			Vec2I t = att.Pos + dv;
			if (!grid.InBounds(t) || grid.IsBlocked(t) || t == def.Pos) continue;
			if (att.Energy >= Config.EffectiveMoveCost(att.Facing, att.Pos, t, att.Statuses) && Cheb(t, def.Pos) <= 1)
				return true;
		}
		return false;
	}

	// Clear cardinal line to def within range, now or after one affordable step?
	private static bool CanLine(Combatant att, Combatant def, Grid grid, int rng)
	{
		if (RayHits(att.Pos, def.Pos, grid, rng)) return true;
		foreach (var dv in Grid.DIRS)
		{
			Vec2I t = att.Pos + dv;
			if (!grid.InBounds(t) || grid.IsBlocked(t) || t == def.Pos) continue;
			if (att.Energy >= Config.EffectiveMoveCost(att.Facing, att.Pos, t, att.Statuses) && RayHits(t, def.Pos, grid, rng))
				return true;
		}
		return false;
	}

	private static bool RayHits(Vec2I from, Vec2I target, Grid grid, int rng)
	{
		Vec2I dv = target - from;
		if (dv.X != 0 && dv.Y != 0) return false;
		if (Grid.Dist(from, target) > rng) return false;
		Vec2I step = new(Math.Sign(dv.X), Math.Sign(dv.Y));
		Vec2I p = from;
		for (int i = 0; i < rng; i++)
		{
			p += step;
			if (!grid.InBounds(p) || grid.IsBlocked(p)) return false;
			if (p == target) return true;
		}
		return false;
	}
}
