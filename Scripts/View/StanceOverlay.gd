# StanceOverlay.gd
# The clash sub-round (Fra's spec, round 11): both fighters lunged for the same
# tile, so the board dims and the player picks the stance that decides the
# collision. PUSH beats PULL, PULL beats FEINT, FEINT beats PUSH; the same
# stance bounces both back (-10 energy each). Emits `choice` with
# "push" / "pull" / "feint"; GameController awaits it before resolving.
class_name StanceOverlay
extends ChoiceOverlay

const BTN_W := 380
const BTN_H := 54
const GAP := 12

func _init() -> void:
	_buttons = [
		{"id": "push", "label": "PUSH -- shove through. Beats PULL: tile + damage"},
		{"id": "pull", "label": "PULL -- grab and yank. Beats FEINT: tile + swap"},
		{"id": "feint", "label": "FEINT -- bait the charge. Beats PUSH: foe staggered"},
	]

func _btn_rect(i: int, vp: Vector2) -> Rect2:
	var total_h := _buttons.size() * BTN_H + (_buttons.size() - 1) * GAP
	var x := vp.x * 0.5 - BTN_W * 0.5
	var y := vp.y * 0.56 - total_h * 0.5 + i * (BTN_H + GAP)
	return Rect2(x, y, BTN_W, BTN_H)

func _draw_content(vp: Vector2, font: Font) -> void:
	draw_string(font, Vector2(0, vp.y * 0.24), "CLASH!",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 52, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, vp.y * 0.32), "Both fighters lunge for the same tile.",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 22, ViewConfig.COL_TEXT)
	draw_string(font, Vector2(0, vp.y * 0.365), "Choose your stance -- the same stance bounces both back.",
		HORIZONTAL_ALIGNMENT_CENTER, vp.x, 18, ViewConfig.COL_TEXT)

func _consumes_click() -> bool:
	return true   # a stance click must never fall through to the board
