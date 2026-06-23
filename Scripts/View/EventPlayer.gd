# EventPlayer.gd
# Turns the resolver's event list into animation. It reads events and drives
# the views + the Fx layer — it contains ZERO rules. Same-tick events play
# together; a short gap (plus a hit-stop on impacts) separates ticks.
#
#   await event_player.play(result["events"], result["a"], result["b"])
class_name EventPlayer
extends Node

var board: BoardView
var fx: Fx
var units: Dictionary = {}   # "A" -> UnitView, "B" -> UnitView

func setup(p_board: BoardView, p_fx: Fx, unit_a: UnitView, unit_b: UnitView) -> void:
	board = p_board
	fx = p_fx
	units = {"A": unit_a, "B": unit_b}

func play(events: Array, final_a: Combatant, final_b: Combatant) -> void:
	var i := 0
	while i < events.size():
		var tick = events[i]["tick"]
		var group := []
		while i < events.size() and events[i]["tick"] == tick:
			group.append(events[i])
			i += 1

		var dur := 0.0
		var had_hit := false
		for e in group:
			if e["type"] in ["attack_hit", "spell_hit"]:
				had_hit = true
			dur = maxf(dur, _visualize(e))
		if dur > 0.0:
			await get_tree().create_timer(dur).timeout
		if had_hit:
			await get_tree().create_timer(ViewConfig.HITSTOP).timeout   # weighty pause
		# Pause until the next tick group, proportional to the gap in sim ticks: a
		# traveling bolt or an in-transit blink now waits in real time. GAP_MIN at the end.
		var gap := ViewConfig.GAP_MIN
		if i < events.size():
			gap = clampf((float(events[i]["tick"]) - float(tick)) * ViewConfig.SEC_PER_TICK, ViewConfig.GAP_MIN, ViewConfig.GAP_MAX)
		await get_tree().create_timer(gap).timeout

	units["A"].set_state(final_a)
	units["B"].set_state(final_b)

func _visualize(e: Dictionary) -> float:
	var owner: String = e.get("owner", "")
	var u: UnitView = units.get(owner, null)

	match e["type"]:
		"move":
			if u:
				u.tween_to(e["to"])
			return ViewConfig.MOVE_DUR
		"move_blocked":
			if u:
				u.flash(ViewConfig.FLASH_BLOCK)
			return ViewConfig.FLASH_DUR
		"pivot":
			if u:
				u.set_facing(e["facing"])
			return ViewConfig.PIVOT_DUR
		"blink":
			# Teleport ARRIVES: pop in at the destination, reface, and play the
			# rematerialize half (frames 5→9). Snap alpha back to full first so the
			# reappear frames are visible; the frame content carries the fade-in.
			# Falls back to the old alpha tween when the art is missing.
			if u:
				u.position = ViewConfig.tile_center(e["to"])
				if e.has("facing"):
					u.set_facing(int(e["facing"]))
				fx.burst(u.position, ViewConfig.COL_FX_BUFF, 10)
				var din := u.anim_duration("teleport_in")
				if din > 0.0:
					u.modulate.a = 1.0
					u.play_anim("teleport_in")
					return maxf(ViewConfig.FLASH_DUR, din)
				var tw := create_tween()
				tw.tween_property(u, "modulate:a", 1.0, ViewConfig.FLASH_DUR)
			return ViewConfig.FLASH_DUR
		"attack_hit":
			if u:
				u.play_anim("attack", Vector2(Config.FACING_VEC[u.facing]))
			_impact(units.get(e["target"], null), int(e["damage"]), ViewConfig.FLASH_HIT, ViewConfig.SHAKE_HIT)
			return ViewConfig.HIT_DUR
		"attack_whiff":
			if u:
				u.play_anim("attack", Vector2(Config.FACING_VEC[u.facing]))
			return ViewConfig.FLASH_DUR
		"attack_blocked":
			if u:
				u.play_anim("attack", Vector2(Config.FACING_VEC[u.facing]))
			board.shake(ViewConfig.SHAKE_HIT * 0.5)
			return ViewConfig.HIT_DUR
		"guard_raised":
			if u:
				u.play_anim("guard")
				u.flash(ViewConfig.FLASH_GUARD)
			return ViewConfig.FLASH_DUR
		"guard_success":
			if u:
				u.flash(ViewConfig.FLASH_GUARD_OK)
			return ViewConfig.FLASH_DUR
		"rest", "rest_regen":
			if u:
				u.play_rest()
				u.flash(ViewConfig.FLASH_HEAL)
				if e.has("hp"):
					u.set_display_hp(u.display_hp + int(e["hp"]))
					board.spawn_number(u.position, "+%d" % int(e["hp"]), ViewConfig.COL_HEAL)
					fx.burst(u.position, ViewConfig.COL_HEAL, 8)
			return ViewConfig.FLASH_DUR
		"rest_interrupted":
			if u:
				u.flash(ViewConfig.FLASH_HIT)
			return ViewConfig.FLASH_DUR
		"wait":
			if u:
				u.flash(ViewConfig.FLASH_GUARD)
				board.spawn_number(u.position, "WAIT", ViewConfig.COL_TEXT)
			return ViewConfig.FLASH_DUR
		"spell_cast":
			_cast_visual(u, e)
			return ViewConfig.FX_DUR
		"spell_hit":
			_impact(units.get(e["target"], null), int(e["damage"]), ViewConfig.FLASH_HIT, ViewConfig.SHAKE_SPELL)
			return ViewConfig.HIT_DUR
		"buff_applied":
			if u:
				board.spawn_number(u.position, "BUFF", ViewConfig.COL_HEAL)
			return ViewConfig.FLASH_DUR
		"spell_miss":
			return ViewConfig.FX_DUR
		"blink_depart":
			# Teleport DEPARTS: vanish at the origin. Play the dissolve half
			# (frames 1→5) and fade alpha out over the same span, so the unit
			# stays hidden once it returns to idle — the proportional gap until
			# "blink" (blink_travel ticks) is the real time spent in transit.
			if u:
				fx.burst(u.position, ViewConfig.COL_FX_BUFF, 10)
				var dout := maxf(ViewConfig.FLASH_DUR, u.anim_duration("teleport_out"))
				u.play_anim("teleport_out")
				var tw := create_tween()
				tw.tween_property(u, "modulate:a", 0.0, dout)
				return dout
			return ViewConfig.FLASH_DUR
		"projectile_step":
			# The bolt flies one tile; the hop takes its per-tile tick budget, so the
			# bolt speed matches the sim. Inter-group spacing is the proportional gap.
			var pspell: String = e.get("spell", "")
			var tpt := int(Config.def(pspell).get("tick_per_tile", 0))
			var hop := clampf(float(tpt) * ViewConfig.SEC_PER_TICK, ViewConfig.GAP_MIN, ViewConfig.GAP_MAX)
			fx.bolt_projectile(ViewConfig.tile_center(e.get("from", e["tile"])), ViewConfig.tile_center(e["tile"]), hop)
			return 0.0   # async; the inter-group gap paces it
		_:
			return 0.0

# A landed hit: the drawn hurt flinch + damage number + screen shake.
func _impact(tgt: UnitView, dmg: int, color: Color, shake: float) -> void:
	if tgt == null:
		return
	tgt.play_anim("hurt")
	tgt.set_display_hp(tgt.display_hp - dmg)
	board.spawn_number(tgt.position, "-%d" % dmg, ViewConfig.COL_DMG)
	board.shake(shake)

# Per-spell cast flourish, driven entirely by the spell's "vfx" data — no spell
# id is named here, so any gear's spell renders correctly. vfx = { style,
# cast_anim, projectile? }. Always the drawn animation + shake, nothing else.
func _cast_visual(caster: UnitView, e: Dictionary) -> void:
	if caster == null:
		return
	var spell: String = e.get("spell", "")
	var tiles: Array = e.get("tiles", [])
	var vfx: Dictionary = Config.def(spell).get("vfx", {})
	var style: String = String(vfx.get("style", ""))
	var color := _style_color(style)
	var cast_anim: String = String(vfx.get("cast_anim", ""))
	if cast_anim != "":
		caster.play_anim(cast_anim)
	match style:
		"projectile":
			board.shake(ViewConfig.SHAKE_HIT * 0.5)   # muzzle kick; the bolt travels via projectile_step
		"aoe":
			if not fx.aoe_anim(caster.position):
				board.flash_tiles(tiles, color)            # fallback if art missing
			board.shake(ViewConfig.SHAKE_HIT * 0.7)
		"blink":
			pass   # depart/arrive visuals are driven by the blink_depart / blink events
		"self_buff":
			fx.burst(caster.position, color, 10)
		_:
			if not tiles.is_empty():
				board.flash_tiles(tiles, color)

# FX tint by visual style (palette stays in the view, not in spell data).
func _style_color(style: String) -> Color:
	match style:
		"projectile":
			return ViewConfig.COL_FX_BOLT
		"self_buff":
			return ViewConfig.COL_FX_BUFF
		"blink":
			return ViewConfig.COL_FX_BUFF
		_:
			return ViewConfig.COL_FX_AOE
