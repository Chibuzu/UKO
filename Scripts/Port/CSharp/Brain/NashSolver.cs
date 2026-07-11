// NashSolver.cs -- C# BRAIN PORT. Faithful port of Scripts/AI/NashSolver.gd:
// zero-sum matrix game -> row player's optimal mixed strategy via regret matching.
// Fully deterministic (no RNG): the agreement harness compares mixes to ~1e-9.
namespace UKO;

using System;

public static class NashSolver
{
	public const int ITERS = 600;

	public static double[] Solve(double[][] M) => SolveIters(M, ITERS);

	public static double[] SolveIters(double[][] M, int iters)
	{
		int n = M.Length;
		if (n == 0) return Array.Empty<double>();
		int m = M[0].Length;
		if (m == 0) return Uniform(n);
		// PAYOFF QUANTIZATION -- mirrors NashSolver.gd exactly (see its comment):
		// round to a 1e-6 grid so ulp-level eval drift between the two engines can
		// never flip equilibrium selection. Copy first: callers may reuse M.
		var Q = new double[n][];
		for (int r = 0; r < n; r++)
		{
			Q[r] = new double[m];
			for (int c2 = 0; c2 < m; c2++)
				Q[r][c2] = Math.Floor(M[r][c2] * 1e6 + 0.5) / 1e6;
		}
		M = Q;

		var regR = new double[n];
		var regC = new double[m];
		var sumR = new double[n];
		var ur = new double[n];
		var uc = new double[m];

		for (int t = 0; t < iters; t++)
		{
			var sr = Strategy(regR);
			var sc = Strategy(regC);

			for (int i = 0; i < n; i++)
			{
				double s = 0.0;
				for (int j = 0; j < m; j++) s += M[i][j] * sc[j];
				ur[i] = s;
			}
			double evr = 0.0;
			for (int i = 0; i < n; i++) evr += sr[i] * ur[i];
			for (int i = 0; i < n; i++) regR[i] += ur[i] - evr;

			for (int j = 0; j < m; j++)
			{
				double s2 = 0.0;
				for (int i = 0; i < n; i++) s2 += -M[i][j] * sr[i];
				uc[j] = s2;
			}
			double evc = 0.0;
			for (int j = 0; j < m; j++) evc += sc[j] * uc[j];
			for (int j = 0; j < m; j++) regC[j] += uc[j] - evc;

			for (int i = 0; i < n; i++) sumR[i] += sr[i];
		}
		return Normalize(sumR);
	}

	public static double ValueOf(double[][] M, double[] rowMix)
	{
		int n = M.Length;
		if (n == 0) return 0.0;
		int m = M[0].Length;
		if (m == 0) return 0.0;
		double worst = double.PositiveInfinity;
		for (int j = 0; j < m; j++)
		{
			double cv = 0.0;
			for (int i = 0; i < n; i++) cv += rowMix[i] * M[i][j];
			worst = Math.Min(worst, cv);
		}
		return worst;
	}

	private static double[] Strategy(double[] regret)
	{
		int n = regret.Length;
		var pos = new double[n];
		double tot = 0.0;
		for (int i = 0; i < n; i++)
		{
			pos[i] = Math.Max(0.0, regret[i]);
			tot += pos[i];
		}
		if (tot <= 0.0) return Uniform(n);
		for (int i = 0; i < n; i++) pos[i] /= tot;
		return pos;
	}

	private static double[] Normalize(double[] v)
	{
		double tot = 0.0;
		foreach (var x in v) tot += x;
		if (tot <= 0.0) return Uniform(v.Length);
		var outp = new double[v.Length];
		for (int i = 0; i < v.Length; i++) outp[i] = v[i] / tot;
		return outp;
	}

	private static double[] Uniform(int n)
	{
		var outp = new double[n];
		double p = n > 0 ? 1.0 / n : 0.0;
		for (int i = 0; i < n; i++) outp[i] = p;
		return outp;
	}
}
