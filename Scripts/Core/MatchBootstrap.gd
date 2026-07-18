# MatchBootstrap.gd
# THE one channel for cross-scene match handoff. Every value a new Game scene
# needs from whoever launched it (the menu today) travels through here --
# nothing else may smuggle state across a scene change via foreign statics.
#
# Two kinds of field, on purpose:
#   * difficulty PERSISTS across matches -- a rematch (scene reload) keeps the
#     tier the player picked on the menu.
#   * pending_config/pending_opponent are CONSUMED by GameController._ready via
#     take_*() -- a later single-player match must never inherit an online
#     session's config or a stale opponent.
class_name MatchBootstrap
extends RefCounted

# Persistent: picked on the menu's difficulty page, read at every match start.
static var difficulty: int = AI.Difficulty.CHALLENGING

# Consumed: null -> offline single-player defaults (AI opponent, random seed).
static var pending_config: MatchConfig = null
static var pending_opponent: OpponentSource = null

# The lobby's handoff: both sides hold an identical MatchConfig; the opponent
# wraps the live session. Call right before change_scene_to_file(Game.tscn).
static func start_online(config: MatchConfig, opponent: OpponentSource) -> void:
	pending_config = config
	pending_opponent = opponent

static func take_config() -> MatchConfig:
	var c := pending_config
	pending_config = null
	return c

static func take_opponent() -> OpponentSource:
	var o := pending_opponent
	pending_opponent = null
	return o
