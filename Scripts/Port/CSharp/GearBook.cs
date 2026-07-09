// GearBook.cs -- C# ENGINE PORT (stage 1). Gear CONTENT: a loadout is up to four gear
// pieces, each granting exactly one spell. Only the ENGINE-relevant field (spell) is
// ported; block colour / overlay / cost are view+shop metadata the engine never reads.
namespace UKO;

using System.Collections.Generic;

public static class GearBook
{
	public sealed class GearDef
	{
		public string Name = "";
		public string Spell = "";   // the spell id this gear grants ("" = none)
	}

	public static readonly Dictionary<string, GearDef> Gear = new()
	{
		["discount_charm"] = new GearDef { Name = "Sage Helm",     Spell = "energy_buff" },
		["burst_node"]     = new GearDef { Name = "Burst Plate",   Spell = "aoe_burst" },
		["blink_boots"]    = new GearDef { Name = "Blink Greaves", Spell = "blink_step" },
		["dark_focus"]     = new GearDef { Name = "Bolt Amulet",   Spell = "dark_bolt" },
	};

	public static GearDef GearOf(string gearId) => Gear.GetValueOrDefault(gearId);

	// The spell granted by a gear piece ("" if the slot is empty / gear unknown).
	public static string SpellOf(string gearId) => Gear.TryGetValue(gearId, out var g) ? g.Spell : "";
}
