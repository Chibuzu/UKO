# ReplayController.gd
# The end-of-match replay SYSTEM: records every resolved turn and, on request,
# steps/plays them back on the live board, unit views, EventPlayer and CombatLog.
# Owns NO game rules and NO turn loop -- GameController feeds it each resolved turn
# via record() and calls enter() from the end screen. Replay features (e.g. a
# resource readout per turn) belong here, on top of this system.
class_name ReplayController
extends Node

var board: BoardView
var play: EventPlayer
var combat_log: CombatLog
var menu: ActionMenu
var ua: UnitView
var ub: UnitView

var match_record := MatchRecord.new()   # every resolved turn, for end-of-match replay
var end_screen: EndScreen                # borrowed from GameController, to hide/restore
var replay_bar: ReplayBar
var replay_idx := 0

# Wire the system to the live scene objects (called once by GameController).
func setup(p_board: BoardView, p_play: EventPlayer, p_log: CombatLog,
		p_menu: ActionMenu, p_ua: UnitView, p_ub: UnitView) -> void:
	board = p_board
	play = p_play
	combat_log = p_log
	menu = p_menu
	ua = p_ua
	ub = p_ub

# Log a resolved turn for later playback.
func record(turn: int, pre_a: Combatant, pre_b: Combatant,
		post_a: Combatant, post_b: Combatant, events: Array,
		layout: Array = [], notes: Array = []) -> void:
	match_record.add(turn, pre_a, pre_b, post_a, post_b, events, layout, notes)

# Restore the wall layout recorded for a turn (and clear the live telegraph), so a
# replayed turn shows its own arena, not the match's final layout.
func _restore_layout(t: Dictionary) -> void:
	if board.grid and not t.get("layout", []).is_empty():
		board.grid.restore(t["layout"])
	board.clear_ghost()
	board.queue_redraw()

# Begin replay (called from the end screen, which is borrowed to hide/restore).
func enter(p_end_screen: EndScreen) -> void:
	end_screen = p_end_screen
	_enter_replay()

# ── End-of-match replay ─────────────────────────────────────
# Step the finished match turn by turn. Reuses the live board, unit views,
# EventPlayer and CombatLog; nothing new renders. Stepping snaps to a turn's
# end state; PLAY re-animates that turn from its start.
func _enter_replay() -> void:
	if match_record.size() == 0:
		return
	if end_screen:
		end_screen.visible = false
		end_screen.set_process_input(false)   # hidden screens still eat clicks otherwise
	menu.visible = false
	board.clear_highlights()
	replay_bar = ReplayBar.new()
	add_child(replay_bar)
	replay_bar.replay_action.connect(_on_replay_action)
	_replay_show(0)

func _on_replay_action(which: String) -> void:
	match which:
		"prev":
			_replay_show(replay_idx - 1)
		"next":
			_replay_show(replay_idx + 1)
		"play":
			await _replay_play_current()
		"exit":
			_exit_replay()

# Arrow keys step between turns while the replay is open (LEFT = prev, RIGHT = next).
# Ignored while a turn is animating (the bar is disabled) so a keypress can't desync.
func _unhandled_input(event: InputEvent) -> void:
	if replay_bar == null or not replay_bar._enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_LEFT:
			get_viewport().set_input_as_handled()
			_replay_show(replay_idx - 1)
		elif event.keycode == KEY_RIGHT:
			get_viewport().set_input_as_handled()
			_replay_show(replay_idx + 1)

# Jump to a turn: snap the board to its END state and show the log through it.
func _replay_show(idx: int) -> void:
	replay_idx = clampi(idx, 0, match_record.size() - 1)
	var t := match_record.get_turn(replay_idx)
	_restore_layout(t)
	board.clear_highlights()
	ua.set_state(t["post_a"])
	ub.set_state(t["post_b"])
	_rebuild_log_through(replay_idx)
	replay_bar.set_label("TURN %d / %d" % [t["turn"], match_record.size()])
	replay_bar.set_stats(t["post_a"], t["post_b"])   # resources as of this turn's end

# Re-animate the current turn from its START state, so you watch the actual plays.
func _replay_play_current() -> void:
	var t := match_record.get_turn(replay_idx)
	_restore_layout(t)
	replay_bar.set_enabled(false)
	board.clear_highlights()
	ua.set_state(t["pre_a"])
	ub.set_state(t["pre_b"])
	replay_bar.set_stats(t["pre_a"], t["pre_b"])     # resources entering the turn
	await play.play(t["events"], t["post_a"], t["post_b"])
	replay_bar.set_stats(t["post_a"], t["post_b"])   # ...and after it resolves
	replay_bar.set_enabled(true)

func _exit_replay() -> void:
	if replay_bar:
		replay_bar.queue_free()
		replay_bar = null
	var last := match_record.get_turn(match_record.size() - 1)
	_restore_layout(last)
	ua.set_state(last["post_a"])
	ub.set_state(last["post_b"])
	_rebuild_log_through(match_record.size() - 1)
	if end_screen:
		end_screen.visible = true
		end_screen.set_process_input(true)

func _rebuild_log_through(idx: int) -> void:
	combat_log.clear()
	for i in range(idx + 1):
		var t := match_record.get_turn(i)
		for note in t.get("notes", []):
			combat_log._push(note["text"], note["color"])   # shift/crush lines precede the turn
		combat_log.add_turn(t["turn"], t["events"])
