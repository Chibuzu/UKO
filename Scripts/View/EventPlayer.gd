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
		await get_tree().create_timer(ViewConfig.GROUP_GAP).timeout

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
			return 0.15
		"attack_hit":
			if u:
				u.play_anim("attack")
			_impact(units.get(e["target"], null), int(e["damage"]), ViewConfig.FLASH_HIT, ViewConfig.SHAKE_HIT)
			return ViewConfig.HIT_DUR
		"attack_whiff":
			if u:
				u.play_anim("attack")
			return ViewConfig.FLASH_DUR
		"attack_blocked":
			if u:
				u.play_anim("attack")
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
			if not tiles.is_empty():
				fx.bolt_projectile(caster.position, ViewConfig.tile_center(tiles[-1]))
			board.shake(ViewConfig.SHAKE_HIT * 0.5)
		"aoe":
			if not fx.aoe_anim(caster.position):
				board.flash_tiles(tiles, color)            # fallback if art missing
			board.shake(ViewConfig.SHAKE_HIT * 0.7)
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
		_:
			return ViewConfig.COL_FX_AOE
