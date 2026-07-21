# ResolverEvents.gd
# THE authoritative registry of resolver event type strings — the contract between
# the engine (Resolver.gd emits these) and every consumer (EventPlayer renders,
# CombatLog narrates). Mirrored in C# as Scripts/Port/CSharp/ResolverEvents.cs;
# the VALUES must stay byte-identical in both languages (the parity digest keys
# on them). Add an event here + in the C# twin FIRST, then emit it, then decide
# in each consumer whether it renders, logs, or is deliberately hidden — the
# consumers warn once on any type they don't recognize, so a new event can no
# longer be silently dropped.
class_name ResolverEvents

# movement / posture
const MOVE            := "move"
const MOVE_BLOCKED    := "move_blocked"
const PIVOT           := "pivot"
const CLASH           := "clash"            # contested-tile RPS: result=bounce/win (+damage / +staggered)
# melee
const ATTACK_HIT      := "attack_hit"
const ATTACK_WHIFF    := "attack_whiff"
const ATTACK_BLOCKED  := "attack_blocked"
const ATTACK_DRAINED  := "attack_drained"   # a disrupt emptied the tank -> the queued swing breaks
# guard
const GUARD_RAISED    := "guard_raised"
const GUARD_DROPPED   := "guard_dropped"
const GUARD_SUCCESS   := "guard_success"
const GUARD_FAILED    := "guard_failed"
# recovery / tempo
const REST            := "rest"
const REST_REGEN      := "rest_regen"
const REST_INTERRUPTED := "rest_interrupted"
const WAIT            := "wait"
const ENERGY_PULSE    := "energy_pulse"
# spells / items
const SPELL_CAST      := "spell_cast"
const SPELL_HIT       := "spell_hit"
const SPELL_MISS      := "spell_miss"
const BUFF_APPLIED    := "buff_applied"
# blink
const BLINK           := "blink"
const BLINK_DEPART    := "blink_depart"
const BLINK_FIZZLE    := "blink_fizzle"
# projectiles
const PROJECTILE_STEP := "projectile_step"
# bookkeeping
const ILLEGAL_ACTION  := "illegal_action"
const DEAD_SKIP       := "dead_skip"
const GAME_OVER       := "game_over"

const ALL := [
	MOVE, MOVE_BLOCKED, PIVOT, CLASH,
	ATTACK_HIT, ATTACK_WHIFF, ATTACK_BLOCKED,
	GUARD_RAISED, GUARD_DROPPED, GUARD_SUCCESS, GUARD_FAILED,
	REST, REST_REGEN, REST_INTERRUPTED, WAIT, ENERGY_PULSE,
	SPELL_CAST, SPELL_HIT, SPELL_MISS, BUFF_APPLIED,
	BLINK, BLINK_DEPART, BLINK_FIZZLE, PROJECTILE_STEP,
	ILLEGAL_ACTION, DEAD_SKIP, GAME_OVER,
]

static func is_known(t: String) -> bool:
	return ALL.has(t)
