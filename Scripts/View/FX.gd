# Fx.gd
# A dedicated effects layer (child of the board, so it shares board-local
# coordinates). Pure eye-candy: particle bursts, glowing beams, expanding
# rings. Contains no rules — the EventPlayer calls these to juice up events.
class_name Fx
extends Node2D

# Radial spark burst at a point.
func burst(local_pos: Vector2, color: Color, count: int = ViewConfig.BURST_COUNT) -> void:
	var p := CPUParticles2D.new()
	add_child(p)
	p.position = local_pos
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = count
	p.lifetime = 0.5
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 150.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = color
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.3).timeout.connect(p.queue_free)

# Glowing beam between two points (wide translucent glow + bright core).
func beam(from_local: Vector2, to_local: Vector2, color: Color) -> void:
	var glow := Line2D.new()
	add_child(glow)
	glow.add_point(from_local)
	glow.add_point(to_local)
	glow.width = 16.0
	glow.default_color = Color(color.r, color.g, color.b, 0.35)

	var core := Line2D.new()
	add_child(core)
	core.add_point(from_local)
	core.add_point(to_local)
	core.width = 5.0
	core.default_color = color

	for ln in [glow, core]:
		var t := create_tween()
		t.tween_property(ln, "modulate:a", 0.0, ViewConfig.BEAM_DUR)
		t.finished.connect(ln.queue_free)

# Continuous projectile flight: ONE sprite that travels the whole path
# (caster -> each tile -> impact) in real time, staying visible for the entire
# flight. `seg_durs[k]` is the real time for leg k (tick-derived upstream, so
# the bolt's speed matches the sim). Uses bolt_proj.png if the artist made one,
# otherwise a generated glow dot — so the bolt is ALWAYS visible either way.
func projectile_flight(points: Array, seg_durs: Array, color: Color = ViewConfig.COL_FX_BOLT, delay: float = 0.0) -> void:
	if points.size() < 2:
		return
	var node := _projectile_node(color)
	add_child(node)
	node.position = points[0]
	node.rotation = (points[1] - points[0]).angle()   # bolt art points right; aim it down the path
	var t := create_tween()
	if delay > 0.0:
		t.tween_interval(delay)   # sit at the muzzle while the cast group holds, then launch in sync
	for k in range(1, points.size()):
		var d: float = float(seg_durs[k - 1]) if (k - 1) < seg_durs.size() else 0.12
		t.tween_property(node, "position", points[k], maxf(0.01, d))
	t.finished.connect(node.queue_free)

# The traveling bolt's visual: the looping dark_bolt flight frames if present,
# otherwise bolt_proj.png, otherwise a generated glow dot — always visible.
func _projectile_node(color: Color) -> Node2D:
	var sf := _bolt_sf()
	if sf != null:
		var a := AnimatedSprite2D.new()
		a.sprite_frames = sf
		a.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		a.centered = true
		a.play("bolt")
		return a
	var s := Sprite2D.new()
	s.texture = _bolt_texture(color)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return s

# Looping flight animation from the dark_bolt frames. Frames 3-7 are the bolt
# mid-flight; 1/8 are charge marks and 2/9 the caster, so only the travelling
# frames are used. Built once and cached. null if the art isn't present.
var _bolt_frames: SpriteFrames = null
var _bolt_checked := false
func _bolt_sf() -> SpriteFrames:
	if _bolt_checked:
		return _bolt_frames
	_bolt_checked = true
	var sf := SpriteFrames.new()
	sf.add_animation("bolt")
	sf.set_animation_speed("bolt", 9.0)   # per the FPS table (Dark Bolt = 9)
	sf.set_animation_loop("bolt", true)
	var any := false
	for i in range(3, 8):
		var path := "res://assets/sprites/dark_bolt_%d.png" % i
		if ResourceLoader.exists(path):
			sf.add_frame("bolt", load(path)); any = true
	_bolt_frames = sf if any else null
	return _bolt_frames

# bolt_proj.png if present, else a small soft glow dot built once and cached, so
# a projectile is never invisible just because the art has not been added yet.
static var _dot_tex: Texture2D = null
func _bolt_texture(color: Color) -> Texture2D:
	var path := "res://assets/sprites/bolt_proj.png"
	if ResourceLoader.exists(path):
		return load(path)
	if _dot_tex == null:
		var r := 5
		var sz := r * 2 + 2
		var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
		var c := Vector2(sz, sz) * 0.5
		for y in sz:
			for x in sz:
				var aa := clampf(float(r) - Vector2(x + 0.5, y + 0.5).distance_to(c) + 0.5, 0.0, 1.0)
				img.set_pixel(x, y, Color(color.r, color.g, color.b, aa))   # opaque core, soft edge
		_dot_tex = ImageTexture.create_from_image(img)
	return _dot_tex

# Hand-drawn 3x3 AoE animation, centered on the caster's tile. Each source
# frame is the 3x3 footprint, so it overlays the eight neighbours + centre at
# 1:1. Returns false if the art isn't present (caller can fall back).
var _aoe_frames: SpriteFrames = null
var _aoe_checked := false

func _aoe_sf() -> SpriteFrames:
	if _aoe_checked:
		return _aoe_frames
	_aoe_checked = true
	var sf := SpriteFrames.new()
	sf.add_animation("aoe")
	sf.set_animation_speed("aoe", 9.0)   # per the FPS table (Dark Bolt, Guard, AoE = 9)
	sf.set_animation_loop("aoe", false)
	var any := false
	# Source frame 1 is the caster's pose, not the burst — the real caster is
	# already drawn by its own UnitView, so the Fx burst starts at frame 2.
	for i in range(2, 13):
		var path := "res://assets/sprites/aoe_%d.png" % i
		if ResourceLoader.exists(path):
			sf.add_frame("aoe", load(path)); any = true
	_aoe_frames = sf if any else null
	return _aoe_frames

func aoe_anim(center_local: Vector2) -> bool:
	var sf := _aoe_sf()
	if sf == null:
		return false
	var s := AnimatedSprite2D.new()
	add_child(s)
	s.sprite_frames = sf
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.centered = true
	s.position = center_local
	s.play("aoe")
	s.animation_finished.connect(s.queue_free)
	return true

# Expanding ring centered on a point (for AoE).
func ring(center_local: Vector2, color: Color) -> void:
	var line := Line2D.new()
	add_child(line)
	line.position = center_local
	line.width = 4.0
	line.default_color = color
	var r := ViewConfig.TILE * 0.5
	var seg := 24
	for i in range(seg + 1):
		var ang := TAU * float(i) / float(seg)
		line.add_point(Vector2(cos(ang), sin(ang)) * r)
	line.scale = Vector2(0.4, 0.4)
	var t := create_tween().set_parallel(true)
	t.tween_property(line, "scale", Vector2(2.6, 2.6), ViewConfig.RING_DUR).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(line, "modulate:a", 0.0, ViewConfig.RING_DUR)
	t.finished.connect(line.queue_free)
