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

	// ── Rotation / zone layer (ported for the BRAIN: Eval prices the arena clock) ──
	public const int SHRINK_FLOOR = 4;   // the shrinking zone stops at 4x4
	public const int ROT_STEPS = 4;      // quadrant cycle has 4 orientations
	public static readonly Vec2I[] DIRS =
		{ new(0, -1), new(0, 1), new(-1, 0), new(1, 0) };

	public bool[,] BaseBlocked = new bool[SIZE, SIZE];   // canonical layout; rotations derive from it
	public int RotStep = 0;        // 0-3 clockwise quadrant shifts from canonical
	public int ShrinkLevel = 0;    // rings closed by the zone

	// Chebyshev depth of a tile from the nearest board edge (0 = outermost ring).
	public static int EdgeDepth(int x, int y)
		=> System.Math.Min(System.Math.Min(x, y), System.Math.Min(SIZE - 1 - x, SIZE - 1 - y));

	// One clockwise QUADRANT shift: contents TRANSLATE quadrant-to-quadrant (not rotated).
	private static bool[,] CycleQuadrantsCw(bool[,] src)
	{
		var dst = new bool[SIZE, SIZE];
		int H = SIZE / 2;
		for (int y = 0; y < SIZE; y++)
			for (int x = 0; x < SIZE; x++)
			{
				int qx = x < H ? 0 : 1;
				int qy = y < H ? 0 : 1;
				int rx = x - qx * H;
				int ry = y - qy * H;
				int nqx = 1 - qy;
				int nqy = qx;
				dst[nqy * H + ry, nqx * H + rx] = src[y, x];
			}
		return dst;
	}

	private static bool[,] Cycled(bool[,] baseLayout, int step)
	{
		var outp = (bool[,])baseLayout.Clone();
		for (int i = 0; i < step; i++) outp = CycleQuadrantsCw(outp);
		return outp;
	}

	// Tiles open NOW that become blockers at the next quadrant shift, plus the next
	// closing zone ring -- the telegraph the Eval prices (mirrors Grid.gd exactly).
	public System.Collections.Generic.List<Vec2I> IncomingWalls()
	{
		var next = Cycled(BaseBlocked, (RotStep + 1) % ROT_STEPS);
		var outp = new System.Collections.Generic.List<Vec2I>();
		for (int y = 0; y < SIZE; y++)
			for (int x = 0; x < SIZE; x++)
				if (next[y, x] && !Blocked[y, x])
					outp.Add(new Vec2I(x, y));
		int maxShrink = (SIZE - SHRINK_FLOOR) / 2;
		if (ShrinkLevel < maxShrink)
			for (int y = 0; y < SIZE; y++)
				for (int x = 0; x < SIZE; x++)
					if (EdgeDepth(x, y) == ShrinkLevel && !Blocked[y, x] && !outp.Contains(new Vec2I(x, y)))
						outp.Add(new Vec2I(x, y));
		return outp;
	}

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
		g.BaseBlocked = (bool[,])g.Blocked.Clone();
		return g;
	}
}
