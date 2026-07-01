# QuestKind.gd
# Base class for a STORY QUEST's behavior -- the quest analogue of MobKind. Every quest type
# is a subclass that overrides a few hooks; identity (title / giver / target count / reward)
# is pure data read from the QuestBook def, so a new quest is one entry in QuestBook plus, if
# its tracking is genuinely new, one small subclass here + one line in QuestBook.make_quest.
# The controller feeds world events (on_kill / on_gather / on_rest_found) to every active
# quest, persists each quest's save_state() to PlayerQuests, and offers a hand-in at the NPC
# when can_turn_in() is true. Nothing here touches the combat engine.
#
# Override points, in the order you'll usually reach for them:
#   progress(), the on_* hook(s) it cares about, save_state()/load_state(), and -- only if
#   the hand-in isn't just "grant the reward" -- can_turn_in()/grant_reward().
class_name QuestKind
extends RefCounted

var id: String = ""
var def: Dictionary = {}

func setup(p_id: String, p_def: Dictionary) -> void:
	id = p_id
	def = p_def

# ── identity (data-driven; rarely overridden) ─────────────────────────────────
func title() -> String:
	return String(def.get("title", id))

func giver() -> String:
	return String(def.get("npc", ""))

func summary() -> String:
	return String(def.get("desc", ""))

func target_count() -> int:
	return int(def.get("count", 1))

# ── progress (override per kind) ──────────────────────────────────────────────
# How far along the quest is, in the same units as target_count().
func progress() -> int:
	return 0

func progress_text() -> String:
	return "%d / %d" % [mini(progress(), target_count()), target_count()]

func is_complete() -> bool:
	return progress() >= target_count()

# Can the player hand this in at the NPC right now? Default: it's complete. FetchQuest also
# requires the items to still be in the bag at hand-in time.
func can_turn_in() -> bool:
	return is_complete()

# ── event hooks (override only the ones a kind cares about) ───────────────────
func on_kill(_mob_type: String) -> void:
	pass

func on_gather(_material_id: String) -> void:
	pass

func on_rest_found(_tile: Vector2i) -> void:
	pass

# ── reward + persistence ──────────────────────────────────────────────────────
# Pay out on hand-in: gold via PlayerProfile, item rewards via PlayerInventory. FetchQuest
# overrides to first CONSUME the delivered items, then calls back into this via super.
func grant_reward() -> void:
	var rw: Dictionary = def.get("reward", {})
	var gold := int(rw.get("gold", 0))
	if gold > 0:
		PlayerProfile.add_gold(gold)
	var items: Dictionary = rw.get("items", {})
	for item in items:
		PlayerInventory.add(String(item), int(items[item]))

# A tiny dict persisted per active quest in PlayerQuests. Kinds that track counts/sets
# override both; kinds whose progress is derived live (FetchQuest) leave these empty.
func save_state() -> Dictionary:
	return {}

func load_state(_state: Dictionary) -> void:
	pass
