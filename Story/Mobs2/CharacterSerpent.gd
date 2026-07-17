# CharacterSerpent.gd -- one twin of the cave boss, as a TRUE CHARACTER.
#
# The boss is a PAIR of these (StoryController._spawn_cavern_boss): two identical
# SINGLE-TILE creatures that start side by side at the top of the cage. Both must fall
# before the cage opens. There is no body, no pivot, no span -- a twin is exactly as
# simple as a bat, which is the whole point of the remodel.
#
# BEHAVIOUR (Fra): aggressive, permanently trying to attack. It closes and it bites --
# nothing else. Its bite is ONE adjacent tile (not the ooze's four), and it spends two
# actions a turn, so the pair spends four against your two.
#
# The pair needs no coordination code: two bodies means you cannot face both at once, so
# whenever they end up on opposite sides one of them is flanking you for x1.5. That
# pressure falls out of the geometry instead of being scripted.
class_name CharacterSerpent
extends MobKind

var _loadout: Dictionary = {}

func setup(p_type: String, p_prof: Dictionary) -> void:
	super.setup(p_type, p_prof)
	_loadout = MobSpec.row(p_type).get("loadout", {})

# StoryCombat reads this: its damage comes from the RESOLVER, skip budget strikes.
func uses_true_actions() -> bool:
	return true

# Always exactly two actions: choose, simulate the result, choose again.
func plan(mob: Combatant, player: Combatant, grid: Grid) -> Array:
	var seq: Array = []
	var pos := mob.pos
	for _slot in range(2):
		var act := _best_action(pos, player, grid)
		seq.append(act)
		if String(act["id"]) == "move":
			pos = act["tile"]              # the second choice sees where the first landed
	return seq

# Bite if you are in reach; otherwise close on a seat beside you. That is the creature.
func _best_action(pos: Vector2i, player: Combatant, grid: Grid) -> Dictionary:
	if Grid.dist(pos, player.pos) == 1 and _has("attack"):
		return { "id": "attack", "tile": player.pos }
	if _has("move"):
		var step := _close_in(pos, player.pos, grid)
		if step != pos:
			return { "id": "move", "tile": step }
	return { "id": "wait" }

# Threat preview: the four tiles it could bite from where it stands.
func attack_pattern(origin: Vector2i) -> Array:
	return cardinal_ring(origin, 1)

# One step toward the seat it wants beside you. It aims at a free SEAT rather than at
# you directly: the combat grid already blocks its twin, so the two of them settle on
# DIFFERENT seats instead of fighting over one -- and a twin whose sibling stands between
# it and you still has somewhere to go, instead of freezing.
func _close_in(pos: Vector2i, target: Vector2i, grid: Grid) -> Vector2i:
	var goal := _seat(pos, target, grid)
	var best := pos
	var bestd := Grid.dist(pos, goal)
	for t: Vector2i in _neighbours(pos):
		if grid.is_blocked(t) or t == target:
			continue
		var d := Grid.dist(t, goal)
		if d < bestd:
			bestd = d
			best = t
	return best

# The nearest free tile beside you (falling back to you, if it is hemmed in).
func _seat(pos: Vector2i, target: Vector2i, grid: Grid) -> Vector2i:
	var seat := target
	var best := 99999
	for t: Vector2i in _neighbours(target):
		if grid.is_blocked(t) or t == pos:
			continue
		var d := Grid.dist(pos, t)
		if d < best:
			best = d
			seat = t
	return seat

func _neighbours(p: Vector2i) -> Array:
	return [p + Vector2i(0, -1), p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(-1, 0)]

func _has(spell: String) -> bool:
	return _loadout.has(spell)
