// ValueCfg.cs -- reads the learned judge's cfg (written by FitValue.gd as a
// Godot ConfigFile) WITHOUT Godot: a tiny parser for the exact subset that file
// uses -- [section] headers and `key = <godot literal>` lines where the values
// we need are float arrays (w/mean/std) and an int-pair array (crosses).
// Handles v1 cfgs (no crosses) and v3+ (crosses present). Anything unexpected
// returns false and the runner plays the hand eval -- never crashes a night.
namespace UKO;

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.RegularExpressions;

public static class ValueCfg
{
    public static bool TryArm(string path)
    {
        try
        {
            if (!File.Exists(path)) return false;
            string text = File.ReadAllText(path);
            var w = ParseDoubles(text, "w");
            var mean = ParseDoubles(text, "mean");
            var std = ParseDoubles(text, "std");
            var crosses = ParsePairs(text, "crosses");
            if (w == null || mean == null || std == null) return false;
            int n = 28 + (crosses?.Length ?? 0);
            if (w.Length != n + 1 || mean.Length != n || std.Length != n) return false;
            Eval.VW = w;
            Eval.VMEAN = mean;
            Eval.VSTD = std;
            Eval.VCROSS = crosses ?? Array.Empty<int[]>();
            Eval.VALUE_ON = true;
            return true;
        }
        catch
        {
            return false;
        }
    }

    // `key = [1.0, 2.0, ...]` possibly spanning lines. Godot may also emit
    // typed wrappers; we only match the plain bracket form FitValue produces.
    private static double[] ParseDoubles(string text, string key)
    {
        var m = Regex.Match(text, @"(?m)^" + key + @"\s*=\s*\[(?<body>[^\]]*)\]");
        if (!m.Success) return null;
        string body = m.Groups["body"].Value.Trim();
        if (body == "") return Array.Empty<double>();
        var parts = body.Split(',');
        var outp = new double[parts.Length];
        for (int i = 0; i < parts.Length; i++)
            if (!double.TryParse(parts[i].Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out outp[i]))
                return null;
        return outp;
    }

    // `crosses = [[0, 6], [3, 6], ...]` -- match the outer list, then each pair.
    private static int[][] ParsePairs(string text, string key)
    {
        var m = Regex.Match(text, @"(?m)^" + key + @"\s*=\s*\[(?<body>.*?)\]\s*$",
            RegexOptions.Singleline);
        if (!m.Success) return null;
        var pairs = new List<int[]>();
        foreach (Match pm in Regex.Matches(m.Groups["body"].Value, @"\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]"))
            pairs.Add(new[] {
                int.Parse(pm.Groups[1].Value, CultureInfo.InvariantCulture),
                int.Parse(pm.Groups[2].Value, CultureInfo.InvariantCulture) });
        return pairs.ToArray();
    }
}
