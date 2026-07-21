// Wire.cs -- the JSON protocol between game clients and the server. One text
// frame = one JSON object with a "t" discriminator. Action sequences use the
// same dict shape the game's plans do: {"id":"move","tile":[x,y],"facing":n,
// "stance":"push"} with absent fields omitted -- mirrors what GDScript sends.
// Parsing is defensive everywhere: a malformed client message becomes null,
// never an exception into the room.
namespace UKO.Server;

using System;
using System.Collections.Generic;
using System.Text.Json;
using System.Text.Json.Nodes;
using UKO;

public static class Wire
{
    public const int MAX_SEQ = 4;      // a plan is 1-2 actions; anything bigger is abuse
    public const int MAX_STR = 64;

    public static JsonNode Parse(string text)
    {
        try { return JsonNode.Parse(text); }
        catch { return null; }
    }

    public static string Str(JsonNode n, string key, string dflt = "")
    {
        var v = n?[key];
        if (v is JsonValue jv && jv.TryGetValue<string>(out string s))
            return s.Length <= MAX_STR ? s : s[..MAX_STR];
        return dflt;
    }

    public static int Int(JsonNode n, string key, int dflt = 0)
    {
        var v = n?[key];
        if (v is JsonValue jv && jv.TryGetValue<int>(out int i)) return i;
        return dflt;
    }

    // ── plans ──
    public static List<PlanAction> ParseSeq(JsonNode node)
    {
        if (node is not JsonArray arr || arr.Count == 0 || arr.Count > MAX_SEQ)
            return null;
        var outp = new List<PlanAction>();
        foreach (var item in arr)
        {
            string id = Str(item, "id");
            if (id == "" || Config.Def(id) == null) return null;   // unknown action
            Vec2I? tile = null;
            if (item?["tile"] is JsonArray t && t.Count == 2)
                tile = new Vec2I(Int2(t[0]), Int2(t[1]));
            int? facing = null;
            if (item?["facing"] != null) facing = Int(item, "facing");
            string stance = Str(item, "stance", "push");
            if (stance != "push" && stance != "pull" && stance != "feint") stance = "push";
            outp.Add(new PlanAction(id, tile, facing, stance));
        }
        return outp;
    }

    private static int Int2(JsonNode n)
        => n is JsonValue jv && jv.TryGetValue<int>(out int i) ? i : 0;

    public static JsonArray SeqJson(List<PlanAction> seq)
    {
        var arr = new JsonArray();
        foreach (var a in seq)
        {
            var o = new JsonObject { ["id"] = a.Id };
            if (a.HasTile) o["tile"] = new JsonArray(a.Tile.Value.X, a.Tile.Value.Y);
            if (a.HasFacing) o["facing"] = a.Facing.Value;
            if (a.Stance != null && a.Stance != "push") o["stance"] = a.Stance;
            arr.Add(o);
        }
        return arr;
    }

    // ── messages (server -> client) ──
    public static string Msg(string t, Action<JsonObject> fill = null)
    {
        var o = new JsonObject { ["t"] = t };
        fill?.Invoke(o);
        return o.ToJsonString();
    }

    public static JsonArray RowsJson(bool[,] blocked)
    {
        var rows = new JsonArray();
        for (int y = 0; y < Grid.SIZE; y++)
        {
            var sb = new System.Text.StringBuilder(Grid.SIZE);
            for (int x = 0; x < Grid.SIZE; x++)
                sb.Append(blocked[y, x] ? '#' : '.');
            rows.Add(sb.ToString());
        }
        return rows;
    }

    public static JsonArray GearJson(IEnumerable<string> gear)
    {
        var arr = new JsonArray();
        foreach (string g in gear) arr.Add(g);
        return arr;
    }

    // Gear list from hello: unknown ids become "" (empty slot) -- the client's
    // own equip() tolerates that, and the server never trusts names it can't find.
    public static List<string> ParseGear(JsonNode node)
    {
        var outp = new List<string> { "", "", "", "" };
        if (node is not JsonArray arr) return outp;
        for (int i = 0; i < 4 && i < arr.Count; i++)
        {
            string id = arr[i] is JsonValue jv && jv.TryGetValue<string>(out string s) ? s : "";
            outp[i] = GearBook.Gear.ContainsKey(id) ? id : "";
        }
        return outp;
    }
}
