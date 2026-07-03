# GameController.gd
# Match ORCHESTRATOR: builds the scene, runs the turn loop, and owns the two
# systems it delegates to -- SelectionController (player input/targeting) and
# ReplayController (record + end-of-match replay). It holds the Godot wiring
# (nodes, signals, the loop) so the systems stay pure logic; new systems/features
# get their own script and are instantiated + wired here.
class_name GameController
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
var hud_a: ResourceHUD          # your HP/MP/EP bars
var hud_b: ResourceHUD          # opponent's HP/MP/EP bars
var a: Combatant
var b: Combatant
var turn_num := 0
var _shift_notes: Array = []   # this turn's rotation/crush log lines, recorded for replay

var selection: SelectionController   # player input / targeting system
var replay: ReplayController         # record + replay system
var end_screen: EndScreen
var opponent: OpponentSource         # AI or remote human -- swap this for online play
var match_config: MatchConfig        # map seed + loadouts + which side is local

# Lobby handoff: set these before change_scene_to_file(game) and _ready consumes them.
# Null -> single-player defaults. (static so they survive the scene change.)
static var pending_config: MatchConfig
static var pending_opponent: OpponentSource

# Story/overworld hooks (single-player): a custom B loadout (a mob's kit), where to
# return when the match ends, and the last result -- so the overworld can hand off a
# mob duel and read the outcome back. Empty/"" -> normal (AI gear, return to menu).
static var pending_b_gear: Array = []
static var pending_return_scene: String = ""
static var last_match_won: bool = false

# Pin the base (1152x648) to a keep-aspect canvas so it's always centred in the window, then, if the
# window is taller/wider than the usable screen (its bottom clipped by the title bar/taskbar -- which
# reads as "more space above the board than below"), shrink it to the largest 16:9 that fits and
# re-centre it on screen. Done in code so it applies even when project.godot isn't copied across.
func _center_display() -> void:
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	w.content_scale_size = Vector2i(1152, 648)
	if w.mode != Window.MODE_WINDOWED:
		return                              # maximised/fullscreen: the WM fits it; keep-aspect centres the base
	# Windowed: if the window is taller/wider than the usable screen (title bar/taskbar would clip
	# its bottom), shrink to the largest 16:9 that fits and re-centre it near the top of the screen.
	var usable := DisplayServer.screen_get_usable_rect(w.current_screen)
	var max_h := usable.size.y - 40         # leave headroom for the title bar
	if w.size.y > max_h or w.size.x > usable.size.x:
		var s: float = minf(float(usable.size.x) / 1152.0, float(max_h) / 648.0)
		w.size = Vector2i(int(round(1152.0 * s)), int(round(648.0 * s)))
	w.position = usable.position + Vector2i(int((usable.size.x - w.size.x) / 2), 24)

func _ready() -> void:
	_center_display()   # base is centred in the window regardless of project.godot / window size
	difficulty = AI.selected_difficulty   # whatever the menu's difficulty page picked
	# Lobby handoff (set before the scene change). Null -> single-player vs the AI.
	match_config = pending_config
	opponent = pending_opponent
	pending_config = null      # consume: a later single-player match must not inherit these
	pending_opponent = null
	var b_gear_override: Array = pending_b_gear
	pending_b_gear = []        # consume: a later match must not inherit a story mob's kit

	var rng := RandomNumberGenerator.new()
	if match_config != null:
		rng.seed = match_config.map_seed   # both clients seed identically -> same arena + rotations
	else:
		rng.randomize()
	grid = Grid.new()
	grid.generate(rng)

	board = BoardView.new()
	add_child(board)
	board.setup(grid)
	# Back chrome: grey background + the two full-height side panel frames. Added right after the
	# board node but moved behind it so the board (added above) renders on top of the grey.
	var frame_back := UIFrame.new()
	add_child(frame_back)
	frame_back.z_index = -10

	# Sides are FIXED: a == A, b == B on every client, so the deterministic Resolver
	# is always called in the same order. Which side the LOCAL player drives is
	# match_config.local_is_a; that changes input/menu wiring only, never the slots.
	a = Combatant.new("A", grid.spawn_a, Config.Facing.EAST)
	b = Combatant.new("B", grid.spawn_b, Config.Facing.WEST)
	if match_config != null:
		print("[MP] loadout_a=", match_config.loadout_a, " loadout_b=", match_config.loadout_b)
		a.equip(match_config.loadout_a)
		b.equip(match_config.loadout_b)
	else:
		a.equip(PlayerProfile.loadout())   # offline: your shop gear vs the AI's (or a story mob's) kit
		b.equip(AI_GEAR if b_gear_override.is_empty() else b_gear_override)

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

	# Front chrome: the inset board frame, drawn on top of the board (a window it shakes within).
	var frame_front := UIFrame.new()
	frame_front.front = true
	add_child(frame_front)

	menu = ActionMenu.new()
	add_child(menu)

	combat_log = CombatLog.new()
	add_child(combat_log)

	# Resource bars: yours top-left, the opponent's above the log. (These sit at the top strip
	# for now; they move into the side panels when the framed layout lands.)
	hud_a = ResourceHUD.new()
	add_child(hud_a)
	hud_a.position = Vector2(ViewConfig.PANEL_LEFT.position.x + 40, ViewConfig.PANEL_LEFT.position.y + 12)
	hud_a.bind(a if _local_is_a() else b)
	hud_b = ResourceHUD.new()
	add_child(hud_b)
	hud_b.position = Vector2(ViewConfig.PANEL_RIGHT.position.x + 20, ViewConfig.PANEL_RIGHT.position.y + 12)
	hud_b.bind(b if _local_is_a() else a)

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

# Side mapping. a/b are always A/B; these say which one the LOCAL player drives.
# Single-player (no config) -> local is A, exactly as before. They read the live
# a/b each call, so they stay correct after the per-turn a = out["a"] reassignment.
func _local_is_a() -> bool:
	return match_config == null or match_config.local_is_a

func _local() -> Combatant:
	return a if _local_is_a() else b

func _foe() -> Combatant:
	return b if _local_is_a() else a

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
		var local_plan: Array = await _await_local_plan()
		menu.set_state(_local(), _foe(), false, _local().spell_ids(), [], false, true)   # confirmed -> waiting for opponent
		board.clear_highlights()

		var pre_a := a.clone()   # snapshot the turn's START state for the replay (A/B, fixed)
		var pre_b := b.clone()
		# The opponent's plan comes from the seam: the AI (which absorbs the repaint
		# yield) offline, or a remote human online. The loop doesn't know which.
		var opponent_plan: Array = await opponent.opponent_sequence(_foe(), _local(), grid, turn_num, local_plan, opp_model)
		if opponent.aborted():
			_end_disconnected()   # remote peer left -> no reveal is coming; stop, don't hang
			return
		# Resolve in the FIXED A/B order on every client; map local/opponent into the
		# right slots so the host (local=A) and client (local=B) feed identical args.
		var seq_a: Array = local_plan if _local_is_a() else opponent_plan
		var seq_b: Array = opponent_plan if _local_is_a() else local_plan
		var out := Resolver.resolve(grid, a, b, seq_a, seq_b, turn_num)
		opp_model.observe(local_plan)   # the AI models its foe (the local player) -> learn their move
		replay.record(turn_num, pre_a, pre_b, out["a"], out["b"], out["events"], grid.snapshot(), _shift_notes.duplicate(true))
		await play.play(out["events"], out["a"], out["b"])
		a = out["a"]
		b = out["b"]
		hud_a.refresh(a if _local_is_a() else b)
		hud_b.refresh(b if _local_is_a() else a)
		menu.set_state(_local(), _foe(), false, _local().spell_ids(), [], false)
		combat_log.add_turn(turn_num, out["events"])

		if out["result"] != "ongoing":
			_show_result(out["result"])
			return

func _begin_turn() -> void:
	selection.begin_turn(_local(), _foe())

# Online turn clock. Offline (vs the AI) there's no clock -- never rush the player and
# the AI can't stall. Online, an AFK player must not hang the opponent forever, so we
# race the player's confirm against a generous deadline and auto-submit a WAIT if it
# lapses. Both clients run this independently, so each side always commits in time and
# the mediator never waits indefinitely.
const MP_TURN_SECONDS := 60.0

func _await_local_plan() -> Array:
	if match_config == null:
		return await selection.player_sequence_ready
	var box := {"seq": null}
	var on_ready := func(seq: Array):
		if box["seq"] == null:
			box["seq"] = seq
	selection.player_sequence_ready.connect(on_ready, CONNECT_ONE_SHOT)
	var deadline := get_tree().create_timer(MP_TURN_SECONDS)
	while box["seq"] == null and deadline.time_left > 0.0:
		await get_tree().process_frame
	if selection.player_sequence_ready.is_connected(on_ready):
		selection.player_sequence_ready.disconnect(on_ready)
	return box["seq"] if box["seq"] != null else [{"id": "wait"}]

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
	last_match_won = false
	if result == "a_wins" or result == "b_wins":
		var a_won := result == "a_wins"
		text = "A WINS" if a_won else "B WINS"
		color = ViewConfig.COL_WIN_A if a_won else ViewConfig.COL_WIN_B
		# Gold is a single-player progression reward for beating the AI. Online play
		# mints nothing (no farming), so a PvP result pays 0 regardless of who won.
		var local_won := a_won == _local_is_a()
		last_match_won = local_won
		reward = Config.gold_reward(difficulty) if (local_won and match_config == null) else 0
	var balance := PlayerProfile.gold()
	if reward > 0:
		balance = PlayerProfile.add_gold(reward)   # bank it (persists to disk)
	var es := EndScreen.new()
	add_child(es)
	es.setup(text, color, reward, balance)
	es.choice.connect(_on_end_choice)
	end_screen = es

# Remote peer dropped mid-match: show a no-contest card (no gold either way) reusing
# the normal end screen, so the player returns to the menu instead of a frozen board.
func _end_disconnected() -> void:
	var es := EndScreen.new()
	add_child(es)
	es.setup("OPPONENT LEFT", ViewConfig.COL_DRAW, 0, PlayerProfile.gold())
	es.choice.connect(_on_end_choice)
	end_screen = es

func _on_end_choice(which: String) -> void:
	match which:
		"rematch":
			get_tree().reload_current_scene()      # fresh match, same scene
		"menu":
			var dest := pending_return_scene if pending_return_scene != "" else MENU_SCENE
			pending_return_scene = ""    # consume: normal matches return to the menu
			get_tree().change_scene_to_file(dest)
		"replay":
			replay.enter(end_screen)
