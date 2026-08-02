// FINAL BROADCAST — WHY YOU DO NOT JUST LEAVE.
//
// "There is no motive." Correct, and it was the deepest problem in the build.
// Every rule was a rule and none of them was a REASON. The game said "hold the
// transmitter until 06:00" and a fair player asked: or what? I'll be fired?
// A horror game whose failure state is a performance review is not a horror
// game, it is a spreadsheet with a skull on it.
//
// So the carrier is a lid.
//
// Whatever is in the signal is IN the signal because KBLK-7 is transmitting.
// The broadcast is not the thing you protect — it is the thing doing the
// holding. Drop the carrier and it does not stay in the tube. That single
// premise converts every existing mechanic without changing one of them:
//
//   the quota      -> the lid has to be fed or it thins
//   DREAD 100      -> not "you lose". You let it out.
//   06:00          -> sunrise takes over. You held it all night.
//   the 8 keys     -> eight ways to put something back down
//   the rack       -> a bigger transmitter is a heavier lid
//
// And the second thread, underneath: you are not the first operator. The
// previous one kept a log. You get one page a night. They were doing exactly
// what you are doing, in this chair, and the handwriting gets worse.

import 'state.dart';

/// The cold open — the first thing a new operator ever reads, before the
/// title. Deliberately short. Nobody reads a wall of prose to get to a game.
const List<String> kColdOpen = <String>[
  'KBLK-7 has been transmitting without interruption since 1963.',
  'Not because anyone is watching.',
  'Because of what happens when it stops.',
];

/// The premise, in one line, wherever it needs restating.
const String kPremise =
    'THE CARRIER IS A LID. WHATEVER IS IN THE SIGNAL IS IN IT BECAUSE '
    'YOU ARE STILL TRANSMITTING.';

/// The standing order, now with a reason attached to it.
const String kStandingOrder =
    'KEEP KBLK-7 ON AIR FROM 23:00 UNTIL 06:00. DO NOT LET THE CARRIER DROP.';

/// What is actually at stake, said plainly, for the loss conditions panel.
const List<String> kStakes = <String>[
  'DREAD 100 — the carrier drops and it comes out here instead.',
  'A MISSED QUOTA thins the lid. 06:00 will not arrive while you are short.',
];

// ---------------------------------------------------------------------------
// THE PREVIOUS OPERATOR
//
// One page a night, in order, found in the desk. It is a slow reveal that the
// person before you did this job well, for a long time, and it did not save
// them — and that the last page is dated tonight.
//
// Written so that a player who never reads past page three still has a whole
// game, and a player who reads all of them gets the floor taken out.
// ---------------------------------------------------------------------------

class LogPage {
  const LogPage({required this.night, required this.head, required this.body});

  /// The night this page turns up on.
  final int night;

  /// The dateline, in the log's own hand.
  final String head;
  final String body;
}

const List<LogPage> kOperatorLog = <LogPage>[
  LogPage(
    night: 2,
    head: 'FROM THE DESK DRAWER — LOG OF R. HALLORAN, NIGHT OPERATOR',
    body: 'Whoever is reading this: the rundown is a lie, the quotas are real. '
        'Keep the needle up. It does not care what you broadcast, only that '
        'you are broadcasting.',
  ),
  LogPage(
    night: 3,
    head: 'HALLORAN — NIGHT 214',
    body: 'Eight of them. There have only ever been eight. I have a key for '
        'each and I have never needed a ninth, which I used to find comforting.',
  ),
  LogPage(
    night: 4,
    head: 'HALLORAN — NIGHT 341',
    body: 'They have started arriving in the order I think of them in. '
        'I have stopped keeping the list in order.',
  ),
  LogPage(
    night: 5,
    head: 'HALLORAN — NIGHT 508',
    body: 'The window in the booth does not open and has never opened. '
        'Whatever is in the field is not getting in that way. I want to be '
        'clear that this is the only reassuring sentence in this book.',
  ),
  LogPage(
    night: 6,
    head: 'HALLORAN — NIGHT 720',
    body: 'Slept four hours in the chair with the carrier up. Woke to find the '
        'log open at a page I had not written yet. The handwriting is mine.',
  ),
  LogPage(
    night: 7,
    head: 'HALLORAN — NIGHT 901',
    body: 'It is not trying to get out. I have had this backwards for two '
        'years. It is trying to get me to stop, which is a different thing, '
        'and it is much more patient about it.',
  ),
  LogPage(
    night: 8,
    head: 'HALLORAN — NIGHT 1,114',
    body: 'There is a second operator on the roster now. I have not met them. '
        'I have not been told their name. The roster is in my handwriting.',
  ),
  LogPage(
    night: 9,
    head: 'HALLORAN — FINAL ENTRY',
    body: 'If you are new: it is not the noise. It is the quiet after the '
        'noise, when you have got it right and you are sitting there being '
        'pleased with yourself. That is when it looks at you properly.',
  ),
  LogPage(
    night: 10,
    head: 'STATION MEMO — UNSIGNED',
    body: 'R. HALLORAN did not sign off on the morning of the 1,115th night. '
        'The carrier was up. The chair was warm. The log was open to a blank '
        'page, and the page is the one you have been writing on.',
  ),
];

/// The page for this night, or null on nights that have none.
LogPage? logPageFor(int night) {
  for (final p in kOperatorLog) {
    if (p.night == night) return p;
  }
  return null;
}

/// Has the operator been handed this page yet?
bool logPageSeen(GameState s, int night) => s.log[night] ?? false;

/// The pages found so far, in order — the manual's LOG tab reads this.
List<LogPage> logPagesFound(GameState s) =>
    kOperatorLog.where((p) => logPageSeen(s, p.night)).toList();
