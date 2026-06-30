# OverworldState.gd
# A tiny STATIC carrier that survives the scene change into a duel and back, so the
# zone restores instead of regenerating: the map seed (same seed -> same map), the
# player's tile, the surviving mobs, and which mob is being fought. Mirrors the
# pattern GameController uses for its lobby handoff. (Later this is what a real save
# file persists.)
class_name OverworldState
extends RefCounted

static var active: bool = false
static var seed_value: int = 0
static var player_tile: Vector2i = Vector2i.ZERO
static var mobs: Array = []           # [{ "type": String, "tile": Vector2i }]
static var fighting: int = -1         # index into mobs of the mob being fought (-1 = none)

static func reset() -> void:
	active = false
	seed_value = 0
	player_tile = Vector2i.ZERO
	mobs = []
	fighting = -1
