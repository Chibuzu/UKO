// Program.cs -- the FAST HARVEST RUNNER: EXTREME-vs-EXTREME self-play as a plain
// console program, no Godot. This is the round-12 throughput engine: the same
// brain, resolver, and rules the game ships, producing selfplay_v3.csv rows at
// tens of thousands of games per night instead of hundreds.
//
// PARALLELISM: the C# brain deliberately uses static state (caches, weights,
// budget dials) and is single-threaded by design, so the runner parallelizes at
// the PROCESS level: the parent spawns N copies of itself in --worker mode with
// disjoint seed ranges, each writes its own shard file, and the parent appends
// the shards to the target CSV serially (no interleaving, no locks, no brain
// changes). Kill it any time -- finished shards are already merged per wave.
//
// CSV CONTRACT: header + column order are OvernightSweep.gd's exactly; the 28
// feature columns are written from Eval.ValueFeatures -- the SAME code inference
// uses, so harvest/fit/inference can never drift apart.
//
// USAGE (run_fast_harvest.bat wraps this):
//   HarvestRunner --minutes 960 --out <path to selfplay_v3.csv> [--user-dir <godot user dir>]
//                 [--workers N] [--budget 0] [--depth 3] [--seed-base 900001] [--matches M]
namespace UKO;

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Program
{
    private const string HEADER =
        "seed,turn,seat,hp,mp,energy,foe_hp,foe_mp,foe_energy,dist,shrink,my_ac,foe_ac,my_nade,foe_nade,my_flank,foe_flank,my_to_pulse,foe_to_pulse,my_locked,foe_locked,my_noguard,foe_noguard,my_rest_ready,foe_rest_ready,my_cd_burst,my_cd_bolt,foe_cd_burst,foe_cd_bolt,my_cc,foe_cc,outcome";
    private static readonly string[] KIT = { "discount_charm", "burst_node", "blink_boots", "dark_focus" };
    private const int MAX_TURNS = 80;
    private const int WAVE = 40;   // matches per worker per wave (merge granularity)

    public static int Main(string[] rawArgs)
    {
        var args = ParseArgs(rawArgs);
        // ROUND 21: the fitter lives here too -- same exe, harvest-scale speed.
        //   HarvestRunner --fit <selfplay_v3.csv> --fit-out <value_fn_new.cfg>
        if (args.ContainsKey("fit"))
            return FitValue.Run(args["fit"], args.GetValueOrDefault("fit-out", "value_fn_new.cfg"));
        int budget = GetInt(args, "budget", 0);
        int depth = GetInt(args, "depth", 3);
        long seedBase = GetLong(args, "seed-base", 900001);
        string userDir = args.GetValueOrDefault("user-dir", "");

        // Brain setup (per process; workers inherit via their own copy of this).
        ExtremeAI.SetProfile("extreme");
        Eval.LOOKAHEAD_DEPTH = depth;
        ExtremeAI.BudgetOverrideMs = budget;
        bool armed = userDir != "" && ValueCfg.TryArm(Path.Combine(userDir, "value_fn.cfg"));

        if (args.ContainsKey("worker"))
            return WorkerMain(args, budget, depth, seedBase, armed);

        // ── Parent: orchestrate workers in waves, merge shards, report. ──
        string outPath = args.GetValueOrDefault("out", "");
        if (outPath == "")
        {
            Console.Error.WriteLine("[harvest] --out <selfplay_v3.csv path> is required.");
            return 1;
        }
        int workers = GetInt(args, "workers", Math.Max(1, Environment.ProcessorCount - 1));
        int minutes = GetInt(args, "minutes", 960);
        long matchCap = GetLong(args, "matches", long.MaxValue);

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath)) ?? ".");
        if (!File.Exists(outPath))
            File.WriteAllText(outPath, HEADER + "\n");

        Console.WriteLine($"[harvest] {workers} workers | budget {budget}ms | depth {depth} | " +
                          $"judge {(armed ? "ARMED (value_fn.cfg)" : "OFF (hand eval)")} | " +
                          $"{(matchCap == long.MaxValue ? minutes + " min" : matchCap + " matches")} -> {outPath}");

        var sw = Stopwatch.StartNew();
        long done = 0, wins = 0, draws = 0, turnsSum = 0, rows = 0;
        long nextSeed = seedBase;
        long waveNum = 0;
        string shardDir = Path.Combine(Path.GetTempPath(), "uko_harvest_" + Environment.ProcessId);
        Directory.CreateDirectory(shardDir);

        while (sw.Elapsed.TotalMinutes < minutes && done < matchCap)
        {
            // One wave: `workers` children, WAVE matches each, disjoint seeds.
            // Shard names are UNIQUE per wave: Windows (antivirus, indexer) can
            // briefly hold a fresh temp file open, and a name that's never reused
            // can never collide with a lingering lock.
            waveNum++;
            var procs = new List<(Process p, string shard)>();
            for (int wi = 0; wi < workers; wi++)
            {
                string shard = Path.Combine(shardDir, $"shard_{waveNum}_{wi}.csv");
                long chunk = Math.Min(WAVE, Math.Max(0, matchCap - done - wi * (long)WAVE));
                if (chunk <= 0) break;
                var psi = new ProcessStartInfo
                {
                    FileName = Environment.ProcessPath,
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                };
                foreach (string a in new[] { "--worker", "1", "--seed-base", nextSeed.ToString(),
                        "--matches", chunk.ToString(), "--shard", shard,
                        "--budget", budget.ToString(), "--depth", depth.ToString(),
                        "--user-dir", userDir })
                    psi.ArgumentList.Add(a);
                nextSeed += chunk;
                var p = Process.Start(psi);
                procs.Add((p, shard));
            }
            if (procs.Count == 0) break;

            foreach (var (p, shard) in procs)
            {
                string stats = p.StandardOutput.ReadToEnd().Trim();
                p.WaitForExit();
                // Worker's last line: "STATS matches wins draws turns rows"
                var last = stats.Split('\n').LastOrDefault(l => l.StartsWith("STATS "));
                if (last != null)
                {
                    var f = last.Split(' ');
                    done += long.Parse(f[1]);
                    wins += long.Parse(f[2]);
                    draws += long.Parse(f[3]);
                    turnsSum += long.Parse(f[4]);
                    rows += long.Parse(f[5]);
                }
                if (File.Exists(shard))
                {
                    if (TryAppend(shard, outPath))
                        TryDelete(shard);
                    else
                        Console.WriteLine($"[harvest] WARN: could not merge {shard} (locked?) -- left in place, continuing.");
                }
            }
            double perMin = done / Math.Max(0.01, sw.Elapsed.TotalMinutes);
            Console.WriteLine($"[harvest] {done} matches  ({perMin:F1}/min)  draw-rate {100.0 * draws / Math.Max(1, done):F1}%  " +
                              $"avg-turns {(double)turnsSum / Math.Max(1, done):F1}  rows {rows}  elapsed {sw.Elapsed.TotalMinutes:F0}m");
        }
        try { Directory.Delete(shardDir, true); } catch { /* best effort */ }
        Console.WriteLine($"[harvest] DONE  {done} matches, {rows} training rows -> {outPath}");
        Console.WriteLine("[harvest] next: run_fit_value.bat -> run_value_arena.bat (challenger vs live).");
        return 0;
    }

    // ── Worker: play a block of matches, write one shard, print STATS. ──
    private static int WorkerMain(Dictionary<string, string> args, int budget, int depth, long seedBase, bool armed)
    {
        long matches = GetLong(args, "matches", WAVE);
        string shard = args.GetValueOrDefault("shard", "shard.csv");
        var sb = new StringBuilder();
        long wins = 0, draws = 0, turnsSum = 0, rows = 0;
        for (long mi = 0; mi < matches; mi++)
        {
            long seed = seedBase + mi;
            var r = PlayMatch(seed, sb);
            if (r.result == "draw") draws++; else wins++;
            turnsSum += r.turns;
            rows += r.rows;
        }
        File.WriteAllText(shard, sb.ToString());
        Console.WriteLine($"STATS {matches} {wins} {draws} {turnsSum} {rows}");
        return 0;
    }

    private static (string result, int turns, int rows) PlayMatch(long seed, StringBuilder sb)
    {
        var rng = new Random(unchecked((int)seed));
        var w = SimWorld.Generate(rng);
        var a = new Combatant("A", w.SpawnA, (int)Config.Facing.EAST);
        a.Equip(KIT);
        var b = new Combatant("B", w.SpawnB, (int)Config.Facing.WEST);
        b.Equip(KIT);
        var pending = new List<(string line, bool seatA)>();
        int rows = 0;
        string result = "draw";
        int turn = 1;
        for (; turn <= MAX_TURNS; turn++)
        {
            pending.Add((Row(seed, turn, "A", a, b, w.G), true));
            pending.Add((Row(seed, turn, "B", b, a, w.G), false));
            var sa = Choose(a, b, w.G);
            var sb2 = Choose(b, a, w.G);
            var outp = Resolver.Resolve(w.G, a, b, sa, sb2, turn);
            a = outp.A;
            b = outp.B;
            if (outp.Result != "ongoing") { result = outp.Result; break; }
            if (turn % Config.MAP_ROTATE_EVERY == 0)
            {
                var positions = new[] { a.Pos, b.Pos };
                var (crushed, newPos) = SimWorld.RotateBlockers(w, positions);
                a.Pos = newPos[0];
                b.Pos = newPos[1];
                foreach (int idx in crushed)
                {
                    var who = idx == 0 ? a : b;
                    who.Hp = Math.Max(1, who.Hp - Config.MAP_CRUSH_DAMAGE);
                    who.RestReady = false;
                }
            }
        }
        // Outcome column (+1 win / -1 loss per seat / 0 draw), mirror of _flush_csv.
        foreach (var (line, seatA) in pending)
        {
            int z = 0;
            if (result == "a_wins") z = seatA ? 1 : -1;
            else if (result == "b_wins") z = seatA ? -1 : 1;
            sb.Append(line).Append(',').Append(z).Append('\n');
            rows++;
        }
        return (result, Math.Min(turn, MAX_TURNS), rows);
    }

    private static List<PlanAction> Choose(Combatant me, Combatant foe, Grid g)
    {
        Eval.ClearCache();
        var seq = ExtremeAI.ChooseSequence(me, foe, g, null);
        return seq.Count > 0 ? seq : new List<PlanAction> { new("wait") };
    }

    // One training row minus the outcome column. The 28 feature columns come from
    // Eval.ValueFeatures -- the exact vector inference standardizes at play time.
    private static string Row(long seed, int turn, string seat, Combatant me, Combatant foe, Grid g)
    {
        var f = Eval.ValueFeatures(me, foe, g);
        var sb = new StringBuilder(160);
        sb.Append(seed).Append(',').Append(turn).Append(',').Append(seat);
        foreach (double v in f)
        {
            sb.Append(',');
            if (v == Math.Floor(v)) sb.Append((long)v);
            else sb.Append(v.ToString("0.####", CultureInfo.InvariantCulture));
        }
        return sb.ToString();
    }

    // ── Windows-tolerant temp-file IO: antivirus/indexers briefly lock fresh
    // files; retry with backoff, and treat a stubborn lock as a shrug, never a
    // crash -- a stray temp shard is nothing against a lost 16-hour night. ──
    private static bool TryAppend(string src, string dst)
    {
        for (int i = 0; i < 6; i++)
        {
            try
            {
                using var w = new FileStream(dst, FileMode.Append, FileAccess.Write);
                using var r = new FileStream(src, FileMode.Open, FileAccess.Read,
                    FileShare.ReadWrite | FileShare.Delete);
                r.CopyTo(w);
                return true;
            }
            catch (IOException) { System.Threading.Thread.Sleep(300); }
            catch (UnauthorizedAccessException) { System.Threading.Thread.Sleep(300); }
        }
        return false;
    }

    private static void TryDelete(string path)
    {
        for (int i = 0; i < 6; i++)
        {
            try { File.Delete(path); return; }
            catch (IOException) { System.Threading.Thread.Sleep(300); }
            catch (UnauthorizedAccessException) { System.Threading.Thread.Sleep(300); }
        }
    }

    // ── tiny arg plumbing ──
    private static Dictionary<string, string> ParseArgs(string[] raw)
    {
        var outp = new Dictionary<string, string>();
        for (int i = 0; i < raw.Length; i++)
            if (raw[i].StartsWith("--"))
                outp[raw[i][2..]] = (i + 1 < raw.Length && !raw[i + 1].StartsWith("--")) ? raw[++i] : "1";
        return outp;
    }

    private static int GetInt(Dictionary<string, string> a, string k, int dflt)
        => a.TryGetValue(k, out string v) && int.TryParse(v, out int n) ? n : dflt;

    private static long GetLong(Dictionary<string, string> a, string k, long dflt)
        => a.TryGetValue(k, out string v) && long.TryParse(v, out long n) ? n : dflt;
}
