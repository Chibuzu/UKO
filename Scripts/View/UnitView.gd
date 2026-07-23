# UnitView.gd
# Draws and animates ONE duelist. The body is an AnimatedSprite2D playing the
# player sprite frames (standing / buff / rest); the HP bar and facing marker
# are drawn on top. If the sprite art isn't in the project yet, it falls back
# to a plain colored disc so the game still runs.
#
# Holds only display state — never game rules. The EventPlayer drives it.
class_name UnitView
extends Node2D

# Art tables + frame builders live in UnitFrames (player rows) and SpriteBook
# (mob sets). This view only PLAYS what those tables declare -- after an asset
# reorg, edit the tables, never this file.
const PIVOT_DUR := 0.18    # how long the facing bar takes to swing to a new side
const SPRITE_OFFSET_Y := 0.0    # 32px art on a 32px tile sits FLUSH; no nudge (was -6: everyone floated)

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
var prop: bool = false                 # NPCs: no facing/HP bars (not a combatant)
var npc_art: Array = []                # NPC idle frames (UnitFrames.NPC_ART_DIR); empty -> disc
var body: AnimatedSprite2D = null     # null = no art found, draw the disc instead
var _body_offset_y: float = SPRITE_OFFSET_Y   # this body's seated offset (player -6; mobs from their set)
var _anim_offset: Dictionary = {}     # per-animation vertical seat (player anims); mobs fall back to _body_offset_y
var overlay: AnimatedSprite2D = null  # one-shot effects drawn ON TOP (e.g. pivot)
var _held: String = ""                # an animation frozen on its last frame until released (the raised guard)
var _gear_layers: Array = []          # AnimatedSprite2D overlays for equipped gear (idle-only for now)
# Draw equipped gear ON the fighter sprite. OFF for now — the current overlay art
# reads as messy in-engine; flip back to true once clean per-piece art is in.
# (Gear still drives spells and the shop regardless of this flag.)
const SHOW_GEAR_OVERLAYS := true

func init_state(c: Combatant) -> void:
	unit_id = c.id
	base_color = disc_color if disc_only else (ViewConfig.COL_A if c.id == "A" else ViewConfig.COL_B)
	if body == null:
		if prop and npc_art.size() > 0:
			_build_npc_body()                                    # villager character art
		elif art_key != "" and SpriteBook.has(art_key):
			_build_mob_body(SpriteBook.set_of(art_key))          # animated monster from its sprite set
		elif not disc_only and ResourceLoader.exists(UnitFrames.BASE_DIR + "Idle_1.png"):
			_build_player_body()                                 # the duelist sprite (+ effect overlay)
	if SHOW_GEAR_OVERLAYS:
		_build_gear_layers(c)
	set_state(c)

# The player's fighter sprite plus the shared effect overlay (pivot etc.). Unchanged behavior;
# extracted so mobs can build their own body without this player-only overlay wiring.
func _build_player_body() -> void:
	body = AnimatedSprite2D.new()
	body.sprite_frames = UnitFrames.build_player(_anim_offset, SPRITE_OFFSET_Y)
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

# A villager's little idle body: 1 frame = still portrait, 2 frames = gentle sway.
func _build_npc_body() -> void:
	var sf := UnitFrames.build_npc(npc_art)
	if sf.get_frame_count("idle") == 0:
		return                                               # art missing -> keep the disc
	body = AnimatedSprite2D.new()
	body.sprite_frames = sf
	body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body.centered = true
	body.offset = Vector2(0, SPRITE_OFFSET_Y)                # feet on the tile, like fighters
	body.show_behind_parent = true
	add_child(body)
	body.play("idle")

# A story monster's animated body, built from its SpriteBook set. No effect overlay (mobs don't
# pivot/cast); art plays upright (directional_art from the set). Falls back to a disc if the set
# has no loadable frames.
func _build_mob_body(art_set: Dictionary) -> void:
	directional_art = bool(art_set.get("directional", false))
	_rows = art_set.get("anims", {})            # this creature's own rows (its "points" live here)
	_body_offset_y = float(art_set.get("offset_y", 0.0))
	for an in art_set.get("anims", {}):
		var ad: Dictionary = art_set["anims"][an]
		if ad.has("offset_y"):
			_anim_offset[an] = float(ad["offset_y"])   # per-anim seat (mixed canvas sizes)
	var frames := UnitFrames.build_set(art_set)
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
		var frames := UnitFrames.overlay(prefix)
		if frames == null:
			continue
		var lyr := AnimatedSprite2D.new()
		lyr.sprite_frames = frames
		lyr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		lyr.centered = true
		lyr.offset = body.offset                   # seat exactly with the body's current frame
		lyr.show_behind_parent = true              # above body, below the HP bar
		add_child(lyr)
		lyr.play("idle")
		_gear_layers.append(lyr)

# Keep the gear overlays locked to the body's idle frame; hide them during any
# other animation (no per-action overlays yet) so the figure shows white there.
func _process(_dt: float) -> void:
	# SAFETY NET: a 2-tile clip's half-tile shift must never outlive the clip itself.
	# `animation_finished` is NOT emitted when a clip is interrupted (or when it is
	# replaced mid-play), and a leftover shift is exactly what drew a twin standing
	# between two tiles. This runs every frame, so it cannot be missed: the moment no
	# clip is playing, the sprite sits on its tile.
	# The shift is legal ONLY while a reach clip is the one actually playing. Testing
	# is_playing() alone was not enough: an interrupted clip is usually replaced by the
	# LOOPING idle, which plays forever -- so the net never fired and the sprite stayed
	# stranded on the tile line. Now it clears the moment the current clip isn't a reach.
	if body != null and body.offset.x != 0.0 \
			and (not body.is_playing() or _reach_kind(body.animation) == ""):
		body.offset.x = 0.0
		_reaching = false
	if body == null or _gear_layers.is_empty():
		return
	var show_gear := (body.animation == "idle")
	for lyr in _gear_layers:
		lyr.visible = show_gear
		if show_gear:
			lyr.frame = body.frame
			lyr.flip_h = body.flip_h
			lyr.offset = body.offset       # keep seated exactly on the body as its frame offset changes
			lyr.scale = body.scale
			lyr.rotation = body.rotation

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
		body.offset.y = float(_anim_offset.get("idle", _body_offset_y))
		body.play("idle")
	queue_redraw()

# Attack with direction awareness: sets that ship per-direction attack art
# (attack_up/down/left/right -- the ooze spit) get the frame matching the strike
# vector; everyone else falls back to the plain "attack" (rotated/flipped as usual).
func play_attack(dir: Vector2) -> void:
	# Attack art that declares which way it is DRAWN ("points") simply rotates onto the
	# strike vector -- one path for every such creature, no per-direction files needed.
	if _points_of("attack") != "":
		play_anim("attack", dir)
		return
	if body and dir != Vector2.ZERO:
		var suffix := ""
		if absf(dir.x) >= absf(dir.y):
			suffix = "right" if dir.x >= 0.0 else "left"
		else:
			suffix = "down" if dir.y >= 0.0 else "up"
		var named := "attack_" + suffix
		if body.sprite_frames.has_animation(named) and body.sprite_frames.get_frame_count(named) > 0:
			play_anim(named)
			return
	play_anim("attack", dir)

# ── Two-tile creatures (the serpent). The view sits at the MIDPOINT of head+tail;
# the POSE follows the span using the art's native orientations, measured from the
# actual PNGs: Move/Melee are drawn VERTICAL with the head UP; SideMove is drawn
# HORIZONTAL with the head RIGHT. So:
#   vertical span, head above tail   -> vertical art as-is
#   vertical span, head below tail   -> vertical art flip_v
# ── TWO-TILE BODY (the serpent). Its cells come from the ENGINE (Combatant.cells), so
# the view never decides WHERE it is -- only how to draw it. The art is drawn VERTICAL
# (32x64) at its exact footprint; a HORIZONTAL body is that same art turned 90 degrees
# (_apply_span_pose). A turn is instant (Fra): no sweep, the axis simply flips, and the
# two head bars mark the tiles it strikes from.
var show_facing := true        # mobs: false -- mobs have no facing, so no bars
# COSMETIC look vector: the direction this unit's RESTING art points. The story keeps it
# aimed at the player. Art-only -- it never touches rules, legality, damage, or flank.
# ROUND 28 (Fra): a REACTIVE setter -- writing `aim` refreshes the resting pose
# and the facing bar THE SAME FRAME, so the sprite can never disagree with the
# bar (it used to lag one animation behind whenever aim changed while idle).
# One-shot anims are left alone mid-play; _on_anim_finished re-reads aim anyway.
var aim := Vector2.ZERO:
	set(v):
		aim = v
		if body != null and _span_axis == "" and not _turning and not _reaching \
				and body.animation == "idle":
			body.rotation = _mob_facing_rotation()
			body.flip_h = _mob_facing_flip()
		queue_redraw()
# The art rows for THIS unit: the player's table by default, swapped to the mob's
# SpriteBook set by _build_mob_body. Every "points" lookup MUST read this -- reading the
# player table directly would ask which way a BAT is drawn (and get nothing).
var _rows: Dictionary = UnitFrames.PLAYER_ANIMS
var _span_axis := ""    # "" = single-tile unit; "v" / "h" while spanning
var _span_heads: Array = []   # the two head tiles (Vector2i), for the dual facing bars
var _span_target := Vector2.ZERO     # where the body position settles after a step
var _turning := false                # true while a 90-degree turn owns the pose
# ── 2-TILE ACTION CLIPS ("reach" art) ────────────────────────────────────────
# Some creatures' action art is 2 tiles wide: the creature is drawn in ONE tile and its
# action reaches into the NEXT (the twins' move and bite). The art is tile-aligned, so
# placing it is exact arithmetic: shift the SPRITE half a tile along its own axis and
# rotate its drawn direction onto the real one. The NODE always stays on the creature's
# real tile -- never a midpoint -- so an interrupted clip cannot strand it between tiles,
# and the next step can never measure its delta from a half-tile spot (a diagonal).
var _reaching := false
# How long the body takes to swing 90 degrees once it has landed on its pivot cell.
const TURN_ROT_DUR := 0.28

func _axis_of(a: Vector2i, b: Vector2i) -> String:
	return "h" if a.y == b.y and a.x != b.x else "v"

func set_span(head: Vector2i, tail: Vector2i) -> void:
	position = ViewConfig.tile_center(head).lerp(ViewConfig.tile_center(tail), 0.5)
	_span_axis = _axis_of(head, tail)
	_span_heads = [head, tail]
	queue_redraw()
	_span_rest()
	_apply_span_pose()

# At rest the body loops its idle. The art is drawn vertical, and a HORIZONTAL body is
# that same idle turned 90 degrees by _apply_span_pose -- so no axis lacks art.
func _span_rest() -> void:
	if body == null:
		return
	if body.sprite_frames.has_animation("idle"):
		body.play("idle")

func tween_span(head: Vector2i, tail: Vector2i) -> void:
	# The body glides to its new midpoint. A TURN is NOT animated (Fra): the body simply
	# adopts its new axis and _apply_span_pose rotates the art there instantly. Only a
	# STRAIGHT slither plays its walk cycle. (The 7-frame sidemove sweep is deliberately
	# unused -- it is kept in the art set for a future pass.)
	var target := ViewConfig.tile_center(head).lerp(ViewConfig.tile_center(tail), 0.5)
	var turned := _span_axis != "" and _axis_of(head, tail) != _span_axis
	var stepped := position.distance_to(target) > 0.5
	if turned and _span_heads.size() == 2:
		_play_turn(_span_heads.duplicate(), head, tail)   # the view remembers where it was
		return
	_span_target = target
	_span_axis = _axis_of(head, tail)
	_span_heads = [head, tail]
	queue_redraw()
	# Only a real STEP plays the walk cycle. A stationary turn (or a pure attack, where
	# the controller still re-seats the span) must not twitch through the move frames.
	if body and stepped and not turned and body.sprite_frames.has_animation("move"):
		body.play("move")
	_apply_span_pose()
	# The slide lasts exactly as long as the walk cycle, so the body never arrives early
	# and wriggles in place. The art's own FPS is therefore the movement speed: slow the
	# animation down in SpriteBook and the whole step slows with it.
	var t := create_tween()
	t.tween_property(self, "position", target, _span_step_dur()) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

# The 90-degree TURN, animated procedurally (Fra's idea) -- it needs NO art at all.
# The idle/move art IS the exact 2-tile footprint, so that same sprite turned 90 degrees
# is the horizontal body. This simply plays the creature's two real actions in order:
#   PHASE 1  SLIDE one tile onto the cell it turns on, axis held (its walk cycle plays)
#   PHASE 2  ROTATE 90 degrees around that cell, swinging its far head onto the new axis
# Exact by construction -- it ends on the midpoint the engine committed -- and it cannot
# be misaligned, because nothing here depends on where art sits inside a canvas.
func _play_turn(before: Array, head: Vector2i, tail: Vector2i) -> void:
	var old_dir: Vector2i = before[1] - before[0]    # body axis before the turn
	var new_dir: Vector2i = tail - head              # body axis after it
	_span_axis = _axis_of(head, tail)
	_span_heads = [head, tail]
	_span_target = ViewConfig.tile_center(head).lerp(ViewConfig.tile_center(tail), 0.5)
	queue_redraw()
	if body == null or old_dir == Vector2i.ZERO or new_dir == Vector2i.ZERO:
		position = _span_target
		return
	_turning = true
	# Hang the node on the PRIMARY cell and push the sprite half a tile along its own
	# axis, so the rotation pivots around that cell -- not around the body's middle.
	var half := float(ViewConfig.TILE) * 0.5
	var a0 := Vector2(old_dir).angle() - PI / 2.0    # local +y aligned onto the old axis
	var a1 := Vector2(new_dir).angle() - PI / 2.0    # ...and onto the new one
	a1 = a0 + wrapf(a1 - a0, -PI, PI)                # always swing the short way round
	body.offset = Vector2(0.0, half)
	body.flip_h = false
	body.flip_v = false
	body.scale = Vector2.ONE
	body.rotation = a0
	position = ViewConfig.tile_center(before[0])     # unchanged on screen: the sprite is
	if body.sprite_frames.has_animation("move"):     # still exactly where it already was
		body.play("move")
	var t := create_tween()
	t.tween_property(self, "position", ViewConfig.tile_center(head), _span_step_dur())
	t.tween_property(body, "rotation", a1, TURN_ROT_DUR)
	t.tween_callback(_settle_span)

# Back to the plain resting pose, on the cells the engine committed.
func _settle_span() -> void:
	_turning = false
	if body:
		body.offset = Vector2.ZERO
	position = _span_target
	_apply_span_pose()
	_span_rest()

func _span_step_dur() -> float:
	if body and body.sprite_frames.has_animation("move"):
		var n := body.sprite_frames.get_frame_count("move")
		var fps := body.sprite_frames.get_animation_speed("move")
		if fps > 0.0 and n > 0:
			return maxf(ViewConfig.MOVE_DUR, float(n) / float(fps))
	return ViewConfig.MOVE_DUR

func _apply_span_pose() -> void:
	if body == null or _span_axis == "":
		return
	# The serpent's art is drawn VERTICAL (32x64) at its exact 2-tile footprint, so a
	# HORIZONTAL body is that same art turned 90 degrees. There is no separate
	# horizontal sprite and no sweep involved: the pose is derived from the axis the
	# engine gave us, so the sprite can never disagree with the cells it occupies.
	body.rotation = 0.0 if _span_axis == "v" else PI / 2.0
	body.flip_h = false
	body.flip_v = false
	body.offset = Vector2.ZERO
	body.scale = Vector2.ONE

func tween_to(pos: Vector2i) -> void:
	if _span_axis != "":
		return                   # a multi-tile body is moved ONLY by tween_span: it alone
								 # knows both cells, so the node lands on the body midpoint
								 # instead of being dragged to one tile's centre and back
	var target := ViewConfig.tile_center(pos)
	var delta := target - position
	if body and delta.length() > 0.5 and _reach_kind("move") == "step":
		# The move CLIP carries the creature across both tiles, so the node simply lands
		# on its new tile and the art does the travelling. No tween: two things moving
		# one sprite is what made them drift.
		position = target
		_play_reach("move", delta, true)
		return
	if body and delta.length() > 0.5:
		# move art points UP; play_anim rotates the walk to the travel direction.
		play_anim("move", delta)   # orientation comes from the art row ("points")
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
	if _span_axis != "":
		return                       # a spanned body's pose belongs to the span
	if body:
		body.flip_h = _mob_facing_flip()
		body.rotation = _mob_facing_rotation()

# ── ART ORIENTATION ──────────────────────────────────────────────────────────
# THE one place that turns "which way the art was drawn" into "the rotation that
# aims it at `dir`". Each animation row declares its drawn direction as "points"
# (see SpriteBook); art without one plays exactly as drawn, so this is inert for
# every existing set. Callers never carry art knowledge.
# Which way an animation's art was DRAWN. "" = undeclared -> the art plays as drawn.
# "" = a normal 1-tile clip. "step" = 2-tile clip, the creature ENDS in the next tile.
# "strike" = 2-tile clip, it stays put and only the blow reaches.
func _reach_kind(anim: String) -> String:
	return String(_rows.get(anim, {}).get("reach", ""))

# Play a 2-tile action clip acting toward the neighbouring tile in `dir`.
#
# THE NODE NEVER LEAVES A TILE. Only the SPRITE is shifted. Moving the node to the two
# tiles' midpoint (as this used to) stranded the creature between tiles whenever a clip
# was interrupted -- and worse, the NEXT step measured `target - position` from that
# half-tile spot, which is a DIAGONAL, and the error compounded every turn. The node is
# authoritative and always on the creature's real tile; the offset is pixels only.
func _play_reach(anim: String, dir: Vector2, lands: bool) -> void:
	var half := float(ViewConfig.TILE) * 0.5
	# A 2-tile clip spans a creature's tile and ONE cardinal neighbour, so it can only
	# ever act along an axis. Snapping here makes a diagonal strike or step impossible to
	# draw whatever `dir` arrives -- the art can never claim a move the rules don't allow.
	var d := _cardinal_of(dir)
	body.rotation = _rot_for(anim, d)
	# The clip is 2 tiles wide: the creature is drawn in its RIGHT half, the action
	# reaching LEFT. Shifting it half a tile along its own axis (the offset rotates WITH
	# the sprite, so this holds for all four directions) puts the creature's half on the
	# node -- back toward the tile it came FROM for a step, out toward the target for a
	# strike.
	body.offset = Vector2(half if lands else -half, body.offset.y)
	body.flip_h = false
	body.flip_v = false
	_reaching = true
	body.play(anim)

# The nearest cardinal to `v` (ties go horizontal). Never returns zero.
func _cardinal_of(v: Vector2) -> Vector2:
	if v == Vector2.ZERO:
		return Vector2(1.0, 0.0)
	if absf(v.x) >= absf(v.y):
		return Vector2(signf(v.x), 0.0)
	return Vector2(0.0, signf(v.y))

func _points_of(anim: String) -> String:
	return String(_rows.get(anim, {}).get("points", ""))

func _rot_for(anim: String, dir: Vector2) -> float:
	var pts := _points_of(anim)
	if pts == "" or dir == Vector2.ZERO:
		return 0.0
	var rof: float = {"up": PI / 2.0, "down": -PI / 2.0, "right": 0.0, "left": -PI}.get(pts, 0.0)
	return dir.angle() + rof

# The RESTING pose. Mobs have no mechanical facing any more: their idle art simply
# looks along `aim`, which the story keeps pointed at the player.
func _mob_facing_rotation() -> float:
	return _rot_for("idle", aim)

# Config.Facing order (NORTH, EAST, SOUTH, WEST) -> the names SpriteBook data uses.
const _FACING_NAMES := ["north", "east", "south", "west"]

# Whether the mob body sprite mirrors at the current facing. The per-creature rule
# is DATA in its SpriteBook set ("flip_when") -- no creature id is named here.
func _mob_facing_flip() -> bool:
	var flips: Array = ["west"]                   # default for sets without the field
	if art_key != "" and SpriteBook.has(art_key):
		flips = SpriteBook.set_of(art_key).get("flip_when", flips)
	return flips.has(_FACING_NAMES[facing])

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
		body.offset = Vector2(0.0, float(_anim_offset.get(name, _body_offset_y)))
		# This art set declares which way it was DRAWN ("points"); _rot_for turns that
		# into the rotation that aims it at `dir`, so callers never carry art knowledge
		# (re-drawing a sprite only ever means editing its "points" in the art table).
		var pts := _points_of(name)
		if _reach_kind(name) != "" and dir != Vector2.ZERO and _span_axis == "":
			_play_reach(name, dir, _reach_kind(name) == "step")
			return
		if _span_axis != "":
			# Spanned creature: pose is owned by the span, never by per-anim rotation.
			call_deferred("_apply_span_pose")
		elif (directional_art or pts != "") and dir != Vector2.ZERO:
			# Directional one-shot: aim the art at `dir`. Art that declares "points"
			# is converted by _rot_for; older art without one uses the caller's
			# `rot_offset` (the guard shield passes its own -- see EventPlayer).
			body.flip_h = false
			body.rotation = _rot_for(name, dir) if pts != "" else dir.angle() + rot_offset
		else:
			# No action vector for this play: rest the art on `aim`, so a mob keeps
			# looking at the player between turns.
			body.rotation = _rot_for(name, aim)
			body.flip_h = _mob_facing_flip()
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
	if _turning:
		return                       # a turn owns the pose until its tween settles it
	if _reaching:
		_reaching = false
		body.offset.x = 0.0          # the node was already on the right tile: art only
		body.rotation = _mob_facing_rotation()
		body.flip_h = _mob_facing_flip()
		body.offset.y = float(_anim_offset.get("idle", _body_offset_y))
		body.play("idle")
		return
	if _held != "" and body.animation == _held:
		return                       # freeze on the last frame (held guard cube) until released
	if _span_axis != "":
		if _span_target != Vector2.ZERO:
			position = _span_target  # after a turn sweep, settle onto the final tiles
		body.rotation = 0.0          # clear any turn-sweep rotation/flips
		body.flip_h = false
		body.flip_v = false
		_span_rest()                 # a body just loops its idle; the axis rotates the art
		_apply_span_pose()
		return
	body.rotation = _mob_facing_rotation()   # back to the RESTING pose (bat aims its head here)
	body.flip_h = _mob_facing_flip()
	body.offset.y = float(_anim_offset.get("idle", _body_offset_y))   # back to a seated figure
	_apply_facing()              # restore idle facing (flip for west)
	body.play("idle")            # one-shot anims return to idle

# ── Draw HP bar + facing marker (+ fallback disc if no sprite) ──────────
func _draw() -> void:
	var r := ViewConfig.TILE * 0.34
	if body == null:
		draw_circle(Vector2.ZERO, r, base_color)   # fallback when art is missing

	if prop:                                       # NPC marker: just the disc + name, no combat bars
		draw_string(ThemeDB.fallback_font, Vector2(-6, ViewConfig.TILE * 0.5 + 14), unit_id,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
		return

	# Two-tile serpent: a facing bar on BOTH heads at once (it has two heads and can
	# strike from either). Each bar sits on the OUTER edge of its head tile.
	if _span_axis != "":
		# Body bars only if this unit shows facing at all (mobs never do).
		var adir := Vector2(0, 1) if _span_axis == "v" else Vector2(1, 0)
		if not show_facing:
			adir = Vector2.ZERO   # skip the bar loop below; HP bar still draws
		var half := float(ViewConfig.TILE) * 0.5
		var blen2 := ViewConfig.TILE * 0.72
		for sgn: float in ([] if adir == Vector2.ZERO else [1.0, -1.0]):
			var mid2: Vector2 = adir * (half * sgn * 2.0)      # outer edge of one head tile, local
			var perp2: Vector2 = Vector2(-adir.y, adir.x) * (blen2 * 0.5)
			draw_line(mid2 - perp2, mid2 + perp2, Color.WHITE, 3.0)
		# HP bar centered above the whole body.
		var sw := ViewConfig.TILE * 0.8
		var sx := -sw / 2.0
		var sy := -ViewConfig.TILE * (1.0 if _span_axis == "v" else 0.5) - 4.0
		draw_rect(Rect2(sx, sy, sw, 5.0), ViewConfig.COL_HP_BG)
		var sfrac := clampf(shown_hp / float(Config.MAX_HP), 0.0, 1.0)
		draw_rect(Rect2(sx, sy, sw * sfrac, 5.0), ViewConfig.COL_HP_FILL)
		return

	if not show_facing:
		return                    # mobs: no facing bar (HP handled above for spans)
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
