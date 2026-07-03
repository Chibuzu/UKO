# ResourceHUD.gd
# Three stacked bars for one fighter -- HP (red), MP (blue), EP (green) -- each with a number
# beside it. The coloured fill is current/max, so a bar empties proportionally as the resource
# is spent. Bind a Combatant once, then call refresh() whenever its state changes: the fill
# tweens smoothly to the new value. Pure display -- reads Config maxes, holds no game rules.
#
# Layout is top-left anchored: place the node at the panel corner and the bars stack downward.
class_name ResourceHUD
extends Node2D

const TRACK_W := 150.0     # full bar length in px
const BAR_H := 7.0         # bar thickness
const GAP := 6.0           # vertical space between bars
const NUM_GAP := 10.0      # gap from bar end to its number
const FONT := 14

var _c: Combatant = null
var _hp := 0.0
var _mp := 0.0
var _ep := 0.0

func bind(c: Combatant) -> void:
	_c = c
	_hp = float(c.hp)
	_mp = float(c.mp)
	_ep = float(c.energy)
	queue_redraw()

# Tween each bar to the fighter's current values. Pass the current Combatant (controllers
# reassign it each turn); call after a turn resolves / a resource regenerates.
func refresh(c: Combatant = null) -> void:
	if c != null:
		_c = c
	if _c == null:
		return
	var t := create_tween().set_parallel(true)
	t.tween_method(_set_hp, _hp, float(_c.hp), ViewConfig.HP_DRAIN_DUR)
	t.tween_method(_set_mp, _mp, float(_c.mp), ViewConfig.HP_DRAIN_DUR)
	t.tween_method(_set_ep, _ep, float(_c.energy), ViewConfig.HP_DRAIN_DUR)

func _set_hp(v: float) -> void:
	_hp = v
	queue_redraw()

func _set_mp(v: float) -> void:
	_mp = v
	queue_redraw()

func _set_ep(v: float) -> void:
	_ep = v
	queue_redraw()

func _draw() -> void:
	_bar(0, _hp, Config.MAX_HP, ViewConfig.COL_RES_HP)
	_bar(1, _mp, Config.MAX_MP, ViewConfig.COL_RES_MP)
	_bar(2, _ep, Config.MAX_ENERGY, ViewConfig.COL_RES_EP)

func _bar(row: int, val: float, maxv: int, col: Color) -> void:
	var y := row * (BAR_H + GAP)
	var track := Rect2(0.0, y, TRACK_W, BAR_H)
	draw_rect(track, ViewConfig.COL_RES_BG)                             # empty track = the total
	var frac := clampf(val / float(maxv), 0.0, 1.0)
	if frac > 0.0:
		draw_rect(Rect2(0.0, y, TRACK_W * frac, BAR_H), col)           # coloured = availability
	draw_rect(track, ViewConfig.COL_RES_OUTLINE, false, 1.0)           # crisp outline
	draw_string(ThemeDB.fallback_font, Vector2(TRACK_W + NUM_GAP, y + BAR_H),
		"%d" % int(round(val)), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT, col)
