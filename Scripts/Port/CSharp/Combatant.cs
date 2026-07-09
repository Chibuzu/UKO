// Combatant.cs -- C# ENGINE PORT (stage 2). Faithful port of Scripts/Core/Combatant.gd:
// pure state for one duelist, no nodes/drawing. The Resolver only ever works on Clone()s
// of it. Reference type (GDScript RefCounted -> C# class) so clones pass by reference.
namespace UKO;

using System.Collections.Generic;

public sealed class Combatant
{
	public string Id;            // "A" or "B"
	public int Hp;
	public int Mp;
	public int Energy;
	public Vec2I Pos;
	public int Facing;           // Config.Facing (0-3)

	// Speed boost ACTIVE this turn (from a successful guard last turn). The resolver
	// reads it for tick ordering, consumes it, then may set it again for next turn.
	public bool SpeedBoost = false;
	public bool RestReady = true;   // may REST only after a full turn taking no damage

	// Active timed statuses: id -> turns remaining, e.g. {"energy_discount": 5}.
	public Dictionary<string, int> Statuses = new();
	// Spell cooldowns: id -> turns remaining before recast.
	public Dictionary<string, int> Cooldowns = new();
	// once_per_match items already used this match (e.g. the grenade): id -> true.
	public Dictionary<string, bool> SpentOnce = new();

	// Transient (one turn only; deliberately NOT copied in Clone()): when a rooted move is
	// cancelled, the actor's next move inherits the cancelled move's target (grenade spec c).
	public bool RerouteArmed = false;
	public Vec2I RerouteTile = new(0, 0);

	// This fighter's own real-action tally toward the energy pulse metronome.
	public int ActionCount = 0;

	// Loadout: four gear slots (ids into GearBook). "" = empty/neutral block. Spells are
	// DERIVED from this (see SpellIds), not stored -- swapping a slot swaps the spell.
	public List<string> Gear = new() { "", "", "", "" };

	public Combatant(string id, Vec2I pos, int facing)
	{
		Id = id;
		Pos = pos;
		Facing = facing;
		Hp = Config.MAX_HP;
		Mp = Config.MAX_MP;
		Energy = Config.MAX_ENERGY;
	}

	// Equip a loadout (gear ids, null/"" for empty). Pads/truncates to exactly 4 slots.
	public void Equip(IReadOnlyList<string> loadout)
	{
		Gear = new List<string>(4);
		for (int i = 0; i < 4; i++)
		{
			string entry = (loadout != null && i < loadout.Count) ? loadout[i] : "";
			Gear.Add(entry ?? "");   // null (e.g. from serialization) -> "" without crashing
		}
	}

	// The spell ids this fighter can cast, in slot order (empties skipped), plus the
	// universal once-per-match grenade. This is what the menu/AI/resolver read.
	public List<string> SpellIds()
	{
		var outp = new List<string>();
		foreach (var gid in Gear)
		{
			string sid = GearBook.SpellOf(gid);
			if (sid != "") outp.Add(sid);
		}
		outp.Add("grenade");
		return outp;
	}

	// The spell in a specific block slot (0-3), or "" if empty. Slot-indexed input.
	public string SpellInSlot(int slot)
	{
		if (slot < 0 || slot >= Gear.Count) return "";
		return GearBook.SpellOf(Gear[slot]);
	}

	public Combatant Clone()
	{
		var c = new Combatant(Id, Pos, Facing)
		{
			Hp = Hp,
			Mp = Mp,
			Energy = Energy,
			SpeedBoost = SpeedBoost,
			RestReady = RestReady,
			Statuses = new Dictionary<string, int>(Statuses),
			Cooldowns = new Dictionary<string, int>(Cooldowns),
			SpentOnce = new Dictionary<string, bool>(SpentOnce),
			ActionCount = ActionCount,
			Gear = new List<string>(Gear),
		};
		// RerouteArmed / RerouteTile are transient and intentionally reset (not copied).
		return c;
	}

	public bool IsDead() => Hp <= 0;
}
