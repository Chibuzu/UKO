# IntentSelector.gd
# AI STRATEGIC INTENT (new-brain step 3). Reads the resource ECONOMY differential
# (via ResourceModel) and names what the AI is trying to DO this stretch of the
# match: Aggress / Zone / Recover / Kite / Bait. The per-turn layers (tile utility,
# the plan matrix) then act in service of that intent.
#
# MODULARITY IS THE WHOLE POINT HERE:
#   * This file NEVER mentions a specific spell or gear id. It looks only at
#     HP / MP / EP, so it keeps working no matter what kit the fighter carries.
#   * Intent -> which actions to favour is expressed as DATA, using the `ai_role`
#     TAGS that already live on spells (poke / aoe / blink / buff / ...). Add a
#     new gear piece with a role and the plan layer picks it up for the right
#     intents with ZERO changes here.
#   * Adding a new intent later = one INTENTS entry + one line in the cascade.
#
# Hysteresis (not flip-flopping intent every turn) is meant to come mainly from
# the GOAL layer's multi-turn payoff, so classify() is a PURE function of the
# current state. select() adds an OPTIONAL stickiness margin for callers that
# want a little damping before the goal layer exists.
class_name IntentSelector
extends RefCounted

# Intent ids (string-keyed so they're trivially serialisable / loggable).
const AGGRESS := "aggress"
const ZONE := "zone"
const RECOVER := "recover"
const KITE := "kite"
const BAIT := "bait"

# Intent metadata. `favor_roles` are matched against spell `ai_role` tags and the
# generic action categories ("attack"/"move"/"guard"/"rest") by the plan layer,
# so this is the ONLY place the intent->action bias is defined. `posture` tells
# the goal layer how to pick a target tile (approach / back off / hold / space).
const INTENTS := {
	AGGRESS: { "favor_roles": ["poke", "aoe", "attack"], "posture": "close",   "desc": "ahead on resources: press the advantage" },
	ZONE:    { "favor_roles": ["poke", "aoe"],           "posture": "control", "desc": "roughly even: control space (esp. before a shift)" },
	RECOVER: { "favor_roles": ["rest", "blink"],         "posture": "retreat", "desc": "behind on HP: disengage and heal" },
	KITE:    { "favor_roles": ["poke", "blink", "move"], "posture": "retreat", "desc": "behind on resources: trade from range, deny the close" },
	BAIT:    { "favor_roles": ["blink", "guard", "move"],"posture": "space",   "desc": "EP-starved but healthy: provoke a costly enemy commit" },
}

# ── Tunable thresholds (all in ResourceModel value-points unless noted) ──────
const MARGIN := 12.0          # |advantage| under this = "roughly even" -> Zone
const HP_BEHIND := 15         # raw HP deficit that makes Recover dominant
const HP_OK := 50             # raw HP at/above which Bait (provoking) is safe
const EP_LOW := 35            # raw EP at/below which we count as EP-starved
const EP_BEHIND_VAL := 10.0   # EP deficit (valued) that counts as "behind on EP"
const MP_BEHIND_VAL := 10.0   # MP deficit (valued) that counts as "behind on MP"
const HYSTERESIS := 6.0       # optional stickiness band for select()

# Raw decision signals, exposed for logging / tuning / the goal layer.
static func signals(me: Combatant, enemy: Combatant) -> Dictionary:
	var w := ResourceModel.weights(me)   # value MY deficits by what I could do with them
	return {
		"overall": ResourceModel.advantage(me, enemy),
		"hp_def": enemy.hp - me.hp,                                  # >0 = I'm behind on HP
		"mp_def_val": float(enemy.mp - me.mp) * w["mp"],
		"ep_def_val": float(enemy.energy - me.energy) * w["ep"],
		"ep_poor": (enemy.energy - me.energy) * w["ep"] >= EP_BEHIND_VAL or me.energy <= EP_LOW,
		"mp_poor": (enemy.mp - me.mp) * w["mp"] >= MP_BEHIND_VAL,
		"hp_ok": me.hp >= HP_OK,
	}

# Pure classification from the current state. Priority cascade (order matters,
# because the conditions overlap): HP dominates, then the resource economy.
static func classify(me: Combatant, enemy: Combatant) -> String:
	var s := signals(me, enemy)
	if s["hp_def"] >= HP_BEHIND:
		return RECOVER                              # bleeding -> get safe and heal, whatever else is true
	if s["overall"] >= MARGIN:
		return AGGRESS                              # ahead on the economy -> press
	if s["overall"] <= -MARGIN:
		if s["ep_poor"] and s["hp_ok"]:
			return BAIT                             # can't act much but healthy -> bait a costly whiff
		return KITE                                 # behind on resources / hurt -> trade from range, deny
	return ZONE                                     # roughly even -> contest space

# Classification with OPTIONAL stickiness: keep the previous intent unless the
# economy has moved clearly past the boundary, to avoid turn-to-turn churn. Pass
# prev_intent = "" to get the pure classify() result.
static func select(me: Combatant, enemy: Combatant, prev_intent: String = "", margin: float = HYSTERESIS) -> String:
	var fresh := classify(me, enemy)
	if prev_intent == "" or fresh == prev_intent:
		return fresh
	# Only switch if we're not sitting right on the deciding boundary.
	var overall: float = ResourceModel.advantage(me, enemy)
	if absf(overall) < MARGIN + margin and prev_intent != RECOVER:
		# Near the even/ahead/behind seam and not overriding a Recover -> hold.
		if classify(me, enemy) in [AGGRESS, KITE, BAIT, ZONE]:
			return prev_intent
	return fresh

# ── Accessors the plan / goal layers read (keep the data in one place) ──────
static func favored_roles(intent: String) -> Array:
	return INTENTS.get(intent, {}).get("favor_roles", [])

static func posture(intent: String) -> String:
	return String(INTENTS.get(intent, {}).get("posture", "control"))

static func describe(intent: String) -> String:
	return String(INTENTS.get(intent, {}).get("desc", intent))
