# OvernightSweep.gd -- DEPTH x BUDGET SWEEP + LEARNED-VALUE DATA HARVEST.
# Challenger (deeper look, bigger think-time) vs the current champion (d2@700ms):
#   PHASE 1  d3@1400  vs d2@700   -- does paid-for depth beat the champion?
#   PHASE 2  d4@2000  vs d2@700   -- and one notch further?
#   PHASE 3  d3@700   vs d2@700   -- depth at EQUAL time (isolates depth itself)
# EVERY turn of EVERY match also appends a training row to user://selfplay_cs.csv
# (state features + final outcome) -- the raw material for the learned value
# function (priority #5). Results append live to user://sweep_results.txt.
extends SceneTree

const FULL_GEAR := ["discount_charm", "burst_node", "blink_boots", "dark_focus"]
const MATCHES_PER_PHASE := 110   # ~10-12h total; interruption-safe (kill it when you're back, partials count)
const HARVEST_MATCHES := 450     # harvest mode: mirror champion selfplay, ~9-10h
const MAX_TURNS := 80          # cap -> draw (no zone stall runs forever)
const SEED_BASE := 770001
const OUT := "user://sweep_results.txt"
# v2: NEW-PHYSICS training data with the autopsy features (flank/pulse/lockout/cds).
# Never mixes with the old-rules selfplay_cs.csv -- different game, different file.
const CSV := "user://selfplay_v2.csv"

var bridge = null
var _csv_rows: Array = []      # per-match buffer; flushed with the outcome filled in

func _init() -> void:
	bridge = load("res://Scripts/Port/CSharp/BrainBridge.cs").new()
	bridge.SetProfile("extreme")
	bridge.LoadCalibration()
	_csv_header()
	if OS.get_environment("UKO_MODE") == "harvest":
		# HARVEST NIGHT: the live champion (d3@700) plays itself under the NEW physics.
		# Every turn -> a v2 training row; the printout doubles as the new-rules
		# telemetry (draw rate + match length = the stall-meta A/B evidence).
		_log("==== HARVEST start %s | %d mirror matches (d3@700), max %d turns ====" %
				[Time.get_datetime_string_from_system(), HARVEST_MATCHES, MAX_TURNS])
		_phase("harvest_d3_700_mirror", "d3b700", "d3b700", HARVEST_MATCHES)
		_log("==== HARVEST done %s ====" % Time.get_datetime_string_from_system())
		quit(0)
		return
	_log("==== SWEEP start %s | %d matches/phase, max %d turns ====" %
			[Time.get_datetime_string_from_system(), MATCHES_PER_PHASE, MAX_TURNS])
	_phase("d3_1400_vs_d2_700", "d3b1400", "d2b700")
	_phase("d4_2000_vs_d2_700", "d4b2000", "d2b700")
	_phase("d3_700_vs_d2_700", "d3b700", "d2b700")
	_log("==== SWEEP done %s ====" % Time.get_datetime_string_from_system())
	quit(0)

func _phase(name: String, brain_x: String, brain_y: String, n: int = MATCHES_PER_PHASE) -> void:
	var wx := 0
	var wy := 0
	var dr := 0
	var margin := 0.0   # avg (x hp - y hp) at match end, a finer signal than W/L
	var turns_sum := 0   # new-physics telemetry: average match length
	for mi in range(n):
		# Seat alternation: even matches X sits in seat A, odd in seat B.
		var x_is_a := (mi % 2 == 0)
		var r := _run_match(SEED_BASE + mi, brain_x if x_is_a else brain_y, brain_y if x_is_a else brain_x)
		var x_hp: int = r["a_hp"] if x_is_a else r["b_hp"]
		var y_hp: int = r["b_hp"] if x_is_a else r["a_hp"]
		margin += float(x_hp - y_hp)
		turns_sum += int(r.get("turns", 0))
		match r["result"]:
			"a_wins": if x_is_a: wx += 1
			else: wy += 1
			"b_wins": if x_is_a: wy += 1
			else: wx += 1
			_: dr += 1
		if (mi + 1) % 10 == 0:
			_log("[%s] %d/%d  %s %d - %d %s (draws %d)  avg-margin %+.1f  avg-turns %.1f" %
					[name, mi + 1, n, brain_x, wx, wy, brain_y, dr, margin / float(mi + 1),
					float(turns_sum) / float(mi + 1)])
	_log("[%s] FINAL  %s %d - %d %s (draws %d)  winrate %.1f%%  avg-margin %+.1f  avg-turns %.1f  draw-rate %.1f%%" %
			[name, brain_x, wx, wy, brain_y, dr,
			100.0 * float(wx) / maxf(1.0, float(wx + wy)), margin / float(n),
			float(turns_sum) / float(n), 100.0 * float(dr) / float(n)])

func _run_match(match_seed: int, brain_a: String, brain_b: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	var g := Grid.new()
	g.generate(rng)
	var a := Combatant.new("A", g.spawn_a, Config.Facing.EAST)
	a.equip(FULL_GEAR)
	var b := Combatant.new("B", g.spawn_b, Config.Facing.WEST)
	b.equip(FULL_GEAR)
	_csv_rows.clear()
	for turn in range(1, MAX_TURNS + 1):
		_harvest(match_seed, turn, "A", a, b, g)
		_harvest(match_seed, turn, "B", b, a, g)
		var sa := _choose(brain_a, a, b, g)
		var sb := _choose(brain_b, b, a, g)
		var out := Resolver.resolve(g, a, b, sa, sb, turn)
		a = out["a"]
		b = out["b"]
		if String(out["result"]) != "ongoing":
			_flush_csv(String(out["result"]))
			return {"result": out["result"], "a_hp": a.hp, "b_hp": b.hp, "turns": turn}
		# The live rotation/zone clock (mirrors GameController._rotate_map).
		if turn % Config.MAP_ROTATE_EVERY == 0:
			var res := g.rotate_blockers([a.pos, b.pos])
			a.pos = res["positions"][0]
			b.pos = res["positions"][1]
			for idx in res["crushed_idx"]:
				var who: Combatant = a if int(idx) == 0 else b
				who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)
				who.rest_ready = false
	_flush_csv("draw")
	return {"result": "draw", "a_hp": a.hp, "b_hp": b.hp, "turns": MAX_TURNS}

# Brain tag format: d<depth>b<budget_ms>, e.g. "d3b1400".
func _choose(brain: String, me: Combatant, foe: Combatant, g: Grid) -> Array:
	var parts := brain.substr(1).split("b")
	bridge.SetDepth(int(parts[0]))
	bridge.SetBudget(int(parts[1]))
	return _bridge_choose(me, foe, g)

func _bridge_choose(me: Combatant, foe: Combatant, g: Grid) -> Array:
	var seq: Array = Array(bridge.ChooseSequence(_rows(g.blocked), _rows(g.base_blocked),
			g.rot_step, g.shrink_level, _cd(me), _cd(foe), false))
	return seq if not seq.is_empty() else [{"id": "wait"}]

func _rows(blocked: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in range(Grid.SIZE):
		var line := ""
		for x in range(Grid.SIZE):
			line += "#" if blocked[y][x] else "."
		rows.append(line)
	return rows

func _cd(c: Combatant) -> Dictionary:
	return c.to_bridge_dict()   # the ONE marshal contract lives on Combatant

# One v2 training row: features FROM `me`'s seat; outcome filled at flush (+1/0/-1).
# v2 adds the AUTOPSY features the model must see to learn Fra's concepts:
# flank tiers, pulse clocks, lockout/guardability, rest paths, cooldowns, statuses.
func _harvest(seed_v: int, turn: int, seat: String, me: Combatant, foe: Combatant, g: Grid) -> void:
	var rel_map := {"front": 0, "side": 1, "back": 2}
	var my_flank: int = rel_map[Config.rel_of(foe.facing, foe.pos, me.pos)]   # tier MY hits land at
	var foe_flank: int = rel_map[Config.rel_of(me.facing, me.pos, foe.pos)]  # tier THEIR hits land at
	var epa := Config.ENERGY_PULSE_ACTIONS
	_csv_rows.append({"seat": seat, "line": "%d,%d,%s,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d" % [
		seed_v, turn, seat, me.hp, me.mp, me.energy, foe.hp, foe.mp, foe.energy,
		Grid.dist(me.pos, foe.pos), g.shrink_level, me.action_count, foe.action_count,
		0 if me.spent_once.has("grenade") else 1, 0 if foe.spent_once.has("grenade") else 1,
		my_flank, foe_flank,
		epa - (me.action_count % epa), epa - (foe.action_count % epa),
		1 if me.energy < Config.COST_ATTACK else 0, 1 if foe.energy < Config.COST_ATTACK else 0,
		1 if me.energy < Config.COST_GUARD else 0, 1 if foe.energy < Config.COST_GUARD else 0,
		1 if me.rest_ready else 0, 1 if foe.rest_ready else 0,
		int(me.cooldowns.get("aoe_burst", 0)), int(me.cooldowns.get("dark_bolt", 0)),
		int(foe.cooldowns.get("aoe_burst", 0)), int(foe.cooldowns.get("dark_bolt", 0)),
		1 if me.statuses.has("rooted") or me.statuses.has("staggered") else 0,
		1 if foe.statuses.has("rooted") or foe.statuses.has("staggered") else 0]})

func _flush_csv(result: String) -> void:
	var f := FileAccess.open(CSV, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(CSV, FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	for r in _csv_rows:
		var z := 0
		if result == "a_wins":
			z = 1 if r["seat"] == "A" else -1
		elif result == "b_wins":
			z = 1 if r["seat"] == "B" else -1
		f.store_line("%s,%d" % [r["line"], z])
	f.close()
	_csv_rows.clear()

func _csv_header() -> void:
	if FileAccess.file_exists(CSV):
		return
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	if f != null:
		f.store_line("seed,turn,seat,hp,mp,energy,foe_hp,foe_mp,foe_energy,dist,shrink,my_ac,foe_ac,my_nade,foe_nade,my_flank,foe_flank,my_to_pulse,foe_to_pulse,my_locked,foe_locked,my_noguard,foe_noguard,my_rest_ready,foe_rest_ready,my_cd_burst,my_cd_bolt,foe_cd_burst,foe_cd_bolt,my_cc,foe_cc,outcome")
		f.close()

func _log(s: String) -> void:
	print(s)
	var f := FileAccess.open(OUT, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(s)
		f.close()
