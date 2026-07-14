# SerpentKind.gd
# The two-tile cave boss. Its body occupies exactly TWO tiles -- `origin` (passed in)
# and `tail` (set each turn by StoryController). Both tiles are HEADS: it has no
# front/back, and it strikes the tile ONE step beyond EACH head, straight out along
# the body axis. So the two threatened tiles sit at the very ends of the 2-tile body:
#   vertical body   -> one tile above the top head, one tile below the bottom head
#   horizontal body -> one tile left of the left head, one right of the right head
# Movement is the base melee walk (chase); only the strike pattern is special.
class_name SerpentKind
extends MobKind

var tail: Vector2i = Vector2i(-99, -99)   # the body's second tile; set per-turn by the controller

func attack_pattern(origin: Vector2i) -> Array:
	if tail == Vector2i(-99, -99) or tail == origin:
		return cardinal_ring(origin, 1)          # unknown tail: bite all neighbors as a fallback
	# The two heads are `origin` and `tail`. Each strikes one tile straight out, away
	# from the other head -- i.e. extending the body line past each end.
	var axis := Vector2i(signi(origin.x - tail.x), signi(origin.y - tail.y))  # tail -> origin
	return [origin + axis, tail - axis]
