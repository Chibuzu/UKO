# MobKind.gd
# Base class for a story monster's BEHAVIOR. Every creature is a subclass that overrides
# a few hooks; shared bits live here so a new creature is one small file (plus a line in
# MobBrain.make_kind). Every creature is a TRUE-ACTION character: plan() returns real
# resolver actions (move/attack/pivot...), so damage, guard, flanks and misses are all
# ENGINE outcomes -- nothing is synthesized story-side. (The old budget-strike fallback
# is gone: a kind that doesn't override plan() simply holds its ground, which is loud
# and obvious in a playtest -- exactly what an unfinished creature should be.)
# Override points, in the order you'll usually reach for them:
#   plan(), attack_pattern(), on_committed(), roll_loot().
class_name MobKind
extends RefCounted

var type: String = ""
var prof: Dictionary = {}

func setup(p_type: String, p_prof: Dictionary) -> void:
	type = p_type
	prof = p_prof

# ── hooks (override per creature) ─────────────────────────────────────────────

# The turn's TRUE-ACTION sequence for the resolver. Base: hold position -- every
# real creature overrides this (see CharacterBat for the pattern).
func plan(_mob: Combatant, _player: Combatant, _grid: Grid) -> Array:
	return []

# The tiles this creature threatens from `origin` (used by the story-side guard
# refund + any threat display). Default: the 4 adjacent tiles.
func attack_pattern(origin: Vector2i) -> Array:
	return cardinal_ring(origin, 1)

# Fired after the turn's state is committed. Hook for thresholds / splits / on-hit logic.
# `entry` is this mob's record {combatant, uv, kind, type, ...}; `ctx` is the StoryController.
func on_committed(entry: Dictionary, player: Combatant, ctx) -> void:
	pass

# Loot rolled when this creature dies: [{item, count}]. Data-driven from the profile's
# "loot" table; override for conditional drops.
func roll_loot() -> Array:
	var out: Array = []
	for drop in prof.get("loot", []):
		if randf() <= float(drop.get("chance", 1.0)):
			out.append({ "item": String(drop["item"]), "count": int(drop.get("count", 1)) })
	return out

# ── shared helpers ────────────────────────────────────────────────────────────

# Is the player on a threatened tile, with line of sight (walls block)?
func threatens(from: Vector2i, ppos: Vector2i, grid: Grid) -> bool:
	if not grid.has_los(from, ppos):
		return false
	for t in attack_pattern(from):
		if t == ppos:
			return true
	return false

# The 4 cardinal tiles at exactly radius r (never diagonal).
static func cardinal_ring(o: Vector2i, r: int) -> Array:
	return [o + Vector2i(0, -r), o + Vector2i(r, 0), o + Vector2i(0, r), o + Vector2i(-r, 0)]
