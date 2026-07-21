// TrainingCsv.cs -- THE training-row format, shared by every C# harvester (the
// fast HarvestRunner and the online GameServer). One place owns the header and
// the row layout; the 28 feature columns come from Eval.ValueFeatures -- the
// exact vector inference standardizes at play time, so harvest, fit, and live
// judging can never drift apart. Mirrors OvernightSweep.gd's CSV byte-for-byte.
namespace UKO;

using System;
using System.Globalization;
using System.Text;

public static class TrainingCsv
{
    public const string HEADER =
        "seed,turn,seat,hp,mp,energy,foe_hp,foe_mp,foe_energy,dist,shrink,my_ac,foe_ac,my_nade,foe_nade,my_flank,foe_flank,my_to_pulse,foe_to_pulse,my_locked,foe_locked,my_noguard,foe_noguard,my_rest_ready,foe_rest_ready,my_cd_burst,my_cd_bolt,foe_cd_burst,foe_cd_bolt,my_cc,foe_cc,outcome";

    // One row minus the outcome column (appended at match end when the result is known).
    public static string Row(long seed, int turn, string seat, Combatant me, Combatant foe, Grid g)
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

    // Outcome from a seat's perspective: +1 win / -1 loss / 0 draw.
    public static int Outcome(string result, bool seatA)
    {
        if (result == "a_wins") return seatA ? 1 : -1;
        if (result == "b_wins") return seatA ? -1 : 1;
        return 0;
    }
}
