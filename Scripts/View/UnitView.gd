# UnitView.gd
# Draws and animates ONE duelist. The body is an AnimatedSprite2D playing the
# player sprite frames (standing / buff / rest); the HP bar and facing marker
# are drawn on top. If the sprite art isn't in the project yet, it falls back
# to a plain colored disc so the game still runs.
#
# Holds only display state — never game rules. The EventPlayer drives it.
class_name UnitView
extends Node2D

# Sprite folders. The player's art now lives in three folders; each animation names its own,
# so a remade animation just points at a new folder. BASE_DIR is the unequipped white figure
# (the foundation gear layers sit on top of); TECH_DIR holds spell/tech effects and the
# gear-piece overlays. (The legacy folder is gone; rows without art simply no-op.)
# remade in the base style (move, guard).
const BASE_DIR   := "res://Assets/Sprites/Unarmed Base Animations/"
const TECH_DIR   := "res://Assets/Sprites/Tech Animations/Tech Spells/"
const GEAR_DIR   := "res://Assets/Sprites/Tech Animations/Tech Gear/"   # per-piece gear overlays (hat_1..4 etc.)
# (Legacy folder removed. Animations without a table row -- e.g. hurt, pivot --
#  simply no-op until art exists: add a row + PNGs and they come alive.)
const PIVOT_DUR := 0.18    # how long the facing bar takes to swing to a new side
const SPRITE_OFFSET_Y := 0.0    # 32px art on a 32px tile sits FLUSH; no nudge (was -6: everyone floated)
# These animations are tile-CENTRED effects (the guard shield cube), not feet-seated figures,
# so they sit centered on the tile. Everything else uses its per-animation "offset" (below) or
# the body's default seat. Buff is NOT here: its art has the aura in the lower half of a tall
# canvas, so it's feet-anchored (offset) to sit in the tile, not centered.
# (Seating is per-row "offset" only -- one mechanism, no special-case lists.)

# Animation table: name -> {dir, prefix, count, fps, loop, offset?}. Frames are
# "<dir><prefix>_1.png".."_<count>.png" (missing numbers are skipped), or a single
# "<prefix>.png" when count == 0. A row may instead carry an explicit "frames" list to use a
# subset / re-ordering of one prefix's PNGs (e.g. the teleport strip split into a vanish half
# and a reappear half). "offset" is the vertical nudge (px) that seats THIS animation in the
# tile -- needed because the art has different canvas sizes: the 32x32 base figure sits at 0
# (it fills the tile), the tall buff aura is pulled up so it lands in the tile, and the older
# 40x46 / 56x56 art keeps the body's default seat. Adding an animation is one row here + PNGs.
const ANIMS := {
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
var npc_art: Array = []                # NPC idle frames (Village Characters/); empty -> disc
const NPC_ART_DIR := "res://Assets/Sprites/Village Characters/"
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
		elif not disc_only and ResourceLoader.exists(BASE_DIR + "Idle_1.png"):
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

# A villager's little idle body: 1 frame = still portrait, 2 frames = gentle sway.
func _build_npc_body() -> void:
	var sf := SpriteFrames.new()
	var files: Array = []
	for f in npc_art:
		files.append(String(f))
	_add_anim(sf, NPC_ART_DIR, "idle", files, 1.6, true)
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
	_body_offset_y = float(art_set.get("offset_y", 0.0))
	for an in art_set.get("anims", {}):
		var ad: Dictionary = art_set["anims"][an]
		if ad.has("offset_y"):
			_anim_offset[an] = float(ad["offset_y"])   # per-anim seat (mixed canvas sizes)
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
		lyr.offset = body.offset                   # seat exactly with the body's current frame
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
		var path := GEAR_DIR + "%s_%d.png" % [prefix, i]
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
	if String(ANIMS.get("attack", {}).get("points", "")) != "":
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
#   horizontal span, "move"          -> the native SIDEMOVE set, flip_h when head is LEFT
#   horizontal span, other anims     -> vertical art rotated ±90° toward the head
# ── TWO-TILE SYMMETRIC SERPENT (Fra's final spec). It has TWO identical heads and
# NO facing: the only thing that matters is which AXIS its two tiles lie along.
#   tiles stacked vertically   -> the "move" art (drawn vertical), no flip
#   tiles side by side          -> the "sidemove" art (drawn horizontal), no flip
# Movement chooses the anim by TURN ANGLE: continuing straight (same axis) = "move";
# turning 90 deg (axis change) = "sidemove". No rotation, no mirroring -- the art is
# symmetric end-to-end, so whichever tile it moved into simply reads as the head.
var show_facing := true        # mobs: false -- mobs have no facing, so no bars
# COSMETIC look vector: the direction this unit's RESTING art points. The story keeps it
# aimed at the player. Art-only -- it never touches rules, legality, damage, or flank.
var aim := Vector2.ZERO
var _span_axis := ""    # "" = single-tile unit; "v" / "h" while spanning
var _span_heads: Array = []   # the two head tiles (Vector2i), for the dual facing bars
var _span_target := Vector2.ZERO     # where the body position settles after a step

func _axis_of(a: Vector2i, b: Vector2i) -> String:
	return "h" if a.y == b.y and a.x != b.x else "v"

func set_span(head: Vector2i, tail: Vector2i) -> void:
	position = ViewConfig.tile_center(head).lerp(ViewConfig.tile_center(tail), 0.5)
	_span_axis = _axis_of(head, tail)
	_span_heads = [head, tail]
	queue_redraw()
	_span_rest()
	_apply_span_pose()

# At rest: a VERTICAL serpent plays its looping idle (clean 32x64 idle art); a
# HORIZONTAL serpent has no idle art, so it holds the sidemove first frame still.
func _span_rest() -> void:
	if body == null:
		return
	if _span_axis == "v" and body.sprite_frames.has_animation("idle"):
		body.play("idle")
	elif body.sprite_frames.has_animation("sidemove"):
		body.animation = "sidemove"
		body.frame = 0
		body.pause()

func tween_span(head: Vector2i, tail: Vector2i) -> void:
	# STRAIGHT slither: play the art matching the body's AXIS (vertical body -> vertical
	# "move" art; horizontal body -> horizontal "sidemove" art), then tween to the new
	# midpoint. Playing "move" unconditionally drew vertical art on a horizontal body.
	var target := ViewConfig.tile_center(head).lerp(ViewConfig.tile_center(tail), 0.5)
	_span_axis = _axis_of(head, tail)
	_span_heads = [head, tail]
	queue_redraw()
	if body:
		var anim := "move" if _span_axis == "v" else "sidemove"
		if body.sprite_frames.has_animation(anim):
			body.play(anim)
	_apply_span_pose()
	var t := create_tween()
	t.tween_property(self, "position", target, ViewConfig.MOVE_DUR) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

# ── THE TURN SWEEP (explicit from -> to) ──────────────────────────────────────
# Called when the serpent pivots 90 degrees. The controller passes the BEFORE body
# (from_pos + from_facing) and the AFTER body (new head + tail). The sweep art is drawn
# ONCE for one canonical turn (vertical body pivoting to horizontal-EAST, rotating
# around the vertical body's lower cell). We flip it to serve all turns and anchor the
# 88x59 canvas so the shared PIVOT cell lands on the tile both bodies share.
const TURN_SWEEP := Vector2(88.0, 59.0)
func play_turn_from(from_pos: Vector2i, from_facing: int, head: Vector2i, tail: Vector2i) -> void:
	_span_axis = _axis_of(head, tail)
	_span_heads = [head, tail]
	_span_target = ViewConfig.tile_center(head).lerp(ViewConfig.tile_center(tail), 0.5)
	if body == null or not body.sprite_frames.has_animation("sidemove"):
		# No sweep art: settle straight onto the new tiles.
		position = _span_target
		queue_redraw(); _apply_span_pose(); _span_rest()
		return
	# The two bodies (before = from_pos & from_pos+from_facing; after = head & tail)
	# share exactly ONE cell: the pivot. Find it.
	var before := [from_pos, from_pos + Vector2i(Config.FACING_VEC[from_facing])]
	var after := [head, tail]
	var pivot: Vector2i = before[0]
	for b in before:
		if b in after:
			pivot = b
			break
	# The far NEW cell (the head that swung out): the after-cell that isn't the pivot.
	var new_far: Vector2i = after[0] if after[1] == pivot else after[1]
	# The old cell that swung AWAY: the before-cell that isn't the pivot.
	var old_far: Vector2i = before[0] if before[1] == pivot else before[1]
	# Canonical art: BEFORE vertical (old_far ABOVE pivot, i.e. old_far - pivot = (0,-1))
	# turning so the new head goes EAST (new_far - pivot = (+1,0)). Derive flips that map
	# our actual (old_dir -> new_dir) onto that canonical (up -> east).
	var old_dir := old_far - pivot            # where the body pointed before (from pivot)
	var new_dir := new_far - pivot            # where it points after
	# We need a flip_h/flip_v (and possibly a 90-deg mental rotation) so that:
	#   canonical old_dir (0,-1) maps to `old_dir`, canonical new_dir (+1,0) maps to `new_dir`.
	# Enumerate the 8 turn cases directly for correctness (4 start axes x 2 sides).
	var fh := false
	var fv := false
	var rot := 0.0
	# Represent the turn as (old_dir, new_dir); pick flips from a small table.
	var key := [old_dir, new_dir]
	# canonical: old (0,-1) new (1,0)  -> no transform
	# Build by reflection: flip_v maps up<->down, flip_h maps left<->right. A turn whose
	# old_dir is vertical uses flips; whose old_dir is horizontal needs a 90-deg rotation
	# of the whole sprite (since the art's "start" is vertical).
	if old_dir.y != 0:
		# start vertical (up or down). Canonical start is UP (0,-1).
		fv = old_dir.y > 0                     # started DOWN -> mirror vertically
		# after flip_v, new head East(+1) or West(-1): flip_h if it should go the OTHER way.
		var want_new_x := new_dir.x
		fh = want_new_x < 0                    # new head West -> mirror horizontally
	else:
		# start horizontal (left/right). Rotate the sprite 90 deg so its vertical start
		# aligns with our horizontal start, then apply flips for the specific case.
		rot = PI / 2.0
		fh = old_dir.x > 0                     # nuance handled with rotation+flip
		fv = new_dir.y > 0
	body.rotation = rot
	body.flip_h = fh
	body.flip_v = fv
	body.scale = Vector2.ONE
	# Anchor: in canonical art the pivot cell center is the bottom-center of the 88x59
	# canvas. Canvas center = (44,30); pivot center ~ (44,46) -> art offset (0,+16).
	# Under flips/rotation, transform that offset the same way.
	var off := Vector2(0.0, 16.0)
	if rot != 0.0:
		off = Vector2(off.y, -off.x)           # rotate the offset 90 deg with the sprite
	if fh: off.x = -off.x
	if fv: off.y = -off.y
	position = ViewConfig.tile_center(pivot) - off
	queue_redraw()
	body.play("sidemove")

func _apply_span_pose() -> void:
	if body == null or _span_axis == "":
		return
	# The clean serpent art is drawn at its EXACT tile footprint (32x64 vertical /
	# 64x32 horizontal) on a transparent canvas, so it needs no scaling, rotation, or
	# flipping -- just centered on the span midpoint (AnimatedSprite2D centers by
	# default). The animation itself (move vs sidemove) carries the orientation.
	body.rotation = 0.0
	body.flip_h = false
	body.flip_v = false
	body.offset = Vector2.ZERO
	body.scale = Vector2.ONE

func tween_to(pos: Vector2i) -> void:
	var target := ViewConfig.tile_center(pos)
	var delta := target - position
	if body and delta.length() > 0.5:
		# move art points UP; play_anim rotates the walk to the travel direction.
		play_anim("move", delta)   # orientation comes from the ANIMS row ("points")
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
func _rot_for(anim: String, dir: Vector2) -> float:
	var pts := String(ANIMS.get(anim, {}).get("points", ""))
	if pts == "" or dir == Vector2.ZERO:
		return 0.0
	var rof: float = {"up": PI / 2.0, "down": -PI / 2.0, "right": 0.0, "left": -PI}.get(pts, 0.0)
	return dir.angle() + rof

# The RESTING pose. Mobs have no mechanical facing any more: their idle art simply
# looks along `aim`, which the story keeps pointed at the player.
func _mob_facing_rotation() -> float:
	return _rot_for("idle", aim)

func _mob_facing_flip() -> bool:
	match art_key:
		"ooze":
			return facing == Config.Facing.WEST or facing == Config.Facing.NORTH
		"bat":
			return false                          # bat aims via rotation, never mirrored
		_:
			return facing == Config.Facing.WEST

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
		body.offset.y = float(_anim_offset.get(name, _body_offset_y))
		# Each art set declares which way it was DRAWN ("points"); the rotation
		# needed to aim it at `dir` is computed here, so callers never carry
		# art knowledge (swapping a sprite folder can no longer break rotation).
		var rof := rot_offset
		var pts := String(ANIMS.get(name, {}).get("points", ""))
		if pts != "":
			rof = {"up": PI / 2.0, "down": -PI / 2.0, "right": 0.0}.get(pts, rot_offset)
		if _span_axis != "":
			# Spanned creature: pose is owned by the span, never by per-anim rotation.
			call_deferred("_apply_span_pose")
		elif (directional_art or pts != "") and dir != Vector2.ZERO:
			# Directional one-shot. `rot_offset` accounts for where the art's
			# reference points by default: the move/attack figure points UP
			# (+PI/2 turns UP onto `dir`); the guard shield's closed side points
			# RIGHT, so it passes its facing with a 0 offset (see EventPlayer).
			body.flip_h = false
			body.rotation = dir.angle() + rof
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
	if _held != "" and body.animation == _held:
		return                       # freeze on the last frame (held guard cube) until released
	if _span_axis != "":
		if _span_target != Vector2.ZERO:
			position = _span_target  # after a turn sweep, settle onto the final tiles
		body.rotation = 0.0          # clear any turn-sweep rotation/flips
		body.flip_h = false
		body.flip_v = false
		_span_rest()                 # vertical -> looping idle; horizontal -> still sidemove
		_apply_span_pose()
		return
	body.rotation = _mob_facing_rotation()   # back to the RESTING pose (bat aims its head here)
	body.flip_h = _mob_facing_flip()
	body.offset.y = float(_anim_offset.get("idle", _body_offset_y))   # back to a seated figure
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
		_add_anim(sf, String(a.get("dir", BASE_DIR)), name, files, float(a["fps"]), bool(a["loop"]))
		# Per-animation seat: explicit "offset" wins; centered effects sit on the tile; everything
		# else keeps the body's default feet nudge.
		_anim_offset[name] = float(a.get("offset", SPRITE_OFFSET_Y))   # per-row "offset" is the ONE seat source (guard rows carry 0.0 explicitly)
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
