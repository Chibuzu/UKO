# OpponentModel.gd
# Tracks what the opponent ACTUALLY does, so the AI can adapt instead of forever
# assuming they'll play the move that's theoretically best for them.
#
# v2: observations are bucketed by SITUATION (their hp/energy bands, distance,
# flank exposure, hurt) -- "he guards 70% when flanked at low HP" instead of "he
# guards 40% overall" -- with the old global tally kept as the cold-bucket
# fallback. The model also persists to disk between matches (it learns YOU across
# sessions) and reports a confidence the brain uses to scale its exploitation.
class_name OpponentModel
extends RefCounted

const DECAY := 0.6                       # recency bias inside a tally
const SAVE_PATH := "user://uko_opp_model.cfg"
const WARM_BUCKET := 3.0                 # bucket observations before it overrides the global read

var _w: Dictionary = {}                  # global: category -> decayed weight
var _total: float = 0.0
var _buckets: Dictionary = {}            # situation -> {"w": Dictionary, "total": float}

# Record the categories in the foe's actual chosen sequence, under its situation.
func observe(seq: Array, sit: String = "") -> void:
	for k in _w:
		_w[k] = float(_w[k]) * DECAY
	_total *= DECAY
	var bk: Dictionary = {}
	if sit != "":
		if not _buckets.has(sit):
			_buckets[sit] = {"w": {}, "total": 0.0}
		bk = _buckets[sit]
		for k in bk["w"]:
			bk["w"][k] = float(bk["w"][k]) * DECAY
		bk["total"] = float(bk["total"]) * DECAY
	for action in seq:
		var cat := category_of(action)
		if cat == "":
			continue
		_w[cat] = float(_w.get(cat, 0.0)) + 1.0
		_total += 1.0
		if sit != "":
			bk["w"][cat] = float(bk["w"].get(cat, 0.0)) + 1.0
			bk["total"] = float(bk["total"]) + 1.0

# Frequency of a category: the situation bucket when it's warm, else the global tally.
func freq(category: String, sit: String = "") -> float:
	if sit != "" and _buckets.has(sit) and float(_buckets[sit]["total"]) >= WARM_BUCKET:
		return float(_buckets[sit]["w"].get(category, 0.0)) / float(_buckets[sit]["total"])
	if _total <= 0.0:
		return 0.0
	return float(_w.get(category, 0.0)) / _total

func is_warm() -> bool:
	return _total >= 1.0

# How much history backs the read, 0..1: the brain scales its exploitation tilt by
# this, so a thin model tilts a little and a thick one tilts the full bounded amount.
func confidence() -> float:
	return minf(1.0, _total / 12.0)

static func category_of(action: Dictionary) -> String:
	var id: String = action.get("id", "")
	if id == "" or id == "_noop":
		return ""
	if Config.is_spell(id):
		return "spell"
	return String(Config.def(id).get("category", ""))

# The situation `actor` is choosing in, against `other` -- the bucket key. Coarse on
# purpose: hp band, energy band, distance band, which flank the foe holds, and hurt
# (rest denied). Coarse buckets fill fast; fine ones would never get warm.
static func situation_of(actor: Combatant, other: Combatant, grid: Grid) -> String:
	var hp := "L" if actor.hp < 40 else ("H" if actor.hp > 70 else "M")
	var en := "L" if actor.energy < 30 else ("H" if actor.energy >= 70 else "M")
	var dist := Grid.dist(actor.pos, other.pos)
	var d := "adj" if dist <= 1 else ("near" if dist <= 2 else "far")
	var f := String(Config.flank_tier(actor.facing, actor.pos, other.pos))
	var hurt := 0 if actor.rest_ready else 1
	return "h%s|e%s|d%s|f%s|w%d" % [hp, en, d, f, hurt]

# Relative likelihood the foe plays a sequence with these categories.
func weight_of(seq: Array, sit: String = "") -> float:
	if not is_warm():
		return 1.0
	var sum := 0.0
	var n := 0
	for action in seq:
		var cat := category_of(action)
		if cat == "":
			continue
		sum += freq(cat, sit) + 0.05
		n += 1
	if n == 0:
		return 0.05
	return sum / float(n)

# ── persistence: the model survives between matches ──────────────────────────
func save_disk() -> void:
	var cf := ConfigFile.new()
	cf.set_value("global", "w", _w)
	cf.set_value("global", "total", _total)
	for sit in _buckets:
		cf.set_value("buckets", sit, _buckets[sit])
	cf.save(SAVE_PATH)

func load_disk() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	_w = cf.get_value("global", "w", {})
	_total = float(cf.get_value("global", "total", 0.0))
	_buckets = {}
	if cf.has_section("buckets"):
		for sit in cf.get_section_keys("buckets"):
			_buckets[sit] = cf.get_value("buckets", sit)
