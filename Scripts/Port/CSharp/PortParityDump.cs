using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using UKO;

// C# ParityDump: mirrors Scripts/Port/ParityDump.gd exactly (same 673 cases, order,
// line format, and fingerprint) so parity_cs.txt can be diffed byte-for-byte against
// the GDScript golden parity_gd.txt.
public partial class PortParityDump : Node
{
	static readonly List<string> FULL_GEAR = new() { "discount_charm", "burst_node", "blink_boots", "dark_focus" };

	sealed class Case { public Grid Grid; public Combatant A, B; public List<PlanAction> Sa, Sb; public int Turn; }

	// Attach to a Node in any scene and press Play. Writes user://parity_cs.txt next to
	// the GDScript user://parity_gd.txt so you can diff the two. See SETUP notes for the diff.
	public override void _Ready()
	{
		var cases = BuildCases();
		var lines = new List<string>();
		lines.Add($"# UKO parity oracle v1 -- {cases.Count} cases -- GDScript reference");
		lines.Add("# fmt: idx|grid|Ain|Bin|PA|PB|turn=>result|Aout|Bout|events");
		for (int idx = 0; idx < cases.Count; idx++)
			lines.Add(RunCase(idx, cases[idx]));
		using (var fa = FileAccess.Open("user://parity_cs.txt", FileAccess.ModeFlags.Write))
			fa.StoreString(string.Join("\n", lines) + "\n");
		string outPath = ProjectSettings.GlobalizePath("user://parity_cs.txt");
		GD.Print($"[parity-cs] wrote {cases.Count} cases -> {outPath}");
		foreach (int probe in new[] { 648, 650, 668 })   // eyeball vs the golden file
			GD.Print(lines[probe + 2]);
		GetTree().Quit();
	}

	static string RunCase(int idx, Case c)
	{
		var outp = Resolver.Resolve(c.Grid, c.A, c.B, c.Sa, c.Sb, c.Turn);
		return $"{idx}|{GridSig(c.Grid)}|{Fp(c.A)}|{Fp(c.B)}|{PlanStr(c.Sa)}|{PlanStr(c.Sb)}|{c.Turn}=>{outp.Result}|{Fp(outp.A)}|{Fp(outp.B)}|{EventsDigest(outp.Events)}";
	}

	// ── Fingerprints (must match ParityDump.gd exactly) ──────────────────────
	static string Fp(Combatant c) =>
		$"{c.Pos.X},{c.Pos.Y},{c.Facing},{c.Hp},{c.Mp},{c.Energy},{c.ActionCount},{(c.RestReady ? 1 : 0)},{(c.SpeedBoost ? 1 : 0)},{DictInt(c.Cooldowns)},{DictInt(c.Statuses)},{DictBool(c.SpentOnce)}";

	static string DictInt(Dictionary<string, int> d)
	{
		var keys = d.Keys.ToList(); keys.Sort();
		return "{" + string.Join(",", keys.Select(k => $"{k}={d[k]}")) + "}";
	}
	static string DictBool(Dictionary<string, bool> d)
	{
		var keys = d.Keys.ToList(); keys.Sort();
		// lowercase true/false to match GDScript str(true)
		return "{" + string.Join(",", keys.Select(k => $"{k}={(d[k] ? "true" : "false")}")) + "}";
	}

	static string EventsDigest(List<Event> events)
	{
		var tally = new Dictionary<string, int>();
		foreach (var e in events) tally[e.Type] = tally.GetValueOrDefault(e.Type, 0) + 1;
		var keys = tally.Keys.ToList(); keys.Sort();
		return string.Join(";", keys.Select(k => $"{k}:{tally[k]}"));
	}

	static string PlanStr(List<PlanAction> seq)
	{
		if (seq.Count == 0) return "-";
		var parts = new List<string>();
		foreach (var a in seq)
		{
			string s = a.Id;
			if (a.HasTile) s += $"@{a.Tile.Value.X}.{a.Tile.Value.Y}";
			if (a.HasFacing) s += $"^{a.Facing.Value}";
			parts.Add(s);
		}
		return string.Join("+", parts);
	}

	static string GridSig(Grid g)
	{
		var sb = new System.Text.StringBuilder();
		for (int y = 0; y < Grid.SIZE; y++)
			for (int x = 0; x < Grid.SIZE; x++)
				sb.Append(g.Blocked[y, x] ? "1" : "0");
		return sb.ToString();
	}

	// ── Builders (mirror ParityDump.gd) ──────────────────────────────────────
	static Grid Open() => Grid.FromRows("........", "........", "........", "........", "........", "........", "........", "........");

	static Combatant C(string id, Vec2I pos, int facing, int hp, int mp, int energy,
			int actionCount = 0, bool restReady = true, bool speedBoost = false,
			Dictionary<string, int> statuses = null, Dictionary<string, bool> spentOnce = null)
	{
		var c = new Combatant(id, pos, facing);
		c.Equip(FULL_GEAR);
		c.Hp = hp; c.Mp = mp; c.Energy = energy;
		c.ActionCount = actionCount; c.RestReady = restReady; c.SpeedBoost = speedBoost;
		if (statuses != null) c.Statuses = new Dictionary<string, int>(statuses);
		if (spentOnce != null) c.SpentOnce = new Dictionary<string, bool>(spentOnce);
		return c;
	}

	static int Opp(int f) => (f + 2) % 4;

	static List<(string tag, List<PlanAction> seq)> Alpha(Vec2I p, int f, Vec2I q)
	{
		Vec2I fv = Config.FACING_VEC[f];
		Vec2I perp = new(-fv.Y, fv.X);
		Vec2I fwd = p + fv, back = p - fv, sidea = p + perp, sideb = p - perp;
		Vec2I blinkAim = p + fv * 2;
		return new()
		{
			("rest", new() { new PlanAction("rest") }),
			("wait", new() { new PlanAction("wait") }),
			("guard", new() { new PlanAction("guard") }),
			("atk", new() { new PlanAction("attack", q) }),
			("mv_fwd", new() { new PlanAction("move", fwd) }),
			("mv_sa", new() { new PlanAction("move", sidea) }),
			("mv_sb", new() { new PlanAction("move", sideb) }),
			("mv_back", new() { new PlanAction("move", back) }),
			("pivot", new() { new PlanAction("pivot", null, Opp(f)) }),
			("bolt", new() { new PlanAction("dark_bolt", q) }),
			("burst", new() { new PlanAction("aoe_burst") }),
			("buff", new() { new PlanAction("energy_buff") }),
			("blink", new() { new PlanAction("blink_step", blinkAim, f) }),
			("nade", new() { new PlanAction("grenade", q) }),
			("grd_atk", new() { new PlanAction("guard"), new PlanAction("attack", q) }),
			("wait_atk", new() { new PlanAction("wait"), new PlanAction("attack", q) }),
			("buff_mv", new() { new PlanAction("energy_buff"), new PlanAction("move", fwd) }),
			("sa_atk", new() { new PlanAction("move", sidea), new PlanAction("attack", q) }),
		};
	}

	static List<Case> BuildCases()
	{
		var cases = new List<Case>();
		int E = (int)Config.Facing.EAST, W = (int)Config.Facing.WEST;

		// Block 1: adjacent A(3,4)E vs B(4,4)W, turn 3.
		var apos = new Vec2I(3, 4); var bpos = new Vec2I(4, 4);
		var A = Alpha(apos, E, bpos); var B = Alpha(bpos, W, apos);
		foreach (var ea in A) foreach (var eb in B)
			cases.Add(new Case { Grid = Open(), A = C("A", apos, E, 100, 100, 100), B = C("B", bpos, W, 100, 100, 100), Sa = ea.seq, Sb = eb.seq, Turn = 3 });

		// Block 2: spaced dist-3 A(2,4)E vs B(5,4)W, turn 4.
		var a2 = new Vec2I(2, 4); var b2 = new Vec2I(5, 4);
		var A2 = Alpha(a2, E, b2); var B2 = Alpha(b2, W, a2);
		foreach (var ea in A2) foreach (var eb in B2)
			cases.Add(new Case { Grid = Open(), A = C("A", a2, E, 100, 100, 100), B = C("B", b2, W, 100, 100, 100), Sa = ea.seq, Sb = eb.seq, Turn = 4 });

		cases.AddRange(Fixtures());
		return cases;
	}

	static List<Case> Fixtures()
	{
		int N = (int)Config.Facing.NORTH, E = (int)Config.Facing.EAST, S = (int)Config.Facing.SOUTH, W = (int)Config.Facing.WEST;
		var f = new List<Case>();
		List<PlanAction> Seq(params PlanAction[] a) => a.ToList();

		// 0 back-attack flank
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), E, 100, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 2 });
		// 1 side flank
		f.Add(new Case { Grid = Open(), A = C("A", new(4, 3), S, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 2 });
		// 2 front guard fully blocked
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("guard")), Turn = 2 });
		// 3 back guard slips past
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), E, 100, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("guard")), Turn = 2 });
		// 4 mutual swap
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("move", new Vec2I(4, 4))), Sb = Seq(new PlanAction("move", new Vec2I(3, 4))), Turn = 2 });
		// 5 move fizzle into wall
		f.Add(new Case { Grid = Grid.FromRows("........", "........", "........", "........", "...#....", "........", "........", "........"),
			A = C("A", new(3, 4), N, 100, 100, 100), B = C("B", new(6, 6), W, 100, 100, 100),
			Sa = Seq(new PlanAction("move", new Vec2I(3, 3))), Sb = Seq(new PlanAction("wait")), Turn = 2 });
		// 6 bolt dodge
		f.Add(new Case { Grid = Open(), A = C("A", new(2, 4), E, 100, 100, 100), B = C("B", new(5, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("dark_bolt", new Vec2I(5, 4))), Sb = Seq(new PlanAction("move", new Vec2I(5, 5))), Turn = 3 });
		// 7 bolt wall-stop
		f.Add(new Case { Grid = Grid.FromRows("........", "........", "........", "........", "....#...", "........", "........", "........"),
			A = C("A", new(2, 4), E, 100, 100, 100), B = C("B", new(6, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("dark_bolt", new Vec2I(6, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 8 diagonal grenade root+drain
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 3), E, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 60),
			Sa = Seq(new PlanAction("grenade", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 9 rooted carryover
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100),
			B = C("B", new(5, 4), W, 100, 100, 100, statuses: new() { ["rooted"] = 2 }),
			Sa = Seq(new PlanAction("wait")), Sb = Seq(new PlanAction("move", new Vec2I(4, 4))), Turn = 4 });
		// 10 blink settle one short
		f.Add(new Case { Grid = Open(), A = C("A", new(2, 4), E, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("blink_step", new Vec2I(4, 4), E)), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 11 blink fizzle at edge
		f.Add(new Case { Grid = Open(), A = C("A", new(7, 4), E, 100, 100, 100), B = C("B", new(2, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("blink_step", new Vec2I(9, 4), E)), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 12 aoe burst adjacent
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("aoe_burst")), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 13 rest uninterrupted
		f.Add(new Case { Grid = Open(), A = C("A", new(1, 1), E, 40, 40, 100), B = C("B", new(6, 6), W, 100, 100, 100),
			Sa = Seq(new PlanAction("rest")), Sb = Seq(new PlanAction("wait")), Turn = 5 });
		// 14 rest interrupted
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 40, 40, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("rest")), Sb = Seq(new PlanAction("attack", new Vec2I(3, 4))), Turn = 5 });
		// 15 rest locked (not rest_ready)
		f.Add(new Case { Grid = Open(), A = C("A", new(1, 1), E, 40, 40, 100, restReady: false), B = C("B", new(6, 6), W, 100, 100, 100),
			Sa = Seq(new PlanAction("rest")), Sb = Seq(new PlanAction("wait")), Turn = 5 });
		// 16 energy pulse crossing
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 40, actionCount: 5), B = C("B", new(6, 6), W, 100, 100, 100),
			Sa = Seq(new PlanAction("move", new Vec2I(3, 3))), Sb = Seq(new PlanAction("wait")), Turn = 6 });
		// 17 no_guard_combo guard+bolt voids bolt
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("guard"), new PlanAction("dark_bolt", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 18 cooldown in sequence
		f.Add(new Case { Grid = Open(), A = C("A", new(2, 4), E, 100, 100, 100), B = C("B", new(5, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("dark_bolt", new Vec2I(5, 4)), new PlanAction("dark_bolt", new Vec2I(5, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 19 grenade spent_once
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100, spentOnce: new() { ["grenade"] = true }), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("grenade", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 20 lethal
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100), B = C("B", new(4, 4), E, 12, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 8 });
		// 21 double-KO draw
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 12, 100, 100), B = C("B", new(4, 4), W, 12, 100, 100),
			Sa = Seq(new PlanAction("aoe_burst")), Sb = Seq(new PlanAction("aoe_burst")), Turn = 9 });
		// 22 speed boost front-of-band
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 100, speedBoost: true), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("attack", new Vec2I(3, 4))), Turn = 4 });
		// 23 discount move cost cut
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 15, statuses: new() { ["energy_discount"] = 3 }), B = C("B", new(6, 6), W, 100, 100, 100),
			Sa = Seq(new PlanAction("move", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		// 24 energy starvation noop
		f.Add(new Case { Grid = Open(), A = C("A", new(3, 4), E, 100, 100, 5), B = C("B", new(4, 4), W, 100, 100, 100),
			Sa = Seq(new PlanAction("attack", new Vec2I(4, 4))), Sb = Seq(new PlanAction("wait")), Turn = 3 });
		return f;
	}
}
