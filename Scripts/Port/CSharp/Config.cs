// Config.cs -- C# ENGINE PORT (stage 1). Faithful port of Scripts/Core/Config.gd:
// core engine numbers + the basic action schema + pure lookups/helpers. Spell/status
// CONTENT lives in SpellBook.cs (as in GDScript). Grid-dependent helpers
// (projectile_path, blink_landing) are DEFERRED to the Grid stage and noted below.
//
// FAITHFULNESS RULES (so C# reproduces GDScript byte-for-byte):
//  * enum int values match GDScript exactly (Band 0..7, Facing 0..3).
//  * Optional def keys are nullable; each use site applies the SAME default the
//    GDScript get(key, default) used (e.g. range defaults to 1 for a bolt line but 3
//    for a grenade throw) -- so the default is never hard-coded on the field.
//  * integer ops use C# int (same overflow-free ranges as GDScript ints here).
namespace UKO;

using System;
using System.Collections.Generic;

// ── Shared def records (used by Config.ACTIONS and SpellBook.SPELLS) ──────────
// One record spans the union of action+spell fields; absent GDScript keys are null
// (nullable) or the type default, and use sites apply get(key, default) explicitly.
public sealed class ActionDef
{
	public string Id = "";
	public bool IsEmpty = false;      // Config.def() returns this for an unknown id (GDScript {} )
	public Config.Band Band;
	public int BaseTick;
	public int EnergyCost;
	public int MpCost;
	public bool NeedsTile;
	public string Category = "";      // move/pivot/attack/guard/rest/wait/noop/spell
	public int Cooldown;              // get("cooldown", 0)
	public bool OncePerMatch;         // get("once_per_match", false)
	public string Shape = "";         // spells only: self/around/line/throw/blink
	public int? Range;                // get("range", <site default>)
	public int? DiagRange;            // get("diag_range", 1)  (grenade)
	public bool Projectile;           // get("projectile", false)
	public int? TickPerTile;          // get("tick_per_tile", 0)
	public bool Pierce;               // get("pierce", false)
	public bool NoGuardCombo;         // get("no_guard_combo", false)
	public int? Radius;               // get("radius", AROUND_RADIUS)  (around blasts)
	public Effect Effect;             // null if no effect block
	public string Name = "";          // metadata (engine-unused; kept for readability)
}

// A spell effect block: { type, ... }. Type in damage/apply_status/blink/disrupt.
public sealed class Effect
{
	public string Type = "";
	public int? Amount;               // damage
	public string Status = "";        // apply_status / disrupt
	public string To = "";            // apply_status target; get("to", "self")
	public int? EnergyDrain;          // disrupt
}

public static class Config
{
	// ── Tick bands (earliest resolves first) ─────────────────────────────────
	public enum Band { BUFF, PIVOT, GUARD, ATTACK, AOE, MOVE, SPECIAL, REST }

	public const int BAND_WIDTH = 100;
	// Indexed by (int)Band. BUFF..REST -> 0,100,...,700.
	public static readonly int[] BAND_BASE = { 0, 100, 200, 300, 400, 500, 600, 700 };
	// Indexed by (int)Band. Priority == band order (0..7) when ticks tie.
	public static readonly int[] BAND_PRIORITY = { 0, 1, 2, 3, 4, 5, 6, 7 };
	// Out-of-band priorities for mid-loop injected entries (blink arrival / projectile step).
	public const int PRIORITY_BLINK_ARRIVE = 1;   // ties resolve in the pivot slot
	public const int PRIORITY_PROJECTILE = 9;     // above all bands (0-7)

	// ── Arena / resources ────────────────────────────────────────────────────
	public const int MAP_ROTATE_EVERY = 10;
	public const int MAP_CRUSH_DAMAGE = 20;
	public const double BLOCKER_DENSITY_MIN = 0.085;
	public const double BLOCKER_DENSITY_MAX = 0.11;
	public const int SPAWN_INSET = 1;
	public const int MAX_HP = 100;
	public const int MAX_MP = 100;
	public const int MAX_ENERGY = 100;
	public const int ENERGY_REGEN = 30;
	public const int ENERGY_PULSE_ACTIONS = 6;
	public const int WAIT_ENERGY = 10;

	// ── Rewards (gold for beating the AI), keyed by difficulty int ───────────
	public static readonly Dictionary<int, int> GOLD_REWARD = new()
	{ [0] = 10, [1] = 25, [2] = 60, [3] = 150 };
	public const int GOLD_REWARD_DRAW = 0;
	public static int GoldReward(int difficulty) => GOLD_REWARD.GetValueOrDefault(difficulty, 0);

	// ── Energy costs (directional movement) ──────────────────────────────────
	public const int COST_MOVE_FWD = 15;
	public const int COST_MOVE_SIDE = 20;
	public const int COST_MOVE_BACK = 25;
	public const int COST_ATTACK = 20;
	public const int COST_GUARD = 30;
	public const int GUARD_REFUND = 15;
	public static readonly Dictionary<string, double> GUARD_BLOCK = new()
	{ ["front"] = 1.0, ["side"] = 0.5, ["back"] = 0.0 };
	public static readonly Dictionary<string, int> GUARD_REFUND_TIER = new()
	{ ["front"] = GUARD_REFUND, ["side"] = 10, ["back"] = 0 };
	public const int BACK_MOVE_TAX = 0;   // RETIRED (subsumed by DirTax)

	// ── THE TICK BUNDLE (mirrors Config.gd exactly) ─────────────────────────
	public const int TAX_SECOND_DIFFERENT = 80;
	public const int CLASH_PUSH_DAMAGE = 10;
	public const int CLASH_BOUNCE_COST = 10;
	private static readonly Dictionary<string, int> DIR_TAX_MOVE =
		new() { ["front"] = 0, ["side"] = 50, ["back"] = 100 };
	private static readonly Dictionary<string, int> DIR_TAX_AIMED =
		new() { ["front"] = 0, ["side"] = 190, ["back"] = 290 };

	public static string RelOf(int facing, Vec2I from, Vec2I to)
	{
		Vec2I d = to - from;
		if (d == new Vec2I(0, 0) || (d.X != 0 && d.Y != 0)) return "front";
		Vec2I dir = new(System.Math.Sign(d.X), System.Math.Sign(d.Y));
		Vec2I f = FACING_VEC[facing];
		if (dir == f) return "front";
		if (dir == new Vec2I(-f.X, -f.Y)) return "back";
		return "side";
	}

	public static int DirTax(string id, string category, int facing, Vec2I from, Vec2I to)
	{
		string rel = RelOf(facing, from, to);
		if (category == "move") return DIR_TAX_MOVE[rel];
		var d = Def(id);
		bool aimed = category == "attack" || d.NeedsTile || IsBlink(id);
		return aimed ? DIR_TAX_AIMED[rel] : 0;
	}

	// ── Facing & flanking ────────────────────────────────────────────────────
	public enum Facing { NORTH, EAST, SOUTH, WEST }
	// Indexed by (int)Facing.
	public static readonly Vec2I[] FACING_VEC =
	{
		new(0, -1),  // NORTH
		new(1, 0),   // EAST
		new(0, 1),   // SOUTH
		new(-1, 0),  // WEST
	};
	public static readonly Dictionary<string, double> FLANK_MULT = new()
	{ ["front"] = 1.0, ["side"] = 1.5, ["back"] = 2.0 };
	public const int ATTACK_DAMAGE = 15;
	public const int AROUND_RADIUS = 1;

	// Which face of a defender the attacker sits on: "front"/"side"/"back".
	public static string FlankTier(int facing, Vec2I defPos, Vec2I atkPos)
	{
		Vec2I toAtk = atkPos - defPos;
		Vec2I f = FACING_VEC[facing];
		int dot = toAtk.X * f.X + toAtk.Y * f.Y;
		if (dot > 0) return "front";
		if (dot < 0) return "back";
		return "side";
	}

	// ── Basic actions ────────────────────────────────────────────────────────
	public static readonly Dictionary<string, ActionDef> ACTIONS = new()
	{
		["move"]  = new ActionDef { Id = "move",  Band = Band.MOVE,   BaseTick = 20, EnergyCost = COST_MOVE_FWD, MpCost = 0, NeedsTile = true,  Category = "move" },
		["pivot"] = new ActionDef { Id = "pivot", Band = Band.PIVOT,  BaseTick = 10, EnergyCost = 5,             MpCost = 0, NeedsTile = false, Category = "pivot" },   // ROUND 11: pivots cost 5 (mirrors Config.gd)
		["attack"]= new ActionDef { Id = "attack",Band = Band.ATTACK, BaseTick = 50, EnergyCost = COST_ATTACK,  MpCost = 0, NeedsTile = true,  Category = "attack" },
		["guard"] = new ActionDef { Id = "guard", Band = Band.GUARD,  BaseTick = 0,  EnergyCost = COST_GUARD,   MpCost = 0, NeedsTile = false, Category = "guard" },
		["rest"]  = new ActionDef { Id = "rest",  Band = Band.REST,   BaseTick = 90, EnergyCost = 0,             MpCost = 0, NeedsTile = false, Category = "rest" },
		["wait"]  = new ActionDef { Id = "wait",  Band = Band.MOVE,   BaseTick = 80, EnergyCost = 0,             MpCost = 0, NeedsTile = false, Category = "wait" },
		["_noop"] = new ActionDef { Id = "_noop", Band = Band.BUFF,   BaseTick = 0,  EnergyCost = 0,             MpCost = 0, NeedsTile = false, Category = "noop" },
	};

	private static readonly ActionDef Empty = new() { IsEmpty = true };

	// ── Lookups (basic actions here + spells from SpellBook) ─────────────────
	public static ActionDef Def(string id)
	{
		if (ACTIONS.TryGetValue(id, out var a)) return a;
		if (SpellBook.SPELLS.TryGetValue(id, out var s)) return s;
		return Empty;
	}

	public static bool IsSpell(string id) => SpellBook.SPELLS.ContainsKey(id);

	public static bool IsBlink(string id)
	{
		var e = Def(id).Effect;
		return e != null && e.Type == "blink";
	}

	// Total flight time of a teleport: range tiles * tick_per_tile each.
	public static int BlinkTravel(string id)
	{
		var d = Def(id);
		return (d.Range ?? 1) * (d.TickPerTile ?? 0);
	}

	public static bool IsProjectile(string id) => Def(id).Projectile;

	public static int CooldownOf(string id) => Def(id).Cooldown;

	public static StatusDef StatusDef(string id) => SpellBook.STATUSES.GetValueOrDefault(id);

	public static int FinalTick(Band band, int withinTick)
		=> BAND_BASE[(int)band] + Math.Clamp(withinTick, 0, BAND_WIDTH - 1);

	// Energy cost after any active energy_cost_reduction statuses. Non-positive base
	// (moves compute cost via EffectiveMoveCost) returns as-is.
	public static int EffectiveEnergyCost(string id, IReadOnlyDictionary<string, int> statuses)
	{
		int base_ = Def(id).EnergyCost;
		if (base_ <= 0) return base_;
		int reduction = 0;
		foreach (var kv in statuses)
			if (kv.Value > 0)
			{
				var sd = StatusDef(kv.Key);
				if (sd != null) reduction += sd.EnergyCostReduction;
			}
		return Math.Max(0, base_ - reduction);
	}

	public static bool CanAfford(int energy, int mp, IReadOnlyDictionary<string, int> statuses, string id)
	{
		var d = Def(id);
		if (d.IsEmpty) return false;
		return energy >= EffectiveEnergyCost(id, statuses) && mp >= d.MpCost;
	}

	// ── Directional movement cost ───────────────────────────────────────────
	public static string MoveDirection(int facing, Vec2I from, Vec2I to)
	{
		Vec2I delta = to - from;
		Vec2I fwd = FACING_VEC[facing];
		if (delta == fwd) return "forward";
		if (delta == -fwd) return "back";
		return "side";
	}

	public static int MoveBaseCost(int facing, Vec2I from, Vec2I to) => MoveDirection(facing, from, to) switch
	{
		"forward" => COST_MOVE_FWD,
		"back" => COST_MOVE_BACK,
		_ => COST_MOVE_SIDE,
	};

	public static int EffectiveMoveCost(int facing, Vec2I from, Vec2I to, IReadOnlyDictionary<string, int> statuses)
	{
		int base_ = MoveBaseCost(facing, from, to);
		int reduction = 0;
		foreach (var kv in statuses)
			if (kv.Value > 0)
			{
				var sd = StatusDef(kv.Key);
				if (sd != null) reduction += sd.EnergyCostReduction;
			}
		return Math.Max(0, base_ - reduction);
	}

	// A self-buff that commits earlier in a sequence discounts LATER actions this same
	// turn: mutates `statuses` in place. No-op for anything but a self-targeted apply_status.
	public static void ApplyPlannedSelfBuff(Dictionary<string, int> statuses, string actionId)
	{
		if (!IsSpell(actionId)) return;
		var eff = Def(actionId).Effect;
		if (eff == null) return;
		string to = string.IsNullOrEmpty(eff.To) ? "self" : eff.To;   // get("to", "self")
		if (eff.Type == "apply_status" && to == "self")
		{
			string st = eff.Status;
			if (st != "")
			{
				var sd = StatusDef(st);
				statuses[st] = sd != null ? sd.Duration : 0;
			}
		}
	}

	// ── Grid-dependent helper (un-deferred at the Grid stage) ────────────────
	// A projectile's flight path from `from` along cardinal `dir`: one entry per tile,
	// each `tax` ticks after the previous, first at `launchTick`. Stops at a wall/edge.
	public struct PathStep { public Vec2I Tile; public int Tick; public int Step; }
	public static List<PathStep> ProjectilePath(Grid grid, Vec2I from, Vec2I dir, int rng, int tax, int launchTick)
	{
		var path = new List<PathStep>();
		Vec2I p = from;
		for (int k = 1; k <= rng; k++)
		{
			p += dir;
			if (!grid.InBounds(p) || grid.IsBlocked(p)) break;
			path.Add(new PathStep { Tile = p, Tick = launchTick + (k - 1) * tax, Step = k });
		}
		return path;
	}

	// Landing tile of a fixed-distance directional blink (un-deferred with the brain):
	// land as far along `dir` as possible (up to dist), stepping back toward `from`
	// when far tiles are walls/foe. Returns null when no tile in the line is landable.
	public static Vec2I? BlinkLanding(Grid grid, Vec2I from, Vec2I dir, int dist, Vec2I foePos)
	{
		if (dir == new Vec2I(0, 0) || dist <= 0) return null;
		for (int dd = dist; dd >= 1; dd--)
		{
			Vec2I land = from + dir * dd;
			if (grid.InBounds(land) && !grid.IsBlocked(land) && land != foePos)
				return land;
		}
		return null;
	}
}
