# ValueArena.gd -- THE gate every learned judge must pass before touching live
# play: the same C# EXTREME brain (d3 @ 700ms, PINNED -- the live profile now
# thinks 3s/turn, which would make 450 matches a multi-DAY run; judged A/Bs
# stay comparable at the established 700ms condition) on both seats, 450 seeded
# matches, seat alternation, live rotation/zone clock. Two modes, picked by what
# exists on disk:
#   CHALLENGER MODE (user://value_fn_new.cfg AND user://value_fn.cfg exist):
#     the fresh fit (NEW) vs the live judge (LIVE). This is the generation gate
#     -- every generation must dethrone the last, not the hand eval.
#   BOOTSTRAP MODE (only user://value_fn.cfg): value-ON vs value-OFF, the
#     original gen-1 gate vs the hand eval.
# Adoption rule (mirrors ValidateChampion): >=55% for the challenger -> promote
# (run_promote_value.bat copies new -> live; gates with USE_VALUE first);
# <50% -> keep; in between -> more data (another harvest night) before deciding.
# Results append live to user://value_arena.txt (interruption-safe).
extends SceneTree

const MATCHES := 450       # Fra's dial: ~1-2 min/match; even number keeps seats balanced
const MAX_TURNS := 80
const SEED_BASE := 770001
const OUT := "user://value_arena.txt"
const LIVE_CFG := "user://value_fn.cfg"
const NEW_CFG := "user://value_fn_new.cfg"

var bridge = null
var challenger_mode := false

func _init() -> void:
	bridge = load("res://Scripts/Port/CSharp/BrainBridge.cs").new()
	bridge.SetProfile("extreme")
	bridge.LoadCalibration()
	bridge.SetDepth(3)
	bridge.SetBudget(700)   # pin: arena condition stays 700ms even as the live profile grows
	var have_live := FileAccess.file_exists(LIVE_CFG)
	var have_new := FileAccess.file_exists(NEW_CFG)
	if have_new and have_live:
		challenger_mode = true
		if not bridge.LoadValueSlot(0, LIVE_CFG) or not bridge.LoadValueSlot(1, NEW_CFG):
			_log("[arena] ERROR: a value cfg failed to parse -- refit (run_fit_value.bat).")
			quit(1)
			return
		_log("==== VALUE ARENA start %s | %d matches, CHALLENGER (value_fn_new) vs LIVE (value_fn) ====" %
				[Time.get_datetime_string_from_system(), MATCHES])
	elif have_live:
		if not bridge.LoadValueFn():
			_log("[arena] ERROR: %s invalid -- refit (run_fit_value.bat)." % LIVE_CFG)
			quit(1)
			return
		_log("==== VALUE ARENA start %s | %d matches, value-ON vs value-OFF (bootstrap) ====" %
				[Time.get_datetime_string_from_system(), MATCHES])
	else:
		_log("[arena] ERROR: no value cfg found -- run run_fit_value.bat first.")
		quit(1)
		return
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
			_log("[arena] %d/%d  %s %d - %d %s (draws %d)  avg-margin %+.1f" %
					[mi + 1, MATCHES, _name_on(), w_on, w_off, _name_off(), dr, margin / float(mi + 1)])
	var rate := 100.0 * float(w_on) / maxf(1.0, float(w_on + w_off))
	_log("[arena] FINAL  %s %d - %d %s (draws %d)  winrate %.1f%%  avg-margin %+.1f" %
			[_name_on(), w_on, w_off, _name_off(), dr, rate, margin / float(MATCHES)])
	if rate >= 55.0:
		_log("[arena] VERDICT: PROMOTE -- %s wins. Next: gates with USE_VALUE, then run_promote_value.bat." % _name_on())
	elif rate < 50.0:
		_log("[arena] VERDICT: KEEP %s -- harvest a richer night and refit before retrying." % _name_off())
	else:
		_log("[arena] VERDICT: INCONCLUSIVE -- harvest more data (another night) and refit.")
	quit(0)

func _name_on() -> String:
	return "NEW" if challenger_mode else "ON"

func _name_off() -> String:
	return "LIVE" if challenger_mode else "OFF"

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
		var sa := _choose(a, b, g, on_is_a)          # A's judge = ON/NEW exactly when on_is_a
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

# Per-decision judge dial (cache clears per decision, so this is safe):
# challenger mode swaps WEIGHT SETS (slot 1 = NEW, slot 0 = LIVE), both armed;
# bootstrap mode toggles the judge on/off against the hand eval.
func _choose(me: Combatant, foe: Combatant, g: Grid, on_side: bool) -> Array:
	if challenger_mode:
		bridge.UseValueSlot(1 if on_side else 0)
	else:
		bridge.SetValueEnabled(on_side)
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
