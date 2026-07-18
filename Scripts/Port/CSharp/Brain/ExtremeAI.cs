// ExtremeAI.cs -- C# BRAIN PORT. Faithful port of Scripts/AI/ExtremeAI.gd: the
// equilibrium brain (shallow matrix -> selective+budgeted deepening -> calibrated
// win-prob map -> dominance pruning -> Nash mix -> selective depth-3 refine ->
// bounded exploitation -> support prune -> sample).
// Framework-free: clock = Environment.TickCount64; sampling RNG injectable so the
// harness can compare the deterministic MIX (ChooseMix) instead of the sample.
namespace UKO;

using System;
using System.Collections.Generic;

public static class ExtremeAI
{
	public const double DOM_EPS = 0.001;
	public const double MIN_MIX = 0.05;
	public const double EXPLOIT_TEMP = 3.0;

	public sealed class Profile
	{
		public int BudgetMs, BudgetEndMs, Rows, Cols, RowsEnd, ColsEnd;
		public double Lambda;
	}

	public static readonly Dictionary<string, Profile> Profiles = new()
	{
		["challenging"] = new Profile { BudgetMs = 250, BudgetEndMs = 250, Rows = 3, Cols = 6, RowsEnd = 5, ColsEnd = 9, Lambda = 0.0 },
		["extreme"] = new Profile { BudgetMs = 700, BudgetEndMs = 1400, Rows = 4, Cols = 8, RowsEnd = 6, ColsEnd = 10, Lambda = 0.6 },
	};

	public static Profile P = Profiles["extreme"];
	public static int BudgetOverrideMs = -1;   // sweep dial: -1 = use the profile's budget
	private static readonly Random Rng = new();

	public static void SetProfile(string name)
	{
		P = Profiles.GetValueOrDefault(name, Profiles["extreme"]);
		// Champion shelved (see GDScript note): both tiers play hand defaults.
		Eval.SetWeights(Eval.Defaults);
		// Calibration (CAL_A) is loaded by the BRIDGE from user://calibration.cfg.
	}

	public static List<PlanAction> ChooseSequence(Combatant me, Combatant foe, Grid grid, OpponentModel oppModel = null)
	{
		var r = ChooseMix(me, foe, grid, oppModel);
		return r.Cands[Sample(r.Mix)];
	}

	// GuaranteedValue: min over foe columns of mixᵀM -- the floor this mix secures.
	// Equilibrium "twins" (equally valid equilibria selected under fp drift) share
	// this value, so the agreement harness compares IT rather than raw mix indices.
	public sealed class MixResult
	{
		public List<List<PlanAction>> Cands;
		public double[] Mix;
	
		public double GuaranteedValue;}

	// The whole pipeline up to (but not including) the random sample -- deterministic
	// given unlimited budget, which is what the agreement harness exploits.
	public static MixResult ChooseMix(Combatant me, Combatant foe, Grid grid,
			OpponentModel oppModel = null, int budgetOverrideMs = -1)
	{
		var myCands = Clean(AIToolkit.Candidates(me, foe, grid));
		var foeCands = Clean(AIToolkit.Candidates(foe, me, grid));
		if (myCands.Count == 0)
			return new MixResult { Cands = new() { new() { new PlanAction("rest") } }, Mix = new[] { 1.0 }, GuaranteedValue = 0.0 };
		if (foeCands.Count == 0)
			foeCands = new List<List<PlanAction>> { new() { new PlanAction("rest") } };
		long t0 = Environment.TickCount64;
		int budget = grid.ShrinkLevel >= 2 ? P.BudgetEndMs : P.BudgetMs;
		if (BudgetOverrideMs >= 0) budget = BudgetOverrideMs;
		if (budgetOverrideMs >= 0) budget = budgetOverrideMs;   // explicit param still wins
		Eval.ClearCache();

		// Shallow payoff matrix.
		int n = myCands.Count, m = foeCands.Count;
		var M = new double[n][];
		for (int i = 0; i < n; i++)
		{
			M[i] = new double[m];
			for (int j = 0; j < m; j++)
				M[i][j] = Eval.ScoreRich(me, foe, grid, myCands[i], foeCands[j]);
		}

		// DEPTH: baseline selective deepening, then budgeted extension.
		if (Eval.LOOKAHEAD_DEPTH >= 2)
		{
			int deepRows = grid.ShrinkLevel >= 2 ? P.RowsEnd : P.Rows;
			int deepCols = grid.ShrinkLevel >= 2 ? P.ColsEnd : P.Cols;
			int leaf = Eval.LOOKAHEAD_DEPTH - 1;
			if (grid.ShrinkLevel >= 3) leaf = Eval.LOOKAHEAD_DEPTH;
			var done = new HashSet<(int, int)>();
			foreach (int i in TopRows(M, deepRows))
				foreach (int j in WorstCols(M[i], deepCols))
				{
					M[i][j] = Eval.ScoreDeep(me, foe, grid, myCands[i], foeCands[j], leaf);
					done.Add((i, j));
				}
			foreach (var cell in DeepenOrder(M))
			{
				if (Environment.TickCount64 - t0 >= budget) break;
				if (done.Contains(cell)) continue;
				M[cell.Item1][cell.Item2] = Eval.ScoreDeep(me, foe, grid, myCands[cell.Item1], foeCands[cell.Item2], leaf);
			}
		}

		// Calibrated judgment: convert to win-prob before solving.
		if (Eval.CAL_A > 0.0)
			for (int i = 0; i < n; i++)
				for (int j = 0; j < m; j++)
					M[i][j] = Eval.ToWinprob(M[i][j]);

		var dom = DominanceFilter(M);
		var mix = Expand(NashSolver.Solve(Submatrix(M, dom.Rows, dom.Cols)), dom.Rows, n);

		// DEPTH 3 (selective) inside remaining budget.
		if (Eval.LOOKAHEAD_DEPTH >= 2 && Environment.TickCount64 - t0 < budget)
		{
			int deep2 = Eval.LOOKAHEAD_DEPTH;
			bool touched = false;
			for (int i = 0; i < mix.Length; i++)
			{
				if (mix[i] < 0.10) continue;
				foreach (int j in WorstCols(M[i], P.Cols))
				{
					if (Environment.TickCount64 - t0 >= budget) break;
					double v3 = Eval.ScoreDeep(me, foe, grid, myCands[i], foeCands[j], deep2);
					M[i][j] = Eval.CAL_A > 0.0 ? Eval.ToWinprob(v3) : v3;
					touched = true;
				}
			}
			if (touched)
			{
				dom = DominanceFilter(M);
				mix = Expand(NashSolver.Solve(Submatrix(M, dom.Rows, dom.Cols)), dom.Rows, n);
			}
		}

		// EXPLOITATION: bounded tilt toward punishing observed habits.
		if (oppModel != null && P.Lambda > 0.0 && oppModel.IsWarm())
		{
			string sit = OpponentModel.SituationOf(foe, me, grid);
			var q = Predict(oppModel, foeCands, sit);
			var ev = new double[n];
			for (int i = 0; i < n; i++)
			{
				double e = 0.0;
				for (int j = 0; j < m; j++) e += M[i][j] * q[j];
				ev[i] = e;
			}
			var exploit = Softmax(ev, EXPLOIT_TEMP);
			double lam = P.Lambda * oppModel.Confidence();
			for (int i = 0; i < mix.Length; i++)
				mix[i] = (1.0 - lam) * mix[i] + lam * exploit[i];
		}

		mix = PruneSupport(mix, MIN_MIX);
		double gv = double.PositiveInfinity;
		for (int j = 0; j < m; j++)
		{
			double col = 0.0;
			for (int i2 = 0; i2 < n; i2++) col += mix[i2] * M[i2][j];
			if (col < gv) gv = col;
		}
		return new MixResult { Cands = myCands, Mix = mix, GuaranteedValue = gv };
	}

	private static List<List<PlanAction>> Clean(List<List<PlanAction>> cands)
	{
		var outp = new List<List<PlanAction>>();
		foreach (var s in cands)
			if (s.Count > 0) outp.Add(s);
		return outp;
	}

	public sealed class Dom { public List<int> Rows; public List<int> Cols; }

	// Iterated elimination of strictly dominated moves (rows max, cols min).
	public static Dom DominanceFilter(double[][] M)
	{
		var rows = new List<int>();
		for (int i = 0; i < M.Length; i++) rows.Add(i);
		var cols = new List<int>();
		for (int j = 0; j < M[0].Length; j++) cols.Add(j);
		bool changed = true;
		while (changed)
		{
			changed = false;
			var keepR = new List<int>();
			foreach (int i in rows)
			{
				bool dominated = false;
				foreach (int k in rows)
				{
					if (k == i) continue;
					bool beatsAll = true;
					foreach (int j in cols)
						if (M[k][j] < M[i][j] + DOM_EPS) { beatsAll = false; break; }
					if (beatsAll) { dominated = true; break; }
				}
				if (dominated) changed = true;
				else keepR.Add(i);
			}
			if (keepR.Count > 0) rows = keepR;
			var keepC = new List<int>();
			foreach (int j in cols)
			{
				bool dominated2 = false;
				foreach (int l in cols)
				{
					if (l == j) continue;
					bool lowerAll = true;
					foreach (int i in rows)
						if (M[i][l] > M[i][j] - DOM_EPS) { lowerAll = false; break; }
					if (lowerAll) { dominated2 = true; break; }
				}
				if (dominated2) changed = true;
				else keepC.Add(j);
			}
			if (keepC.Count > 0) cols = keepC;
		}
		return new Dom { Rows = rows, Cols = cols };
	}

	public static double[][] Submatrix(double[][] M, List<int> rows, List<int> cols)
	{
		var outp = new double[rows.Count][];
		for (int a = 0; a < rows.Count; a++)
		{
			outp[a] = new double[cols.Count];
			for (int b = 0; b < cols.Count; b++)
				outp[a][b] = M[rows[a]][cols[b]];
		}
		return outp;
	}

	private static double[] Expand(double[] mix, List<int> rows, int n)
	{
		var outp = new double[n];
		for (int k = 0; k < rows.Count; k++)
			outp[rows[k]] = mix[k];
		return outp;
	}

	// Rows with the best WORST-CASE value; STABLE descending (GDScript insertion sort).
	// Mirrors ExtremeAI.gd._rq: selection ranks on a 1e-4 grid so ulp-scale eval
	// drift between the engines can never pick different cells to deepen.
	private static double Rq(double v) => Math.Floor(v * 1e4 + 0.5) / 1e4;

	private static List<int> TopRows(double[][] M, int k)
	{
		var worst = new double[M.Length];
		for (int i = 0; i < M.Length; i++)
		{
			double w = double.PositiveInfinity;
			foreach (var v in M[i]) w = Math.Min(w, v);
			worst[i] = Rq(w);
		}
		var idx = new List<int>();
		for (int i = 0; i < M.Length; i++) idx.Add(i);
		idx.Sort((a, b) => { int c = worst[b].CompareTo(worst[a]); return c != 0 ? c : a.CompareTo(b); });
		var outp = new List<int>();
		for (int n2 = 0; n2 < Math.Min(k, idx.Count); n2++) outp.Add(idx[n2]);
		return outp;
	}

	// The k lowest cells of a row; STABLE ascending.
	private static List<int> WorstCols(double[] row, int k)
	{
		var q = new double[row.Length];
		for (int j = 0; j < row.Length; j++) q[j] = Rq(row[j]);
		var idx = new List<int>();
		for (int j = 0; j < row.Length; j++) idx.Add(j);
		idx.Sort((a, b) => { int c = q[a].CompareTo(q[b]); return c != 0 ? c : a.CompareTo(b); });
		var outp = new List<int>();
		for (int n2 = 0; n2 < Math.Min(k, idx.Count); n2++) outp.Add(idx[n2]);
		return outp;
	}

	private static List<(int, int)> DeepenOrder(double[][] M)
	{
		var outp = new List<(int, int)>();
		foreach (int i in TopRows(M, M.Length))
			foreach (int j in WorstCols(M[i], M[i].Length))
				outp.Add((i, j));
		return outp;
	}

	private static double[] Predict(OpponentModel oppModel, List<List<PlanAction>> foeCands, string sit)
	{
		var w = new double[foeCands.Count];
		double tot = 0.0;
		for (int i = 0; i < foeCands.Count; i++)
		{
			w[i] = oppModel.WeightOf(foeCands[i], sit);
			tot += w[i];
		}
		if (tot <= 0.0) return Uniform(foeCands.Count);
		for (int i = 0; i < w.Length; i++) w[i] /= tot;
		return w;
	}

	private static double[] Softmax(double[] xs, double temp)
	{
		if (xs.Length == 0) return Array.Empty<double>();
		double hi = double.NegativeInfinity;
		foreach (var x in xs) hi = Math.Max(hi, x);
		var outp = new double[xs.Length];
		double z = 0.0;
		for (int i = 0; i < xs.Length; i++)
		{
			outp[i] = Math.Exp((xs[i] - hi) / Math.Max(0.0001, temp));
			z += outp[i];
		}
		for (int i = 0; i < outp.Length; i++) outp[i] /= z;
		return outp;
	}

	private static double[] Uniform(int n)
	{
		var outp = new double[n];
		double p = n > 0 ? 1.0 / n : 0.0;
		for (int i = 0; i < n; i++) outp[i] = p;
		return outp;
	}

	private static double[] PruneSupport(double[] mix, double floorP)
	{
		var outp = new double[mix.Length];
		double tot = 0.0;
		for (int i = 0; i < mix.Length; i++)
		{
			outp[i] = mix[i] >= floorP ? mix[i] : 0.0;
			tot += outp[i];
		}
		if (tot <= 0.0) return mix;
		for (int i = 0; i < outp.Length; i++) outp[i] /= tot;
		return outp;
	}

	private static int Sample(double[] dist)
	{
		double r = Rng.NextDouble();
		double acc = 0.0;
		for (int i = 0; i < dist.Length; i++)
		{
			acc += dist[i];
			if (r <= acc) return i;
		}
		return Math.Max(0, dist.Length - 1);
	}
}
