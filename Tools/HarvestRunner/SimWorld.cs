// SimWorld.cs -- the match-world simulation the Godot layer normally provides:
// map GENERATION, quadrant ROTATION, zone SHRINK, and crush. Mirrors Grid.gd's
// rules (same density, connectivity requirement, spawns, cycle geometry, crush
// order) but rolls its own PRNG (System.Random), so layouts are drawn from the
// SAME DISTRIBUTION as live maps without replaying Godot's exact seeds -- for
// training data that's a feature: every night explores fresh arenas instead of
// re-walking the fixed 450 seeds. Grid.cs itself stays resolver-only on purpose.
namespace UKO;

using System;
using System.Collections.Generic;

public static class SimWorld
{
    public const int SIZE = Grid.SIZE;           // 8
    public const int SHRINK_FLOOR = 4;           // zone stops at 4x4
    public const int ROT_STEPS = 4;

    public sealed class World
    {
        public Grid G = new();
        public bool[,] BaseBlocked = new bool[SIZE, SIZE];
        public int RotStep;
        public int ShrinkLevel;
        public Vec2I SpawnA, SpawnB;
    }

    // ── Generation (mirror of Grid.generate: 8-10% blockers, connected spawns) ──
    public static World Generate(Random rng)
    {
        var w = new World();
        for (int attempt = 0; attempt < 200; attempt++)
        {
            Array.Clear(w.G.Blocked, 0, w.G.Blocked.Length);
            w.SpawnA = new Vec2I(Config.SPAWN_INSET, SIZE / 2);
            w.SpawnB = new Vec2I(SIZE - 1 - Config.SPAWN_INSET, SIZE / 2);
            int target = (int)Math.Round(SIZE * SIZE *
                (Config.BLOCKER_DENSITY_MIN + rng.NextDouble() * (Config.BLOCKER_DENSITY_MAX - Config.BLOCKER_DENSITY_MIN)),
                MidpointRounding.AwayFromZero);
            int placed = 0, guard = 0;
            while (placed < target && guard < 400)
            {
                guard++;
                var p = new Vec2I(rng.Next(SIZE), rng.Next(SIZE));
                if (w.G.Blocked[p.Y, p.X] || p == w.SpawnA || p == w.SpawnB) continue;
                w.G.Blocked[p.Y, p.X] = true;
                placed++;
            }
            if (Connected(w.G.Blocked, w.SpawnA, w.SpawnB))
            {
                w.BaseBlocked = (bool[,])w.G.Blocked.Clone();
                w.G.BaseBlocked = (bool[,])w.G.Blocked.Clone();
                return w;
            }
        }
        // Fallback (mirrors Grid.gd): empty arena.
        Array.Clear(w.G.Blocked, 0, w.G.Blocked.Length);
        w.BaseBlocked = (bool[,])w.G.Blocked.Clone();
        w.G.BaseBlocked = (bool[,])w.G.Blocked.Clone();
        return w;
    }

    private static bool Connected(bool[,] blocked, Vec2I start, Vec2I goal)
    {
        var seen = new bool[SIZE, SIZE];
        var q = new Queue<Vec2I>();
        q.Enqueue(start);
        seen[start.Y, start.X] = true;
        while (q.Count > 0)
        {
            var cur = q.Dequeue();
            if (cur == goal) return true;
            foreach (var d in Grid.DIRS)
            {
                var n = new Vec2I(cur.X + d.X, cur.Y + d.Y);
                if (n.X < 0 || n.X >= SIZE || n.Y < 0 || n.Y >= SIZE) continue;
                if (blocked[n.Y, n.X] || seen[n.Y, n.X]) continue;
                seen[n.Y, n.X] = true;
                q.Enqueue(n);
            }
        }
        return false;
    }

    private static int EdgeDepth(int x, int y) => Math.Min(Math.Min(x, y), Math.Min(SIZE - 1 - x, SIZE - 1 - y));

    // One clockwise quadrant cycle (contents translated, mirror of _cycle_quadrants_cw).
    private static bool[,] CycleCw(bool[,] src)
    {
        var dst = new bool[SIZE, SIZE];
        int H = SIZE / 2;
        for (int y = 0; y < SIZE; y++)
            for (int x = 0; x < SIZE; x++)
            {
                if (!src[y, x]) continue;
                int qx = x < H ? 0 : 1, qy = y < H ? 0 : 1;
                int rx = x - qx * H, ry = y - qy * H;
                (int nqx, int nqy) = (qx, qy) switch
                {
                    (0, 0) => (1, 0), (1, 0) => (1, 1), (1, 1) => (0, 1), _ => (0, 0),
                };
                dst[nqy * H + ry, nqx * H + rx] = true;
            }
        return dst;
    }

    private static bool[,] Cycled(bool[,] baseB, int step)
    {
        var outB = (bool[,])baseB.Clone();
        for (int i = 0; i < step; i++) outB = CycleCw(outB);
        return outB;
    }

    // Mirror of Grid.rotate_blockers: rotate from base, shrink, crush occupants
    // (zone shove first, interior-wall suppress second), keep spawns connected.
    public static (List<int> crushed, Vec2I[] positions) RotateBlockers(World w, Vec2I[] positions)
    {
        w.RotStep = (w.RotStep + 1) % ROT_STEPS;
        w.G.Blocked = Cycled(w.BaseBlocked, w.RotStep);
        int maxShrink = (SIZE - SHRINK_FLOOR) / 2;
        if (w.ShrinkLevel < maxShrink) w.ShrinkLevel++;
        for (int y = 0; y < SIZE; y++)
            for (int x = 0; x < SIZE; x++)
                if (EdgeDepth(x, y) < w.ShrinkLevel)
                    w.G.Blocked[y, x] = true;
        var crushed = new List<int>();
        for (int i = 0; i < positions.Length; i++)
        {
            var p = positions[i];
            if (EdgeDepth(p.X, p.Y) < w.ShrinkLevel)
            {
                // Fra's rule (round 15): dragged one tile straight toward the centre
                // (north edge drags south, west drags east, corners diagonal); a
                // blocker on the landing tile is SMASHED and costs a second crush
                // hit -- the fighter appears in `crushed` once per hit. Exact mirror
                // of Grid.gd.rotate_blockers.
                crushed.Add(i);
                int guard = 0;
                while (guard < SIZE)
                {
                    guard++;
                    bool inRing = EdgeDepth(p.X, p.Y) < w.ShrinkLevel;
                    bool taken = false;
                    for (int oi = 0; oi < positions.Length; oi++)
                        if (oi != i && positions[oi] == p) taken = true;
                    if (!inRing && !taken) break;
                    int dx = 0, dy = 0;
                    if (inRing)
                    {
                        if (p.X < w.ShrinkLevel) dx = 1;
                        else if (p.X >= SIZE - w.ShrinkLevel) dx = -1;
                        if (p.Y < w.ShrinkLevel) dy = 1;
                        else if (p.Y >= SIZE - w.ShrinkLevel) dy = -1;
                    }
                    else
                    {
                        dx = Math.Sign(SIZE / 2 - p.X);
                        dy = Math.Sign(SIZE / 2 - p.Y);
                        if (dx == 0 && dy == 0) dy = 1;
                    }
                    p = new Vec2I(p.X + dx, p.Y + dy);
                    // Only INTERIOR walls smash (and charge the extra hit); ring
                    // tiles are the zone itself and must never be punched open.
                    if (w.G.Blocked[p.Y, p.X] && EdgeDepth(p.X, p.Y) >= w.ShrinkLevel)
                    {
                        w.G.Blocked[p.Y, p.X] = false;
                        crushed.Add(i);
                    }
                }
                positions[i] = p;
            }
            else if (w.G.Blocked[p.Y, p.X])
            {
                w.G.Blocked[p.Y, p.X] = false;
                crushed.Add(i);
            }
        }
        if (positions.Length == 2 && !Connected(w.G.Blocked, positions[0], positions[1]))
            Carve(w, positions[0], positions[1]);
        w.G.RotStep = w.RotStep;
        w.G.ShrinkLevel = w.ShrinkLevel;
        return (crushed, positions);
    }

    // L-shaped corridor carve between stranded fighters (exact mirror of Grid._carve).
    private static void Carve(World w, Vec2I a, Vec2I b)
    {
        int x = a.X, y = a.Y;
        while (x != b.X) { x += Math.Sign(b.X - x); w.G.Blocked[y, x] = false; }
        while (y != b.Y) { y += Math.Sign(b.Y - y); w.G.Blocked[y, x] = false; }
    }
}
