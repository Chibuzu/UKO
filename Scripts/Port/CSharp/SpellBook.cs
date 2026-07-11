// SpellBook.cs -- C# ENGINE PORT (stage 1). ALL spell + status CONTENT, away from the
// engine numbers in Config.cs (mirrors the GDScript split). A spell is data: a SHAPE
// (which tiles it touches) + an EFFECT (what it does). vfx / ai_role are view+AI-hint
// metadata and are intentionally NOT ported (the Resolver never reads them).
namespace UKO;

using System.Collections.Generic;

public sealed class StatusDef
{
	public int Duration;
	public int EnergyCostReduction;   // energy_discount
	public bool BlocksMove;           // rooted
}

public static class SpellBook
{
	public static readonly Dictionary<string, ActionDef> SPELLS = new()
	{
		["energy_buff"] = new ActionDef
		{
			Id = "energy_buff", Name = "DISCOUNT", Category = "spell",
			Band = Config.Band.BUFF, BaseTick = 20,
			EnergyCost = 0, MpCost = 10, Cooldown = 3,
			NeedsTile = false, Shape = "self",
			Effect = new Effect { Type = "apply_status", Status = "energy_discount", To = "self" },
		},
		["aoe_burst"] = new ActionDef
		{
			Id = "aoe_burst", Name = "BURST", Category = "spell",
			Band = Config.Band.AOE, BaseTick = 40,
			EnergyCost = 0, MpCost = 30, Cooldown = 2,
			NeedsTile = false, Shape = "around",
			Effect = new Effect { Type = "damage", Amount = 15 },
		},
		["dark_bolt"] = new ActionDef
		{
			Id = "dark_bolt", Name = "DARK BOLT", Category = "spell",
			Band = Config.Band.ATTACK, BaseTick = 50,
			EnergyCost = 0, MpCost = 40, Cooldown = 4,
			NeedsTile = true, Shape = "line", Range = 3,
			Projectile = true, TickPerTile = 200, Pierce = false,
			Effect = new Effect { Type = "damage", Amount = 25 },
			NoGuardCombo = true,
		},
		["grenade"] = new ActionDef
		{
			Id = "grenade", Name = "GRENADE", Category = "spell",
			Band = Config.Band.ATTACK, BaseTick = 0,
			EnergyCost = 0, MpCost = 0, Cooldown = 0,
			OncePerMatch = true,
			NeedsTile = true, Shape = "throw", Range = 3, DiagRange = 1,
			Projectile = true, TickPerTile = 180, Pierce = false,
			Effect = new Effect { Type = "disrupt", EnergyDrain = 20, Status = "rooted", Amount = 1 },
			NoGuardCombo = true,
		},
		["blink_step"] = new ActionDef
		{
			Id = "blink_step", Name = "BLINK", Category = "spell",
			Band = Config.Band.PIVOT, BaseTick = 0,
			EnergyCost = 0, MpCost = 40, Cooldown = 4,
			NeedsTile = true, Shape = "blink", Range = 2,
			TickPerTile = 300,
			Effect = new Effect { Type = "blink" },
		},
	};

	public static readonly Dictionary<string, StatusDef> STATUSES = new()
	{
		["energy_discount"] = new StatusDef { Duration = 3, EnergyCostReduction = 5 },
		["rooted"]          = new StatusDef { Duration = 2, BlocksMove = true },
	};
}
