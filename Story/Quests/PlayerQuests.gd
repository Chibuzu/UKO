# PlayerQuests.gd
# The player's persistent QUEST LOG, saved to user://quests.cfg. Same static-carrier pattern
# as PlayerInventory / PlayerProfile: it lazy-loads on first touch and saves on every change,
# so the controller can read/write it without an autoload. It stores only ids + a tiny state
# dict per active quest (progress); the live QuestKind objects are rebuilt from these by
# QuestBook.make_quest + load_state. Like the inventory, quest progress is PERMANENT -- it is
# not rewound by a story-snapshot reload (consistent with how looted items persist).
class_name PlayerQuests
extends RefCounted

const SAVE_PATH := "user://quests.cfg"

static var _active: Dictionary = {}     # quest_id -> state dict (progress)
static var _done: Dictionary = {}       # quest_id -> true
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		_active = cf.get_value("quests", "active", {}).duplicate(true)
		_done = cf.get_value("quests", "done", {}).duplicate(true)

static func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("quests", "active", _active)
	cf.set_value("quests", "done", _done)
	cf.save(SAVE_PATH)

static func is_active(quest_id: String) -> bool:
	_ensure_loaded()
	return _active.has(quest_id)

static func is_done(quest_id: String) -> bool:
	_ensure_loaded()
	return _done.has(quest_id)

static func active_ids() -> Array:
	_ensure_loaded()
	return _active.keys()

# Take on a quest (no-op if already active or already completed).
static func accept(quest_id: String) -> void:
	_ensure_loaded()
	if not _active.has(quest_id) and not _done.has(quest_id):
		_active[quest_id] = {}
		_save()

static func state_of(quest_id: String) -> Dictionary:
	_ensure_loaded()
	return _active.get(quest_id, {})

# Persist a live quest's progress (only if it's active).
static func set_state(quest_id: String, st: Dictionary) -> void:
	_ensure_loaded()
	if _active.has(quest_id):
		_active[quest_id] = st
		_save()

# Hand-in: retire the quest to the completed set.
static func complete(quest_id: String) -> void:
	_ensure_loaded()
	_active.erase(quest_id)
	_done[quest_id] = true
	_save()

static func clear() -> void:
	_active = {}
	_done = {}
	_loaded = true
	_save()
