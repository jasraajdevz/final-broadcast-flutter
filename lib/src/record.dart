// FINAL BROADCAST — THE RECORD.
//
// "make it a psychological horror ... and have an outcome to whatever u do"
//
// Everything in this game has consequences that last exactly one night. You
// take the carrier down and dread spikes; the night ends; it is forgotten. You
// take the sponsor's money and get a worse revive; the night ends; forgotten.
// Nothing you do has ever followed you.
//
// That is the difference between a scary game and a psychological one. A scary
// game frightens you in the moment. A psychological one makes you responsible
// for something, remembers it, and lets you feel it being remembered.
//
// The record is what the station has decided about you. It is built only from
// things the player CHOSE — never from things that were done to them — because
// being judged for bad luck is unfair and being judged for your own decisions
// is the whole point.
//
// It never announces itself. There is no "REPUTATION: 42" anywhere. It surfaces
// as the archive's tone, as what the sign-off sheet says, and as what arrives
// on the tube. The player is supposed to notice that the paperwork has started
// describing someone they recognise.

import 'dart:math' as math;

import 'state.dart';

/// The four things the station keeps count of. Each one is a decision the
/// operator made, repeatedly, when they could have done otherwise.
enum Mark {
  /// Took the lid off. The one act the whole fiction says never to commit.
  hand,

  /// Beat on live transmission equipment instead of answering.
  panic,

  /// Took the sponsor's money rather than accept the loss.
  debt,

  /// Left the book unsigned while something was in the room.
  neglect,
}

extension MarkKey on Mark {
  String get key => switch (this) {
        Mark.hand => 'hand',
        Mark.panic => 'panic',
        Mark.debt => 'debt',
        Mark.neglect => 'neglect',
      };
}

/// How many times the operator has done this, across the whole career.
int markOf(GameState s, Mark m) => s.record[m.key] ?? 0;

void addMark(GameState s, Mark m, [int n = 1]) {
  s.record[m.key] = markOf(s, m) + n;
}

/// The thresholds at which the station starts to have an opinion. Deliberately
/// high enough that a player doing these things occasionally is never judged —
/// only a pattern counts, because a pattern is a choice and an incident is not.
const Map<Mark, int> kMarkNotices = <Mark, int>{
  Mark.hand: 3,
  Mark.panic: 40,
  Mark.debt: 4,
  Mark.neglect: 12,
};

bool noticed(GameState s, Mark m) => markOf(s, m) >= (kMarkNotices[m] ?? 999);

/// How heavily, 0..1, for anything that wants to scale by it.
double weightOf(GameState s, Mark m) {
  final need = kMarkNotices[m] ?? 999;
  return (markOf(s, m) / (need * 3)).clamp(0.0, 1.0);
}

/// The single thing the station has most decided about this operator, or null
/// while they are still unremarkable.
Mark? dominant(GameState s) {
  Mark? best;
  var bestW = 0.0;
  for (final m in Mark.values) {
    if (!noticed(s, m)) continue;
    final w = weightOf(s, m);
    if (w > bestW) {
      bestW = w;
      best = m;
    }
  }
  return best;
}

/// What the paperwork has started calling them. One line, in the register of a
/// personnel note — never a score, never a label the player can farm.
String? recordLine(GameState s) {
  final m = dominant(s);
  if (m == null) return null;
  final n = markOf(s, m);
  return switch (m) {
    Mark.hand => 'Has taken the carrier down $n times. The first operator to '
        'do it more than once. We have stopped writing the date.',
    Mark.panic => 'Strikes the glass when he does not know the answer. $n '
        'recorded blows. The set is not built for it and neither is he.',
    Mark.debt => 'Has accepted emergency sponsorship $n times. The account is '
        'settled at the end of the arrangement, not during it.',
    Mark.neglect => 'Has left the book unsigned $n times with something in the '
        'room. The hour is still missing from the log and always will be.',
  };
}

/// A short form for the sign-off sheet — the station's summary of the shift's
/// author rather than of the shift.
String? verdictLine(GameState s) {
  final m = dominant(s);
  if (m == null) return null;
  return switch (m) {
    Mark.hand => 'THE ONE WHO TURNS IT OFF',
    Mark.panic => 'THE ONE WHO HITS IT',
    Mark.debt => 'THE ONE WHO TAKES THE MONEY',
    Mark.neglect => 'THE ONE WHO DOES NOT WRITE IT DOWN',
  };
}

// ---------------------------------------------------------------------------
// THE OUTCOMES
//
// Each mark bends the game itself, so the record is a mechanic and not a mood
// board. Every effect is bounded, and every one of them is a consequence of a
// decision rather than of luck.
// ---------------------------------------------------------------------------

/// The lid remembers being lifted: arrivals come sooner for an operator who
/// has taken it down. Up to 22% off the gap.
double recordGapMul(GameState s) => 1 - 0.22 * weightOf(s, Mark.hand);

/// A set that has been beaten holds its picture worse: the window is shorter
/// for an operator who fights it. Up to 14% off.
double recordWindowMul(GameState s) => 1 - 0.14 * weightOf(s, Mark.panic);

/// The account is settled at the end. Sponsorship costs prestige, later.
double recordRpMul(GameState s) => 1 - 0.30 * weightOf(s, Mark.debt);

/// An unwritten hour does not decay. Dread bleeds off slower.
double recordDecayMul(GameState s) => 1 - 0.25 * weightOf(s, Mark.neglect);

/// Nothing here may compound into an unwinnable game, so the worst possible
/// record still leaves every dial inside a survivable band. Asserted in tests.
double worstCase() => math.min(
    math.min(recordGapMulAt(1), recordWindowMulAt(1)),
    math.min(recordRpMulAt(1), recordDecayMulAt(1)));

double recordGapMulAt(double w) => 1 - 0.22 * w;
double recordWindowMulAt(double w) => 1 - 0.14 * w;
double recordRpMulAt(double w) => 1 - 0.30 * w;
double recordDecayMulAt(double w) => 1 - 0.25 * w;
