// FitValue.cs -- the value-function fitter at HARVEST SCALE (round 21). An exact
// port of Scripts/AI/Tuning/FitValue.gd (the spec file; change the CROSSES list
// THERE and mirror it here), rebuilt in C# because the GDScript fitter was born
// at 21k rows and the fast harvest now banks MILLIONS -- this one chews ~5M rows
// in about a minute instead of hours.
//
// Same everything, deliberately: 28 base features + the same 22 hand-chosen
// crosses, draws skipped, 80/20 train/val split BY MATCH SEED (row-level splits
// leak), standardization on TRAIN stats, full-batch logistic regression at
// LR 1.0 for 400 epochs, bias last. DETERMINISTIC despite parallelism: rows are
// summed in fixed chunk ranges and the chunks are combined in index order, so
// the gradient never depends on thread scheduling.
//
// Output: value_fn_new.cfg in Godot ConfigFile text format (hand-emitted; both
// Eval.gd.load_value_fn and BrainBridge.ParseValueCfg read it unchanged). The
// CHALLENGER path only -- it goes live via the arena + gates + promote ritual.
namespace UKO;

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

public static class FitValue
{
    private const int N_BASE = 28;
    private const int EPOCHS = 400;
    private const double LR = 1.0;
    private const double VAL_FRACTION = 0.2;

    private static readonly string[] FEATURE_NAMES = {
        "hp", "mp", "energy", "foe_hp", "foe_mp", "foe_energy",
        "dist", "shrink", "my_ac", "foe_ac", "my_nade", "foe_nade", "my_flank", "foe_flank",
        "my_to_pulse", "foe_to_pulse", "my_locked", "foe_locked", "my_noguard", "foe_noguard",
        "my_rest_ready", "foe_rest_ready", "my_cd_burst", "my_cd_bolt", "foe_cd_burst",
        "foe_cd_bolt", "my_cc", "foe_cc",
    };

    // MIRROR of FitValue.gd CROSSES -- the interactions the duel actually runs on.
    private static readonly int[][] CROSSES = {
        new[]{0, 6}, new[]{3, 6},        // hp x dist, foe_hp x dist
        new[]{2, 6}, new[]{5, 6},        // energy x dist, foe_energy x dist
        new[]{1, 6}, new[]{4, 6},        // mp x dist, foe_mp x dist
        new[]{0, 3},                     // hp x foe_hp
        new[]{0, 7}, new[]{3, 7},        // hp x shrink, foe_hp x shrink
        new[]{16, 6}, new[]{17, 6},      // locked x dist
        new[]{18, 5}, new[]{19, 2},      // noguard x foe_energy (both ways)
        new[]{20, 6}, new[]{21, 6},      // rest_ready x dist
        new[]{26, 6}, new[]{27, 6},      // cc x dist
        new[]{0, 4}, new[]{3, 1},        // hp x foe_mp, foe_hp x mp
        new[]{6, 6}, new[]{0, 0}, new[]{3, 3},   // dist^2, hp^2, foe_hp^2
    };

    public static int Run(string csvPath, string outPath)
    {
        var sw = Stopwatch.StartNew();
        Console.WriteLine($"[fit] reading {csvPath} ...");
        if (!File.Exists(csvPath))
        {
            Console.WriteLine($"[fit] ERROR: {csvPath} not found -- run the harvest first.");
            return 1;
        }
        int nFeat = N_BASE + CROSSES.Length;
        var xs = new List<float[]>(1 << 20);
        var ys = new List<byte>(1 << 20);
        var seeds = new List<long>(1 << 20);
        long draws = 0, bad = 0;
        bool first = true;
        foreach (string raw in File.ReadLines(csvPath))
        {
            string line = raw.Trim();
            if (line.Length == 0) continue;
            if (first)
            {
                first = false;
                if (line.StartsWith("seed")) continue;
            }
            string[] c = line.Split(',');
            if (c.Length != N_BASE + 4) { bad++; continue; }
            if (!int.TryParse(c[^1], NumberStyles.Integer, CultureInfo.InvariantCulture, out int z)) { bad++; continue; }
            if (z == 0) { draws++; continue; }
            var row = new float[nFeat];
            bool ok = true;
            for (int i = 0; i < N_BASE; i++)
                if (double.TryParse(c[3 + i], NumberStyles.Float, CultureInfo.InvariantCulture, out double v))
                    row[i] = (float)v;
                else { ok = false; break; }
            if (!ok) { bad++; continue; }
            for (int k = 0; k < CROSSES.Length; k++)
                row[N_BASE + k] = row[CROSSES[k][0]] * row[CROSSES[k][1]];
            xs.Add(row);
            ys.Add((byte)(z > 0 ? 1 : 0));
            seeds.Add(long.TryParse(c[0], out long sd) ? sd : 0);
        }
        int n = xs.Count;
        Console.WriteLine($"[fit] {n} rows, {nFeat} features (28 base + {CROSSES.Length} crosses) " +
                          $"(skipped {draws} draw rows, {bad} malformed)  [{sw.Elapsed.TotalSeconds:F0}s]");
        if (n < 500)
        {
            Console.WriteLine("[fit] ERROR: not enough data to fit -- need a harvest night.");
            return 1;
        }

        // ── split BY MATCH SEED: last 20% of the sorted unique seeds are validation ──
        var seedList = seeds.Distinct().ToList();
        seedList.Sort();
        int nValSeeds = (int)(seedList.Count * VAL_FRACTION);
        var valSet = new HashSet<long>(seedList.Skip(seedList.Count - nValSeeds));
        var trIdx = new List<int>(n);
        var vaIdx = new List<int>(n);
        for (int i = 0; i < n; i++)
            (valSet.Contains(seeds[i]) ? vaIdx : trIdx).Add(i);
        Console.WriteLine($"[fit] split: {trIdx.Count} train rows ({seedList.Count - nValSeeds} matches) / " +
                          $"{vaIdx.Count} val rows ({nValSeeds} matches)");

        // ── standardize on TRAIN statistics (stored in the cfg for inference) ──
        var mean = new double[nFeat];
        var std = new double[nFeat];
        foreach (int i in trIdx)
        {
            var r = xs[i];
            for (int j = 0; j < nFeat; j++) mean[j] += r[j];
        }
        for (int j = 0; j < nFeat; j++) mean[j] /= trIdx.Count;
        foreach (int i in trIdx)
        {
            var r = xs[i];
            for (int j = 0; j < nFeat; j++) { double d = r[j] - mean[j]; std[j] += d * d; }
        }
        for (int j = 0; j < nFeat; j++) std[j] = Math.Sqrt(std[j] / trIdx.Count);
        Parallel.For(0, n, i =>
        {
            var r = xs[i];
            for (int j = 0; j < nFeat; j++)
            {
                double sd2 = std[j];
                r[j] = (float)((r[j] - mean[j]) / (sd2 > 0.0 ? sd2 : 1.0));
            }
        });

        // ── full-batch logistic regression; deterministic chunked parallelism ──
        var w = new double[nFeat + 1];
        int ntr = trIdx.Count;
        int chunks = Math.Min(64, Math.Max(1, ntr / 10000));
        var ranges = new (int lo, int hi)[chunks];
        for (int cix = 0; cix < chunks; cix++)
            ranges[cix] = (ntr * cix / chunks, ntr * (cix + 1) / chunks);
        var partial = new double[chunks][];
        var partialStats = new (double loss, long correct)[chunks];
        for (int epoch = 0; epoch < EPOCHS; epoch++)
        {
            Parallel.For(0, chunks, cix =>
            {
                var g = new double[nFeat + 1];
                double loss = 0; long correct = 0;
                var (lo, hi) = ranges[cix];
                for (int t = lo; t < hi; t++)
                {
                    int i = trIdx[t];
                    var r = xs[i];
                    double z = w[nFeat];
                    for (int j = 0; j < nFeat; j++) z += w[j] * r[j];
                    double p = 1.0 / (1.0 + Math.Exp(-z));
                    double y = ys[i];
                    loss += -(y * Math.Log(Math.Max(p, 1e-12)) + (1.0 - y) * Math.Log(Math.Max(1.0 - p, 1e-12)));
                    if ((p >= 0.5) == (y >= 0.5)) correct++;
                    double err = p - y;
                    for (int j = 0; j < nFeat; j++) g[j] += err * r[j];
                    g[nFeat] += err;
                }
                partial[cix] = g;
                partialStats[cix] = (loss, correct);
            });
            var grad = new double[nFeat + 1];
            double eLoss = 0; long eCorrect = 0;
            for (int cix = 0; cix < chunks; cix++)   // fixed order -> deterministic sums
            {
                var g = partial[cix];
                for (int j = 0; j <= nFeat; j++) grad[j] += g[j];
                eLoss += partialStats[cix].loss;
                eCorrect += partialStats[cix].correct;
            }
            for (int j = 0; j <= nFeat; j++) w[j] -= LR * grad[j] / ntr;
            if ((epoch + 1) % 50 == 0)
                Console.WriteLine($"[fit] epoch {epoch + 1}  train log-loss {eLoss / ntr:F4}  " +
                                  $"acc {100.0 * eCorrect / ntr:F1}%  [{sw.Elapsed.TotalSeconds:F0}s]");
        }

        // ── honest quality: the held-out validation matches ──
        double vaLoss = 0; long vaCorrect = 0;
        foreach (int i in vaIdx)
        {
            var r = xs[i];
            double z = w[nFeat];
            for (int j = 0; j < nFeat; j++) z += w[j] * r[j];
            double p = 1.0 / (1.0 + Math.Exp(-z));
            double y = ys[i];
            vaLoss += -(y * Math.Log(Math.Max(p, 1e-12)) + (1.0 - y) * Math.Log(Math.Max(1.0 - p, 1e-12)));
            if ((p >= 0.5) == (y >= 0.5)) vaCorrect++;
        }
        double acc = 100.0 * vaCorrect / Math.Max(1, vaIdx.Count);
        Console.WriteLine($"[fit] FINAL  VALIDATION log-loss {vaLoss / Math.Max(1, vaIdx.Count):F4}  " +
                          $"accuracy {acc:F1}%  (coin flip = 50%)");

        // ── the story the weights tell ──
        var ranked = Enumerable.Range(0, nFeat)
            .Select(j => (name: j < N_BASE ? FEATURE_NAMES[j]
                : $"{FEATURE_NAMES[CROSSES[j - N_BASE][0]]}*{FEATURE_NAMES[CROSSES[j - N_BASE][1]]}", wj: w[j]))
            .OrderByDescending(t => Math.Abs(t.wj)).Take(10);
        Console.WriteLine("[fit] strongest signals (standardized weights):");
        foreach (var (name, wj) in ranked)
            Console.WriteLine($"      {name,-24} {wj:+0.000;-0.000}");

        // ── emit Godot ConfigFile text (Eval.gd + BrainBridge read this verbatim) ──
        var sb = new StringBuilder();
        sb.Append("[value]\n\n");
        sb.Append("w=").Append(FloatArray(w)).Append('\n');
        sb.Append("mean=").Append(FloatArray(mean)).Append('\n');
        sb.Append("std=").Append(FloatArray(std)).Append('\n');
        sb.Append("crosses=[").Append(string.Join(", ", CROSSES.Select(c2 => $"[{c2[0]}, {c2[1]}]"))).Append("]\n");
        sb.Append("n=").Append(n).Append('\n');
        sb.Append("acc=").Append(Num(acc)).Append('\n');
        sb.Append("names=[").Append(string.Join(", ", FEATURE_NAMES.Select(s => $"\"{s}\""))).Append("]\n");
        File.WriteAllText(outPath, sb.ToString());
        Console.WriteLine($"[fit] wrote {outPath} (the CHALLENGER) -- next: run_value_arena.bat (champion vs challenger).");
        Console.WriteLine("[fit] it goes live ONLY via run_promote_value.bat after winning the arena + gates.");
        return 0;
    }

    // A number Godot's expression parser reads back as a FLOAT (always a '.' or exponent).
    private static string Num(double v)
    {
        string s = v.ToString("R", CultureInfo.InvariantCulture);
        if (!s.Contains('.') && !s.Contains('E') && !s.Contains('e')) s += ".0";
        return s;
    }

    private static string FloatArray(double[] a)
        => "[" + string.Join(", ", a.Select(Num)) + "]";
}
