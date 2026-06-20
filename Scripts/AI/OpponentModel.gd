# OpponentModel.gd
# Tracks what the opponent ACTUALLY does, so the AI can adapt instead of forever
# assuming they'll play the move that's theoretically best for them. It's a
# recency-weighted tally of action categories -> frequency.
#
# Modular by design: GameController owns one instance per match and feeds it the
# foe's real moves (observe); HardAI reads freq() to bias its prediction of the
# foe. Nothing else depends on it, and a null model just means "no history yet".
class_name OpponentModel
extends RefCounted

const DECAY := 0.6   # each turn, old observations keep this fraction (recency bias)

var _w: Dictionary = {}    # category -> decayed weight
var _total: float = 0.0

# Record the categories in the foe's actual chosen sequence for this turn.
func observe(seq: Array) -> void:
	for k in _w:
		_w[k] = float(_w[k]) * DECAY
	_total *= DECAY
	for action in seq:
		var cat := category_of(action)
		if cat == "":
			continue
		_w[cat] = float(_w.get(cat, 0.0)) + 1.0
		_total += 1.0

# Recent frequency of a category in [0,1]; 0 if nothing relevant seen yet.
func freq(category: String) -> float:
	if _total <= 0.0:
		return 0.0
	return float(_w.get(category, 0.0)) / _total

# Enough history to be worth trusting (cold-start guard for turn 1).
func is_warm() -> bool:
	return _total >= 1.0

# Map an action to the category the model tallies (spells collapse to "spell").
static func category_of(action: Dictionary) -> String:
	var id: String = action.get("id", "")
	if id == "" or id == "_noop":
		return ""
	if Config.is_spell(id):
		return "spell"
	return String(Config.def(id).get("category", ""))
