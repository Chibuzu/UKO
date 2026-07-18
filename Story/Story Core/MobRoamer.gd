# MobRoamer.gd
# The out-of-combat mob movement POLICY: the shared wander cadence and the
# one-step choice rule (beeline toward the player inside AGGRO, else drift,
# never a wall / the village / an occupied tile / the player's tile). Pure
# policy — StoryController applies the effects (sprite tweens, visibility,
# starting combat when a mob enters the window). Split step 3 of the
# StoryController plan (CameraRig → DayNightClock → this).
class_name MobRoamer
extends RefCounted

const ROAM_CD := 0.55   # seconds between world-wander steps (slower than you: you can outrun them)
const AGGRO := 3        # mobs beeline toward you inside this range; engagement uses it too

var _cd := 0.0          # countdown to the next shared wander step

# Tick the cadence; true exactly when the next wander step is due.
func due(delta: float) -> bool:
	_cd -= delta
	if _cd > 0.0:
		return false
	_cd = ROAM_CD
	return true

# One wander step for a mob at `pos`: chase the player if close, else a random
# open step (sometimes idling, for a calmer drift). Returns `pos` to stand still.
static func wander_step(pos: Vector2i, player_pos: Vector2i, grid, occ: Dictionary) -> Vector2i:
	var dirs: Array = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	if int(round(Vector2(pos - player_pos).length())) <= AGGRO:
		dirs.sort_custom(func(a, b): return Grid.dist(pos + a, player_pos) < Grid.dist(pos + b, player_pos))
	else:
		dirs.shuffle()
		if randf() < 0.4:
			return pos                               # idle sometimes -> a calmer, natural drift
	for d: Vector2i in dirs:
		var t: Vector2i = pos + d
		if grid.is_blocked(t) or OverworldMap.in_village(t) or occ.has(t) or t == player_pos:
			continue
		return t
	return pos
