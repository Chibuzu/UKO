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
var _flights: Dictionary = {}   # owner -> {points, seg_durs, color}: a projectile's whole path, pre-planned
var _bolt_tweens: Dictionary = {}   # owner -> active bolt tween, so a hit can wait for the bolt to ARRIVE

func setup(p_board: BoardView, p_fx: Fx, unit_a: UnitView, unit_b: UnitView) -> void:
	board = p_board
	fx = p_fx
	units = {"A": unit_a, "B": unit_b}

func play(events: Array, final_a: Combatant, final_b: Combatant) -> void:
	_flights = _plan_flights(events)   # gather each bolt's full path up front
	_bolt_tweens = {}
	var i := 0
	while i < events.size():
		var tick = events[i]["tick"]
		var group := []
		while i < events.size() and events[i]["tick"] == tick:
			group.append(events[i])
			i += 1

		# If a projectile LANDS this tick, wait for the bolt to actually reach the tile before
		# playing the impact -- so the damage number / flinch never shows before the bolt arrives.
		var lands := false
		for e in group:
			if e["type"] == "spell_hit":
				lands = true
		if lands:
			await _await_bolts()

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

# Wait for every in-flight bolt to finish arriving. Called just before a projectile impact so the
# hit lands only once the bolt has visually reached the tile. Returns at once if none are flying.
func _await_bolts() -> void:
	for owner in _bolt_tweens.keys():
		var tw = _bolt_tweens[owner]
		if is_instance_valid(tw) and tw.is_valid() and tw.is_running():
			await tw.finished
	_bolt_tweens.clear()

func _visualize(e: Dictionary) -> float:
	var owner: String = e.get("owner", "")
	var u: UnitView = units.get(owner, null)

	match e["type"]:
		ResolverEvents.MOVE:
			if u:
				u.tween_to(e["to"])
			return ViewConfig.MOVE_DUR
		ResolverEvents.MOVE_BLOCKED:
			if u:
				u.flash(ViewConfig.FLASH_BLOCK)
			return ViewConfig.FLASH_DUR
		ResolverEvents.PIVOT:
			if u:
				u.set_facing(e["facing"])
			return ViewConfig.PIVOT_DUR
		ResolverEvents.BLINK:
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
		ResolverEvents.ATTACK_HIT:
			if u:
				u.play_anim("attack", Vector2(e.get("dir", Config.FACING_VEC[u.facing])))
			_impact(units.get(e["target"], null), int(e["damage"]), ViewConfig.FLASH_HIT, ViewConfig.SHAKE_HIT)
			return ViewConfig.HIT_DUR
		ResolverEvents.ATTACK_WHIFF:
			if u:
				u.play_anim("attack", Vector2(e.get("dir", Config.FACING_VEC[u.facing])))
			return ViewConfig.FLASH_DUR
		ResolverEvents.ATTACK_BLOCKED:
			if u:
				u.play_anim("attack", Vector2(e.get("dir", Config.FACING_VEC[u.facing])))
			board.shake(ViewConfig.SHAKE_HIT * 0.5)
			return ViewConfig.HIT_DUR
		ResolverEvents.GUARD_RAISED:
			if u:
				# Rotate the shield so its OPEN side sits behind the fighter (closed
				# side toward the facing), and HOLD the cube up for the rest of the
				# turn — it drops on guard_dropped or when the turn ends (set_state).
				u.hold_anim("guard_up", Vector2(Config.FACING_VEC[u.facing]), 0.0)
				u.flash(ViewConfig.FLASH_GUARD)
			return ViewConfig.FLASH_DUR
		ResolverEvents.GUARD_DROPPED:
			if u:
				u.clear_hold()   # an offensive action this turn drops the shield
			return 0.0
		ResolverEvents.GUARD_SUCCESS:
			if u:
				u.flash(ViewConfig.FLASH_GUARD_OK)
			return ViewConfig.FLASH_DUR
		ResolverEvents.REST, ResolverEvents.REST_REGEN:
			if u:
				u.play_rest()
				u.flash(ViewConfig.FLASH_HEAL)
				if e.has("hp"):
					u.set_display_hp(u.display_hp + int(e["hp"]))
					board.spawn_number(u.position, "+%d" % int(e["hp"]), ViewConfig.COL_HEAL)
					fx.burst(u.position, ViewConfig.COL_HEAL, 8)
			return ViewConfig.FLASH_DUR
		ResolverEvents.REST_INTERRUPTED:
			if u:
				u.flash(ViewConfig.FLASH_HIT)
			return ViewConfig.FLASH_DUR
		ResolverEvents.WAIT:
			if u:
				u.flash(ViewConfig.FLASH_GUARD)
				board.spawn_number(u.position, "WAIT", ViewConfig.COL_TEXT)
			return ViewConfig.FLASH_DUR
		ResolverEvents.SPELL_CAST:
			_cast_visual(u, e)
			return ViewConfig.FX_DUR
		ResolverEvents.SPELL_HIT:
			if e.get("disrupt", false):
				# The grenade's full receipt: chip damage (rest-breaker), root, drain.
				_impact(units.get(e["target"], null), int(e["damage"]), ViewConfig.FLASH_HIT, ViewConfig.SHAKE_SPELL)
				var tgt0: UnitView = units.get(e["target"], null)
				if tgt0:
					board.spawn_number(tgt0.position + Vector2(0, -14), "ROOTED", ViewConfig.COL_DMG)
					if int(e.get("drain", 0)) > 0:
						board.spawn_number(tgt0.position + Vector2(0, 14), "-%d ENERGY" % int(e.get("drain", 0)), ViewConfig.COL_DMG)
			else:
				_impact(units.get(e["target"], null), int(e["damage"]), ViewConfig.FLASH_HIT, ViewConfig.SHAKE_SPELL)
			if e.get("disrupt", false):                       # the grenade landed -> explode where it FELL
				var fl: Dictionary = {}
				for k in _flights:
					# match THIS thrower's grenade flight, not whichever comes first
					if String(_flights[k].get("spell", "")) == "grenade" and String(k).begins_with(String(e.get("owner", ""))):
						fl = _flights[k]
				if not fl.is_empty():
					fx.grenade_burst(fl["points"].back())      # the thrown tile, even if the target moved
				else:
					var tgt: UnitView = units.get(e["target"], null)
					if tgt:
						fx.grenade_burst(tgt.position)
			return ViewConfig.HIT_DUR
		ResolverEvents.BUFF_APPLIED:
			if u:
				board.spawn_number(u.position, "BUFF", ViewConfig.COL_HEAL)
			return ViewConfig.FLASH_DUR
		ResolverEvents.SPELL_MISS:
			return ViewConfig.FX_DUR
		ResolverEvents.BLINK_DEPART:
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
		ResolverEvents.PROJECTILE_STEP:
			# The visible bolt is ONE sprite launched at spell_cast that flies the
			# whole path (see _cast_visual / _plan_flights). These step events now
			# only PACE the timeline — their tick spacing is the inter-group gap, so
			# the bolt stays in sync with the sim and the hit lands on time.
			return 0.0
		ResolverEvents.CLASH, ResolverEvents.BLINK_FIZZLE, ResolverEvents.ENERGY_PULSE, \
		ResolverEvents.GUARD_FAILED, ResolverEvents.GAME_OVER, \
		ResolverEvents.DEAD_SKIP, ResolverEvents.ILLEGAL_ACTION:
			# Deliberately unrendered here: CombatLog narrates these (clash animations
			# are the tick bundle's pending Stage C).
			return 0.0
		_:
			_warn_unknown(String(e["type"]))
			return 0.0

# A resolver event type this consumer doesn't know: warn ONCE (a rename/addition
# in Resolver must be a loud mismatch here, never a silently skipped visual).
static var _unknown_warned := {}
func _warn_unknown(t: String) -> void:
	if not _unknown_warned.has(t):
		_unknown_warned[t] = true
		push_warning("[EventPlayer] unknown resolver event type '%s' -- update ResolverEvents/the match" % t)

# A landed hit: the drawn hurt flinch + damage number + screen shake.
func _impact(tgt: UnitView, dmg: int, color: Color, shake: float) -> void:
	if tgt == null:
		return
	tgt.flash(color)   # the hit tint callers pass (FLASH_HIT) -- was threaded through but never applied
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
			board.shake(ViewConfig.SHAKE_HIT * 0.5)   # muzzle kick
			# Fire the whole flight now: one sprite travels caster -> ... -> impact,
			# staying visible the entire time (paced to match the step ticks).
			var fl: Dictionary = _flights.get("%s|%s" % [e.get("owner", ""), String(e.get("spell", ""))], {})
			if not fl.is_empty():
				# One sprite flies caster -> ... -> impact, delayed by the cast hold so it launches
				# after the muzzle. The tween is stored so the spell_hit waits for it to arrive.
				var tw := fx.projectile_flight(fl["points"], fl["seg_durs"], fl["color"], ViewConfig.FX_DUR, fl.get("spell", ""))
				if tw != null:
					_bolt_tweens["%s|%s" % [e.get("owner", ""), String(e.get("spell", ""))]] = tw
		"aoe":
			if not fx.aoe_anim(caster.position):
				board.flash_tiles(tiles, color)            # fallback if art missing
			board.shake(ViewConfig.SHAKE_HIT * 0.7)
		ResolverEvents.BLINK:
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
		ResolverEvents.BLINK:
			return ViewConfig.COL_FX_BUFF
		_:
			return ViewConfig.COL_FX_AOE

# Walk the event list and assemble each projectile's WHOLE path before playback,
# keyed by caster (one bolt per caster per turn). points = [launch tile center,
# tile1, tile2, ...]; one seg_dur per leg, tick-derived so the sprite's speed
# matches the sim (and the inter-group gaps). If the bolt is consumed early, the
# path simply ends at the hit tile — only the emitted steps are included.
func _plan_flights(events: Array) -> Dictionary:
	var out := {}
	for e in events:
		if String(e.get("type", "")) != "projectile_step":
			continue
		var owner: String = e.get("owner", "")
		var spell: String = e.get("spell", "")
		var key := "%s|%s" % [owner, spell]   # per owner AND spell: grenade + bolt in one turn stay separate
		# A step index that RESETS means a SECOND flight of the same spell by the same
		# owner: give it its own key, or the two paths weld into one bouncing zigzag.
		if out.has(key) and int(e.get("step", 1)) <= int(out[key].get("last_step", 0)):
			key += "#2"
		var tpt := int(Config.def(spell).get("tick_per_tile", 0))
		var seg := clampf(float(tpt) * ViewConfig.SEC_PER_TICK, ViewConfig.GAP_MIN, ViewConfig.GAP_MAX)
		if not out.has(key):
			out[key] = {
				"points": [ViewConfig.tile_center(e.get("from", e["tile"]))],
				"seg_durs": [],
				"color": _style_color("projectile"),
				"spell": spell,
			}
		out[key]["points"].append(ViewConfig.tile_center(e["tile"]))
		out[key]["seg_durs"].append(seg)
		out[key]["last_step"] = int(e.get("step", 1))
	return out
