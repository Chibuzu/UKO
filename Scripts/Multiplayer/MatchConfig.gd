# MatchConfig.gd
# The agreed starting conditions for an online match, produced by the handshake
# before turn 1. BOTH clients must hold an identical config or their deterministic
# Resolvers would diverge: same map seed -> same wall layout / rotations; same
# loadouts -> same spells (derived from gear ids via GearBook, never hardcoded);
# same content version -> same rules. `local_is_a` is the only field that differs
# per client -- it says which side this client drives.
class_name MatchConfig
extends RefCounted

var map_seed: int = 0
var content_version: String = ""
var loadout_a: Array = []      # gear ids for side A (spells are derived, not sent)
var loadout_b: Array = []      # gear ids for side B
var local_is_a: bool = true    # this client controls A (false = controls B)
# Server-authoritative map: the wall layout as "#"/"." row strings. When set,
# clients LOAD it (Grid.load_rows) instead of seeding a generator -- rotations
# then derive deterministically from the same base everywhere. Empty = seed era.
var map_rows: Array = []

static func make(seed_value: int, version: String, la: Array, lb: Array, local_a: bool) -> MatchConfig:
	var c := MatchConfig.new()
	c.map_seed = seed_value
	c.content_version = version
	c.loadout_a = la.duplicate()
	c.loadout_b = lb.duplicate()
	c.local_is_a = local_a
	return c
