# UIFrame.gd
# The UI chrome, drawn in two layers so the board sits BETWEEN them:
#   back  (added before the board): the uniform grey background + the two full-height side
#         panel frames (action buttons left, combat log right).
#   front (added after the board):  the inset board frame, so it reads as a window the live
#         board renders inside.
# Crisp straight purple borders, matching the reference exactly. The board rectangle is left
# transparent -- the live 12x12 board, figures and effects render there. Pure decoration.
class_name UIFrame
extends Node2D

const LINE_W := 3.0                  # crisp border thickness

@export var front: bool = false      # false = grey bg + side frames; true = center board frame

func _draw() -> void:
	if front:
		draw_rect(ViewConfig.BOARD_FRAME, ViewConfig.COL_FRAME, false, LINE_W)
		return
	# Uniform grey background across the whole viewport, then the two side frames on top.
	draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), ViewConfig.COL_PANEL)
	draw_rect(ViewConfig.PANEL_LEFT, ViewConfig.COL_FRAME, false, LINE_W)
	draw_rect(ViewConfig.PANEL_RIGHT, ViewConfig.COL_FRAME, false, LINE_W)
