# GameController.gd
# Match ORCHESTRATOR: builds the scene, runs the turn loop, and owns the two
# systems it delegates to -- SelectionController (player input/targeting) and
# ReplayController (record + end-of-match replay). It holds the Godot wiring
# (nodes, signals, the loop) so the systems stay pure logic; new systems/features
# get their own script and are instantiated + wired here.
extends Node

const PLAYER_GEAR := ["discount_charm", "burst_node", "dark_focus", "blink_boots"]
const AI_GEAR := ["discount_charm", "burst_node", "dark_focus", "blink_boots"]
const MENU_SCENE := "res://MainMenu.tscn"   # adjust if your menu scene lives elsewhere

var difficulty: int = AI.Difficulty.CHALLENGING

var grid: Grid
var board: BoardView
var ua: UnitView
var ub: UnitView
var play: EventPlayer
var fx: Fx
var menu: ActionMenu
var combat_log: CombatLog
var a: Combatant
var b: Combatant
var turn_num := 0

var selection: SelectionController   # player input / targeting system
var replay: ReplayController         # record + replay system
var end_screen: EndScreen

func _ready() -> void:
	difficulty = AI.selected_difficulty   # whatever the menu's difficulty page picked
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	grid = Grid.new()
	grid.generate(rng)

	board = BoardView.new()
	add_child(board)
	board.setup(grid)

	a = Combatant.new("A", grid.spawn_a, Config.Facing.EAST)
	b = Combatant.new("B", grid.spawn_b, Config.Facing.WEST)
	a.equip(PLAYER_GEAR)
	b.equip(AI_GEAR)

	ua = UnitView.new()
	board.add_child(ua)
	ua.init_state(a)
	ub = UnitView.new()
	board.add_child(ub)
	ub.init_state(b)

	fx = Fx.new()
	board.add_child(fx)

	play = EventPlayer.new()
	add_child(play)
	play.setup(board, fx, ua, ub)

	menu = ActionMenu.new()
	add_child(menu)

	combat_log = CombatLog.new()
	add_child(combat_log)

	# Systems: pure-logic controllers this orchestrator owns and wires.
	selection = SelectionController.new()
	add_child(selection)
	selection.setup(grid, board, menu)
	board.tile_clicked.connect(selection._on_tile_clicked)
	board.selection_cancelled.connect(selection._on_cancel)
	menu.action_chosen.connect(selection._on_action_chosen)

	replay = ReplayController.new()
	add_child(replay)
	replay.setup(board, play, combat_log, menu, ua, ub)

	_game_loop()

func _game_loop() -> void:
	var opp_model := OpponentModel.new()   # learns player A's habits across this match
	while true:
		turn_num += 1
		if turn_num > 1 and (turn_num - 1) % Config.MAP_ROTATE_EVERY == 0:
			_rotate_map()
		_begin_turn()
		var seq_a: Array = await selection.player_sequence_ready
		menu.set_state(a, b, false, a.spell_ids(), [], false, true)   # confirmed -> waiting for opponent
		board.clear_highlights()

		var pre_a := a.clone()   # snapshot the turn's START state for the replay
		var pre_b := b.clone()
		# Yield two frames so the menu actually PAINTS "Waiting for opponent..." before
		# the synchronous AI search hogs the main thread -- otherwise the queued redraw
		# never reaches the screen until the search is already finished.
		await get_tree().process_frame
		await get_tree().process_frame
		var seq_b: Array = AI.choose_sequence(difficulty, b, a, grid, b.spell_ids(), opp_model)
		var out := Resolver.resolve(grid, a, b, seq_a, seq_b, turn_num)
		opp_model.observe(seq_a)   # learn what A actually did, for next turn's prediction
		replay.record(turn_num, pre_a, pre_b, out["a"], out["b"], out["events"])
		await play.play(out["events"], out["a"], out["b"])
		a = out["a"]
		b = out["b"]
		menu.set_state(a, b, false, a.spell_ids(), [], false)
		combat_log.add_turn(turn_num, out["events"])

		if out["result"] != "ongoing":
			_show_result(out["result"])
			return

func _begin_turn() -> void:
	selection.begin_turn(a, b)

# Every MAP_ROTATE_EVERY turns the arena spins 90: walls reposition around the
# (stationary) fighters. A wall that would land on a fighter is suppressed and that
# fighter takes crush damage instead; the grid then repairs connectivity if the
# rotation stranded them. Naive to the AI (it plans each turn's board, not ahead).
func _rotate_map() -> void:
	var crushed := grid.rotate_blockers([a.pos, b.pos])
	for p in crushed:
		var who: Combatant = a if p == a.pos else b
		who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)   # avoidable + telegraphed -> non-lethal cap
		who.rest_ready = false                                # took damage -> no REST next turn
		combat_log._push("%s crushed by a shifting wall (-%d)" % [who.id, Config.MAP_CRUSH_DAMAGE], ViewConfig.COL_WIN_B)
	combat_log._push("-- MAP ROTATES 90 --", ViewConfig.COL_TEXT)
	board.queue_redraw()   # walls moved; repaint the arena

# ── End screen ────────────────────────────
func _show_result(result: String) -> void:
	var text := "DRAW"
	var color := ViewConfig.COL_DRAW
	if result == "a_wins":
		text = "A WINS"
		color = ViewConfig.COL_WIN_A
	elif result == "b_wins":
		text = "B WINS"
		color = ViewConfig.COL_WIN_B
	var es := EndScreen.new()
	add_child(es)
	es.setup(text, color)
	es.choice.connect(_on_end_choice)
	end_screen = es

func _on_end_choice(which: String) -> void:
	match which:
		"rematch":
			get_tree().reload_current_scene()      # fresh match, same scene
		"menu":
			get_tree().change_scene_to_file(MENU_SCENE)
		"replay":
			replay.enter(end_screen)
