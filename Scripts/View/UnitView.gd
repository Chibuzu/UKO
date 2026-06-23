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
const SPRITE_OFFSET_Y := -6.0   # nudge the sprite so the feet sit on the tile (tune in-engine)

# Animation table: name -> {prefix, count, fps, loop}. Frames are
# "<prefix>_1.png".."<prefix>_<count>.png" (missing numbers are skipped),
# or a single "<prefix>.png" when count == 0. Adding an animation is one row
# here + dropping the PNGs in; trigger it with play_anim("name").
const ANIMS := {
	"idle":     {"prefix": "idle",      "count": 4, "fps": 3.0,  "loop": true},
	"move":     {"prefix": "move",      "count": 6, "fps": 6.0,  "loop": false},
	"rest":     {"prefix": "rest",      "count": 5, "fps": 3.0,  "loop": false},
	"buff":     {"prefix": "buff",      "count": 9, "fps": 14.0, "loop": false},
	"attack":   {"prefix": "melee",     "count": 9, "fps": 18.0, "loop": false},
	"bolt":     {"prefix": "dark_bolt", "count": 9, "fps": 16.0, "loop": false},
	"hurt":     {"prefix": "hurt",      "count": 9, "fps": 16.0, "loop": false},
	"guard":    {"prefix": "guard",     "count": 9, "fps": 14.0, "loop": false},
	"pivot":    {"prefix": "pivot",     "count": 7, "fps": 18.0, "loop": false},
}

var unit_id: String = ""
var facing: int = 0
var face_angle: float = 0.0           # visual facing, tweened on pivot (radians)
var display_hp: int = Config.MAX_HP
var shown_hp: float = Config.MAX_HP
var base_color: Color = Color.WHITE
var body: AnimatedSprite2D = null     # null = no art found, draw the disc instead
var overlay: AnimatedSprite2D = null  # one-shot effects drawn ON TOP (e.g. pivot)

func init_state(c: Combatant) -> void:
	unit_id = c.id
	base_color = ViewConfig.COL_A if c.id == "A" else ViewConfig.COL_B
	if body == null and ResourceLoader.exists(SPRITE_DIR + "idle_1.png"):
		body = AnimatedSprite2D.new()
		body.sprite_frames = _build_frames()
		body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp pixels
		body.centered = true
		body.offset = Vector2(0, SPRITE_OFFSET_Y)
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
	set_state(c)

# Snap instantly to a combatant's state (start, and re-sync at turn end).
func set_state(c: Combatant) -> void:
	facing = c.facing
	face_angle = _facing_angle(c.facing)
	display_hp = c.hp
	shown_hp = c.hp
	position = ViewConfig.tile_center(c.pos)
	scale = Vector2.ONE
	_apply_facing()
	if body:
		body.rotation = 0.0
	queue_redraw()

func tween_to(pos: Vector2i) -> void:
	var target := ViewConfig.tile_center(pos)
	var delta := target - position
	if body and delta.length() > 0.5:
		play_anim("move")
		body.flip_h = false
		# move art points UP; rotate the whole sprite to face the travel direction.
		body.rotation = delta.angle() + PI / 2.0
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
func play_anim(name: String) -> void:
	if body and body.sprite_frames.has_animation(name) \
			and body.sprite_frames.get_frame_count(name) > 0:
		body.play(name)

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
	if body:
		body.rotation = 0.0          # clear any move-direction rotation
		_apply_facing()              # restore idle facing (flip for west)
		body.play("idle")            # one-shot anims return to idle

func _build_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	for name in ANIMS:
		var a: Dictionary = ANIMS[name]
		var files: Array = []
		if int(a["count"]) <= 0:
			files.append("%s.png" % a["prefix"])
		else:
			for i in range(1, int(a["count"]) + 1):
				files.append("%s_%d.png" % [a["prefix"], i])
		_add_anim(sf, name, files, float(a["fps"]), bool(a["loop"]))
	return sf

func _add_anim(sf: SpriteFrames, anim: String, files: Array, fps: float, loop: bool) -> void:
	sf.add_animation(anim)
	sf.set_animation_speed(anim, fps)
	sf.set_animation_loop(anim, loop)
	for f in files:
		var path: String = SPRITE_DIR + f
		if ResourceLoader.exists(path):
			sf.add_frame(anim, load(path))

# ── Draw HP bar + facing marker (+ fallback disc if no sprite) ──────────
func _draw() -> void:
	var r := ViewConfig.TILE * 0.34
	if body == null:
		draw_circle(Vector2.ZERO, r, base_color)   # fallback when art is missing

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
