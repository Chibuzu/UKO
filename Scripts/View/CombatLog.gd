# CombatLog.gd
# A scrolling text record of what happened each turn. Like the EventPlayer, it
# is just a CONSUMER of the resolver's event list — it contains no rules, it
# only formats events into readable lines. Newest entries appear at the bottom.
class_name CombatLog
extends Node2D

# Each entry: { "text": String, "color": Color }
var lines: Array = []

func _ready() -> void:
	position = ViewConfig.LOG_ORIGIN
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
	queue_redraw()

func _push(text: String, color: Color) -> void:
	lines.append({"text": text, "color": color})

# ── Event -> readable line. Returns "" for events not worth showing. ────
func _format(e: Dictionary) -> String:
	var o: String = e.get("owner", "")
	match e["type"]:
		"move":
			return "%s moves to %s" % [o, _t(e["to"])]
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
			return "%s waits (acts first next turn)" % o
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
		_:
			return ""    # guard_raised, rest, dead_skip, illegal_action: hidden

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
	draw_rect(Rect2(0, 0, ViewConfig.LOG_W, ViewConfig.LOG_H), ViewConfig.COL_BOARD_EDGE, false, 2.0)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(10, 22), "COMBAT LOG", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, ViewConfig.COL_TEXT)

	var top := 40
	var avail := ViewConfig.LOG_H - top - 8
	var fit := int(avail / ViewConfig.LOG_LINE_H)
	var start := maxi(0, lines.size() - fit)
	var y := top + ViewConfig.LOG_LINE_H
	for i in range(start, lines.size()):
		var entry: Dictionary = lines[i]
		draw_string(font, Vector2(10, y), entry["text"], HORIZONTAL_ALIGNMENT_LEFT,
			ViewConfig.LOG_W - 16, ViewConfig.LOG_FONT, entry["color"])
		y += ViewConfig.LOG_LINE_H
