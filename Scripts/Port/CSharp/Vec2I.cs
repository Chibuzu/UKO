// Vec2I.cs -- C# ENGINE PORT (stage 1). A tiny framework-free integer vector so the
// ported engine (Config/Combatant/Grid/Resolver) stays Godot-independent: it compiles
// and unit-tests outside Godot, runs without marshaling, and a thin adapter converts
// Godot.Vector2I <-> Vec2I at the GDScript boundary later. Semantics mirror Godot's
// Vector2I exactly for the ops the engine uses (component-wise +/-, scalar *, sign).
namespace UKO;

using System;

public readonly struct Vec2I : IEquatable<Vec2I>
{
	public readonly int X;
	public readonly int Y;
	public Vec2I(int x, int y) { X = x; Y = y; }

	public static Vec2I operator +(Vec2I a, Vec2I b) => new(a.X + b.X, a.Y + b.Y);
	public static Vec2I operator -(Vec2I a, Vec2I b) => new(a.X - b.X, a.Y - b.Y);
	public static Vec2I operator -(Vec2I a) => new(-a.X, -a.Y);
	public static Vec2I operator *(Vec2I a, int s) => new(a.X * s, a.Y * s);

	public bool Equals(Vec2I o) => X == o.X && Y == o.Y;
	public override bool Equals(object obj) => obj is Vec2I v && Equals(v);
	public override int GetHashCode() => HashCode.Combine(X, Y);
	public static bool operator ==(Vec2I a, Vec2I b) => a.Equals(b);
	public static bool operator !=(Vec2I a, Vec2I b) => !a.Equals(b);
	public override string ToString() => $"({X}, {Y})";

	public Vec2I Sign() => new(Math.Sign(X), Math.Sign(Y));

	// Grid.dist (Manhattan) and Grid.cheb (Chebyshev), kept here so callers share one definition.
	public static int Man(Vec2I a, Vec2I b) => Math.Abs(a.X - b.X) + Math.Abs(a.Y - b.Y);
	public static int Cheb(Vec2I a, Vec2I b) => Math.Max(Math.Abs(a.X - b.X), Math.Abs(a.Y - b.Y));
}
