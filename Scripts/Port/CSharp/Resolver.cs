// Resolver.cs -- C# ENGINE PORT (stage 4). Faithful port of Scripts/Core/Resolver.gd:
// THE pure rules engine (grid, combatants, actions) -> (new state, events, result).
// Never mutates inputs (works on Clone()s); knows nothing about rendering.
//
// PARITY-CRITICAL CHOICES (why this matches the GDScript byte-for-byte):
//  * round(): Godot rounds halves AWAY FROM ZERO; C# Math.Round defaults to banker's
//    (to-even). All round() sites use Rnd() = MidpointRounding.AwayFromZero.
//  * schedule sort: Godot's sort_custom is UNSTABLE (proven by the brain harness);
//    parity still holds because same-tick same-priority ties in the schedule are
//    OUTCOME-NEUTRAL by construction (same-tick entries resolve as one group; attack
//    order within a group cannot change results, mutual moves are handled explicitly).
//    We sort stably by (tick, band_priority) anyway so C#-side order is DEFINED.
//  * events carry only Type/Tick/Owner here (the parity digest tallies Type); the event
//    DATA payloads are view-only and omitted, like vfx.
namespace UKO;

using System;
using System.Collections.Generic;
using System.Linq;

// An action in a player's committed sequence: id (+ optional aim tile / facing).
public sealed class PlanAction
{
	public string Id;
	public Vec2I? Tile;
	public int? Facing;
	public PlanAction(string id, Vec2I? tile = null, int? facing = null) { Id = id; Tile = tile; Facing = facing; }
	public bool HasTile => Tile.HasValue;
	public bool HasFacing => Facing.HasValue;
}

// A scheduled entry on the shared tick clock (union of all entry kinds).
public sealed class SchedEntry
{
	public string Owner;
	public string Id;
	public string Category;
	public int Tick;
	public int BandPriority;
	public Vec2I Tile;
	public int Facing;
	public bool Resolved;        // _resolved
	public int EnergyCost;       // for move-fizzle refund
	// projectile / blink injected fields:
	public Vec2I Dest, Origin, From;
	public int Step;
	public string Pid;
	public int Dwell;
	public bool Pierce;
	public int Damage;
}

public sealed class Event
{
	public string Type;
	public int Tick;
	public string Owner;
	public Event(string type, int tick, string owner) { Type = type; Tick = tick; Owner = owner; }
}

public sealed class ResolveResult
{
	public Combatant A;
	public Combatant B;
	public List<Event> Events;
	public string Result;
}

public static class Resolver
{
	// While teleporting, a fighter sits on NO tile (untargetable) between DEPART and ARRIVE.
	public static readonly Vec2I IN_TRANSIT = new(-9999, -9999);

	// round half AWAY FROM ZERO (Godot's round), then to int.
	private static int Rnd(double x) => (int)Math.Round(x, MidpointRounding.AwayFromZero);

	private static int Sign(int v) => Math.Sign(v);

	// STABLE sort by (tick, band_priority) -- matches Godot's insertion sort on small arrays.
	private static void StableSort(List<SchedEntry> list)
	{
		var sorted = list.OrderBy(e => e.Tick).ThenBy(e => e.BandPriority).ToList();
		for (int k = 0; k < list.Count; k++) list[k] = sorted[k];
	}
	// Stable re-sort of only the unprocessed tail [i, end).
	private static void ResortTail(List<SchedEntry> sched, int i)
	{
		var tail = sched.GetRange(i, sched.Count - i);
		var sorted = tail.OrderBy(e => e.Tick).ThenBy(e => e.BandPriority).ToList();
		for (int k = 0; k < sorted.Count; k++) sched[i + k] = sorted[k];
	}

	private static Event Ev(string type, int tick, string owner) => new(type, tick, owner);

	public static ResolveResult Resolve(Grid grid, Combatant inA, Combatant inB,
			List<PlanAction> seqA, List<PlanAction> seqB, int turn)
	{
		var a = inA.Clone();
		var b = inB.Clone();
		var events = new List<Event>();

		// statuses applied THIS turn must not be decremented at end of it.
		var freshStatus = new Dictionary<string, List<string>> { ["A"] = new(), ["B"] = new() };

		var planA = Plan(a, seqA, events);
		var planB = Plan(b, seqB, events);
		a.SpeedBoost = false;
		b.SpeedBoost = false;

		var sched = new List<SchedEntry>();
		sched.AddRange(planA.Entries);
		sched.AddRange(planB.Entries);
		StableSort(sched);

		var guarding = new Dictionary<string, bool> { ["A"] = false, ["B"] = false };
		var guardBlocked = new Dictionary<string, int> { ["A"] = 0, ["B"] = 0 };
		var guarded = new Dictionary<string, bool> { ["A"] = false, ["B"] = false };
		var damagedTick = new Dictionary<string, int> { ["A"] = -1, ["B"] = -1 };
		var deadTick = new Dictionary<string, int> { ["A"] = -1, ["B"] = -1 };
		var projConsumed = new Dictionary<string, bool>();

		int i = 0;
		while (i < sched.Count)
		{
			int tick = sched[i].Tick;
			var group = new List<SchedEntry>();
			while (i < sched.Count && sched[i].Tick == tick) { group.Add(sched[i]); i++; }

			// Offensive actions drop the actor's OWN guard the instant they fire (whole group first).
			foreach (var s in group)
				if (guarding[s.Owner] && IsOffensive(s))
				{
					guarding[s.Owner] = false;
					events.Add(Ev("guard_dropped", tick, s.Owner));
				}

			foreach (var s in group)
			{
				Combatant actor = s.Owner == "A" ? a : b;
				Combatant target = s.Owner == "A" ? b : a;
				if (deadTick[actor.Id] != -1 && deadTick[actor.Id] < tick)
				{
					events.Add(Ev("dead_skip", tick, actor.Id));
					continue;
				}
				switch (s.Category)
				{
					case "guard":
						guarding[actor.Id] = true;
						guarded[actor.Id] = true;
						events.Add(Ev("guard_raised", tick, actor.Id));
						break;
					case "pivot":
						if (actor.Statuses.ContainsKey("rooted"))
							events.Add(Ev("illegal_action", tick, actor.Id));
						else
						{
							actor.Facing = s.Facing;
							events.Add(Ev("pivot", tick, actor.Id));
						}
						break;
					case "move":
						if (!s.Resolved)
						{
							Vec2I aWas = actor.Pos;
							Vec2I tWas = target.Pos;
							DoMove(s, actor, target, group, grid, deadTick, tick, events);
							if (actor.Pos != aWas)
								MoveIntoProjectile(actor, sched, tick, projConsumed, damagedTick, deadTick, events);
							if (target.Pos != tWas)
								MoveIntoProjectile(target, sched, tick, projConsumed, damagedTick, deadTick, events);
						}
						break;
					case "attack":
						Attack(actor, target, s, tick, guarding, guardBlocked, damagedTick, deadTick, events);
						break;
					case "spell":
						CastSpell(grid, actor, target, s, tick, damagedTick, deadTick, freshStatus, events);
						if (Config.IsProjectile(s.Id))
							LaunchProjectile(grid, s, actor, sched, i, events);
						else if (Config.IsBlink(s.Id))
							LaunchBlink(grid, s, actor, target, sched, i, tick, events);
						break;
					case "projectile":
						ProjectileStep(s, actor, target, tick, projConsumed, grid, damagedTick, deadTick, events);
						break;
					case "blink_arrive":
						actor.Pos = BlinkSettle(grid, target, s.Origin, s.Dest);
						actor.Facing = s.Facing;
						events.Add(Ev("blink", tick, actor.Id));
						break;
					case "rest":
						events.Add(Ev("rest", tick, actor.Id));
						break;
					case "wait":
						actor.Energy = Math.Min(Config.MAX_ENERGY, actor.Energy + Config.WAIT_ENERGY);
						events.Add(Ev("wait", tick, actor.Id));
						break;
					case "noop":
						break;
				}

				// The grenade root bites only the target's NEXT action; clear it after any non-move action.
				if (actor.Statuses.ContainsKey("rooted"))
					actor.Statuses.Remove("rooted");
			}
		}

		// Guard outcome (use the LATCH, not the live shield).
		foreach (var c in new[] { a, b })
			if (guarded[c.Id])
			{
				if (guardBlocked[c.Id] != 0)
				{
					c.Energy = Math.Min(Config.MAX_ENERGY, c.Energy + guardBlocked[c.Id]);
					c.SpeedBoost = true;
					events.Add(Ev("guard_success", -1, c.Id));
				}
				else events.Add(Ev("guard_failed", -1, c.Id));
			}

		// Rest regen, only if uninterrupted.
		foreach (var s in sched)
			if (s.Category == "rest")
			{
				Combatant c = s.Owner == "A" ? a : b;
				if (damagedTick[c.Id] == -1) RestRegen(c, sched, s, events);
				else events.Add(Ev("rest_interrupted", damagedTick[c.Id], c.Id));
			}

		// End of turn: tick down statuses (skip ones applied this turn).
		foreach (var c in new[] { a, b })
			TickDown(c.Statuses, freshStatus[c.Id]);

		// Passive energy regen: per-player metronome.
		TallyEnergy(a, b, planA.Actions, planB.Actions, events);

		a.RestReady = damagedTick["A"] == -1;
		b.RestReady = damagedTick["B"] == -1;

		string result = ResultOf(a, b);
		if (result != "ongoing") events.Add(Ev("game_over", -1, ""));

		return new ResolveResult { A = a, B = b, Events = events, Result = result };
	}

	// ── Validation / costs ──────────────────────────────────────────────────
	private static PlanAction Legalize(Combatant c, PlanAction action, Vec2I vpos, int vfacing,
			List<Event> events, Dictionary<string, int> statuses)
	{
		string id = action.Id ?? "";
		var d = Config.Def(id);
		if (d.IsEmpty || id == "_noop")
		{
			events.Add(Ev("illegal_action", -1, c.Id));
			return new PlanAction("_noop");
		}
		if (Config.IsSpell(id) && !c.SpellIds().Contains(id))
		{ events.Add(Ev("illegal_action", -1, c.Id)); return new PlanAction("_noop"); }
		if (Config.IsSpell(id) && c.Cooldowns.GetValueOrDefault(id, 0) > 0)
		{ events.Add(Ev("illegal_action", -1, c.Id)); return new PlanAction("_noop"); }
		if (d.OncePerMatch && c.SpentOnce.ContainsKey(id))
		{ events.Add(Ev("illegal_action", -1, c.Id)); return new PlanAction("_noop"); }
		if (d.Category == "rest" && !c.RestReady)
		{ events.Add(Ev("illegal_action", -1, c.Id)); return new PlanAction("_noop"); }
		if (d.Category == "move" && action.HasTile)
		{
			if (c.Energy < Config.EffectiveMoveCost(vfacing, vpos, action.Tile.Value, statuses))
			{ events.Add(Ev("illegal_action", -1, c.Id)); return new PlanAction("_noop"); }
		}
		else if (!Config.CanAfford(c.Energy, c.Mp, statuses, id))
		{ events.Add(Ev("illegal_action", -1, c.Id)); return new PlanAction("_noop"); }
		return action;
	}

	private static void AgeCooldowns(Combatant c)
	{
		foreach (var k in c.Cooldowns.Keys.ToList())
			c.Cooldowns[k] = Math.Max(0, c.Cooldowns[k] - 1);
	}

	private static int Pay(Combatant c, PlanAction action, Vec2I vpos, int vfacing, Dictionary<string, int> statuses)
	{
		string id = action.Id;
		var d = Config.Def(id);
		int ecost = Config.EffectiveEnergyCost(id, statuses);
		if (d.Category == "move" && action.HasTile)
			ecost = Config.EffectiveMoveCost(vfacing, vpos, action.Tile.Value, statuses);
		c.Energy = Math.Max(0, c.Energy - ecost);
		c.Mp = Math.Max(0, c.Mp - d.MpCost);
		return ecost;
	}

	private static bool RealAction(PlanAction action)
	{
		string cat = Config.Def(action.Id ?? "").Category;
		return cat != "" && cat != "wait" && cat != "noop";
	}

	private static bool IsOffensive(SchedEntry s)
	{
		switch (s.Category)
		{
			case "attack": return true;
			case "spell":
				var e = Config.Def(s.Id).Effect;
				return e != null && e.Type == "damage";
		}
		return false;
	}

	private static void TallyEnergy(Combatant a, Combatant b, List<PlanAction> actsA, List<PlanAction> actsB, List<Event> events)
	{
		TallyOne(a, actsA, "A", events);
		TallyOne(b, actsB, "B", events);
	}

	private static void TallyOne(Combatant c, List<PlanAction> acts, string id, List<Event> events)
	{
		int count = c.ActionCount;
		foreach (var act in acts) if (RealAction(act)) count++;
		while (count >= Config.ENERGY_PULSE_ACTIONS)
		{
			count -= Config.ENERGY_PULSE_ACTIONS;
			c.Energy = Math.Min(Config.MAX_ENERGY, c.Energy + Config.ENERGY_REGEN);
			events.Add(Ev("energy_pulse", -1, id));
		}
		c.ActionCount = count;
	}

	private sealed class PlanResult { public List<SchedEntry> Entries; public List<PlanAction> Actions; }

	private static PlanResult Plan(Combatant c, List<PlanAction> seq, List<Event> events)
	{
		var entries = new List<SchedEntry>();
		var acts = new List<PlanAction>();
		int cum = 0;
		int slot = 0;
		Vec2I vpos = c.Pos;
		int vfacing = c.Facing;
		var pstat = new Dictionary<string, int>(c.Statuses);
		bool seenGuard = false;
		bool seenNoGuardSpell = false;

		foreach (var raw0 in seq)
		{
			PlanAction raw = raw0;
			string rid = raw.Id ?? "";
			bool wantGuard = Config.Def(rid).Category == "guard";
			bool wantNg = Config.IsSpell(rid) && Config.Def(rid).NoGuardCombo;
			if ((wantGuard && seenNoGuardSpell) || (wantNg && seenGuard))
			{
				events.Add(Ev("illegal_action", -1, c.Id));
				raw = new PlanAction("_noop");
			}
			AgeCooldowns(c);
			var act = Legalize(c, raw, vpos, vfacing, events, pstat);
			int paid = Pay(c, act, vpos, vfacing, pstat);
			string aid = act.Id ?? "";
			if (Config.IsSpell(aid))
			{
				int cdv = Config.CooldownOf(aid);
				if (cdv > 0) c.Cooldowns[aid] = cdv;
				// Burn once-per-match at PLAN time (like cooldowns) -- double-grenade fix.
				if (Config.Def(aid).OncePerMatch) c.SpentOnce[aid] = true;
			}
			bool boost = c.SpeedBoost && slot == 0;
			var entry = Schedule(c, act, slot, vpos, vfacing, boost);
			entry.EnergyCost = paid;
			cum += entry.Tick;      // this action's own duration
			entry.Tick = cum;       // strike time = cumulative (= a blink's DEPART tick)
			if (Config.IsBlink(aid)) cum += Config.BlinkTravel(aid);
			entries.Add(entry);
			acts.Add(act);

			string cat = Config.Def(act.Id ?? "").Category;
			if (cat == "move" && act.HasTile) vpos = act.Tile.Value;
			else if (cat == "pivot" && act.HasFacing) vfacing = act.Facing.Value;
			else if (Config.IsBlink(aid) && act.HasTile)
			{
				vpos = act.Tile.Value;
				if (act.HasFacing) vfacing = act.Facing.Value;
			}
			Config.ApplyPlannedSelfBuff(pstat, aid);
			if (cat == "guard") seenGuard = true;
			else if (Config.IsSpell(aid) && Config.Def(aid).NoGuardCombo) seenNoGuardSpell = true;
			slot++;
		}
		return new PlanResult { Entries = entries, Actions = acts };
	}

	private static SchedEntry Schedule(Combatant c, PlanAction action, int slot, Vec2I vpos, int vfacing, bool boost)
	{
		var d = Config.Def(action.Id);
		int within = d.BaseTick;
		if (d.Category == "move" && action.HasTile)
			if (action.Tile.Value == vpos - Config.FACING_VEC[vfacing])
				within += Config.BACK_MOVE_TAX;
		if (boost) within = 0;
		int facing = vfacing;
		bool blinkEff = d.Effect != null && d.Effect.Type == "blink";
		if (action.HasFacing && (d.Category == "pivot" || blinkEff))
			facing = action.Facing.Value;
		return new SchedEntry
		{
			Owner = c.Id,
			Id = action.Id,
			Category = d.Category,
			Tick = Config.FinalTick(d.Band, within),
			BandPriority = Config.BAND_PRIORITY[(int)d.Band],
			Tile = action.HasTile ? action.Tile.Value : c.Pos,
			Facing = facing,
		};
	}

	// ── Basic combat ────────────────────────────────────────────────────────
	private static bool CanMove(Grid grid, Combatant actor, Combatant other, Vec2I tile)
	{
		if (Grid.Dist(actor.Pos, tile) != 1) return false;
		if (grid.IsBlocked(tile)) return false;
		if (other.Pos == tile) return false;
		return true;
	}

	private static void DoMove(SchedEntry s, Combatant actor, Combatant target,
			List<SchedEntry> group, Grid grid, Dictionary<string, int> deadTick, int tick, List<Event> events)
	{
		if (actor.Statuses.ContainsKey("rooted"))
		{
			actor.Statuses.Remove("rooted");
			events.Add(Ev("move_blocked", tick, actor.Id));
			s.Resolved = true;
			actor.RerouteArmed = true;
			actor.RerouteTile = s.Tile;
			return;
		}
		if (actor.RerouteArmed)
		{
			actor.RerouteArmed = false;
			s.Tile = actor.RerouteTile;
		}
		Vec2I T = s.Tile;
		var foeMove = MoveInGroup(group, target.Id);
		bool foeUnresolved = foeMove != null && !foeMove.Resolved;
		// Mutual move into each other's tile -> swap, atomically.
		if (target.Pos == T && foeUnresolved && foeMove.Tile == actor.Pos)
		{
			Vec2I ap = actor.Pos;
			actor.Pos = target.Pos;
			target.Pos = ap;
			s.Resolved = true;
			foeMove.Resolved = true;
			events.Add(Ev("move", tick, actor.Id));
			events.Add(Ev("move", tick, target.Id));
			return;
		}
		// Foe sits on the destination and is moving elsewhere this tick: it resolves first.
		if (target.Pos == T && foeUnresolved && AliveAt(target, deadTick, tick))
		{
			SimpleMove(foeMove, target, actor, grid, tick, events);
			foeMove.Resolved = true;
		}
		SimpleMove(s, actor, target, grid, tick, events);
	}

	private static SchedEntry MoveInGroup(List<SchedEntry> group, string ownerId)
	{
		foreach (var e in group)
			if (e.Owner == ownerId && e.Category == "move") return e;
		return null;
	}

	private static bool AliveAt(Combatant c, Dictionary<string, int> deadTick, int tick)
		=> deadTick[c.Id] == -1 || deadTick[c.Id] >= tick;

	private static void SimpleMove(SchedEntry s, Combatant mover, Combatant other, Grid grid, int tick, List<Event> events)
	{
		if (CanMove(grid, mover, other, s.Tile))
		{
			mover.Pos = s.Tile;
			events.Add(Ev("move", tick, mover.Id));
		}
		else
		{
			int refund = s.EnergyCost;
			mover.Energy = Math.Min(Config.MAX_ENERGY, mover.Energy + refund);
			events.Add(Ev("move_blocked", tick, mover.Id));
		}
	}

	private static void Attack(Combatant attacker, Combatant target, SchedEntry s, int tick,
			Dictionary<string, bool> guarding, Dictionary<string, int> guardBlocked,
			Dictionary<string, int> damagedTick, Dictionary<string, int> deadTick, List<Event> events)
	{
		if (attacker.AttackAllAdjacent)
		{
			if (Grid.Dist(attacker.Pos, target.Pos) != 1) { events.Add(Ev("attack_whiff", tick, attacker.Id)); return; }
		}
		else if (Grid.Dist(attacker.Pos, s.Tile) > attacker.AttackRange) { events.Add(Ev("attack_whiff", tick, attacker.Id)); return; }
		if (!attacker.AttackAllAdjacent && target.Pos != s.Tile) { events.Add(Ev("attack_whiff", tick, attacker.Id)); return; }
		string rel = Flank(target, attacker.Pos);
		int dmg = Rnd(Config.ATTACK_DAMAGE * Config.FLANK_MULT[rel]);
		if (guarding[target.Id])
		{
			guardBlocked[target.Id] = Config.GUARD_REFUND_TIER[rel];
			double blocked = Config.GUARD_BLOCK[rel];
			if (blocked >= 1.0) { events.Add(Ev("attack_blocked", tick, attacker.Id)); return; }
			dmg = Rnd(dmg * (1.0 - blocked));
		}
		ApplyDamage(target, dmg, tick, damagedTick, deadTick);
		events.Add(Ev("attack_hit", tick, attacker.Id));
	}

	// ── Spells (data-driven) ────────────────────────────────────────────────
	private static void CastSpell(Grid grid, Combatant caster, Combatant target, SchedEntry s,
			int tick, Dictionary<string, int> damagedTick, Dictionary<string, int> deadTick,
			Dictionary<string, List<string>> fresh, List<Event> events)
	{
		string id = s.Id;
		var d = Config.Def(id);
		if (d.OncePerMatch) caster.SpentOnce[id] = true;

		var tiles = ShapeTiles(grid, caster, d, s.Tile);
		events.Add(Ev("spell_cast", tick, caster.Id));

		var eff = d.Effect;
		switch (eff.Type)
		{
			case "blink":
				break;   // DEPART/ARRIVE handled live by LaunchBlink
			case "apply_status":
			{
				Combatant who = (string.IsNullOrEmpty(eff.To) ? "self" : eff.To) == "self" ? caster : target;
				string st = eff.Status;
				who.Statuses[st] = Config.StatusDef(st).Duration;
				fresh[who.Id].Add(st);
				events.Add(Ev("buff_applied", tick, who.Id));
				break;
			}
			case "damage":
				if (Config.IsProjectile(id)) { }   // projectile resolves via flight steps
				else if (tiles.Contains(target.Pos))
				{
					int dmg = eff.Amount ?? 0;
					ApplyDamage(target, dmg, tick, damagedTick, deadTick);
					events.Add(Ev("spell_hit", tick, caster.Id));
				}
				else events.Add(Ev("spell_miss", tick, caster.Id));
				break;
		}
	}

	private static List<Vec2I> ShapeTiles(Grid grid, Combatant caster, ActionDef d, Vec2I targetTile)
	{
		string shape = string.IsNullOrEmpty(d.Shape) ? "self" : d.Shape;
		switch (shape)
		{
			case "self":
				return new List<Vec2I> { caster.Pos };
			case "blink":
			{
				Vec2I bdir = DirFrom(caster.Pos, targetTile);
				var bt = new List<Vec2I>();
				Vec2I bp = caster.Pos;
				for (int k = 0; k < (d.Range ?? 1); k++)
				{
					bp += bdir;
					if (grid.InBounds(bp)) bt.Add(bp);
				}
				return bt;
			}
			case "around":
			{
				var outp = new List<Vec2I>();
				int r = d.Radius ?? Config.AROUND_RADIUS;
				for (int dy = -r; dy <= r; dy++)
					for (int dx = -r; dx <= r; dx++)
					{
						if (dx == 0 && dy == 0) continue;
						Vec2I p = caster.Pos + new Vec2I(dx, dy);
						if (grid.InBounds(p)) outp.Add(p);
					}
				return outp;
			}
			case "line":
			{
				Vec2I dir = DirFrom(caster.Pos, targetTile);
				var outp = new List<Vec2I>();
				Vec2I p = caster.Pos;
				for (int k = 0; k < (d.Range ?? 1); k++)
				{
					p += dir;
					if (!grid.InBounds(p) || grid.IsBlocked(p)) break;
					outp.Add(p);
				}
				return outp;
			}
			case "throw":
			{
				int gdx = targetTile.X - caster.Pos.X;
				int gdy = targetTile.Y - caster.Pos.Y;
				int gadx = Math.Abs(gdx), gady = Math.Abs(gdy);
				int grng = d.Range ?? 3;
				int gdrng = d.DiagRange ?? 1;
				bool isOrtho = (gdx == 0 || gdy == 0) && (gadx + gady) >= 1 && (gadx + gady) <= grng;
				bool isDiag = gadx == gady && gadx >= 1 && gadx <= gdrng;
				if (!(isOrtho || isDiag)) return new List<Vec2I>();
				Vec2I gstep = new(Sign(gdx), Sign(gdy));
				var gout = new List<Vec2I>();
				Vec2I gp = caster.Pos;
				while (gp != targetTile)
				{
					gp += gstep;
					if (!grid.InBounds(gp) || grid.IsBlocked(gp)) break;
					gout.Add(gp);
				}
				return gout;
			}
		}
		return new List<Vec2I>();
	}

	private static Vec2I DirFrom(Vec2I a, Vec2I b)
	{
		Vec2I dv = b - a;
		if (Math.Abs(dv.X) >= Math.Abs(dv.Y)) return new Vec2I(Sign(dv.X), 0);
		return new Vec2I(0, Sign(dv.Y));
	}

	// ── Shared helpers ──────────────────────────────────────────────────────
	private static void ApplyDamage(Combatant target, int dmg, int tick, Dictionary<string, int> damagedTick, Dictionary<string, int> deadTick)
	{
		target.Hp = Math.Max(0, target.Hp - dmg);
		if (damagedTick[target.Id] == -1) damagedTick[target.Id] = tick;
		if (target.Hp <= 0 && deadTick[target.Id] == -1) deadTick[target.Id] = tick;
	}

	private static void LaunchBlink(Grid grid, SchedEntry s, Combatant caster, Combatant target,
			List<SchedEntry> sched, int i, int tick, List<Event> events)
	{
		var d = Config.Def(s.Id);
		int rng = d.Range ?? 1;
		Vec2I bdir = DirFrom(caster.Pos, s.Tile);
		if (bdir == new Vec2I(0, 0) || !BlinkHasLanding(grid, caster.Pos, bdir, rng))
		{ events.Add(Ev("blink_fizzle", tick, caster.Id)); return; }
		Vec2I dest = caster.Pos + bdir * rng;
		Vec2I origin = caster.Pos;
		int face = s.Facing;
		events.Add(Ev("blink_depart", tick, caster.Id));
		caster.Pos = IN_TRANSIT;
		sched.Add(new SchedEntry
		{
			Owner = caster.Id, Id = s.Id, Category = "blink_arrive",
			Tick = tick + Config.BlinkTravel(s.Id), BandPriority = Config.PRIORITY_BLINK_ARRIVE,
			Dest = dest, Origin = origin, Facing = face,
		});
		ResortTail(sched, i);
	}

	private static bool BlinkHasLanding(Grid grid, Vec2I from, Vec2I dir, int rng)
	{
		for (int dd = 1; dd <= rng; dd++)
		{
			Vec2I t = from + dir * dd;
			if (grid.InBounds(t) && !grid.IsBlocked(t)) return true;
		}
		return false;
	}

	private static Vec2I BlinkSettle(Grid grid, Combatant foe, Vec2I origin, Vec2I dest)
	{
		Vec2I step = (origin - dest).Sign();
		Vec2I cur = dest;
		while (true)
		{
			if (grid.InBounds(cur) && !grid.IsBlocked(cur) && foe.Pos != cur) return cur;
			if (cur == origin || step == new Vec2I(0, 0)) break;
			cur += step;
		}
		return origin;
	}

	private static void LaunchProjectile(Grid grid, SchedEntry s, Combatant caster, List<SchedEntry> sched, int i, List<Event> events)
	{
		var pd = Config.Def(s.Id);
		Vec2I pdir = DirFrom(caster.Pos, s.Tile);
		List<Config.PathStep> path;
		if (pd.Shape == "throw")
		{
			// Invalid from the LIVE tile (earlier action fizzled) -> miss, no ghost flight.
			if (ShapeTiles(grid, caster, pd, s.Tile).Count == 0)
			{
				events.Add(Ev("spell_miss", s.Tick, caster.Id));
				return;
			}
			path = new List<Config.PathStep>();
			Vec2I cur = caster.Pos;
			int t = s.Tick;
			int tpt = pd.TickPerTile ?? 0;
			int n = 0;
			while (cur != s.Tile && n < 8)
			{
				n++;
				cur += new Vec2I(Sign(s.Tile.X - cur.X), Sign(s.Tile.Y - cur.Y));
				t += tpt;
				path.Add(new Config.PathStep { Tile = cur, Step = n, Tick = t });
			}
		}
		else
		{
			path = Config.ProjectilePath(grid, caster.Pos, pdir, pd.Range ?? 1, pd.TickPerTile ?? 0, s.Tick);
		}
		if (path.Count == 0) return;
		string pid = $"{caster.Id}:{s.Tick}";
		Vec2I prev = caster.Pos;
		foreach (var st in path)
		{
			sched.Add(new SchedEntry
			{
				Owner = caster.Id, Id = s.Id, Category = "projectile",
				Tick = st.Tick, BandPriority = Config.PRIORITY_PROJECTILE,
				Tile = st.Tile, From = prev, Step = st.Step, Pid = pid,
				Dwell = pd.TickPerTile ?? 0,
				Pierce = pd.Pierce,
				Damage = pd.Effect?.Amount ?? 0,
			});
			prev = st.Tile;
		}
		ResortTail(sched, i);
	}

	private static void MoveIntoProjectile(Combatant mover, List<SchedEntry> sched, int tick,
			Dictionary<string, bool> consumed, Dictionary<string, int> damagedTick, Dictionary<string, int> deadTick, List<Event> events)
	{
		if (deadTick[mover.Id] != -1) return;
		foreach (var e in sched)
		{
			if (e.Category != "projectile" || e.Owner == mover.Id) continue;
			if (consumed.GetValueOrDefault(e.Pid, false) || e.Tile != mover.Pos) continue;
			if (tick >= e.Tick && tick < e.Tick + e.Dwell)
			{
				int dmg = e.Damage;
				ApplyDamage(mover, dmg, tick, damagedTick, deadTick);
				events.Add(Ev("spell_hit", tick, mover.Id));
				if (!e.Pierce) consumed[e.Pid] = true;
				return;
			}
		}
	}

	private static void ProjectileStep(SchedEntry s, Combatant actor, Combatant target, int tick,
			Dictionary<string, bool> consumed, Grid grid, Dictionary<string, int> damagedTick, Dictionary<string, int> deadTick, List<Event> events)
	{
		string pid = s.Pid;
		if (consumed.GetValueOrDefault(pid, false)) return;
		Vec2I tile = s.Tile;
		events.Add(Ev("projectile_step", tick, actor.Id));
		if (target.Pos == tile && deadTick[target.Id] == -1)
		{
			var eff = Config.Def(s.Id).Effect;
			if (eff != null && eff.Type == "disrupt")
				ApplyDisrupt(eff, s, actor, target, tick, events, damagedTick, deadTick);
			else
			{
				int dmg = s.Damage;
				ApplyDamage(target, dmg, tick, damagedTick, deadTick);
				events.Add(Ev("spell_hit", tick, actor.Id));
			}
			if (!s.Pierce) consumed[pid] = true;
		}
	}

	private static void ApplyDisrupt(Effect eff, SchedEntry s, Combatant actor, Combatant target, int tick, List<Event> events,
			Dictionary<string, int> damagedTick, Dictionary<string, int> deadTick)
	{
		string st = eff.Status ?? "";
		if (st != "")
			target.Statuses[st] = Config.StatusDef(st)?.Duration ?? 1;
		int drain = eff.EnergyDrain ?? 0;
		if (drain > 0) target.Energy = Math.Max(0, target.Energy - drain);
		int dmg = eff.Amount ?? 0;
		if (dmg > 0) ApplyDamage(target, dmg, tick, damagedTick, deadTick);   // rides the normal path: rest interrupt + block
		events.Add(Ev("spell_hit", tick, actor.Id));
	}

	private static string Flank(Combatant defender, Vec2I attackerPos)
		=> Config.FlankTier(defender.Facing, defender.Pos, attackerPos);

	private static void RestRegen(Combatant c, List<SchedEntry> sched, SchedEntry own, List<Event> events)
	{
		int enemyTick = 0;
		foreach (var s in sched)
			if (s.Owner != c.Id) enemyTick = s.Tick;
		double scale = (double)enemyTick / (Config.BAND_BASE[(int)Config.Band.REST] + Config.BAND_WIDTH);
		scale = Math.Clamp(scale, 0.0, 1.0);
		int hpGain = Rnd(Config.MAX_HP * 0.10 * (0.5 + scale));
		int mpGain = Rnd(Config.MAX_MP * 0.10 * (0.5 + scale));
		c.Hp = Math.Min(Config.MAX_HP, c.Hp + hpGain);
		c.Mp = Math.Min(Config.MAX_MP, c.Mp + mpGain);
		events.Add(Ev("rest_regen", own.Tick, c.Id));
	}

	private static void TickDown(Dictionary<string, int> timers, List<string> skip)
	{
		foreach (var key in timers.Keys.ToList())
		{
			if (skip.Contains(key)) continue;
			timers[key] -= 1;
			if (timers[key] <= 0) timers.Remove(key);
		}
	}

	private static string ResultOf(Combatant a, Combatant b)
	{
		bool ad = a.IsDead();
		bool bd = b.IsDead();
		if (ad && bd) return "draw";
		if (ad) return "b_wins";
		if (bd) return "a_wins";
		return "ongoing";
	}
}
