// FINAL BROADCAST — THE STATION CHECKS.
//
// "after this I get bored and there isn't really much of a thing to do."
//
// Measured: the tube has something on it for 6.5% to 11.8% of a night. Nine
// tenths of a shift was watching a number rise and clicking a screen. The
// quiet was not tense, it was EMPTY — and an empty quiet is the thing a player
// notices as boredom no matter how good the loud part is.
//
// A night shift is not a vigil, it is a job. The station asks for routine
// operator checks: log the hour, turn the tape, ink the pen recorder. Each one
// is mundane, none of them is an anomaly, and every one of them takes your
// attention off the tube for a moment.
//
// That is the whole design. The check is answered with ONE key, always the
// same, because it is not a memory test — it is an ATTENTION test. It competes
// with the eight keys for the only resource the player actually has. And it
// can, deliberately, land while something is already on the tube.
//
// Mashing does not work: a press outside a live window is a false entry and
// costs you. You have to notice.

import 'dart:math' as math;

import 'consts.dart';
import 'state.dart';

/// One routine the station wants signed off.
class CheckKind {
  const CheckKind({
    required this.id,
    required this.nm,
    required this.ds,
    required this.window,
  });

  final String id;

  /// What the desk lamp says.
  final String nm;

  /// The line in the toast. Station voice, never game voice.
  final String ds;

  /// Seconds to answer it.
  final double window;
}

const List<CheckKind> kChecks = <CheckKind>[
  CheckKind(
    id: 'log',
    nm: 'LOG THE HOUR',
    ds: 'The book wants a line and a time. It always has.',
    window: 6.5,
  ),
  CheckKind(
    id: 'tape',
    nm: 'TURN THE TAPE',
    ds: 'Side one has run out. Something is still on side two.',
    window: 5.5,
  ),
  CheckKind(
    id: 'ink',
    nm: 'INK THE RECORDER',
    ds: 'The pen has been dry for a while and the paper is not blank.',
    window: 6.0,
  ),
  CheckKind(
    id: 'meter',
    nm: 'READ THE METER',
    ds: 'Write down what it says. Do not write down what it said last hour.',
    window: 5.0,
  ),
  CheckKind(
    id: 'door',
    nm: 'CHECK THE CORRIDOR DOOR',
    ds: 'It is closed. Confirm that it is closed.',
    window: 5.0,
  ),
];

final Map<String, CheckKind> kCheckBy = <String, CheckKind>{
  for (final c in kChecks) c.id: c,
};

/// The live state of the routine-check loop. Owned by the runtime.
class CheckRuntime {
  /// The check currently being asked for, or null.
  CheckKind? active;

  /// Seconds left to answer it.
  double left = 0;

  /// How long it started with, so the UI can draw a bar.
  double span = 0;

  /// Seconds until the next one is raised.
  double next = 12;

  /// How many have been missed tonight. Drives DRIFT.
  int missed = 0;

  /// How many have been signed tonight.
  int signed = 0;

  /// 0..1 — how far out of alignment the station has drifted from neglected
  /// checks. Costs output continuously and never resets inside a night.
  double drift = 0;

  /// Presses made when nothing was being asked for. A false entry in the log
  /// is its own small cost, and it is what stops the key being mashed.
  int falseEntries = 0;

  /// 0 -> 1 -> 0, for the desk lamp flashing an accepted signature.
  double okFx = 0;

  /// Is the operator's hand on the book right now?
  bool signing = false;

  /// Seconds of signature laid down so far, 0..[kSignSeconds].
  double held = 0;

  /// How far through the signature, 0..1.
  double get heldP => (held / kSignSeconds).clamp(0.0, 1.0);

  bool get pending => active != null;

  /// Fraction of the answer window still left, 1 -> 0.
  double get p => span <= 0 ? 0 : (left / span).clamp(0.0, 1.0);

  void resetForNight() {
    active = null;
    left = 0;
    span = 0;
    next = 12;
    missed = 0;
    signed = 0;
    drift = 0;
    falseEntries = 0;
    okFx = 0;
    signing = false;
    held = 0;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'missed': missed,
        'signed': signed,
        'drift': drift,
      };
}

/// Output multiplier from an out-of-alignment station. Bounded so neglect is
/// expensive but never a death sentence on its own.
double driftPenalty(CheckRuntime c) => 1 - 0.42 * c.drift.clamp(0.0, 1.0);

/// Dread per second the drift adds. Small — it is a tax, not a killer.
double driftDread(CheckRuntime c) => 0.30 * c.drift.clamp(0.0, 1.0);

/// Seconds until the next check, given how deep the night is.
///
/// Deliberately NOT synchronised with the anomaly scheduler. The two loops
/// have to be able to collide, because the collision is the interesting part:
/// something is on the tube and the book still wants a line.
/// Tuned by measurement, not by feel. At rr(26,52) a whole night asked the
/// player for something only 12.3% of the time — barely above the tube on its
/// own, so the quiet was still mostly empty. This cadence puts the station's
/// demands and the tube's together at roughly a third of the shift, which is
/// the difference between a vigil and a job.
double nextCheckGap(GameState s, double dread) =>
    rr(14, 30) * (1 - 0.22 * dread.clamp(0.0, 1.0));

/// How long a signature takes to lay down.
///
/// This is the whole reason the check is a mechanic rather than a notification.
/// Measured: an instant keypress occupied a realistic player for 0.7s out of
/// every 22 seconds — 3% of a night — and the quiet stayed empty. A signature
/// you have to HOLD is a commitment: while your hand is on the book you are
/// not on the keys, and something arriving mid-signature is a real choice
/// rather than a reflex.
const double kSignSeconds = 1.45;

/// How much drift one missed check adds.
const double kDriftPerMiss = 0.16;

/// How much a signed check takes back off.
const double kDriftPerSign = 0.06;

/// Dread for missing one.
const double kMissDread = 5.0;

/// Dread for signing the book when nobody asked.
const double kFalseEntryDread = 2.2;

/// Advance the loop one frame. Returns a [CheckEvent] when something happened
/// this frame, so the caller can make the noise and write the toast — this
/// file deliberately knows nothing about audio or the UI.
CheckEvent? tickChecks(
  CheckRuntime c,
  GameState s,
  double dt, {
  required bool canRaise,
}) {
  c.okFx = math.max(0, c.okFx - dt * 2.2);

  if (c.active != null) {
    c.left -= dt;
    if (c.left <= 0) {
      final CheckKind k = c.active!;
      c.active = null;
      c.left = 0;
      c.span = 0;
      c.signing = false;
      c.held = 0;
      c.missed++;
      c.drift = math.min(1.0, c.drift + kDriftPerMiss);
      c.next = nextCheckGap(s, s.dread / 100);
      return CheckEvent(CheckEventKind.missed, k);
    }
    return null;
  }

  c.next -= dt;
  if (c.next <= 0 && canRaise) {
    final k = kChecks[(rand() * kChecks.length).floor().clamp(0, kChecks.length - 1)];
    c.active = k;
    c.span = k.window;
    c.left = k.window;
    return CheckEvent(CheckEventKind.raised, k);
  }
  return null;
}

/// The operator puts a hand on the book.
CheckEvent? beginSign(CheckRuntime c, GameState s) {
  if (c.active == null) {
    // A false entry. This is what stops the key being mashed: the check is an
    // attention test, and answering a question nobody asked is its own answer.
    c.falseEntries++;
    s.dread = math.min(100, s.dread + kFalseEntryDread);
    return const CheckEvent(CheckEventKind.falseEntry, null);
  }
  c.signing = true;
  return null;
}

/// The hand comes off the book — deliberately, or because the keys needed it.
void endSign(CheckRuntime c) {
  c.signing = false;
  c.held = 0;
}

/// Advances a signature in progress. Returns the completion event on the frame
/// it finishes.
CheckEvent? tickSign(CheckRuntime c, GameState s, double dt) {
  if (!c.signing || c.active == null) return null;
  c.held += dt;
  if (c.held < kSignSeconds) return null;
  final k = c.active!;
  c.active = null;
  c.left = 0;
  c.span = 0;
  c.signing = false;
  c.held = 0;
  c.signed++;
  c.okFx = 1;
  c.drift = math.max(0, c.drift - kDriftPerSign);
  c.next = nextCheckGap(s, s.dread / 100);
  return CheckEvent(CheckEventKind.signed, k);
}

enum CheckEventKind { raised, signed, missed, falseEntry }

class CheckEvent {
  const CheckEvent(this.kind, this.check);
  final CheckEventKind kind;
  final CheckKind? check;
}
