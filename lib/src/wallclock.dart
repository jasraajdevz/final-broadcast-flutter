// FINAL BROADCAST — THE STATION KNOWS WHAT TIME IT IS.
//
// Everything frightening in this build has happened inside the fiction. The
// shift clock runs 23:00 to 06:00 and it is made up; the roster is made up; the
// thing behind the chair is made up. A player can be unsettled by all of it
// and still, correctly, feel safe, because none of it has ever touched the
// room they are actually sitting in.
//
// This does. It reads the wall clock, the date and the gap since the last save
// — all of it handed over freely by the browser, none of it leaving the
// machine — and lets the station's paperwork refer to it.
//
// The three beats, in order of how badly they land:
//
//   IT KNOWS THE HOUR. If the player is at the desk at three in the morning,
//   their real three, the station says so. The fictional clock reading 03:00
//   is set dressing. The real one being 03:00 at the same moment is not.
//
//   IT KNOWS HOW LONG YOU HAVE BEEN SITTING THERE. Not airtime, not shift
//   minutes — the actual elapsed wall time of this sitting.
//
//   IT WAS ON THE WHOLE TIME. Come back after four days and the station knows
//   it was four days, and does not congratulate you for returning.
//
// Nothing here is a mechanic. It costs nothing and rewards nothing. It exists
// so that once, on a specific night, the game says something true about the
// room the player is in.

import 'state.dart';

/// Injectable so the whole thing is testable. Nothing in the game sets it;
/// only tests do.
DateTime Function() gNow = DateTime.now;

/// When this sitting began.
DateTime gSessionStart = DateTime.now();

void resetSession() => gSessionStart = gNow();

/// Real seconds the player has been at the desk this sitting.
double sessionSeconds() =>
    gNow().difference(gSessionStart).inMilliseconds / 1000.0;

/// Real seconds since the save was last written.
double awaySeconds(GameState s) =>
    (gNow().millisecondsSinceEpoch - s.lastSave) / 1000.0;

/// Is it actually the small hours where the player is sitting?
///
/// 00:00 to 04:59. Not "late" — the specific window where somebody playing a
/// game about a night shift is themselves on a night shift.
bool isSmallHours() {
  final h = gNow().hour;
  return h >= 0 && h < 5;
}

/// The real clock, as the station would write it.
String realClock() {
  final n = gNow();
  final hh = n.hour.toString().padLeft(2, '0');
  final mm = n.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// A duration in the flat register the paperwork uses.
String plainDuration(double seconds) {
  if (seconds < 90) return '${seconds.round()} seconds';
  final m = seconds / 60;
  if (m < 90) return '${m.round()} minutes';
  final h = m / 60;
  if (h < 40) {
    final whole = h.floor();
    final rem = ((h - whole) * 60).round();
    if (rem < 5) return '$whole ${whole == 1 ? "hour" : "hours"}';
    return '$whole ${whole == 1 ? "hour" : "hours"} and $rem minutes';
  }
  final d = h / 24;
  return '${d.round()} days';
}

/// The line the station adds to the closed file about the reader, or null when
/// there is nothing true enough to say.
///
/// Deliberately at most ONE line. A paragraph of this reads as a gimmick; a
/// single sentence, buried in a personnel record, reads as an oversight.
String? wallClockLine(GameState s) {
  if (isSmallHours()) {
    return 'Signed on at ${realClock()}. He kept the same hours as the post, '
        'which is not something the post asks for.';
  }
  final sess = sessionSeconds();
  if (sess > 45 * 60) {
    return 'Sat the desk for ${plainDuration(sess)} without getting up. '
        'The chair was warm when we came to it.';
  }
  return null;
}

/// What the station says when the operator comes back after a gap. Null if
/// they were not really gone.
///
/// It never says "welcome back". Nobody at this station is pleased to see you.
String? returnLine(GameState s) {
  if (!s.started) return null;
  final away = awaySeconds(s);
  if (away < 8 * 3600) return null;
  return 'YOU WERE GONE ${plainDuration(away).toUpperCase()}. '
      'IT WAS ON THE WHOLE TIME.';
}
