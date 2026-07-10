# WorldGrid.gd
# The grid the SAME combat engine runs on in story mode -- sized to the open world
# (60x60) and fed by an OverworldMap's walls, with the arena-only mechanics (quadrant
# rotation, spawn-connectivity reroll, incoming-wall telegraph) turned off. The
# Resolver only asks a grid is_blocked()/in_bounds() and uses the static dist/cheb,
# so the deterministic core runs on this with zero changes -- and PLAY's 12x12 Grid
# is left completely untouched.
class_name WorldGrid
extends Grid

# Character colliders: tiles occupied by NPCs are solid for every mover
# (player and mobs alike) -- maintained by StoryController.
var occupied: Dictionary = {}

var world_size: int = OverworldMap.SIZE

var gem_map: OverworldMap = null   # ungathered gemstone nodes are solid; gathering clears them

# Build a small standalone arena: everything is wall except `open_rect` (the boss
# fighting floor). No overworld behind it -- gem_map stays null, occupied starts empty.
func build_arena(size: int, open_rect: Rect2i) -> void:
	world_size = size
	gem_map = null
	occupied = {}
	blocked = []
	for y in size:
		var row: Array = []
		for x in size:
			row.append(not open_rect.has_point(Vector2i(x, y)))
		blocked.append(row)
	base_blocked = _copy(blocked)

# Adopt an overworld's wall layout as this grid's terrain.
func build(map: OverworldMap) -> void:
	world_size = OverworldMap.SIZE
	gem_map = map
	blocked = []
	for y in world_size:
		blocked.append(map.blocked[y].duplicate())
	base_blocked = _copy(blocked)

# A tile is solid if it's a wall OR still holds a gemstone node. Gems live in the map's gem_set
# (not the blocked array), so they still DRAW as gems -- but you can't step onto one until it's
# gathered, at which point remove_gem() clears it here too (shared reference).
func is_blocked(p: Vector2i) -> bool:
	if occupied.has(p):
		return true
	if gem_map != null and (gem_map.is_gem(p) or gem_map.is_mushroom(p)):
		return true
	return super.is_blocked(p)

# Bounds follow the WORLD size, not the arena's const SIZE. is_blocked() (inherited)
# is defined in terms of in_bounds() + blocked, so overriding this is enough for the
# whole grid to behave at 60x60.
func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < world_size and p.y >= 0 and p.y < world_size

# The open world does not rotate, so these arena mechanics are no-ops here.
func rotate_blockers(occupants: Array) -> Dictionary:
	return {"crushed_idx": [], "positions": occupants}   # story: no quadrant rotation, no shrinking zone

func incoming_walls() -> Array:
	return []
