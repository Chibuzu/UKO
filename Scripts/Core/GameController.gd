# GameController.gd
# Match ORCHESTRATOR: builds the scene, runs the turn loop, and owns the two
# systems it delegates to -- SelectionController (player input/targeting) and
# ReplayController (record + end-of-match replay). It holds the Godot wiring
# (nodes, signals, the loop) so the systems stay pure logic; new systems/features
# get their own script and are instantiated + wired here.
extends Node

# The player's loadout is whatever they've bought and equipped in the shop
# (PlayerProfile.loadout()); an ungeared player is white with no spells. The AI
# always fights fully kitted.
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
var _shift_notes: Array = []   # this turn's rotation/crush log lines, recorded for replay

var selection: SelectionController   # player input / targeting system
var replay: ReplayController         # record + replay system
var end_screen: EndScreen
var opponent: OpponentSource         # AI or remote human -- swap this for online play

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
	a.equip(PlayerProfile.loadout())
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
	if opponent == null:
		opponent = AIOpponent.new(difficulty, get_tree())   # offline default; a lobby swaps in NetworkOpponent
	while true:
		turn_num += 1
		_shift_notes.clear()
		if turn_num > 1 and (turn_num - 1) % Config.MAP_ROTATE_EVERY == 0:
			_rotate_map()
		_update_shift_telegraph()
		_begin_turn()
		var seq_a: Array = await selection.player_sequence_ready
		menu.set_state(a, b, false, a.spell_ids(), [], false, true)   # confirmed -> waiting for opponent
		board.clear_highlights()

		var pre_a := a.clone()   # snapshot the turn's START state for the replay
		var pre_b := b.clone()
		# The opponent's plan comes from the seam: the AI (which absorbs the repaint
		# yield) offline, or a remote human online. The loop doesn't know which.
		var seq_b: Array = await opponent.opponent_sequence(b, a, grid, turn_num, seq_a, opp_model)
		var out := Resolver.resolve(grid, a, b, seq_a, seq_b, turn_num)
		opp_model.observe(seq_a)   # learn what A actually did, for next turn's prediction
		replay.record(turn_num, pre_a, pre_b, out["a"], out["b"], out["events"], grid.snapshot(), _shift_notes.duplicate(true))
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

# Every MAP_ROTATE_EVERY turns the arena's four quadrants shift one step clockwise:
# walls reposition around the
# (stationary) fighters. A wall that would land on a fighter is suppressed and that
# fighter takes crush damage instead; the grid then repairs connectivity if the
# rotation stranded them. Naive to the AI (it plans each turn's board, not ahead).
func _rotate_map() -> void:
	var crushed := grid.rotate_blockers([a.pos, b.pos])
	for p in crushed:
		var who: Combatant = a if p == a.pos else b
		who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)   # avoidable + telegraphed -> non-lethal cap
		who.rest_ready = false                                # took damage -> no REST next turn
		_log_shift("%s crushed by a shifting wall (-%d)" % [who.id, Config.MAP_CRUSH_DAMAGE], ViewConfig.COL_WIN_B)
	_log_shift("-- QUADRANTS SHIFT --", ViewConfig.COL_TEXT)
	board.queue_redraw()   # walls moved; repaint the arena
	board.earthquake()     # rumble + trembling walls to sell the shift

# Push a shift/crush line to the live log AND remember it for this turn, so the
# replay reproduces it (these lines live outside the turn's resolved events).
func _log_shift(text: String, color: Color) -> void:
	combat_log._push(text, color)
	_shift_notes.append({"text": text, "color": color})

# Telegraph: on the turn BEFORE a shift, ghost the tiles that will become walls so
# the player can step clear (keeps the crush damage avoidable, not RNG). The next
# turn shifts when turn_num is a multiple of MAP_ROTATE_EVERY.
func _update_shift_telegraph() -> void:
	if turn_num % Config.MAP_ROTATE_EVERY == 0:
		board.set_ghost(grid.incoming_walls())
		combat_log._push("Quadrants shift next turn -- amber tiles become walls", ViewConfig.COL_DRAW)
	else:
		board.clear_ghost()

# ── End screen ────────────────────────────
func _show_result(result: String) -> void:
	var text := "DRAW"
	var color := ViewConfig.COL_DRAW
	var reward := Config.GOLD_REWARD_DRAW
	if result == "a_wins":
		text = "A WINS"
		color = ViewConfig.COL_WIN_A
		reward = Config.gold_reward(difficulty)   # player beat the AI -> purse by tier
	elif result == "b_wins":
		text = "B WINS"
		color = ViewConfig.COL_WIN_B
		reward = 0                                 # the AI won; no payout
	var balance := PlayerProfile.gold()
	if reward > 0:
		balance = PlayerProfile.add_gold(reward)   # bank it (persists to disk)
	var es := EndScreen.new()
	add_child(es)
	es.setup(text, color, reward, balance)
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
