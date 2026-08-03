// FINAL BROADCAST — THE ROSTER.
//
// "a crystal clear progression loop that keeps the player hooked for a long
//  time and keeps the fear factor as a compliment to the addictive loop"
//
// The game already had progression — SIGNAL, transmitters, RATINGS POINTS, a
// station board, night cards, 28 archive documents. What it did not have was a
// SPINE: one legible thing you are climbing, visible at all times, with a named
// next rung and a distance to it. Currencies are not a progression loop. A
// progression loop is knowing what you are working toward and how close you
// are, at every single moment, without opening a menu.
//
// The spine is the roster, because the lore already wrote it: the payroll memo
// in the archive says twenty-two names in twenty-four years on a one-man post.
// You are the twenty-third. You do not level up — you OUTLAST the people who
// sat in this chair before you, one at a time, and the game tells you exactly
// whose record you are standing on and whose is next.
//
// That is why the fear complements the loop instead of fighting it. Every rung
// is a person who did this job and stopped doing it, the rungs get further
// apart, and the last name on the list held the chair for 1,114 nights and did
// not sign off on the morning of the 1,115th.

import 'archive.dart';
import 'state.dart';

/// One operator who sat here before you.
class Operator {
  const Operator({
    required this.name,
    required this.nights,
    required this.rank,
    required this.fate,
    this.unlock,
  });

  /// As it appears on the payroll.
  final String name;

  /// Nights they lasted. Passing this is the rung.
  final int nights;

  /// What the station calls you once you have passed them.
  final String rank;

  /// One line. Never says "died" — the paperwork would not.
  final String fate;

  /// What passing them hands you, if anything. Kept concrete and mechanical:
  /// a rung that pays only a title is a leaderboard, not a progression loop.
  final String? unlock;
}

/// Twenty-two names, then you. Thresholds are deliberately close together at
/// the bottom — four rungs inside the first ten nights, so the ladder is
/// legible before it is long — and stretch out fast, because the research on
/// incremental pacing is consistent that early rungs must land quickly or the
/// player never learns the shape of the climb.
const List<Operator> kRoster = <Operator>[
  Operator(
    name: 'D. KEEL',
    nights: 1,
    rank: 'PROBATIONARY',
    fate: 'Did not come back for a second shift. Left the badge on the desk.',
    unlock: 'THE CANTEEN opens.',
  ),
  Operator(
    name: 'M. ARDEN',
    nights: 2,
    rank: 'NIGHT OPERATOR',
    fate: 'Resigned by telephone, at 06:04, from a call box outside.',
    unlock: 'THE FILE — one document recovered from the desk every night.',
  ),
  Operator(
    name: 'S. BRIGHT',
    nights: 4,
    rank: 'OPERATOR, SECOND CLASS',
    fate: 'Transferred to daytime. Would not say why in writing.',
    unlock: 'THE STATION BOARD — permanent upgrades bought with RATINGS POINTS.',
  ),
  Operator(
    name: 'R. OKONKWO',
    nights: 7,
    rank: 'OPERATOR, FIRST CLASS',
    fate: 'Took the annual leave he was owed and did not use the return half.',
    unlock: 'THE TOOL RACK — charged equipment on the Q-T row.',
  ),
  Operator(
    name: 'J. FENN',
    nights: 11,
    rank: 'SENIOR OPERATOR',
    fate: 'Signed off every morning for eleven days and then simply did not '
        'sign on.',
    unlock: 'AUTOMATION — the bots on the AUTO tab.',
  ),
  Operator(
    name: 'A. VOSS',
    nights: 16,
    rank: 'DUTY OPERATOR',
    fate: 'Requested a second operator in writing four times. Filed the '
        'refusals in date order.',
    unlock: 'A ninth key. It is not on the deck yet.',
  ),
  Operator(
    name: 'P. LARSSON',
    nights: 23,
    rank: 'SHIFT SUPERVISOR',
    fate: 'Kept a tally on the underside of the desk. It stops at 23.',
  ),
  Operator(
    name: 'E. MARSH',
    nights: 32,
    rank: 'DUTY SUPERVISOR',
    fate: 'Wrote "IT IS NOT THE NOISE" on the wall behind the rack. It is '
        'still there.',
  ),
  Operator(
    name: 'C. IVERS',
    nights: 45,
    rank: 'TRANSMISSION CONTROLLER',
    fate: 'Stopped using the corridor. Slept in the booth for the last three '
        'weeks of it.',
  ),
  Operator(
    name: 'B. NAKASHIMA',
    nights: 62,
    rank: 'SENIOR CONTROLLER',
    fate: 'Asked the day staff to stop leaving him notes. They had not been '
        'leaving him notes.',
  ),
  Operator(
    name: 'T. GRUBER',
    nights: 84,
    rank: 'CHIEF OPERATOR',
    fate: 'Logged every hour of every shift. The last forty entries are in '
        'someone else\'s hand.',
  ),
  Operator(
    name: 'W. ODELL',
    nights: 112,
    rank: 'DUTY ENGINEER',
    fate: 'Climbed the mast once. Would not say what the handholds were.',
  ),
  Operator(
    name: 'N. PRYCE',
    nights: 150,
    rank: 'SENIOR ENGINEER',
    fate: 'Requested the booth window be bricked up. The request was approved '
        'and never carried out.',
  ),
  Operator(
    name: 'F. AMANI',
    nights: 200,
    rank: 'TRANSMISSION ENGINEER',
    fate: 'Two hundred nights without a single missed quota. No note, no '
        'resignation, no last shift.',
  ),
  Operator(
    name: 'K. SOLT',
    nights: 268,
    rank: 'STATION ENGINEER',
    fate: 'Started signing the book with the previous operator\'s name. '
        'Nobody corrected him.',
  ),
  Operator(
    name: 'H. VANCE',
    nights: 355,
    rank: 'DUTY MANAGER',
    fate: 'The only one who ever turned the carrier down. For nine seconds.',
  ),
  Operator(
    name: 'G. REEDY',
    nights: 470,
    rank: 'NIGHT MANAGER',
    fate: 'Left a full flask and a coat on the back of the chair. Both are '
        'still there.',
  ),
  Operator(
    name: 'L. ASHE',
    nights: 620,
    rank: 'SENIOR NIGHT MANAGER',
    fate: 'Stopped appearing in the day staff\'s accounts of the handover, '
        'while continuing to attend it.',
  ),
  Operator(
    name: 'V. CORRIGAN',
    nights: 810,
    rank: 'CONTROLLER OF TRANSMISSION',
    fate: 'Answered the phone in the booth. There is no phone in the booth.',
  ),
  Operator(
    name: 'O. STRAND',
    nights: 1000,
    rank: 'DEPUTY CHIEF',
    fate: 'A thousand nights. The card in the vault has his face on it.',
  ),
  Operator(
    name: 'I. BRENNAN',
    nights: 1080,
    rank: 'CHIEF OF TRANSMISSION',
    fate: 'Wrote the memos. Signed the refusals. Sat the post himself for the '
        'last eleven weeks of it.',
  ),
  Operator(
    name: 'R. HALLORAN',
    nights: 1114,
    rank: 'THE LONGEST NIGHT',
    fate: 'Did not sign off on the morning of the 1,115th. The carrier was up. '
        'The chair was warm.',
    unlock: 'There is nobody left on the roster above you.',
  ),
];

/// How many of them you have outlasted.
int passedCount(GameState s) =>
    kRoster.where((o) => s.survived >= o.nights).length;

/// Your current rank, or the starting one.
String rankOf(GameState s) {
  var r = 'RELIEF OPERATOR';
  for (final o in kRoster) {
    if (s.survived >= o.nights) r = o.rank;
  }
  return r;
}

/// The next name on the list, or null once the roster is spent.
Operator? nextOnRoster(GameState s) {
  for (final o in kRoster) {
    if (s.survived < o.nights) return o;
  }
  return null;
}

/// The one you have most recently passed.
Operator? lastPassed(GameState s) {
  Operator? p;
  for (final o in kRoster) {
    if (s.survived >= o.nights) p = o;
  }
  return p;
}

/// Names passed by going from [before] nights to [after]. Usually 0 or 1.
List<Operator> passedBetween(int before, int after) =>
    kRoster.where((o) => before < o.nights && after >= o.nights).toList();

/// 0..1 toward the next name. Measured from the PREVIOUS rung rather than from
/// zero, so the bar always starts empty and always fills — a bar that is 94%
/// full for six nights tells the player nothing.
double rosterProgress(GameState s) {
  final next = nextOnRoster(s);
  if (next == null) return 1;
  final prev = lastPassed(s)?.nights ?? 0;
  final span = (next.nights - prev).clamp(1, 100000);
  return ((s.survived - prev) / span).clamp(0.0, 1.0);
}

// ---------------------------------------------------------------------------
// WHAT IS OPEN YET
//
// A rung that pays only a title is a leaderboard. These are the actual
// features, and they arrive one at a time up the roster.
//
// This also fixes the opposite problem: a first-time operator was handed four
// rack tabs, eight emergency keys, five tools, six bots, a canteen, a station
// board, a document archive and a routine-check loop in their first ninety
// seconds. Everything at once is the same as nothing, because none of it is
// legible. Night one is now the tube, the rack and the eight keys — and every
// night after that opens exactly one new thing, with a name attached to it.
// ---------------------------------------------------------------------------

/// Nights survived required for each feature. Matches the roster's own
/// `unlock` lines — if you change one, change the other.
const Map<String, int> kUnlockAt = <String, int>{
  'canteen': 1, // D. KEEL
  'archive': 2, // M. ARDEN
  'board': 4, // S. BRIGHT
  'tools': 7, // R. OKONKWO
  'bots': 11, // J. FENN
};

bool unlocked(GameState s, String feature) =>
    s.survived >= (kUnlockAt[feature] ?? 0);

/// Who opens it, for the "not yet" line in the UI. Naming the person is the
/// point: it turns a locked panel into a rung you can see from here.
Operator? gatekeeperOf(String feature) {
  final n = kUnlockAt[feature];
  if (n == null) return null;
  for (final o in kRoster) {
    if (o.nights == n) return o;
  }
  return null;
}

/// The line a locked panel shows instead of its contents.
String lockedLine(GameState s, String feature) {
  final o = gatekeeperOf(feature);
  if (o == null) return 'NOT YET';
  final left = o.nights - s.survived;
  return 'OUTLAST ${o.name} — ${left <= 1 ? "ONE MORE NIGHT" : "$left MORE NIGHTS"}';
}

// ---------------------------------------------------------------------------
// THE NEXT THING
//
// The single most important line in the whole game and it did not exist. At
// any moment the player should be able to look at one place and read what they
// are working toward and how close it is — not a currency, a GOAL. Four ladders
// run at once (the roster, the station board, the file, the rack) and this
// picks whichever rung is nearest, so the answer is never "nothing".
// ---------------------------------------------------------------------------

enum GoalKind { roster, archive, board, tonight }

class NextGoal {
  const NextGoal({
    required this.kind,
    required this.label,
    required this.detail,
    required this.progress,
  });

  final GoalKind kind;

  /// What it is, in four or five words.
  final String label;

  /// How far, concretely. Always a number the player can act on.
  final String detail;

  /// 0..1.
  final double progress;
}

/// Everything currently being climbed, nearest first.
List<NextGoal> goals(GameState s) {
  final out = <NextGoal>[];

  final next = nextOnRoster(s);
  if (next != null) {
    final left = next.nights - s.survived;
    out.add(NextGoal(
      kind: GoalKind.roster,
      label: 'OUTLAST ${next.name}',
      detail: left == 1 ? 'ONE MORE NIGHT' : '$left MORE NIGHTS',
      progress: rosterProgress(s),
    ));
  }

  final found = foundCount(s);
  if (found < archiveTotal) {
    out.add(NextGoal(
      kind: GoalKind.archive,
      label: 'THE FILE',
      detail: '$found OF $archiveTotal RECOVERED',
      progress: found / archiveTotal,
    ));
  }

  return out;
}

/// The nearest goal — the one line that goes on the front desk.
NextGoal? nearestGoal(GameState s) {
  final g = goals(s);
  if (g.isEmpty) return null;
  g.sort((a, b) => b.progress.compareTo(a.progress));
  return g.first;
}

/// The line under your rank on the front desk.
String standingLine(GameState s) {
  final p = passedCount(s);
  if (p >= kRoster.length) {
    return 'THERE IS NOBODY LEFT ON THE ROSTER ABOVE YOU.';
  }
  return 'OPERATOR 23 OF 23  ·  $p OF ${kRoster.length} OUTLASTED';
}
