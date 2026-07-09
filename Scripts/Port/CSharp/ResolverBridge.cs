// ResolverBridge.cs -- the GDScript <-> C# boundary for the ported engine.
// A RefCounted the GDScript brain can instantiate and call:
//
//   var Bridge := load("res://Scripts/Port/CSharp/ResolverBridge.cs")
//   var bridge = Bridge.new()
//   var out := bridge.Resolve(grid_rows, a_dict, b_dict, seq_a, seq_b, turn)
//   # out = { "a": Dictionary, "b": Dictionary, "result": String }
//
// MARSHALING CONTRACT (kept dumb and explicit):
//   grid_rows : PackedStringArray of 8 strings, '#' = wall        ("....#...")
//   combatant : { id, x, y, facing, hp, mp, energy, action_count,
//                 rest_ready, speed_boost, cooldowns:Dict, statuses:Dict,
//                 spent_once:Dict, gear:Array }                    (same fields back)
//   seq       : Array of { "id": String, "tile": Vector2i?, "facing": int? }
//
// Events are NOT returned: the brain never reads them (only the renderer does, and
// it stays on the GDScript resolver). Echo() marshals in+out WITHOUT resolving --
// it exists purely so the benchmark can isolate the boundary-crossing cost.
namespace UKO;

using Godot;
using GC = Godot.Collections;

[GlobalClass]
public partial class ResolverBridge : RefCounted
{
	public GC.Dictionary Resolve(string[] gridRows, GC.Dictionary a, GC.Dictionary b,
			GC.Array seqA, GC.Array seqB, int turn)
	{
		var grid = GridFrom(gridRows);
		var ca = CombatantFrom(a);
		var cb = CombatantFrom(b);
		var sa = SeqFrom(seqA);
		var sb = SeqFrom(seqB);
		var outp = Resolver.Resolve(grid, ca, cb, sa, sb, turn);
		return new GC.Dictionary
		{
			{ "a", ToDict(outp.A) },
			{ "b", ToDict(outp.B) },
			{ "result", outp.Result },
		};
	}

	// Marshal in + marshal out, NO resolve: measures pure boundary cost.
	public GC.Dictionary Echo(string[] gridRows, GC.Dictionary a, GC.Dictionary b,
			GC.Array seqA, GC.Array seqB, int turn)
	{
		var grid = GridFrom(gridRows);
		var ca = CombatantFrom(a);
		var cb = CombatantFrom(b);
		var sa = SeqFrom(seqA);
		var sb = SeqFrom(seqB);
		// touch everything so nothing is optimized away
		int sink = grid.IsBlocked(ca.Pos) ? 1 : 0;
		sink += sa.Count + sb.Count + turn;
		return new GC.Dictionary
		{
			{ "a", ToDict(ca) },
			{ "b", ToDict(cb) },
			{ "result", sink >= 0 ? "echo" : "?" },
		};
	}

	// ── marshal in ───────────────────────────────────────────────────────────
	private static Grid GridFrom(string[] rows) => Grid.FromRows(rows);

	private static Combatant CombatantFrom(GC.Dictionary d)
	{
		var c = new Combatant(
			d["id"].AsString(),
			new Vec2I(d["x"].AsInt32(), d["y"].AsInt32()),
			d["facing"].AsInt32());
		c.Hp = d["hp"].AsInt32();
		c.Mp = d["mp"].AsInt32();
		c.Energy = d["energy"].AsInt32();
		c.ActionCount = d["action_count"].AsInt32();
		c.RestReady = d["rest_ready"].AsBool();
		c.SpeedBoost = d["speed_boost"].AsBool();
		var cds = d["cooldowns"].AsGodotDictionary();
		foreach (var k in cds.Keys)
			c.Cooldowns[k.AsString()] = cds[k].AsInt32();
		var sts = d["statuses"].AsGodotDictionary();
		foreach (var k in sts.Keys)
			c.Statuses[k.AsString()] = sts[k].AsInt32();
		var sps = d["spent_once"].AsGodotDictionary();
		foreach (var k in sps.Keys)
			c.SpentOnce[k.AsString()] = sps[k].AsBool();
		var gear = new System.Collections.Generic.List<string>();
		foreach (var g in d["gear"].AsGodotArray())
			gear.Add(g.AsString());
		c.Equip(gear);
		return c;
	}

	private static System.Collections.Generic.List<PlanAction> SeqFrom(GC.Array seq)
	{
		var outp = new System.Collections.Generic.List<PlanAction>();
		foreach (var v in seq)
		{
			var d = v.AsGodotDictionary();
			string id = d["id"].AsString();
			Vec2I? tile = null;
			int? facing = null;
			if (d.ContainsKey("tile"))
			{
				var t = d["tile"].AsVector2I();
				tile = new Vec2I(t.X, t.Y);
			}
			if (d.ContainsKey("facing"))
				facing = d["facing"].AsInt32();
			outp.Add(new PlanAction(id, tile, facing));
		}
		return outp;
	}

	// ── marshal out ──────────────────────────────────────────────────────────
	private static GC.Dictionary ToDict(Combatant c)
	{
		var cd = new GC.Dictionary();
		foreach (var kv in c.Cooldowns) cd[kv.Key] = kv.Value;
		var st = new GC.Dictionary();
		foreach (var kv in c.Statuses) st[kv.Key] = kv.Value;
		var sp = new GC.Dictionary();
		foreach (var kv in c.SpentOnce) sp[kv.Key] = kv.Value;
		var gear = new GC.Array();
		foreach (var g in c.Gear) gear.Add(g);
		return new GC.Dictionary
		{
			{ "id", c.Id },
			{ "x", c.Pos.X }, { "y", c.Pos.Y },
			{ "facing", c.Facing },
			{ "hp", c.Hp }, { "mp", c.Mp }, { "energy", c.Energy },
			{ "action_count", c.ActionCount },
			{ "rest_ready", c.RestReady },
			{ "speed_boost", c.SpeedBoost },
			{ "cooldowns", cd }, { "statuses", st }, { "spent_once", sp },
			{ "gear", gear },
		};
	}
}
