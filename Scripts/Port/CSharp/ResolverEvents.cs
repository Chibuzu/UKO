// ResolverEvents.cs — C# twin of Scripts/Core/ResolverEvents.gd.
// THE authoritative registry of resolver event type strings on the C# side.
// The VALUES must stay byte-identical with the GDScript registry (the parity
// digest keys on them). Pure/framework-free: compiles outside Godot.
namespace UKO;

public static class ResolverEvents
{
	// movement / posture
	public const string Move = "move";
	public const string MoveBlocked = "move_blocked";
	public const string Pivot = "pivot";
	public const string Clash = "clash";
	// melee
	public const string AttackHit = "attack_hit";
	public const string AttackWhiff = "attack_whiff";
	public const string AttackBlocked = "attack_blocked";
	// guard
	public const string GuardRaised = "guard_raised";
	public const string GuardDropped = "guard_dropped";
	public const string GuardSuccess = "guard_success";
	public const string GuardFailed = "guard_failed";
	// recovery / tempo
	public const string Rest = "rest";
	public const string RestRegen = "rest_regen";
	public const string RestInterrupted = "rest_interrupted";
	public const string Wait = "wait";
	public const string EnergyPulse = "energy_pulse";
	// spells / items
	public const string SpellCast = "spell_cast";
	public const string SpellHit = "spell_hit";
	public const string SpellMiss = "spell_miss";
	public const string BuffApplied = "buff_applied";
	// blink
	public const string Blink = "blink";
	public const string BlinkDepart = "blink_depart";
	public const string BlinkFizzle = "blink_fizzle";
	// projectiles
	public const string ProjectileStep = "projectile_step";
	// bookkeeping
	public const string IllegalAction = "illegal_action";
	public const string DeadSkip = "dead_skip";
	public const string GameOver = "game_over";
}
