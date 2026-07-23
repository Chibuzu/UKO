// AIToolkit.cs -- C# BRAIN PORT. Faithful port of Scripts/AI/AIToolkit.gd:
// projection, castability, line trace, and bounded candidate generation.
// Candidate/action ORDER matches the GDScript exactly (the agreement harness
// compares serialized candidate lists 1:1).
namespace UKO;

using System;
using System.Collections.Generic;

public static class AIToolkit
{
	// Mirror the resolver's upfront pay (+ position/facing/cooldown). Statuses NOT applied.
	public static void ApplyProjection(Combatant c, PlanAction action)
	{
		string id = action.Id ?? "";
		var d = Config.Def(id);
		string cat = d.Category;
		if (cat == "move" && action.HasTile)
		{
			c.Energy = Math.Max(0, c.Energy - Config.EffectiveMoveCost(c.Facing, c.Pos, action.Tile.Value, c.Statuses));
			c.Pos = action.Tile.Value;
		}
		else if (cat == "attack" && action.HasTile)
		{
			c.Energy = Math.Max(0, c.Energy - Config.EffectiveAttackCost(c.Facing, c.Pos, action.Tile.Value, c.Statuses));   // round 30
		}
		else if (cat == "pivot" && action.HasFacing)
		{
			c.Facing = action.Facing.Value;
		}
		else if (Config.IsBlink(id) && action.HasTile)
		{
			c.Energy = Math.Max(0, c.Energy - Config.EffectiveEnergyCost(id, c.Statuses));
			c.Mp = Math.Max(0, c.Mp - d.MpCost);
			c.Pos = action.Tile.Value;
			if (action.HasFacing) c.Facing = action.Facing.Value;
		}
		else
		{
			c.Energy = Math.Max(0, c.Energy - Config.EffectiveEnergyCost(id, c.Statuses));
			c.Mp = Math.Max(0, c.Mp - d.MpCost);
		}
		if (Config.IsSpell(id))
		{
			int cd = Config.CooldownOf(id);
			if (cd > 0) c.Cooldowns[id] = cd;
		}
	}

	public static bool CanUse(Combatant me, string id)
	{
		if (me.Cooldowns.GetValueOrDefault(id, 0) > 0) return false;
		if (Config.Def(id).OncePerMatch && me.SpentOnce.ContainsKey(id)) return false;
		return Config.CanAfford(me.Energy, me.Mp, me.Statuses, id);
	}

	public static bool ClearLine(Combatant me, Combatant foe, Grid grid, int rng)
	{
		int dx = foe.Pos.X - me.Pos.X;
		int dy = foe.Pos.Y - me.Pos.Y;
		if (dx != 0 && dy != 0) return false;
		int dist = Math.Abs(dx) + Math.Abs(dy);
		if (dist < 1 || dist > rng) return false;
		Vec2I step = new(Math.Sign(dx), Math.Sign(dy));
		Vec2I p = me.Pos;
		for (int i = 0; i < dist; i++)
		{
			p += step;
			if (grid.IsBlocked(p)) return false;
		}
		return true;
	}

	// ── Candidate generation (order preserved vs GDScript) ───────────────────
	public static List<List<PlanAction>> Candidates(Combatant me, Combatant foe, Grid grid)
	{
		var seqs = new List<List<PlanAction>>();
		if ((Config.MAX_HP - me.Hp) + (Config.MAX_MP - me.Mp) >= 25 && me.RestReady)
			seqs.Add(new List<PlanAction> { new("rest") });
		foreach (var a1 in SlotActions(me, foe, grid))
		{
			if (a1.Id != "wait")
				seqs.Add(new List<PlanAction> { a1, new("wait") });
			var proj = me.Clone();
			ApplyProjection(proj, a1);
			foreach (var a2 in SlotActions(proj, foe, grid))
			{
				if (a2.Id == "wait" && proj.Energy >= Config.MAX_ENERGY)
					continue;
				seqs.Add(new List<PlanAction> { a1, a2 });
			}
		}
		if (seqs.Count == 0)
			seqs.Add(new List<PlanAction> { new("wait"), new("wait") });
		return seqs;
	}

	public static List<PlanAction> SlotActions(Combatant c, Combatant foe, Grid grid)
	{
		var acts = new List<PlanAction>();
		int dist = Grid.Dist(c.Pos, foe.Pos);

		foreach (var dv in Grid.DIRS)
		{
			Vec2I tile = c.Pos + dv;
			if (!grid.InBounds(tile) || grid.IsBlocked(tile) || tile == foe.Pos) continue;
			if (c.Energy >= Config.EffectiveMoveCost(c.Facing, c.Pos, tile, c.Statuses))
				acts.Add(new PlanAction("move", tile));
		}

		if (dist == 1 && c.Energy >= Config.EffectiveAttackCost(c.Facing, c.Pos, foe.Pos, c.Statuses))
			acts.Add(new PlanAction("attack", foe.Pos));

		int face = FacingToward(c.Pos, foe.Pos);
		if (face != c.Facing && Config.CanAfford(c.Energy, c.Mp, c.Statuses, "pivot"))
			acts.Add(new PlanAction("pivot", null, face));

		if (Config.CanAfford(c.Energy, c.Mp, c.Statuses, "guard") && ThreatModel.HasMeleeThreat(foe, c, grid))
			acts.Add(new PlanAction("guard"));

		foreach (var sid in c.SpellIds())
		{
			if (!CanUse(c, sid)) continue;
			var d = Config.Def(sid);
			if (Config.IsBlink(sid))
			{
				foreach (var dv in Grid.DIRS)
				{
					var bl = Config.BlinkLanding(grid, c.Pos, dv, d.Range ?? 1, foe.Pos);
					if (!bl.HasValue) continue;
					acts.Add(new PlanAction(sid, bl.Value, FacingToward(bl.Value, foe.Pos)));
				}
				continue;
			}
			if (d.NeedsTile)
			{
				if (ClearLine(c, foe, grid, d.Range ?? 1))
					acts.Add(new PlanAction(sid, foe.Pos));
			}
			else
			{
				if (!AroundWhiffs(d, c.Pos, foe.Pos))
					acts.Add(new PlanAction(sid));
			}
		}

		acts.Add(new PlanAction("wait"));
		return acts;
	}

	private static bool AroundWhiffs(ActionDef d, Vec2I from, Vec2I foePos)
	{
		if (d.Shape != "around") return false;
		if (d.Effect == null || d.Effect.Type != "damage") return false;
		return Vec2I.Cheb(from, foePos) > (d.Radius ?? Config.AROUND_RADIUS) + 1;
	}

	// Cardinal facing pointing at the foe (dominant axis; +y is south).
	public static int FacingToward(Vec2I from, Vec2I to)
	{
		Vec2I d = to - from;
		if (Math.Abs(d.X) >= Math.Abs(d.Y))
			return d.X >= 0 ? (int)Config.Facing.EAST : (int)Config.Facing.WEST;
		return d.Y >= 0 ? (int)Config.Facing.SOUTH : (int)Config.Facing.NORTH;
	}
}
