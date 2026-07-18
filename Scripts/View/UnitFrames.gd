# UnitFrames.gd
# THE frame-building toolkit + the PLAYER's animation table, extracted from
# UnitView so asset knowledge has one home beside SpriteBook (which owns the
# mob sets). UnitView renders; this file knows folders, filenames, fps, and
# seating offsets. After any asset folder reorg: fix the dirs/rows HERE (and
# SpriteBook for mobs) — no view code changes.
#
# PLAYER_ANIMS rows: name -> {dir, prefix, count, fps, loop, offset?, points?,
# frames?}. Frames are "<dir><prefix>_1.png".."_<count>.png" (missing numbers
# skipped), or a single "<prefix>.png" when count == 0, or an explicit "frames"
# subset/re-order. "points" = which way the art was DRAWN (UnitView rotates it
# onto the action). "offset" = the vertical nudge that seats THAT animation in
# the tile (mixed canvas sizes); rows without one keep the body's default seat.
class_name UnitFrames
extends RefCounted

const BASE_DIR   := "res://Assets/Sprites/Unarmed Base Animations/"
const TECH_DIR   := ViewConfig.DIR_TECH_SPELLS   # shared root: FX reads the same line
const GEAR_DIR   := "res://Assets/Sprites/Tech Animations/Tech Gear/"   # per-piece gear overlays (hat_1..4 etc.)
const NPC_ART_DIR := "res://Assets/Sprites/Village Characters/"

const PLAYER_ANIMS := {
	"idle":     {"dir": BASE_DIR,   "prefix": "Idle",      "count": 4,  "fps": 3.0, "loop": true,  "offset": 0.0},
	"move":     {"dir": BASE_DIR,   "prefix": "Move",      "count": 5,  "fps": 6.0, "loop": false, "points": "down"},
	"rest":     {"dir": BASE_DIR,   "prefix": "Rest",      "count": 5,  "fps": 3.0, "loop": false, "offset": 0.0},
	"buff":     {"dir": TECH_DIR,   "prefix": "buff",      "count": 5,  "fps": 3.0, "loop": false, "offset": -14.0},
	"attack":   {"dir": BASE_DIR,   "prefix": "Melee",     "count": 5,  "fps": 6.0, "loop": false, "points": "up", "offset": 0.0},
	"bolt":     {"dir": TECH_DIR,   "prefix": "dark_bolt", "count": 9,  "fps": 9.0, "loop": false},
	"guard":    {"dir": BASE_DIR, "prefix": "guard",     "count": 11, "fps": 9.0, "loop": false, "points": "right", "offset": 0.0},
	# Guard raise that ENDS on the shield cube (frames 1-9) and is held there for
	# the whole duration the guard is up (see hold_anim / EventPlayer guard_raised);
	# frames 10-11 (the lower) play on release via the normal idle return.
	"guard_up": {"dir": BASE_DIR, "prefix": "guard", "frames": [1, 2, 3, 4, 5, 6, 7, 8, 9], "fps": 9.0, "loop": false, "points": "right", "offset": 0.0},
	# Teleport is ONE 9-frame strip: figure -> portal -> nothing -> portal ->
	# figure. Split so the vanish plays at the origin (blink_depart) and the
	# reappear plays at the destination (blink). Frame 5 (fully gone) is shared.
	"teleport_out": {"dir": TECH_DIR, "prefix": "teleport", "frames": [1, 2, 3, 4, 5], "fps": 6.0, "loop": false},
	"teleport_in":  {"dir": TECH_DIR, "prefix": "teleport", "frames": [5, 6, 7, 8, 9], "fps": 6.0, "loop": false},
}

# The player's full SpriteFrames. Fills `offsets_out` (anim -> seat offset) as a
# side table the view reads on every play (per-row "offset" is the ONE seat source).
static func build_player(offsets_out: Dictionary, default_seat: float) -> SpriteFrames:
	var sf := SpriteFrames.new()
	for name in PLAYER_ANIMS:
		var a: Dictionary = PLAYER_ANIMS[name]
		var files: Array = []
		if a.has("frames"):                    # explicit subset / re-order of one prefix
			for n in a["frames"]:
				files.append("%s_%d.png" % [a["prefix"], int(n)])
		elif int(a["count"]) <= 0:
			files.append("%s.png" % a["prefix"])
		else:
			for i in range(1, int(a["count"]) + 1):
				files.append("%s_%d.png" % [a["prefix"], i])
		add_anim(sf, String(a.get("dir", BASE_DIR)), name, files, float(a["fps"]), bool(a["loop"]))
		offsets_out[name] = float(a.get("offset", default_seat))
	return sf

# Frames from a SpriteBook set: each animation carries an explicit file list, fps, loop.
static func build_set(art_set: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var dir: String = String(art_set.get("dir", ""))
	var anims: Dictionary = art_set.get("anims", {})
	for name in anims:
		var a: Dictionary = anims[name]
		var files: Array = []
		for fn in a.get("files", []):
			files.append(String(fn))
		add_anim(sf, dir, name, files, float(a.get("fps", 5.0)), bool(a.get("loop", false)))
	return sf

# A villager's idle: 1 frame = still portrait, 2 frames = gentle sway.
static func build_npc(art_files: Array) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var files: Array = []
	for f in art_files:
		files.append(String(f))
	add_anim(sf, NPC_ART_DIR, "idle", files, 1.6, true)
	return sf

# A 4-frame gear-overlay idle from "<prefix>_1..4.png", or null if absent.
static func overlay(prefix: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 3.0)   # match the body idle fps so they stay in lockstep
	sf.set_animation_loop("idle", true)
	var any := false
	for i in range(1, 5):
		var path := GEAR_DIR + "%s_%d.png" % [prefix, i]
		if ResourceLoader.exists(path):
			sf.add_frame("idle", load(path)); any = true
	return sf if any else null

# The one loader: adds `anim` to `sf` from explicit filenames (missing files skipped).
static func add_anim(sf: SpriteFrames, dir: String, anim: String, files: Array, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for f in files:
		var path: String = dir + f
		if ResourceLoader.exists(path):
			sf.add_frame(anim, load(path))
