// Grid.cs -- C# ENGINE PORT (stage 3). The ENGINE-relevant slice of Scripts/Core/Grid.gd:
// bounds, blocked-tile lookup, and the two distance helpers. Arena GENERATION, quadrant
// ROTATION, and the shrinking ZONE are deliberately NOT ported -- the Resolver never reads
// them (they live in the turn loop), and parity arenas are built tile-by-tile. Blocked is
// indexed [y, x] to mirror the GDScript blocked[p.y][p.x].
namespace UKO;

public sealed class Grid
{
	public const int SIZE = 8;   // 8x8 duel arena

	// true = wall. Indexed [y, x]. Defaults to all-open.
	public bool[,] Blocked = new bool[SIZE, SIZE];

	public bool InBounds(Vec2I p) => p.X >= 0 && p.X < SIZE && p.Y >= 0 && p.Y < SIZE;

	// Out-of-bounds counts as blocked (mirrors Grid.gd: a move off the edge fizzles).
	public bool IsBlocked(Vec2I p)
	{
		if (!InBounds(p)) return true;
		return Blocked[p.Y, p.X];
	}

	// Grid.dist / Grid.cheb were static in GDScript; the math lives on Vec2I so callers share one definition.
	public static int Dist(Vec2I a, Vec2I b) => Vec2I.Man(a, b);
	public static int Cheb(Vec2I a, Vec2I b) => Vec2I.Cheb(a, b);

	// ── Tooling helper (parity dump + tests): build an arena from ASCII rows ─────
	// '#' = wall, any other char (incl. missing) = open. Mirrors ParityDump._grid_from.
	public static Grid FromRows(params string[] rows)
	{
		var g = new Grid();
		for (int y = 0; y < SIZE; y++)
		{
			string line = y < rows.Length ? rows[y] : "";
			for (int x = 0; x < SIZE; x++)
				g.Blocked[y, x] = x < line.Length && line[x] == '#';
		}
		return g;
	}
}
