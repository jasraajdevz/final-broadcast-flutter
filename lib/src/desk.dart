// FINAL BROADCAST — THE RIG.
//
// The core. This replaces the Cookie Clicker economy, which was asked about
// twice before it went.
//
// WHAT WAS WRONG, measured rather than felt (test/demand_test.dart):
//
//   The player acted 2.6 times a minute and was interrupted 12.9 times a
//   minute. The median stretch with nothing to do was TWENTY SECONDS, and it
//   was twenty seconds on night 1 and still twenty seconds on night 12 — the
//   ramp added more isolated pokes and never made a single moment busier. Two
//   things were never happening at once. Worse, playing WELL made it emptier:
//   a competent player cleared each threat in two seconds and got more silence
//   for it. Competence was punished with boredom.
//
// THE INVERSION.
//
//   Before: you CLICK TO EARN, and threats interrupt the earning.
//   Now:    you HOLD A MACHINE INSIDE ITS LIMITS, and it is always leaving them.
//
// NO KEY IN THIS FILE MAKES A NUMBER GO UP.
//
// That is the rule the first attempt broke. It had a push() that added +13 to
// the carrier per press, and counting the simulated operator's actions showed
// push was 51-68% of everything they did and rising — a clicker with a new
// name, which is exactly what it had been written not to be. DRIVE is a
// SETPOINT instead: the operator holds a dial, the carrier tracks toward it on
// its own, and holding it high cooks the plate on a square law. Spamming the
// key just pins the dial at 100 and melts the transmitter. The skill is
// choosing where to sit, second by second, as the conditions move under you.
//
// FOUR SYSTEMS, ALL LIVE, ALL ON DIFFERENT CLOCKS — and the reason it works is
// that you CANNOT WATCH THEM ALL. Divided attention is not a detail of this
// design, it IS the design, and it is what "you're supposed to be in multiple
// things" asked for.
//
// THE LEDGER IS THE SCORE AND IT ONLY EVER COUNTS UP. Four mechanical drums
// on the master recorder totalling the seconds the county spent hearing
// something that was not you. There is nothing to farm, nothing to bank and no
// number anywhere that a player can make bigger.
//
// Every constant was tuned in an isolated headless sim before it touched the
// game, and what the tuning found is recorded at the constant it produced,
// because a bare number tells the next reader nothing about which way it may
// safely move.

import 'dart:math' as math;

/// THE TAPE.
///
/// Every hand the operator puts on the desk, written down with the time. THE
/// RERUN plays it back.
///
/// The one horror beat all three design judges picked out independently, and
/// the player's own phrase made literal — "the fists of your entities". In
/// telegraphy an operator's FIST is their keying signature, the thing another
/// operator recognises them by down the wire. The Rerun has no fist of its
/// own. It uses yours, twelve seconds late.
///
/// It frightens for a mechanical reason rather than a theatrical one: the
/// replayed inputs were CORRECT when they were made and are wrong now. The
/// drive you wound up twelve seconds ago to save a sagging carrier arrives on
/// a plate that is already too hot. You cannot play around it by playing well.
/// Playing well is what loads it.
class Tape {
  final List<(double, String)> _hits = <(double, String)>[];

  void write(double t, String act) => _hits.add((t, act));

  /// Everything done in the frame that ended [delay] seconds ago.
  List<String> playback(double t, double delay, double dt) {
    final hi = t - delay;
    final lo = hi - dt;
    final out = <String>[];
    for (final h in _hits) {
      if (h.$1 > lo && h.$1 <= hi) out.add(h.$2);
    }
    return out;
  }

  void trim(double t, double keep) => _hits.removeWhere((h) => h.$1 < t - keep);

  int get length => _hits.length;
}

/// Something that got its teeth in and did not let go.
class Attach {
  Attach(this.id, this.rail, this.rate);
  final String id;
  final Rail rail;

  /// Units per second off that rail, for the rest of the shift.
  final double rate;
}

/// Which part of the machine something is eating.
enum Rail { carrier, modulation, plate, log }

/// One line on the invoice.
class Debit {
  Debit(this.at, this.what, this.amount);

  /// Shift seconds when it happened.
  final double at;
  final String what;
  double amount;
}

// ---------------------------------------------------------------------------
// THE NUMBERS
// ---------------------------------------------------------------------------

/// Seconds between hours that must be signed.
const double kLogPeriod = 60;

/// How long an unsigned hour runs before the station is judged unattended.
const double kLogGrace = 25;

/// How fast the carrier closes the gap to DRIVE, per second.
///
/// Must comfortably exceed the worst carrierDecay or the dial cannot hold the
/// needle up at all on a late night. At 0.5 the resting carrier sits at
/// `drive - 2*decay`, so the same dial position is worth less as the career
/// goes on — which is the difficulty arriving as something the operator can
/// SEE on an instrument rather than as an invisible multiplier.
const double kTrack = 0.5;

/// Plate heating, square law on drive. A transmitter run hard does not heat
/// linearly and neither should this: the square is what makes the last ten
/// points of drive cost four times what the first ten did, and therefore what
/// makes "just turn it up" a decision instead of a reflex.
const double kPlateGain = 13.6;
const double kPlateCoolBase = 2.0;
const double kPlateCoolPerDeg = 0.06;

/// Where the transmitter recycles. Not death — a trip costs a flat charge on
/// the ledger and drops the carrier while the contactor is out, which is
/// punishment enough and, unlike death, is something the operator can watch
/// themselves cause.
const double kPlateTrip = 100.0;
const double kTripCharge = 2.5;
const double kTripLockout = 3.2;
const double kTripPlateAfter = 44.0;

/// One correction on the modulation pot.
const double kNudgeMod = 17.0;

/// Outside this the transmitter is splattering across the band.
const double kModTripLow = 4.0;
const double kModTripHigh = 96.0;

/// And outside THIS it is merely wrong, and the drums turn slowly.
///
/// Without a cost here the modulation had no pressure on it at all until it
/// was catastrophic, forty-six points from the mark — so on an early night the
/// operator could let the needle wander and simply stop working. Measured, a
/// night 1 run had an EIGHTEEN AND A HALF SECOND stretch with nothing to do,
/// which is the exact defect this whole rewrite exists to remove, walking back
/// in through the one gauge that was not on the ledger.
///
/// A system with no tariff is a system the player may ignore, and a system the
/// player may ignore is dead air with extra steps.
const double kModGreen = 15.0;
const double kTariffOffMod = 0.35;

/// Below this the county is hearing hiss, and the drums turn.
///
/// Set from the resting point, not guessed. The carrier settles at
/// `drive - 2*carrierDecay*shiftRamp`, so at 34 the operator could park the
/// dial at its starting 62 and never be threatened on any night up to 20 —
/// measured, the drums read 0.0 and the drive was touched once in eight
/// minutes. At 52 the resting point crosses the line partway through a
/// mid-career night, so the operator has to keep winding the drive UP as the
/// shift wears on, and that is exactly what heats the plate.
const double kLowPower = 52.0;

// --- the ledger ---

/// Seconds off the air the licence allows before it is void.
const double kCeiling0 = 180.0;

/// Tariffs, seconds charged per second (or flat).
const double kTariffDeadAir = 1.0;
const double kTariffLowPower = 0.5;
const double kTariffLockout = 1.0;
const double kTariffAttach = 0.12;
const double kChargeSplatter = 25.0;
const double kChargeUnsigned = 20.0;

/// IN SPEC has to be held this long before it starts buying anything back.
const double kInSpecArm = 4.0;

/// and then every this many seconds adds one second to the allowance.
const double kInSpecPeriod = 12.0;
const double kCeilingMax = 220.0;

// --- strain and dread: KEPT EXACTLY, do not re-derive ---

/// The strain each system contributes when fully out of spec.
///
/// BUSY IS THE LARGEST TERM AND THAT IS THE POINT. Difficulty does not arrive
/// as worse gauges — a competent operator answers a harder night by acting
/// MORE OFTEN while holding every needle in the same place. Measured: 33.7
/// actions/min on night 1 rising to 57.4 on night 12, with gauge-deviation
/// strain flat at 0.219-0.221 across nights 1 through 8. Dread driven by the
/// gauges alone therefore never moved at all. What escalates is the workload,
/// so the workload has to be part of what frightens you.
const double kStrainCarrier = 0.34;
const double kStrainPlate = 0.20;
const double kStrainMod = 0.14;
const double kStrainBusy = 0.32;
const double kBusyTau = 3.0;

/// The strain at which dread holds level.
///
/// Set from measurement, and set WRONG THREE TIMES first — twice in opposite
/// directions on the earlier four-gauge core (at 0.45, above the peak a
/// competent operator ever reaches, it pinned at zero all night; at 0.25,
/// below their mean, it pinned at 100), and then once more by carrying 0.315
/// across to this rig without re-deriving it. The rig runs a hotter plate and
/// a lower carrier by design, so measured strain moved up to a 0.325-0.427
/// band and 0.315 was suddenly BELOW the mean of even night 1 — dread climbed
/// on every night in the career and sat at 100 from night 3.
///
/// Measured means, this rig: 0.325 / 0.337 / 0.342 / 0.361 / 0.396 / 0.419 /
/// 0.427 across nights 1, 3, 5, 8, 12, 16, 20. Peaks run 0.53-0.62. The hold
/// point belongs between the early-career mean and the late one.
///
/// A CONSTANT THAT WAS TUNED AGAINST DIFFERENT PHYSICS IS NOT A TUNED
/// CONSTANT. It has to be re-derived whenever the thing it measures changes.
const double kDreadHold = 0.360;
const double kDreadGain = 14.0;

/// And how much faster it recovers below it.
///
/// Without asymmetry it RATCHETS: bursts drove it up at ~1.7/s while calm bled
/// it at only 0.25/s, so any night with spikes climbed to 100 and stayed. A
/// dread that is always maxed says exactly as little as one that never moves.
/// At 3x it breathes, and breathing is the only way the player feels a causal
/// link between their own hands and their own fear.
const double kDreadRecover = 3.0;

/// How fast the carrier falls on a given night. THE difficulty dial.
///
/// Sub-linear at the top on purpose. Linear produced a cliff rather than a
/// wall: a competent operator survived night 12 comfortably and then died 64
/// seconds into night 16, because once the demanded rate crosses what two
/// hands can serve the failure is a cascade and arrives all at once.
double carrierDecay(int night) =>
    2.9 + math.pow(night.toDouble(), 0.85).toDouble() * 0.42;

/// And how much harder it falls as the shift wears on, 0..1 through the night.
///
/// WITHOUT THIS A NIGHT HAS NO SHAPE. Flat decay meant a night you could not
/// win was lost in its first minute — measured, night 20 died at 66 seconds of
/// 480 while night 16 survived comfortably. That is a cliff between careers
/// rather than a wall inside one, and it throws away the near miss, which is
/// the entire "one more night" hook: you want to lose at 05:40 having nearly
/// made it, not at 23:01.
double shiftRamp(double progress) => 0.72 + 0.62 * progress.clamp(0.0, 1.0);

/// THE LINE WANDERS ON ITS OWN.
///
/// Mains sag, ice on the antenna, the feeder warming and cooling — the load a
/// transmitter is working into is never the load it was working into a minute
/// ago, and the operating point moves with it.
///
/// Mechanically this is what stops an early night from being solvable ONCE.
/// Without it, measured on night 1: the operator made two drive corrections in
/// the first minute, the resting carrier was then safe for the remaining
/// seven, and there was a SIXTEEN AND A HALF SECOND stretch with nothing to
/// do. Two adjustments bought the whole shift. The difficulty ramp cannot fix
/// that, because on an early night the ramp's effect is only a few points.
///
/// So the operating point drifts on a slow cycle at EVERY difficulty, and the
/// dial has to be walked all night. Amplitude is deliberately small — this is
/// texture, not threat. It makes an easy night quiet, not empty.
/// Periods of 20s and 64s. The first pass used 56s and 170s and it was far too
/// slow to be work: night 1 measured THIRTY-FIVE separate stretches over four
/// seconds long with nothing to do, up to 16.8s, because between threshold
/// crossings of a system on a one-minute cycle there is genuinely nothing for
/// two hands to do. The median hid it completely at 2.57s. A distribution has
/// to be looked at, not summarised.
double lineWander(double t) =>
    (math.sin(t * 0.31) + math.sin(t * 0.097) * 0.8) * 2.3;

/// Modulation's wander. THREE incommensurable periods, so the sign flips on a
/// schedule the operator cannot learn and pre-empt with a held correction.
///
/// The third term is the fast one and it is why there is a third at all. With
/// only the 30s and 86s components the needle sits almost still near their
/// turning points, and a night 1 run measured an EIGHTEEN AND A HALF SECOND
/// stretch with nothing whatever to do — the exact defect this rewrite exists
/// to remove, walking back in through the one system slow enough to rest.
/// Programme audio does not rest. Neither does this.
double modDrift(double t) =>
    (math.sin(t * 0.34) +
        math.sin(t * 0.11) * 0.7 +
        math.sin(t * 0.83) * 0.7) *
    4.8;

// ---------------------------------------------------------------------------

/// The transmitter, and the drums that count what it cost.
///
/// Pure Dart: no Flutter, no rendering, no audio. That is what makes a whole
/// night simulate in about forty milliseconds, which is the only reason any of
/// this could be tuned honestly.
class Rig {
  Rig(this.night, {this.nightSeconds = 8 * 60});

  final int night;
  final double nightSeconds;

  // --- the operator's one continuous control ---

  /// DRIVE, 0..100. A dial, not a pump. The carrier tracks toward it.
  double drive = 56;

  // --- the machine ---
  double carrier = 56;
  double modulation = 50;
  double plate = 30;
  double logDue = kLogPeriod;

  // --- the ledger, which only ever counts up ---
  double offAir = 0;
  double ceiling = kCeiling0;
  double inSpec = 0;
  final Map<String, double> offAirBy = <String, double>{};
  final List<Debit> invoice = <Debit>[];

  // --- state ---
  double dread = 0;
  double busy = 0;
  double lockout = 0;
  int trips = 0;
  bool voided = false;
  double _splatterFor = 0;
  double _t = 0;

  /// Scales how fast dread bleeds off. The runtime raises it inside a
  /// protection window, because recovering from a scare is supposed to be
  /// something the player can WATCH happen, and the calm bought with a clean
  /// kill should visibly pay for the last one.
  double recoveryScale = 1.0;

  final Tape tape = Tape();
  final List<Attach> attached = <Attach>[];
  final Map<Rail, double> bite = <Rail, double>{};

  /// Seconds behind the operator the Rerun's hands are.
  static const double kGhostDelay = 12.0;
  bool ghosting = false;

  double get t => _t;
  bool get dead => carrier <= 0.5;
  bool get lowPower => carrier < kLowPower;

  double attachedOn(Rail r) =>
      attached.where((a) => a.rail == r).fold(0.0, (n, a) => n + a.rate);

  /// 0..1. How badly the operator is keeping up, right now.
  double get strain {
    final c = (1 - carrier / 100).clamp(0.0, 1.0) * kStrainCarrier;
    final p = (plate / 100).clamp(0.0, 1.0) * kStrainPlate;
    final m = ((modulation - 50).abs() / 42).clamp(0.0, 1.0) * kStrainMod;
    final b = busy.clamp(0.0, 1.0) * kStrainBusy;
    return c + p + m + b;
  }

  /// How many systems are outside their comfortable band. Drives how long the
  /// operator takes to NOTICE the next thing going wrong.
  int get wrongCount =>
      (lowPower ? 1 : 0) +
      (plate > 74 ? 1 : 0) +
      ((modulation - 50).abs() > 12 ? 1 : 0) +
      (logDue <= 0 ? 1 : 0) +
      (lockout > 0 ? 1 : 0);

  /// Everything green, nothing on the air, nothing attached.
  bool get allGreen =>
      !lowPower &&
      plate < 74 &&
      (modulation - 50).abs() < 14 &&
      logDue > 0 &&
      lockout <= 0 &&
      attached.isEmpty &&
      bite.isEmpty;

  void _charge(String what, double amount) {
    if (amount <= 0) return;
    offAir += amount;
    offAirBy[what] = (offAirBy[what] ?? 0) + amount;
    final last = invoice.isNotEmpty ? invoice.last : null;
    // Per-second tariffs coalesce into one line, or the invoice is 4,000 rows
    // of "DEAD AIR 0.03" and nobody can read what killed them.
    if (last != null && last.what == what && _t - last.at < 12) {
      last.amount += amount;
    } else {
      invoice.add(Debit(_t, what, amount));
    }
  }

  void tick(double dt, {bool handsCommitted = false}) {
    if (voided) return;

    final ramp = shiftRamp(_t / nightSeconds);

    // --- the carrier tracks the dial, and everything pulls it down ---
    carrier += (drive - carrier) * kTrack * dt;
    carrier -= (carrierDecay(night) * ramp + lineWander(_t)) * dt;
    carrier -= ((bite[Rail.carrier] ?? 0) + attachedOn(Rail.carrier)) * dt;
    if (lockout > 0) {
      // contactor out: the dial is not connected to anything
      carrier -= 26 * dt;
      lockout -= dt;
    }
    carrier = carrier.clamp(0.0, 100.0);

    // --- the plate, on a square law, cooling by Newton ---
    final double d = (lockout > 0 ? 0 : drive) / 100;
    plate += d * d * kPlateGain * dt;
    plate -= (kPlateCoolBase + plate * kPlateCoolPerDeg) * dt;
    plate += ((bite[Rail.plate] ?? 0) + attachedOn(Rail.plate)) * dt;
    plate = plate.clamp(0.0, 140.0);
    if (plate >= kPlateTrip && lockout <= 0) {
      trips++;
      lockout = kTripLockout;
      plate = kTripPlateAfter;
      _charge('OVERLOAD RECYCLE', kTripCharge);
    }

    // --- modulation ---
    modulation += modDrift(_t) * dt;
    modulation -=
        ((bite[Rail.modulation] ?? 0) + attachedOn(Rail.modulation)) * dt;
    modulation = modulation.clamp(0.0, 100.0);
    if (modulation < kModTripLow || modulation > kModTripHigh) {
      _splatterFor += dt;
      if (_splatterFor > 1.5) {
        _splatterFor = 0;
        modulation = 50;
        _charge('SPLATTER', kChargeSplatter);
      }
    } else {
      _splatterFor = 0;
    }

    // --- the book ---
    logDue -= dt;
    logDue -= ((bite[Rail.log] ?? 0) + attachedOn(Rail.log)) * dt;
    if (logDue < -kLogGrace) {
      logDue = kLogPeriod;
      _charge('LOG NOT SIGNED', kChargeUnsigned);
    }

    // --- your own hands, twelve seconds late ---
    if (ghosting) {
      for (final act in tape.playback(_t, kGhostDelay, dt)) {
        _apply(act, ghost: true);
      }
    }
    tape.trim(_t, kGhostDelay + 4);

    // --- THE DRUMS ---
    if (lockout > 0) {
      _charge('LOCKOUT', kTariffLockout * dt);
    } else if (dead) {
      _charge('DEAD AIR', kTariffDeadAir * dt);
    } else if (lowPower) {
      _charge('LOW POWER', kTariffLowPower * dt);
    }
    if ((modulation - 50).abs() > kModGreen) {
      _charge(modulation > 50 ? 'OVERMODULATION' : 'LOW MODULATION',
          kTariffOffMod * dt);
    }
    if (attached.isNotEmpty) {
      _charge('ATTACHMENTS', kTariffAttach * attached.length * dt);
    }

    // IN SPEC buys allowance back. THE DRUMS NEVER RUN BACKWARD — the ceiling
    // rises instead, so the score stays monotonic and there is still something
    // to chase. Watching an eleven-second green stretch break because the hour
    // came due is the near-miss shape, and it costs the player nothing they
    // had already banked.
    if (allGreen) {
      inSpec += dt;
      if (inSpec > kInSpecArm) {
        final earned = ((inSpec - kInSpecArm) / kInSpecPeriod).floor();
        final want = math.min(kCeilingMax, kCeiling0 + earned.toDouble());
        if (want > ceiling) ceiling = want;
      }
    } else {
      inSpec = 0;
    }

    if (offAir >= ceiling) voided = true;

    // --- strain and dread ---
    busy += ((handsCommitted ? 1.0 : 0.0) - busy) * dt / kBusyTau;
    final dd = (strain - kDreadHold) * kDreadGain;
    dread += (dd < 0 ? dd * kDreadRecover * recoveryScale : dd) * dt;
    dread = dread.clamp(0.0, 100.0);

    _t += dt;
  }

  // --- the operator's hands ---

  /// Wind the drive up or down. A SETPOINT, not an increment — see the note at
  /// the top of this file about why that distinction is the whole rewrite.
  void trim(int dir) => _apply(dir > 0 ? 'drive+' : 'drive-');

  /// Correct the modulation.
  void nudge(int dir) => _apply(dir > 0 ? 'mod+' : 'mod-');

  /// Sign the hour.
  void sign() => _apply('sign');

  void _apply(String act, {bool ghost = false}) {
    switch (act) {
      case 'drive+':
        drive = math.min(100, drive + 6);
      case 'drive-':
        drive = math.max(0, drive - 6);
      case 'mod+':
        modulation = (modulation + kNudgeMod).clamp(0.0, 100.0);
      case 'mod-':
        modulation = (modulation - kNudgeMod).clamp(0.0, 100.0);
      case 'sign':
        // The Rerun cannot sign for you. It only does the things that cost.
        if (!ghost) logDue = kLogPeriod;
    }
    if (!ghost) tape.write(_t, act);
  }

  /// SOMETHING FRIGHTENING HAPPENED, or stopped happening.
  ///
  /// Every penalty and relief in the game lands here, and NOT on
  /// GameState.dread. The rig assigns that field once a frame, so a write to
  /// it anywhere else is silently thrown away — which is exactly what happened
  /// to the ninth key's escalating price, to a fumbled counter, to a false
  /// entry in the book and to nineteen other places, all at once and all
  /// without a single test noticing except the one that measured the price of
  /// pressing 9 three times.
  ///
  /// One field, one owner, one door.
  void bump(double d) => dread = (dread + d).clamp(0.0, 100.0);

  /// A window went unanswered. It does not leave.
  void attach(String id, Rail rail, double rate) =>
      attached.add(Attach(id, rail, rate));

  bool detach(String id) {
    final i = attached.indexWhere((a) => a.id == id);
    if (i < 0) return false;
    attached.removeAt(i);
    return true;
  }
}
