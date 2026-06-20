# AIToolkit.gd
# Shared substrate for the AI brains: the rules-faithful helpers every brain needs
# -- project an action onto a clone, test castability, trace a clear line. These
# used to live in StubOpponent and were reached into across the class boundary by
# ChallengingAI; they now have ONE owner here, so the brains depend on a system
# rather than on each other's internals. Pure / static / no brain logic of its own.
class_name AIToolkit
extends RefCounted

# Mirror the resolver's upfront pay (+ position/facing/cooldown) so a second pick
# in a sequence is judged from where the first leaves us. Statuses are NOT applied:
# the resolver pays upfront, before a same-turn buff would discount anything.
static func apply_projection(c: Combatant, action: Dictionary) -> void:
	var id: String = action.get("id", "")
	var d := Config.def(id)
	var cat: String = d.get("category", "")
	if cat == "move" and action.has("tile"):
		c.energy = maxi(0, c.energy - Config.effective_move_cost(c.facing, c.pos, action["tile"], c.statuses))
		c.pos = action["tile"]
	elif cat == "pivot" and action.has("facing"):
		c.facing = int(action["facing"])
	else:
		c.energy = maxi(0, c.energy - Config.effective_energy_cost(id, c.statuses))
		c.mp = maxi(0, c.mp - int(d.get("mp_cost", 0)))
	if Config.is_spell(id):
		var cd := Config.cooldown_of(id)
		if cd > 0:
			c.cooldowns[id] = cd

# Ready = off cooldown AND affordable.
static func can_use(me: Combatant, id: String) -> bool:
	if int(me.cooldowns.get(id, 0)) > 0:
		return false
	return Config.can_afford(me.energy, me.mp, me.statuses, id)

# True if the foe sits on a clear orthogonal line within range (matches the
# resolver's bolt trace: any blocker between caster and foe stops it).
static func clear_line(me: Combatant, foe: Combatant, grid: Grid, rng: int) -> bool:
	var dx := foe.pos.x - me.pos.x
	var dy := foe.pos.y - me.pos.y
	if dx != 0 and dy != 0:
		return false
	var dist := absi(dx) + absi(dy)
	if dist < 1 or dist > rng:
		return false
	var step := Vector2i(signi(dx), signi(dy))
	var p: Vector2i = me.pos
	for _i in range(dist):
		p += step
		if grid.is_blocked(p):
			return false
	return true
