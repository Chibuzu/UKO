# CombatLog.gd
# A scrolling text record of what happened each turn. Like the EventPlayer, it
# is just a CONSUMER of the resolver's event list — it contains no rules, it
# only formats events into readable lines. Newest entries appear at the bottom.
class_name CombatLog
extends Node2D

# Each entry: { "text": String, "color": Color }
var lines: Array = []
var scroll: int = 0      # lines scrolled UP from the newest (0 = pinned to the latest)

func _ready() -> void:
	position = ViewConfig.LOG_ORIGIN
	queue_redraw()

# How many lines fit in the panel body.
func _fit() -> int:
	var avail := ViewConfig.LOG_H - 48
	return maxi(1, int(avail / ViewConfig.LOG_LINE_H))

# Mouse wheel over the panel scrolls through history; clamps at both ends.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var local := get_local_mouse_position()
	if not Rect2(0, 0, ViewConfig.LOG_W, ViewConfig.LOG_H).has_point(local):
		return
	var max_scroll := maxi(0, lines.size() - _fit())
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		scroll = mini(scroll + 1, max_scroll)
		get_viewport().set_input_as_handled()
		queue_redraw()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scroll = maxi(scroll - 1, 0)
		get_viewport().set_input_as_handled()
		queue_redraw()

# Feed one resolved turn's events. Call this after the turn animates.
func add_turn(turn_num: int, events: Array) -> void:
	_push("-- TURN %d --" % turn_num, ViewConfig.COL_LOG_HEADER)
	for e in events:
		var text := _format(e)
		if text == "":
			continue
		var tick := int(e.get("tick", -1))
		var prefix := ("t%-4d " % tick) if tick >= 0 else "      "
		_push(prefix + text, _line_color(e))
	if lines.size() > ViewConfig.LOG_MAX_LINES:
		lines = lines.slice(lines.size() - ViewConfig.LOG_MAX_LINES, lines.size())
	scroll = 0                          # a fresh turn snaps the view back to the newest lines
	queue_redraw()

# A plain line appended after add_turn -- story mode uses it for mob movement and
# multi-strike notes that never pass through the resolver's event stream.
func add_note(text: String, color: Color = ViewConfig.COL_TEXT) -> void:
	_push("      " + text, color)
	if lines.size() > ViewConfig.LOG_MAX_LINES:
		lines = lines.slice(lines.size() - ViewConfig.LOG_MAX_LINES, lines.size())
	queue_redraw()

func _push(text: String, color: Color) -> void:
	lines.append({"text": text, "color": color})

# Wipe the log (used by the replay viewer to rebuild it through a chosen turn).
func clear() -> void:
	lines = []
	queue_redraw()

# ── Event -> readable line. Returns "" for events not worth showing. ────
func _format(e: Dictionary) -> String:
	# `name` overrides the raw owner id when one is supplied. The story fights several
	# mobs at once and every one of them is "B" in its own resolve, so without this the
	# log cannot say WHICH creature acted.
	var o: String = e.get("name", e.get("owner", ""))
	match e["type"]:
		"move":
			return "%s moves to %s" % [o, _t(e["to"])]
		"blink":
			return "%s blinks to %s" % [o, _t(e["to"])]
		"move_blocked":
			return "%s move blocked" % o
		"pivot":
			return "%s turns %s" % [o, _facing(e["facing"])]
		"attack_hit":
			return "%s hits %s  -%d (%s)" % [o, e["target"], e["damage"], e["flank"]]
		"attack_whiff":
			return "%s swings, misses" % o
		"attack_blocked":
			return "%s hits %s  BLOCKED" % [o, e["target"]]
		"guard_success":
			return "%s guard holds (counter ready)" % o
		"guard_failed":
			return "%s guards, nothing to block" % o
		"rest_regen":
			return "%s rests  +%d hp  +%d mp" % [o, e["hp"], e["mp"]]
		"rest_interrupted":
			return "%s rest interrupted" % o
		"wait":
			return "%s waits (+%d en, next action faster)" % [o, Config.WAIT_ENERGY]
		"energy_pulse":
			return "%s +%d energy" % [o, int(e.get("amount", 0))]
		"spell_cast":
			return "%s casts %s" % [o, _spell(e["spell"])]
		"spell_hit":
			return "   %s hits %s  -%d" % [_spell(e["spell"]), e["target"], e["damage"]]
		"spell_miss":
			return "   %s misses" % _spell(e["spell"])
		"buff_applied":
			return "   %s active" % _status(e["status"])
		"game_over":
			return "== %s ==" % _result(e["result"])
		"guard_raised":
			return "%s guards" % o
		_:
			return ""    # rest, dead_skip, illegal_action: hidden

func _line_color(e: Dictionary) -> Color:
	if e["type"] == "game_over":
		return ViewConfig.COL_LOG_HEADER
	match e.get("owner", ""):
		"A": return ViewConfig.COL_WIN_A
		"B": return ViewConfig.COL_WIN_B
		_:   return ViewConfig.COL_LOG_DIM

func _t(p: Vector2i) -> String:
	return "(%d,%d)" % [p.x, p.y]

func _facing(f: int) -> String:
	return ["N", "E", "S", "W"][f]

func _spell(id: String) -> String:
	return Config.def(id).get("name", id)

func _status(id: String) -> String:
	return id.replace("_", " ")

func _result(r: String) -> String:
	match r:
		"a_wins": return "A WINS"
		"b_wins": return "B WINS"
		_: return "DRAW"

# ── Draw the panel and the lines that fit (newest at the bottom) ────────
func _draw() -> void:
	draw_rect(Rect2(0, 0, ViewConfig.LOG_W, ViewConfig.LOG_H), ViewConfig.COL_LOG_BG)
	draw_rect(Rect2(0, 0, ViewConfig.LOG_W, ViewConfig.LOG_H), ViewConfig.COL_FRAME, false, 2.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(10, 22), "COMBAT LOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ViewConfig.COL_TEXT)

	var top := 40
	var fit := _fit()
	# Newest lines sit at the bottom; `scroll` slides the visible window up through history.
	var end := lines.size() - scroll
	var start := maxi(0, end - fit)
	var y := top + ViewConfig.LOG_LINE_H
	for i in range(start, end):
		var entry: Dictionary = lines[i]
		draw_string(font, Vector2(10, y), entry["text"], HORIZONTAL_ALIGNMENT_LEFT,
			ViewConfig.LOG_W - 22, ViewConfig.LOG_FONT, entry["color"])
		y += ViewConfig.LOG_LINE_H

	# Scrollbar, only when the history overflows the panel.
	var total := lines.size()
	if total > fit:
		var track_h := float(ViewConfig.LOG_H - top - 8)
		var track_x := float(ViewConfig.LOG_W - 6)
		draw_rect(Rect2(track_x, float(top), 3.0, track_h), Color(ViewConfig.COL_LOG_DIM, 0.35))
		var thumb_h := maxf(18.0, track_h * float(fit) / float(total))
		var max_scroll := maxi(1, total - fit)
		var frac := float(max_scroll - scroll) / float(max_scroll)   # 1.0 = pinned to bottom
		var thumb_y := float(top) + frac * (track_h - thumb_h)
		draw_rect(Rect2(track_x, thumb_y, 3.0, thumb_h), ViewConfig.COL_TEXT)
