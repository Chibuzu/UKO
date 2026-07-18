# DayNightClock.gd
# The story's action-driven TIME POLICY: the passive-regen cadence and the
# day/night cycle counters. Pure counters — it owns WHEN things happen, never
# what they do: StoryController applies the effects (energy regen, nightfall's
# wall reshuffle + spawns, the tint, NPC sleep) from the events advance()
# returns. Split step 2 of the StoryController plan (after CameraRig).
class_name DayNightClock
extends RefCounted

const REGEN_EVERY := 6      # your actions per passive-regen tick (roam steps + combat actions)
const REGEN_EP := 10        # energy restored per tick (HP/MP recover only by resting)
const DAY_ACTIONS := 45     # daylight length, in actions
const NIGHT_ACTIONS := 25   # night length, in actions

var actions := 0            # actions since the last regen tick
var day_clock := 0          # actions elapsed in the current day/night cycle
var is_night := false
var day_count := 1

# Advance time by n of the player's actions. Returns the events that fired, in
# order: zero or more "regen" ticks, then at most one "nightfall" or "dawn"
# (same one-transition-per-advance rule as the old inline clock).
func advance(n: int) -> Array:
	if n <= 0:
		return []
	var out: Array = []
	actions += n
	while actions >= REGEN_EVERY:
		actions -= REGEN_EVERY
		out.append("regen")
	day_clock += n
	if not is_night and day_clock >= DAY_ACTIONS:
		is_night = true
		out.append("nightfall")
	elif is_night and day_clock >= DAY_ACTIONS + NIGHT_ACTIONS:
		is_night = false
		day_clock = 0
		day_count += 1
		out.append("dawn")
	return out

# Snapshot for the save file / restore from one. The WORLD side of a night
# (moved walls, night spawns) still comes from the seed at load; this keeps the
# TIME side — tint, NPC sleep, the cycle position — from resetting to day 1.
func to_save() -> Dictionary:
	return {"actions": actions, "day_clock": day_clock, "is_night": is_night, "day_count": day_count}

func from_save(d: Dictionary) -> void:
	actions = int(d.get("actions", 0))
	day_clock = int(d.get("day_clock", 0))
	is_night = bool(d.get("is_night", false))
	day_count = int(d.get("day_count", 1))
