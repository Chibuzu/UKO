# UnitView.gd
# Draws and animates ONE duelist. The body is an AnimatedSprite2D playing the
# player sprite frames (standing / buff / rest); the HP bar and facing marker
# are drawn on top. If the sprite art isn't in the project yet, it falls back
# to a plain colored disc so the game still runs.
#
# Holds only display state — never game rules. The EventPlayer drives it.
class_name UnitView
extends Node2D

const SPRITE_DIR := "res://assets/sprites/"
const PIVOT_DUR := 0.18    # how long the facing bar takes to swing to a new side
const SPRITE_OFFSET_Y := -6.0   # nudge the FIGURE up so its feet seat on the tile (tune in-engine)
# These animations are tile-CENTRED effects (the guard cube, the buff aura), not
# feet-seated figures, so they skip the figure's vertical nudge and sit on the tile.
const CENTERED_ANIMS := ["guard", "guard_up", "buff"]

# Animation table: name -> {prefix, count, fps, loop}. Frames are
# "<prefix>_1.png".."<prefix>_<count>.png" (missing numbers are skipped),
# or a single "<prefix>.png" when count == 0. A row may instead carry an
# explicit "frames" list to use a subset / re-ordering of one prefix's PNGs
# (e.g. the teleport strip split into a vanish half and a reappear half).
# Adding an animation is one row here + dropping the PNGs in; trigger it
# with play_anim("name").
const ANIMS := {
	"idle":     {"prefix": "idle",      "count": 4,  "fps": 3.0, "loop": true},
	"move":     {"prefix": "move",      "count": 6,  "fps": 6.0, "loop": false},
	"rest":     {"prefix": "rest",      "count": 5,  "fps": 3.0, "loop": false},
	"buff":     {"prefix": "buff",      "count": 5,  "fps": 3.0, "loop": false},
	"attack":   {"prefix": "melee",     "count": 8,  "fps": 6.0, "loop": false},
	"bolt":     {"prefix": "dark_bolt", "count": 9,  "fps": 9.0, "loop": false},
	"hurt":     {"prefix": "hurt",      "count": 9,  "fps": 16.0, "loop": false},  # not in the FPS table — left as-is
	"guard":    {"prefix": "guard",     "count": 11, "fps": 9.0, "loop": false},
	# Guard raise that ENDS on the shield cube (frames 1-9) and is held there for
	# the whole duration the guard is up (see hold_anim / EventPlayer guard_raised);
	# frames 10-11 (the lower) play on release via the normal idle return.
	"guard_up": {"prefix": "guard", "frames": [1, 2, 3, 4, 5, 6, 7, 8, 9], "fps": 9.0, "loop": false},
	"pivot":    {"prefix": "pivot",     "count": 7,  "fps": 18.0, "loop": false},  # not in the FPS table — left as-is
	# Teleport is ONE 9-frame strip: figure -> portal -> nothing -> portal ->
	# figure. Split so the vanish plays at the origin (blink_depart) and the
	# reappear plays at the destination (blink). Frame 5 (fully gone) is shared.
	"teleport_out": {"prefix": "teleport", "frames": [1, 2, 3, 4, 5], "fps": 6.0, "loop": false},
	"teleport_in":  {"prefix": "teleport", "frames": [5, 6, 7, 8, 9], "fps": 6.0, "loop": false},
}

var unit_id: String = ""
var facing: int = 0
var face_angle: float = 0.0           # visual facing, tweened on pivot (radians)
var display_hp: int = Config.MAX_HP
var shown_hp: float = Config.MAX_HP
var base_color: Color = Color.WHITE
var disc_only: bool = false            # mobs: skip the fighter sprite, render as a plain colored ball
var disc_color: Color = Color.WHITE    # the ball's color when disc_only
var art_key: String = ""               # non-empty -> build an animated body from SpriteBook.SETS[art_key] (a mob)
# directional_art: player art points UP and is rotated onto the move/attack vector; mob art is
# drawn facing its own way, so it plays upright and is only flipped left/right.
var directional_art: bool = true
var prop: bool = false                 # NPCs: a labeled disc with no facing/HP bars (not a combatant)
var body: AnimatedSprite2D = null     # null = no art found, draw the disc instead
var _body_offset_y: float = SPRITE_OFFSET_Y   # this body's seated offset (player -6; mobs from their set)
var overlay: AnimatedSprite2D = null  # one-shot effects drawn ON TOP (e.g. pivot)
var _held: String = ""                # an animation frozen on its last frame until released (the raised guard)
var _gear_layers: Array = []          # AnimatedSprite2D overlays for equipped gear (idle-only for now)
# Draw equipped gear ON the fighter sprite. OFF for now — the current overlay art
# reads as messy in-engine; flip back to true once clean per-piece art is in.
# (Gear still drives spells and the shop regardless of this flag.)
const SHOW_GEAR_OVERLAYS := false

func init_state(c: Combatant) -> void:
	unit_id = c.id
	base_color = disc_color if disc_only else (ViewConfig.COL_A if c.id == "A" else ViewConfig.COL_B)
	if body == null:
		if art_key != "" and SpriteBook.has(art_key):
			_build_mob_body(SpriteBook.set_of(art_key))          # animated monster from its sprite set
		elif not disc_only and ResourceLoader.exists(SPRITE_DIR + "idle_1.png"):
			_build_player_body()                                 # the duelist sprite (+ effect overlay)
	if SHOW_GEAR_OVERLAYS:
		_build_gear_layers(c)
	set_state(c)

# The player's fighter sprite plus the shared effect overlay (pivot etc.). Unchanged behavior;
# extracted so mobs can build their own body without this player-only overlay wiring.
func _build_player_body() -> void:
	body = AnimatedSprite2D.new()
	body.sprite_frames = _build_frames()
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixels
	body.centered = true
	_body_offset_y = SPRITE_OFFSET_Y
	body.offset = Vector2(0, _body_offset_y)
	body.show_behind_parent = true                           # behind HP bar, but ON TOP of board tiles
	# No modulate tint: the sprite keeps its true colors, since block color
	# will carry spell meaning later. Sides are told apart by the A/B label.
	add_child(body)
	body.animation_finished.connect(_on_anim_finished)
	body.play("idle")
	# Overlay: shares the body's frames, sits on top, hidden until used.
	overlay = AnimatedSprite2D.new()
	overlay.sprite_frames = body.sprite_frames
	overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	overlay.centered = true
	overlay.z_index = 1
	overlay.visible = false
	add_child(overlay)
	overlay.animation_finished.connect(_on_overlay_finished)

# A story monster's animated body, built from its SpriteBook set. No effect overlay (mobs don't
# pivot/cast); art plays upright (directional_art from the set). Falls back to a disc if the set
# has no loadable frames.
func _build_mob_body(art_set: Dictionary) -> void:
	directional_art = bool(art_set.get("directional", false))
	_body_offset_y = float(art_set.get("offset_y", 0.0))
	var frames := _build_frames_set(art_set)
	var loaded := 0
	for a in frames.get_animation_names():
		loaded += frames.get_frame_count(a)
	if loaded == 0:
		return                                               # no frames loaded -> leave body null (disc)
	body = AnimatedSprite2D.new()
	body.sprite_frames = frames
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.centered = true
	body.offset = Vector2(0, _body_offset_y)
	body.show_behind_parent = true
	add_child(body)
	body.animation_finished.connect(_on_anim_finished)
	if body.sprite_frames.has_animation("idle"):
		body.play("idle")

# Equipped-gear overlays. Each equipped slot adds a sprite layer that plays its
# idle-overlay frames on top of the white body; an empty slot shows nothing, so
# an ungeared fighter is plain white. Idle-only for now: the layers show while
# the body idles and hide during other animations (synced in _process).
func _build_gear_layers(c: Combatant) -> void:
	for lyr in _gear_layers:
		lyr.queue_free()
	_gear_layers.clear()
	if body == null:
		return
	for gid in c.gear:
		var prefix := GearBook.overlay_of(String(gid))
		if prefix == "":
			continue
		var frames := _overlay_frames(prefix)
		if frames == null:
			continue
		var lyr := AnimatedSprite2D.new()
		lyr.sprite_frames = frames
		lyr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lyr.centered = true
		lyr.offset = Vector2(0, SPRITE_OFFSET_Y)   # seat with the body
		lyr.show_behind_parent = true              # above body, below the HP bar
		add_child(lyr)
		lyr.play("idle")
		_gear_layers.append(lyr)

# Build a 4-frame idle SpriteFrames from "<prefix>_1..4.png", or null if absent.
func _overlay_frames(prefix: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 3.0)   # match the body idle fps so they stay in lockstep
	sf.set_animation_loop("idle", true)
	var any := false
	for i in range(1, 5):
		var path := SPRITE_DIR + "%s_%d.png" % [prefix, i]
		if ResourceLoader.exists(path):
			sf.add_frame("idle", load(path)); any = true
	return sf if any else null

# Keep the gear overlays locked to the body's idle frame; hide them during any
# other animation (no per-action overlays yet) so the figure shows white there.
func _process(_dt: float) -> void:
	if body == null or _gear_layers.is_empty():
		return
	var show_gear := (body.animation == "idle")
	for lyr in _gear_layers:
		lyr.visible = show_gear
		if show_gear:
			lyr.frame = body.frame
			lyr.flip_h = body.flip_h

# Snap instantly to a combatant's state (start, and re-sync at turn end).
func set_state(c: Combatant) -> void:
	facing = c.facing
	face_angle = _facing_angle(c.facing)
	display_hp = c.hp
	shown_hp = c.hp
	position = ViewConfig.tile_center(c.pos)
	scale = Vector2.ONE
	_apply_facing()
	_held = ""                       # turn ended: drop any held guard cube
	if body:
		body.rotation = 0.0
		body.offset.y = _body_offset_y
		body.play("idle")
	queue_redraw()

func tween_to(pos: Vector2i) -> void:
	var target := ViewConfig.tile_center(pos)
	var delta := target - position
	if body and delta.length() > 0.5:
		# move art points UP; play_anim rotates the walk to the travel direction.
		play_anim("move", delta)
	var t := create_tween()
	t.tween_property(self, "position", target, ViewConfig.MOVE_DUR) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func set_facing(f: int) -> void:
	facing = f
	_apply_facing()
	# Sweep the white facing line from where it is to the new side, the short
	# way round — so the rotation follows whatever turn the player actually made
	# (E->S goes one way, E->N the other), for any facing change.
	var target := _facing_angle(f)
	while target - face_angle > PI: target -= TAU
	while target - face_angle < -PI: target += TAU
	var t := create_tween()
	t.tween_method(_set_face_angle, face_angle, target, PIVOT_DUR) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _facing_angle(f: int) -> float:
	var v := Vector2(Config.FACING_VEC[f])
	return atan2(v.y, v.x)

func _set_face_angle(a: float) -> void:
	face_angle = a
	queue_redraw()

func _apply_facing() -> void:
	if body:
		body.flip_h = (facing == 3)   # face WEST = mirror the front sprite

func set_display_hp(hp: int) -> void:
	display_hp = maxi(0, hp)
	var t := create_tween()
	t.tween_method(_set_shown_hp, shown_hp, float(display_hp), ViewConfig.HP_DRAIN_DUR)

func _set_shown_hp(v: float) -> void:
	shown_hp = v
	queue_redraw()

func flash(color: Color) -> void:
	modulate = color
	var t := create_tween()
	t.tween_property(self, "modulate", Color.WHITE, ViewConfig.FLASH_DUR)

func pop() -> void:
	scale = Vector2(1.25, 0.8)
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ── Frame-animation playback ────────────────────────────────────────────
func play_anim(name: String, dir: Vector2 = Vector2.ZERO, rot_offset: float = PI / 2.0) -> void:
	if body and body.sprite_frames.has_animation(name) \
			and body.sprite_frames.get_frame_count(name) > 0:
		# Centred effects (guard cube, buff aura) sit ON the tile; figures get the
		# feet-seating nudge. Set every play so we never inherit the wrong offset.
		body.offset.y = 0.0 if name in CENTERED_ANIMS else _body_offset_y
		if directional_art and dir != Vector2.ZERO:
			# Directional one-shot. `rot_offset` accounts for where the art's
			# reference points by default: the move/attack figure points UP
			# (+PI/2 turns UP onto `dir`); the guard shield's closed side points
			# RIGHT, so it passes its facing with a 0 offset (see EventPlayer).
			body.flip_h = false
			body.rotation = dir.angle() + rot_offset
		else:
			body.rotation = 0.0    # mob art (and non-directional plays) stay upright; facing via flip_h
		body.play(name)

# Play an animation and FREEZE on its last frame (no return to idle) until
# clear_hold/set_state releases it — used to keep the raised guard cube up for
# the whole duration the guard is valid.
func hold_anim(name: String, dir: Vector2 = Vector2.ZERO, rot_offset: float = PI / 2.0) -> void:
	play_anim(name, dir, rot_offset)
	_held = name

# Release a held animation; the next finished/idle cycle returns to idle.
func clear_hold() -> void:
	_held = ""

# Real-time length of a one-shot animation (frames / fps), or 0 when the art
# is missing. Lets the EventPlayer hold a tick group exactly as long as the
# animation needs, instead of a fixed guess.
func anim_duration(name: String) -> float:
	if body and body.sprite_frames.has_animation(name):
		var fps := body.sprite_frames.get_animation_speed(name)
		if fps > 0.0:
			return float(body.sprite_frames.get_frame_count(name)) / fps
	return 0.0

func play_overlay(name: String) -> void:
	if overlay and overlay.sprite_frames.has_animation(name) \
			and overlay.sprite_frames.get_frame_count(name) > 0:
		overlay.visible = true
		overlay.play(name)

func _on_overlay_finished() -> void:
	if overlay:
		overlay.visible = false

# Back-compat wrappers (EventPlayer can call either).
func play_buff() -> void: play_anim("buff")
func play_rest() -> void: play_anim("rest")

func _on_anim_finished() -> void:
	if body == null:
		return
	if _held != "" and body.animation == _held:
		return                       # freeze on the last frame (held guard cube) until released
	body.rotation = 0.0          # clear any move-direction rotation
	body.offset.y = _body_offset_y   # back to a seated figure
	_apply_facing()              # restore idle facing (flip for west)
	body.play("idle")            # one-shot anims return to idle

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	for name in ANIMS:
		var a: Dictionary = ANIMS[name]
		var files: Array = []
		if a.has("frames"):                    # explicit subset / re-order of one prefix
			for n in a["frames"]:
				files.append("%s_%d.png" % [a["prefix"], int(n)])
		elif int(a["count"]) <= 0:
			files.append("%s.png" % a["prefix"])
		else:
			for i in range(1, int(a["count"]) + 1):
				files.append("%s_%d.png" % [a["prefix"], i])
		_add_anim(sf, SPRITE_DIR, name, files, float(a["fps"]), bool(a["loop"]))
	return sf

# Build frames from a SpriteBook set: each animation carries an explicit file list, fps, loop.
func _build_frames_set(art_set: Dictionary) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var dir: String = String(art_set.get("dir", ""))
	var anims: Dictionary = art_set.get("anims", {})
	for name in anims:
		var a: Dictionary = anims[name]
		var files: Array = []
		for fn in a.get("files", []):
			files.append(String(fn))
		_add_anim(sf, dir, name, files, float(a.get("fps", 5.0)), bool(a.get("loop", false)))
	return sf

func _add_anim(sf: SpriteFrames, dir: String, anim: String, files: Array, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for f in files:
		var path: String = dir + f
		if ResourceLoader.exists(path):
			sf.add_frame(anim, load(path))

# ── Draw HP bar + facing marker (+ fallback disc if no sprite) ──────────
func _draw() -> void:
	var r := ViewConfig.TILE * 0.34
	if body == null:
		draw_circle(Vector2.ZERO, r, base_color)   # fallback when art is missing

	if prop:                                       # NPC marker: just the disc + name, no combat bars
		draw_string(ThemeDB.fallback_font, Vector2(-6, ViewConfig.TILE * 0.5 + 14), unit_id,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		return

	# Facing bar: sits on the tile edge in the facing direction (E=right,
	# N=top, W=left, S=bottom) and swings around when the unit pivots.
	var fd := Vector2(cos(face_angle), sin(face_angle))
	var edge := ViewConfig.TILE * 0.45
	var blen := ViewConfig.TILE * 0.72        # spans most of the unit, like the video
	var mid := fd * edge
	var perp := Vector2(-fd.y, fd.x) * (blen * 0.5)
	draw_line(mid - perp, mid + perp, Color.WHITE, 3.0)

	# HP bar above the figure.
	var w := ViewConfig.TILE * 0.7
	var h := 5.0
	var x := -w / 2.0
	var y := -ViewConfig.TILE * 0.5 - 2.0
	draw_rect(Rect2(x, y, w, h), ViewConfig.COL_HP_BG)
	var frac := clampf(shown_hp / float(Config.MAX_HP), 0.0, 1.0)
	draw_rect(Rect2(x, y, w * frac, h), ViewConfig.COL_HP_FILL)

	draw_string(ThemeDB.fallback_font, Vector2(-6, ViewConfig.TILE * 0.5 + 14), unit_id,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
