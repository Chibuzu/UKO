# CameraRig.gd
# The story camera: a VIEW_TILES-square window over the world with the classic
# tile-RPG edge-scroll follow — the player moves freely inside a centered
# deadzone, and the window slides only when they push within EDGE tiles of its
# border. Pure position policy: this owns WHERE the window is, never what
# becomes visible — StoryController applies visibility to its own entities from
# `win` (its _apply_window). First extraction of the StoryController split
# (HANDOFF next-steps item: CameraRig → NpcDirector → GatherDirector → …).
class_name CameraRig
extends RefCounted

const EDGE := 3                   # deadzone: scroll only when this close to the border

var win: Vector2i = Vector2i.ZERO # current top-left world tile of the visible window

func _limit() -> int:
	return OverworldMap.SIZE - ViewConfig.VIEW_TILES

# Start centered on `p` (clamped so the window stays inside the world).
func center_on(p: Vector2i) -> void:
	var lim := _limit()
	win = Vector2i(
		clampi(p.x - ViewConfig.VIEW_RADIUS, 0, lim),
		clampi(p.y - ViewConfig.VIEW_RADIUS, 0, lim))

# Edge-scroll follow: on open ground you watch yourself walk across the board;
# the world scrolls only at the margins.
func follow(p: Vector2i) -> void:
	var lim := _limit()
	win = Vector2i(
		_axis(p.x, win.x, lim),
		_axis(p.y, win.y, lim))

func _axis(p: int, cur: int, lim: int) -> int:
	var lo := cur + EDGE
	var hi := cur + ViewConfig.VIEW_TILES - 1 - EDGE
	var o := cur
	if p < lo:
		o = cur - (lo - p)
	elif p > hi:
		o = cur + (p - hi)
	return clampi(o, 0, lim)

# Is world tile `p` inside the current window?
func contains(p: Vector2i) -> bool:
	return p.x >= win.x and p.x < win.x + ViewConfig.VIEW_TILES \
		and p.y >= win.y and p.y < win.y + ViewConfig.VIEW_TILES
