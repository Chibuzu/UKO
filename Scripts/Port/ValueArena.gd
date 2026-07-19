# ValueArena.gd -- THE gate for the learned value function: the same C# EXTREME
# brain (depth 3 @ 700ms) with the learned judge ON vs OFF, 150 seeded matches,
# seat alternation, live rotation/zone clock. Run via run_value_arena.bat AFTER
# run_fit_value.bat. Adoption rule (mirrors ValidateChampion): >=55% for the
# learned judge -> promote (flip it on for live EXTREME); <50% -> keep the hand
# eval; in between -> more data (another harvest night) before deciding.
# Results append live to user://value_arena.txt (interruption-safe).
extends SceneTree

const MATCHES := 450
const MAX_TURNS := 80
const SEED_BASE := 770001
const OUT := "user://value_arena.txt"

var bridge = null

func _init() -> void:
	bridge = load("res://Scripts/Port/CSharp/BrainBridge.cs").new()
	bridge.SetProfile("extreme")
	bridge.LoadCalibration()
	bridge.SetDepth(3)
	if not bridge.LoadValueFn():
		_log("[arena] ERROR: user://value_fn.cfg missing/invalid -- run run_fit_value.bat first.")
		quit(1)
		return
	_log("==== VALUE ARENA start %s | %d matches, d3@700, value-ON vs value-OFF ====" %
			[Time.get_datetime_string_from_system(), MATCHES])
	var w_on := 0
	var w_off := 0
	var dr := 0
	var margin := 0.0
	for mi in range(MATCHES):
		var on_is_a := (mi % 2 == 0)               # seat alternation
		var r := _run_match(SEED_BASE + mi, on_is_a)
		var on_hp: int = r["a_hp"] if on_is_a else r["b_hp"]
		var off_hp: int = r["b_hp"] if on_is_a else r["a_hp"]
		margin += float(on_hp - off_hp)
		match String(r["result"]):
			"a_wins": if on_is_a: w_on += 1
			else: w_off += 1
			"b_wins": if on_is_a: w_off += 1
			else: w_on += 1
			_: dr += 1
		if (mi + 1) % 10 == 0:
			_log("[arena] %d/%d  ON %d - %d OFF (draws %d)  avg-margin %+.1f" %
					[mi + 1, MATCHES, w_on, w_off, dr, margin / float(mi + 1)])
	var rate := 100.0 * float(w_on) / maxf(1.0, float(w_on + w_off))
	_log("[arena] FINAL  ON %d - %d OFF (draws %d)  winrate %.1f%%  avg-margin %+.1f" %
			[w_on, w_off, dr, rate, margin / float(MATCHES)])
	if rate >= 55.0:
		_log("[arena] VERDICT: ADOPT -- the learned judge beats the hand eval. Next: gates, then flip it on live.")
	elif rate < 50.0:
		_log("[arena] VERDICT: KEEP HAND EVAL -- refit after a richer harvest before retrying.")
	else:
		_log("[arena] VERDICT: INCONCLUSIVE -- harvest more data (another night) and refit.")
	quit(0)

func _run_match(match_seed: int, on_is_a: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed
	var g := Grid.new()
	g.generate(rng)
	var a := Combatant.new("A", g.spawn_a, Config.Facing.EAST)
	a.equip(GameController.AI_GEAR)
	var b := Combatant.new("B", g.spawn_b, Config.Facing.WEST)
	b.equip(GameController.AI_GEAR)
	for turn in range(1, MAX_TURNS + 1):
		var sa := _choose(a, b, g, on_is_a)          # A's judge = ON exactly when on_is_a
		var sb := _choose(b, a, g, not on_is_a)
		var out := Resolver.resolve(g, a, b, sa, sb, turn)
		a = out["a"]
		b = out["b"]
		if String(out["result"]) != "ongoing":
			return {"result": out["result"], "a_hp": a.hp, "b_hp": b.hp}
		if turn % Config.MAP_ROTATE_EVERY == 0:      # the live rotation/zone clock
			var res := g.rotate_blockers([a.pos, b.pos])
			a.pos = res["positions"][0]
			b.pos = res["positions"][1]
			for idx in res["crushed_idx"]:
				var who: Combatant = a if int(idx) == 0 else b
				who.hp = maxi(1, who.hp - Config.MAP_CRUSH_DAMAGE)
				who.rest_ready = false
	return {"result": "draw", "a_hp": a.hp, "b_hp": b.hp}

func _choose(me: Combatant, foe: Combatant, g: Grid, value_on: bool) -> Array:
	bridge.SetValueEnabled(value_on)                 # per-decision dial; cache clears per decision
	var seq: Array = Array(bridge.ChooseSequence(_rows(g.blocked), _rows(g.base_blocked),
			g.rot_step, g.shrink_level, me.to_bridge_dict(), foe.to_bridge_dict(), false))
	return seq if not seq.is_empty() else [{"id": "wait"}]

func _rows(blocked: Array) -> PackedStringArray:
	var rows := PackedStringArray()
	for y in range(Grid.SIZE):
		var line := ""
		for x in range(Grid.SIZE):
			line += "#" if blocked[y][x] else "."
		rows.append(line)
	return rows

func _log(s: String) -> void:
	print(s)
	var f := FileAccess.open(OUT, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(OUT, FileAccess.WRITE)
	if f != null:
		f.seek_end()
		f.store_line(s)
		f.close()
