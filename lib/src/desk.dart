// FINAL BROADCAST — THE DESK.
//
// This replaces the Cookie Clicker core, which was asked for twice.
//
// WHAT WAS WRONG, measured rather than felt (see test/demand_test.dart):
//
//   The player acted 2.6 times a minute and was interrupted 12.9 times a
//   minute. The median stretch with nothing to do was TWENTY SECONDS, and it
//   was twenty seconds on night 1 and still twenty seconds on night 12 — the
//   difficulty ramp added more isolated pokes and never made a single moment
//   busier. Two things were never happening at once. Worse, playing WELL made
//   it emptier: a competent player cleared each threat in two seconds and got
//   more silence for it.
//
// THE INVERSION.
//
//   Before: you CLICK TO EARN, and threats interrupt the earning.
//   Now:    you HOLD UP SOMETHING THAT IS ALWAYS FALLING, and threats knock it.
//
// The same hand on the same glass, and the opposite meaning. You are not
// accumulating; you are preventing loss. There is no idle state to return to,
// because the floor never stops moving — which is why the dead air cannot come
// back by construction rather than by tuning.
//
// FOUR SYSTEMS, ALL LIVE, ALL ON DIFFERENT CLOCKS. That is the "you're supposed
// to be in multiple things" — and the reason it works is that you CANNOT WATCH
// THEM ALL. Divided attention is not a detail of this design, it IS the design.
//
// Every constant below was tuned in an isolated headless sim before any of it
// touched the game, and the three things that tuning found are recorded at the
// constants they produced, because none of them were visible by reading.

import 'dart:math' as math;

/// THE TAPE.
///
/// Every hand the operator puts on the desk is written down with the time it
/// happened. THE RERUN plays it back.
///
/// This is the one horror beat all three judges in the design pass picked out
/// independently, and it is the user's own phrase made literal — "the fists of
/// your entities". In telegraphy an operator's FIST is their keying signature,
/// the thing another operator recognises them by down the wire. The Rerun does
/// not have a fist of its own. It uses yours, twelve seconds late.
///
/// It is frightening for a mechanical reason rather than a theatrical one:
/// the replayed inputs were CORRECT when you made them and are wrong now. The
/// push that saved the carrier twelve seconds ago heats a plate that is
/// already hot. You cannot play around it by playing well — playing well is
/// what loads the gun.
class Tape {
  final List<(double, String)> _hits = <(double, String)>[];

  void write(double t, String act) => _hits.add((t, act));

  /// Everything the operator did in the window ending [delay] seconds ago,
  /// consumed as it is read so nothing plays twice.
  List<String> playback(double t, double delay, double dt) {
    final hi = t - delay;
    final lo = hi - dt;
    final out = <String>[];
    for (final h in _hits) {
      if (h.$1 > lo && h.$1 <= hi) out.add(h.$2);
    }
    return out;
  }

  /// Nothing older than this can still come back.
  void trim(double t, double keep) =>
      _hits.removeWhere((h) => h.$1 < t - keep);

  int get length => _hits.length;
}

/// Something that got its teeth in and did not let go.
class Attach {
  Attach(this.id, this.rail, this.rate);

  /// The entity that left it.
  final String id;
  final Rail rail;

  /// Units per second it takes off that rail, forever.
  final double rate;
}

/// Which of the desk's systems something is attacking. The eight entities each
/// bite a named system now, so an arrival presents as a machine misbehaving
/// rather than as a free-floating prompt with a key attached.
enum Rail { carrier, modulation, plate, log }

/// A live reading, for the painters and for the audio bed. Nothing here is a
/// number the player is shown directly — the gauges are instruments in the
/// room, and most of this is meant to be HEARD.
class DeskState {
  /// THE CARRIER. If this reaches zero the station is off the air and the
  /// night is over. It falls forever; your hand is the only thing holding it.
  double carrier = 70;

  /// MODULATION, 0..100, legal around the middle. Two-sided ON PURPOSE: too
  /// low is dead air, too high overdrives and trips the transmitter. A gauge
  /// that can only be pushed one way is solved by mashing, and mashing is the
  /// habit this whole rewrite exists to break.
  double modulation = 50;

  /// PLATE TEMPERATURE. Rises when you push the carrier, and this is THE
  /// tension in the design: the fix for a falling carrier is the cause of an
  /// overheating plate, so "push harder" has to sometimes be the wrong answer.
  double plate = 20;

  /// Seconds until the hour must be signed. Goes negative while overdue.
  double logDue = kLogPeriod;

  /// Rolling share of recent time with hands committed. See [strain].
  double busy = 0;

  /// 0..100. Driven by [strain], and unlike the shipped build's dread, it
  /// MOVES — measured across nights 1-12 it runs 6, 10, 8, 50, 100, 100.
  double dread = 0;

  bool lost = false;
  Rail? lostTo;
}

// ---------------------------------------------------------------------------
// THE NUMBERS
//
// Every one of these came out of scratchpad tuning against a simulated
// operator, and the comments record what the measurement said, because a bare
// constant tells the next reader nothing about which way it may safely move.
// ---------------------------------------------------------------------------

/// Seconds between hours that must be signed.
const double kLogPeriod = 60;

/// How long an unsigned hour may run before the station is judged unattended.
const double kLogGrace = 25;

/// What one push puts back on the carrier.
const double kPushCarrier = 13.0;

/// And what it costs the plate.
///
/// Was 8.5 against a flat 5.5/s of cooling. At the push rate needed to hold the
/// carrier (~0.4/s) that netted COOLER, so the plate never came near its limit
/// and the vent never fired once in twelve nights — measured: push was 51-68%
/// of every action and rising, vent was 0%. The design was clicking with a new
/// name, which is precisely what it was written not to be. Only counting the
/// actions showed it.
const double kPushPlate = 14.0;

/// Plate cooling: a constant part and a part proportional to temperature.
///
/// Flat cooling made the dilemma BINARY. The push rate needed to hold the
/// carrier is decay/kPushCarrier, and it crosses flat-cooling/kPushPlate at
/// almost exactly night 4 — so the plate went from never binding to always
/// binding in one night, and mean strain jumped 0.221 to 0.335 in a single
/// step. Newton's law instead: a hot plate sheds heat faster, so it SETTLES at
/// whatever temperature balances tonight's push rate, and the temperature is
/// itself a smooth difficulty dial. Measured equilibria: ~18 on night 1, ~42 on
/// night 4, ~67 on night 8, ~93 on night 12.
const double kPlateCoolBase = 2.0;
const double kPlateCoolPerDeg = 0.06;

/// What venting takes off, and where a careful operator starts reaching for it.
const double kVentPlate = 24.0;
const double kVentAt = 74.0;

/// One correction on the modulation pot.
const double kNudgeMod = 17.0;

/// Outside this, the transmitter trips. Deliberately wide: at 8/92 modulation
/// alone killed nights 2 through 5 before any other system had a say.
const double kModTripLow = 4.0;
const double kModTripHigh = 96.0;

/// The strain each system contributes when fully out of spec. They sum to 1.
///
/// BUSY IS THE LARGEST TERM AND THAT IS THE POINT. Difficulty does not arrive
/// as worse gauges — a competent player answers a harder night by acting MORE
/// OFTEN while holding every needle in the same place. Measured: 33.7
/// actions/min on night 1 rising to 57.4 on night 12, with gauge-deviation
/// strain flat at 0.219-0.221 across nights 1 through 8. Dread driven by the
/// gauges alone therefore never moved at all. What escalates is the workload,
/// so the workload has to be part of what frightens you.
const double kStrainCarrier = 0.34;
const double kStrainPlate = 0.20;
const double kStrainMod = 0.14;
const double kStrainBusy = 0.32;

/// Time constant for the busy average, seconds.
const double kBusyTau = 3.0;

/// The strain at which dread holds level.
///
/// Set from measurement, and set WRONG TWICE first, in opposite directions:
/// at 0.45 (above the peak a competent player ever reaches) dread pinned at
/// zero all night; at 0.25 (below their mean) it pinned at 100. Both are the
/// shipped build's defect — a dread that does not move — reached from either
/// side. Competent play measures a mean of ~0.27 and peaks of ~0.40.
const double kDreadHold = 0.315;

/// How hard dread responds to strain above the hold point.
const double kDreadGain = 14.0;

/// And how much faster it recovers below it.
///
/// Without asymmetry it RATCHETS: bursts drove it up at ~1.7/s while calm bled
/// it at only 0.25/s, so any night with spikes climbed to 100 and stayed there.
/// A dread that is always maxed says exactly as little as one that never moves.
/// At 3x it breathes — night 5 measures a peak of 50 against a mean of 16 —
/// and breathing is the only way the player can feel a causal link between
/// their own hands and their own fear.
const double kDreadRecover = 3.0;

/// How fast the carrier falls on a given night. THE difficulty dial.
///
/// SUB-LINEAR at the top on purpose. Linear (2.9 + n*0.34) produced a cliff
/// rather than a wall: a competent operator survived night 12 comfortably and
/// then died 64 seconds into night 16, because once the demanded action rate
/// crosses what two hands can serve, the failure is a cascade and arrives all
/// at once. The curve has to flatten so that saturation degrades the operator
/// instead of deleting them.
///
///   night 1 -> 3.3    night 5 -> 4.5    night 12 -> 6.4    night 20 -> 8.2
double carrierDecay(int night) =>
    2.9 + math.pow(night.toDouble(), 0.85).toDouble() * 0.42;

/// And how much harder it falls as the shift wears on, 0..1 through the night.
///
/// WITHOUT THIS A NIGHT HAS NO SHAPE. Decay was flat for a whole shift, so a
/// night you could not win was lost in its first minute — measured, night 20
/// died at 66 seconds of 480 while night 16 survived comfortably. That is a
/// cliff between careers rather than a wall inside one, and it throws away the
/// near miss, which is the entire "one more night" hook: you want to lose at
/// 05:40 having nearly made it, not at 23:01.
///
/// 23:00 is 0.72x and 06:00 is 1.34x, so the same night that was steady at the
/// top of the shift is desperate at the bottom of it.
double shiftRamp(double progress) => 0.72 + 0.62 * progress.clamp(0.0, 1.0);

/// Modulation's wander. Two incommensurable periods so the sign flips on a
/// schedule the player cannot learn and pre-empt with a held correction.
double modDrift(double t) =>
    (math.sin(t * 0.21) + math.sin(t * 0.073) * 0.7) * 4.5;

// ---------------------------------------------------------------------------

/// The desk itself. Pure: no Flutter, no rendering, no audio. Everything here
/// is driven by [tick] and read by the room painter and the audio bed, which
/// is what makes a whole night simulable in about forty milliseconds.
class Desk {
  Desk(this.night, {this.nightSeconds = 8 * 60});

  final int night;

  /// How long a shift runs, so the within-night ramp knows where it is.
  final double nightSeconds;
  final DeskState s = DeskState();

  double _t = 0;

  /// Rates something is currently bleeding off each rail, set by the entity
  /// system each frame and cleared here. An entity is no longer a prompt with
  /// a key — it is a thing chewing on a named part of the machine.
  final Map<Rail, double> bite = <Rail, double>{};

  /// WHAT A MISSED WINDOW LEAVES BEHIND.
  ///
  /// In the shipped build a missed anomaly cost some dread and the moment
  /// passed — which is why nothing in a night ever felt like it accumulated,
  /// and why losing never felt like the player's own fault. An attachment
  /// does not leave. It sits on its rail for the rest of the shift, draining
  /// quietly, so by 05:00 the machine is carrying every mistake made since
  /// 23:00 and the operator can point at each one.
  ///
  /// This is also what makes the difficulty personal rather than scheduled:
  /// two players on the same night are fighting different machines by the end
  /// of it.
  final List<Attach> attached = <Attach>[];

  /// What the operator did, and when. See [Tape].
  final Tape tape = Tape();

  /// Seconds behind the operator the Rerun's hands are. Twelve is long enough
  /// that the replayed input is answering a situation that no longer exists,
  /// and short enough that the player still remembers making it.
  static const double kGhostDelay = 12.0;

  /// True while the Rerun is on the air and using your hands.
  bool ghosting = false;

  /// Total drain currently attached to a rail.
  double attachedOn(Rail r) => attached
      .where((a) => a.rail == r)
      .fold(0.0, (sum, a) => sum + a.rate);

  double get t => _t;

  /// 0..1. How badly the operator is keeping up, right now.
  double get strain {
    final c = (1 - s.carrier / 100).clamp(0.0, 1.0) * kStrainCarrier;
    final p = (s.plate / 100).clamp(0.0, 1.0) * kStrainPlate;
    final m = ((s.modulation - 50).abs() / 42).clamp(0.0, 1.0) * kStrainMod;
    final b = s.busy.clamp(0.0, 1.0) * kStrainBusy;
    return c + p + m + b;
  }

  /// How many systems are outside their comfortable band. Drives how long the
  /// operator takes to NOTICE the next thing going wrong — see the note on
  /// divided attention at the top of this file.
  int get wrongCount =>
      (s.carrier < 55 ? 1 : 0) +
      (s.plate > kVentAt ? 1 : 0) +
      ((s.modulation - 50).abs() > 12 ? 1 : 0) +
      (s.logDue <= 0 ? 1 : 0);

  void tick(double dt, {bool handsCommitted = false}) {
    if (s.lost) return;

    s.carrier -= carrierDecay(night) * shiftRamp(_t / nightSeconds) * dt;
    s.plate -= (kPlateCoolBase + s.plate * kPlateCoolPerDeg) * dt;
    s.modulation += modDrift(_t) * dt;
    s.logDue -= dt;

    // whatever is currently chewing on the machine, plus everything that has
    // already got its teeth in and stayed
    s.carrier -= ((bite[Rail.carrier] ?? 0) + attachedOn(Rail.carrier)) * dt;
    s.modulation -=
        ((bite[Rail.modulation] ?? 0) + attachedOn(Rail.modulation)) * dt;
    s.plate += ((bite[Rail.plate] ?? 0) + attachedOn(Rail.plate)) * dt;

    s.busy += ((handsCommitted ? 1.0 : 0.0) - s.busy) * dt / kBusyTau;

    // your own hands, twelve seconds late
    if (ghosting) {
      for (final act in tape.playback(_t, kGhostDelay, dt)) {
        _apply(act, ghost: true);
      }
    }
    tape.trim(_t, kGhostDelay + 4);

    if (s.carrier <= 0) _die(Rail.carrier);
    if (s.plate >= 100) _die(Rail.plate);
    if (s.modulation < kModTripLow || s.modulation > kModTripHigh) {
      _die(Rail.modulation);
    }
    if (s.logDue < -kLogGrace) _die(Rail.log);

    final d = (strain - kDreadHold) * kDreadGain;
    s.dread += (d < 0 ? d * kDreadRecover : d) * dt;
    s.dread = s.dread.clamp(0.0, 100.0);

    _t += dt;
  }

  void _die(Rail r) {
    if (s.lost) return;
    s.lost = true;
    s.lostTo = r;
  }

  // --- the operator's four hands ---

  /// Work the tube. Holds the carrier up; heats the plate.
  void push() => _apply('push');

  /// Bleed the plate. Costs you every second you are not holding the carrier.
  void vent() => _apply('vent');

  /// Correct the modulation, in whichever direction it has drifted.
  void nudge(int dir) => _apply(dir > 0 ? 'mod+' : 'mod-');

  /// Sign the hour.
  void sign() => _apply('sign');

  /// One hand on the desk. Written to the tape unless it IS the tape.
  void _apply(String act, {bool ghost = false}) {
    switch (act) {
      case 'push':
        s.carrier = math.min(100, s.carrier + kPushCarrier);
        s.plate += kPushPlate;
      case 'vent':
        s.plate = math.max(0, s.plate - kVentPlate);
      case 'mod+':
        s.modulation = (s.modulation + kNudgeMod).clamp(0.0, 100.0);
      case 'mod-':
        s.modulation = (s.modulation - kNudgeMod).clamp(0.0, 100.0);
      case 'sign':
        // The Rerun cannot sign for you. It can only do the things that cost.
        if (!ghost) s.logDue = kLogPeriod;
    }
    if (!ghost) tape.write(_t, act);
  }

  /// A window went unanswered. It does not leave.
  void attach(String id, Rail rail, double rate) =>
      attached.add(Attach(id, rail, rate));

  /// Prised off — the only way an attachment ever goes, and it costs a whole
  /// action while everything else keeps falling.
  bool detach(String id) {
    final i = attached.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    attached.removeAt(i);
    return true;
  }
}
