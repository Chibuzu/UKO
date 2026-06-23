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

# Hand-drawn bolt projectile: flies from the caster to the impact tile, rotated
# to its travel direction (the art is drawn pointing right). False if no art.
func bolt_projectile(from_local: Vector2, to_local: Vector2, travel_dur: float = -1.0) -> bool:
	var path := "res://assets/sprites/bolt_proj.png"
	if not ResourceLoader.exists(path):
		return false
	var s := Sprite2D.new()
	add_child(s)
	s.texture = load(path)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = from_local
	s.rotation = (to_local - from_local).angle()
	# Caller may pass a tick-derived duration so the bolt speed matches the sim;
	# otherwise fall back to a fixed pixel speed.
	var dur: float = travel_dur if travel_dur >= 0.0 else clampf((to_local - from_local).length() / 600.0, 0.08, 0.4)
	var t := create_tween()
	t.tween_property(s, "position", to_local, dur)
	t.finished.connect(s.queue_free)
	return true

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
