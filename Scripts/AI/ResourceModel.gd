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

# Per-fighter resource weights {hp, mp, ep}, derived from its loadout.
static func weights(c: Combatant) -> Dictionary:
	return {
		"hp": 1.0,
		"mp": ENABLER_DISCOUNT * _best_dmg_per_mp(c),
		"ep": ENABLER_DISCOUNT * _best_dmg_per_ep(c),
	}

# Value a resource bundle (or a delta) in HP-equivalent points for caster `c`.
static func value(c: Combatant, hp: float, mp: float, ep: float) -> float:
	var w := weights(c)
	return hp * w["hp"] + mp * w["mp"] + ep * w["ep"]

# Worth of a fighter's CURRENT stockpile.
static func stock(c: Combatant) -> float:
	return value(c, float(c.hp), float(c.mp), float(c.energy))

# The economy differential the AI maximises: my stockpile minus the enemy's,
# each side valued by its OWN conversion rates. Positive = I'm ahead.
static func advantage(me: Combatant, enemy: Combatant) -> float:
	return stock(me) - stock(enemy)

# Cost of an action in value-points (the MP + EP it spends), for caster `c`.
static func action_cost_value(c: Combatant, mp_cost: int, ep_cost: int) -> float:
	var w := weights(c)
	return float(mp_cost) * w["mp"] + float(ep_cost) * w["ep"]

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
