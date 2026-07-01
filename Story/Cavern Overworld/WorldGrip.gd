# WorldGrid.gd
# The grid the SAME combat engine runs on in story mode -- sized to the open world
# (60x60) and fed by an OverworldMap's walls, with the arena-only mechanics (quadrant
# rotation, spawn-connectivity reroll, incoming-wall telegraph) turned off. The
# Resolver only asks a grid is_blocked()/in_bounds() and uses the static dist/cheb,
# so the deterministic core runs on this with zero changes -- and PLAY's 12x12 Grid
# is left completely untouched.
class_name WorldGrid
extends Grid

var world_size: int = OverworldMap.SIZE

# Adopt an overworld's wall layout as this grid's terrain.
func build(map: OverworldMap) -> void:
	world_size = OverworldMap.SIZE
	blocked = []
	for y in world_size:
		blocked.append(map.blocked[y].duplicate())
	base_blocked = _copy(blocked)

# Bounds follow the WORLD size, not the arena's const SIZE. is_blocked() (inherited)
# is defined in terms of in_bounds() + blocked, so overriding this is enough for the
# whole grid to behave at 60x60.
func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < world_size and p.y >= 0 and p.y < world_size

# The open world does not rotate, so these arena mechanics are no-ops here.
func rotate_blockers(_occupants: Array) -> Array:
	return []

func incoming_walls() -> Array:
	return []
