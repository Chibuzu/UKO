# ResourceModel.gd
# AI resource ECONOMY (new-brain step 1). Converts a fighter's HP / MP / EP into
# ONE comparable value scale so the AI can reason about exchanges: "spend 40 MP
# to remove 25 enemy HP -- worth it?"
#
# HP is the win condition, so it anchors the scale at weight 1.0. MP and EP are
# ENABLERS, valued ENDOGENOUSLY by how efficiently THIS fighter's current loadout
# converts them into HP damage (best damage-per-MP / per-EP it can actually
# produce). Add an efficient spell and MP auto-revalues -- nothing to hand-tune,
# which matters because gear (and therefore the kit) varies per match.
#
# Everything downstream (tile utility, the plan matrix, the goal layer) scores in
# these value-points, so positions, damage, and resources all add up on one axis.
class_name ResourceModel
extends RefCounted

# Enablers are POTENTIAL, not realised (cooldowns, dodges, you may never spend
# them), so discount them against raw HP. Floors stop a resource valuing at zero
# when the loadout has no damaging use for it yet.
const ENABLER_DISCOUNT := 0.7
const MP_FLOOR := 0.15
const EP_FLOOR := 0.20

# HP is valued by the RACE, not the raw gap: an even trade helps whoever's ahead
# and hurts whoever's behind, so the AI presses a lead and refuses even trades when
# behind -- with no explicit "don't trade when behind" rule. HP_RACE drives the
# relative (win-probability-like) term; HP_LIN keeps a gentle absolute gradient.
const HP_RACE := 80.0
const HP_LIN := 0.3

# Per-fighter resource weights {hp, mp, ep}, derived from its loadout.
static func weights(c: Combatant) -> Dictionary:
	return {
		"hp": 1.0,
		"mp": ENABLER_DISCOUNT * _best_dmg_per_mp(c),
		"ep": ENABLER_DISCOUNT * _best_dmg_per_ep(c),
	}

# Raw LINEAR bundle value (per-point marginal weights). Kept for simple deltas and
# the cost approximations; the DECISION currency is advantage(), which is concave.
static func value(c: Combatant, hp: float, mp: float, ep: float) -> float:
	var w := weights(c)
	return hp * w["hp"] + mp * w["mp"] + ep * w["ep"]

# Solo worth of a fighter's stockpile: linear HP + CONCAVE resources (debug/logging;
# the relative HP race lives in advantage()).
static func stock(c: Combatant) -> float:
	return float(c.hp) + _resource_value(c)

# The economy differential the AI maximises. HP enters as a RACE term (relative),
# resources as CONCAVE stockpiles (banked-but-unusable EP/MP is worth little, so the
# AI won't farm energy by waiting/wiggling, but values it highly when short).
static func advantage(me: Combatant, enemy: Combatant) -> float:
	return _hp_race(float(me.hp), float(enemy.hp)) + (_resource_value(me) - _resource_value(enemy))

# Cost of an action in value-points (the MP + EP it spends), at the base marginal
# weights -- a cheap approximation used for pruning, not the final cell value.
static func action_cost_value(c: Combatant, mp_cost: int, ep_cost: int) -> float:
	var w := weights(c)
	return float(mp_cost) * w["mp"] + float(ep_cost) * w["ep"]

# Relative HP standing. (my-foe)/(my+foe) is +/-1 at a wipe, 0 at parity, and an even
# trade nudges it toward whoever leads -- the convexity that makes pressing pay.
static func _hp_race(my_hp: float, foe_hp: float) -> float:
	var s := my_hp + foe_hp
	var rel := 0.0
	if s > 0.0:
		rel = (my_hp - foe_hp) / s
	return HP_RACE * rel + HP_LIN * (my_hp - foe_hp)

# Concave value of a fighter's MP+EP: marginal worth is ~2x the base weight when the
# bar is near empty and ~0 near full, so surplus you can't spend is nearly worthless.
static func _resource_value(c: Combatant) -> float:
	var w := weights(c)
	return w["mp"] * float(Config.MAX_MP) * _concave(float(c.mp), float(Config.MAX_MP)) \
		+ w["ep"] * float(Config.MAX_ENERGY) * _concave(float(c.energy), float(Config.MAX_ENERGY))

# f(r) = 2r - r^2 : concave, f(0)=0, f(1)=1, slope 2 at empty -> 0 at full.
static func _concave(level: float, cap: float) -> float:
	var r := clampf(level / maxf(1.0, cap), 0.0, 1.0)
	return 2.0 * r - r * r

# Best HP-damage one point of MP can buy on this loadout (>= MP_FLOOR).
static func _best_dmg_per_mp(c: Combatant) -> float:
	var best := MP_FLOOR
	for sid in c.spell_ids():
		var sp: Dictionary = SpellBook.SPELLS.get(sid, {})
		if sp.get("effect", {}).get("type", "") != "damage":
			continue
		var mp := int(sp.get("mp_cost", 0))
		if mp <= 0:
			continue
		best = maxf(best, float(sp["effect"]["amount"]) / float(mp))
	return best

# Best HP-damage one point of EP can buy. The basic attack is the main EP->damage
# converter (spells here spend MP, not EP), but any EP-costing damage spell counts.
static func _best_dmg_per_ep(c: Combatant) -> float:
	var best := float(Config.ATTACK_DAMAGE) / float(maxi(1, Config.COST_ATTACK))
	for sid in c.spell_ids():
		var sp: Dictionary = SpellBook.SPELLS.get(sid, {})
		if sp.get("effect", {}).get("type", "") != "damage":
			continue
		var ep := int(sp.get("energy_cost", 0))
		if ep <= 0:
			continue
		best = maxf(best, float(sp["effect"]["amount"]) / float(ep))
	return maxf(EP_FLOOR, best)
