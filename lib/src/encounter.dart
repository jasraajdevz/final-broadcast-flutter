// FINAL BROADCAST — how a thing arrives, and how the night gets worse.
//
// Everything in this file exists because of one measured finding: the game had
// no arc at any timescale. `telegraph()` returned 2.0 forever, so 23 out of 23
// intrusions arrived behind an identical riser; `kRundown` is const, so night
// two was night one with bigger numbers; and a headless 15-night run pinned
// DREAD at 0 from night two onward.
//
// So this file owns the four dials that make an intrusion feel like an EVENT
// instead of an appointment:
//
//   1. A PER-ENTITY ARRIVAL.  DEAD AIR does not get the same riser as MR.
//      SLEEPWELL: he winds a music box for three seconds, and the absence just
//      turns up. Each entity has its own telegraph length, its own jitter, its
//      own window multiplier and its own one-line TELL — flavour that hints at
//      what is coming WITHOUT naming it, and only once you have met the thing
//      at least once. Learning the tells is the skill ceiling.
//
//   2. THE COLD OPEN.  Some arrivals have no warning at all. The chance rises
//      with DREAD and with the night, is never rolled on a debut or in the
//      first few minutes of a shift, and PAYS THE PLAYER BACK with a much
//      longer banish window when it fires. Surprise, not ambush.
//
//   3. THE SURGE.  The gap between intrusions is bimodal. Most of the time it
//      is the long, legible interval economy.dart rolls; sometimes it is a
//      quick follow-up. This is what makes the ALL CLEAR window mechanically
//      real — before this, calm (max 24s) was always shorter than the gap
//      (29-40s), so the lamp was pure theatre. It is now the one thing that
//      reliably blocks a surge.
//
//   4. NIGHT PRESSURE.  One saturating 0..1 dial, zero on night one, that
//      every night-over-night escalation in the game reads. It saturates, so
//      night forty is hard rather than impossible.
//
// Plus a small MODIFIER set (TWO-STAGE, COUPLED) rolled per visit. The rule
// they must never break: a modifier may never disable the key that banishes
// its own entity. TWO-STAGE asks for the SAME key twice; COUPLED asks for its
// own key AND a second entity's, in either order, and only ever picks a
// partner the player has already met.
//
// Imports consts.dart and state.dart only, so both economy.dart and
// anomalies.dart can depend on it without a cycle.

import 'dart:math' as math;

import 'consts.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Night pressure — the one escalation dial
// ---------------------------------------------------------------------------

/// How deep into the career the current shift is, 0..1, saturating.
///
///   night  1 -> 0.00      night  5 -> 0.50
///   night  2 -> 0.20      night  9 -> 0.67
///   night  3 -> 0.33      night 13 -> 0.75
///   night  4 -> 0.43      night  ∞ -> 1.00
///
/// Night one is deliberately EXACTLY zero: the opening shift is the tutorial
/// and nothing in it is scaled.
double nightPressure(GameState s) {
  final n = math.max(0, s.night - 1).toDouble();
  return n / (n + kNightPressureHalf);
}

/// Nights past the first at which night pressure reaches 0.5.
const double kNightPressureHalf = 4.0;

// ---------------------------------------------------------------------------
// Per-entity arrival profiles
// ---------------------------------------------------------------------------

/// How one entity announces itself.
class EncounterProfile {
  const EncounterProfile({
    required this.id,
    required this.telegraph,
    required this.jitter,
    required this.windowMul,
    required this.coldBias,
    required this.tell,
    required this.coldTell,
  });

  final String id;

  /// Seconds of riser on night one at zero dread, before PHOSPHOR MASK.
  final double telegraph;

  /// Fraction of [telegraph] the roll may wander either way.
  final double jitter;

  /// Multiplier on `banishWindow()` for this entity.
  final double windowMul;

  /// Multiplier on the cold-open chance. DEAD AIR is twice as likely to just
  /// be there; MR. SLEEPWELL practically always announces himself.
  final double coldBias;

  /// The telegraph line, shown ONLY once the player has met this entity. It
  /// hints; it never names. Learning the eight tells is the skill ceiling.
  final String tell;

  /// The line for an arrival with no warning at all.
  final String coldTell;
}

/// Eight profiles, one per entry in [kAnoms].
const Map<String, EncounterProfile> kEncounters = <String, EncounterProfile>{
  'snow': EncounterProfile(
    id: 'snow',
    telegraph: 2.4,
    jitter: 0.16,
    windowMul: 1.0,
    coldBias: 0.9,
    tell: '.. THE GRAIN IS GETTING ORGANISED',
    coldTell: '## IT WAS ALREADY IN THE NOISE',
  ),
  'sleep': EncounterProfile(
    id: 'sleep',
    telegraph: 3.1,
    jitter: 0.10,
    windowMul: 1.06,
    coldBias: 0.35,
    tell: '.. A MUSIC BOX IS WINDING SOMEWHERE',
    coldTell: '## HE IS ALREADY LEANING IN',
  ),
  'vert': EncounterProfile(
    id: 'vert',
    telegraph: 1.3,
    jitter: 0.24,
    windowMul: 0.94,
    coldBias: 1.5,
    tell: '.. THE PICTURE IS STARTING TO TEAR',
    coldTell: '## THE SEAM OPENED WITH NO WARNING',
  ),
  'dead': EncounterProfile(
    id: 'dead',
    telegraph: 0.95,
    jitter: 0.30,
    windowMul: 1.12,
    coldBias: 2.0,
    tell: '.. THE ROOM HAS GONE VERY QUIET',
    coldTell: '## EVERYTHING STOPPED AT ONCE',
  ),
  'card': EncounterProfile(
    id: 'card',
    telegraph: 2.7,
    jitter: 0.14,
    windowMul: 1.06,
    coldBias: 0.7,
    tell: '.. COLOUR IS BLEEDING IN FROM THE EDGES',
    coldTell: '## SHE IS SITTING IN THE FRAME ALREADY',
  ),
  'rerun': EncounterProfile(
    id: 'rerun',
    telegraph: 1.8,
    jitter: 0.22,
    windowMul: 0.96,
    coldBias: 1.25,
    tell: '.. THE AUDIO IS RUNNING A HALF-SECOND LATE',
    coldTell: '## THE LOOP CAUGHT UP WITH YOU',
  ),
  'niel': EncounterProfile(
    id: 'niel',
    telegraph: 2.2,
    jitter: 0.12,
    windowMul: 0.90,
    coldBias: 0.8,
    tell: '.. SOMEBODY IS READING THE OVERNIGHTS',
    coldTell: '## THE AUDIT OPENED WITHOUT NOTICE',
  ),
  'call': EncounterProfile(
    id: 'call',
    telegraph: 1.5,
    jitter: 0.20,
    windowMul: 1.0,
    coldBias: 1.35,
    tell: '.. A LINE IS RINGING SOMEWHERE IN THE BUILDING',
    coldTell: '## EVERY LINE AT ONCE, NO WARNING',
  ),
};

/// The profile for an entity id. Falls back to a neutral one so an id the
/// table has never heard of can never crash a night.
EncounterProfile profileOf(String id) =>
    kEncounters[id] ??
    const EncounterProfile(
      id: '?',
      telegraph: 2.0,
      jitter: 0.18,
      windowMul: 1.0,
      coldBias: 1.0,
      tell: '!! CARRIER DISTURBANCE',
      coldTell: '## SOMETHING IS ON THE CARRIER',
    );

// ---------------------------------------------------------------------------
// The telegraph
// ---------------------------------------------------------------------------

/// No riser may ever be shorter than this, however bad the night gets.
const double kTelegraphFloor = 0.55;

/// How much of the riser the worst night takes away.
const double kTelegraphNightSqueeze = 0.20;

/// How much of the riser a full DREAD bar takes away.
const double kTelegraphDreadSqueeze = 0.16;

/// Seconds of riser for THIS arrival. Randomised per call — roll it once, at
/// [AnomalyRuntime.beginWarn], never per frame.
double telegraphFor(GameState s, Anom def) {
  final p = profileOf(def.id);
  var t = p.telegraph;
  if (s.ups['phosphor'] ?? false) t += 0.9;
  t *= 1 -
      kTelegraphNightSqueeze * nightPressure(s) -
      kTelegraphDreadSqueeze * clampD(s.dread / 100, 0, 1);
  t *= rr(1 - p.jitter, 1 + p.jitter);
  return math.max(kTelegraphFloor, t);
}

/// The mean telegraph over the whole roster, with no jitter and no pressure.
/// Exposed so a stability readout can quote a figure that does not flicker.
double telegraphMean(GameState s) {
  var sum = 0.0;
  for (final a in kAnoms) {
    sum += profileOf(a.id).telegraph;
  }
  var t = sum / kAnoms.length;
  if (s.ups['phosphor'] ?? false) t += 0.9;
  return t * (1 - kTelegraphNightSqueeze * nightPressure(s));
}

/// The line the telegraph toast shows. A tell, never a name, and only for an
/// entity that has actually been on the tube before — a debut always gets the
/// generic warning, because a hint you cannot decode is just noise.
String tellFor(GameState s, Anom def) => (s.seen[def.id] ?? false)
    ? profileOf(def.id).tell
    : '!! CARRIER DISTURBANCE';

/// The line for an arrival with no riser at all.
String coldTellFor(GameState s, Anom def) => (s.seen[def.id] ?? false)
    ? profileOf(def.id).coldTell
    : '## NO WARNING — SOMETHING IS THROUGH';

// ---------------------------------------------------------------------------
// The cold open
// ---------------------------------------------------------------------------

/// Intrusions into a shift before a cold open may be rolled at all.
const int kColdOpenGrace = 3;

/// Floor chance of a cold open once the grace period is over.
const double kColdOpenBase = 0.05;

/// Ceiling, however bad it gets. Three in five arrivals always announce.
const double kColdOpenCap = 0.40;

/// The payback. A cold open is a much longer window than a telegraphed one —
/// you lose the warning, you gain the time.
const double kColdOpenWindowMul = 1.42;

/// Chance this arrival skips the riser entirely.
///
/// Never on a debut, never in the opening minutes of a shift, and never above
/// [kColdOpenCap].
double coldOpenChance(GameState s, Anom def, int nightIndex) {
  if (nightIndex < kColdOpenGrace) return 0;
  if (!(s.seen[def.id] ?? false)) return 0;
  final c = (kColdOpenBase +
          0.26 * clampD(s.dread / 100, 0, 1) +
          0.14 * nightPressure(s)) *
      profileOf(def.id).coldBias;
  return clampD(c, 0, kColdOpenCap);
}

// ---------------------------------------------------------------------------
// The surge — a bimodal gap
// ---------------------------------------------------------------------------

/// Intrusions into a shift before a surge may be rolled.
const int kSurgeGrace = 3;

/// Floor chance of a quick follow-up.
const double kSurgeBase = 0.08;

/// Ceiling. Just over half, at the very worst.
const double kSurgeCap = 0.52;

/// What a surge does to the rolled gap.
const double kSurgeMul = 0.36;

/// However short the roll, a surge never arrives sooner than this.
const double kSurgeFloor = 9.0;

/// Chance the next gap is a quick follow-up rather than the full interval.
///
/// A jumpscare makes it likelier (blood in the water); a clean banish makes it
/// less likely, on top of the ALL CLEAR window the banish already bought.
double surgeChance(GameState s,
    {required bool afterScare, required bool afterBanish}) {
  var c = kSurgeBase +
      0.30 * clampD(s.dread / 100, 0, 1) +
      0.18 * nightPressure(s);
  if (afterScare) c += 0.12;
  if (afterBanish) c -= 0.06;
  return clampD(c, 0, kSurgeCap);
}

/// One rolled gap: how long, and whether it was a surge.
class GapRoll {
  const GapRoll(this.seconds, this.surge);
  final double seconds;
  final bool surge;
}

// ---------------------------------------------------------------------------
// Modifiers
// ---------------------------------------------------------------------------

/// An extra rule rolled onto a single visit.
///
/// INVARIANT, checked by `test/sim_test.dart`: no modifier may ever make the
/// entity's own counter stop working. TWO-STAGE wants that key twice; COUPLED
/// wants that key plus one more. Neither ever rejects it.
enum EncounterMod {
  /// The entity as written.
  none,

  /// The first correct press does not kill it — it splits, the window is
  /// refilled, and the SAME key finishes it.
  twoStage,

  /// Two signatures share one body. Its own counter and the partner's, in
  /// either order. The partner is always something already catalogued.
  coupled,
}

/// Floor chance a visit is modified at all, from night two.
const double kModBase = 0.09;

/// Ceiling.
const double kModCap = 0.40;

/// TWO-STAGE: window multiplier at manifest, and the fraction of a fresh
/// `banishWindow()` refilled when the first correct press lands.
const double kTwoStageWindowMul = 1.20;
const double kTwoStageRefill = 0.90;
const double kTwoStageBonusMul = 1.40;

/// COUPLED: much longer window (two keys to find), much bigger payout.
const double kCoupledWindowMul = 1.65;
const double kCoupledBonusMul = 1.75;

/// Chance this visit carries a modifier.
double modChance(GameState s) {
  if (s.night < 2) return 0;
  return clampD(
      kModBase + 0.20 * nightPressure(s) + 0.10 * clampD(s.dread / 100, 0, 1),
      0,
      kModCap);
}

/// Rolls the modifier for one visit.
///
/// Never on a debut and never on a masked arrival — a mask is already a stage
/// gate, and stacking the two is how a visit becomes unreadable. COUPLED needs
/// a partner the player has already met, so it cannot appear before there is
/// one.
EncounterMod rollMod(
  GameState s, {
  required bool first,
  required bool masked,
  required bool hasPartner,
}) {
  if (first || masked) return EncounterMod.none;
  if (rand() >= modChance(s)) return EncounterMod.none;
  if (s.night < 3 || !hasPartner) return EncounterMod.twoStage;
  return rand() < 0.58 ? EncounterMod.twoStage : EncounterMod.coupled;
}

/// Picks the second signature for a COUPLED visit: a DIFFERENT entity, drawn
/// from the unlocked pool, that the player has already catalogued. Returns
/// null when there is no legal partner, in which case the caller must fall
/// back to [EncounterMod.none].
Anom? pickPartner(GameState s, List<Anom> pool, Anom self) {
  final ok = pool
      .where((a) => a.id != self.id && (s.seen[a.id] ?? false))
      .toList(growable: false);
  if (ok.isEmpty) return null;
  return pick(ok);
}

/// True when a COUPLED roll could legally be satisfied right now.
bool hasCouplePartner(GameState s, List<Anom> pool, Anom self) =>
    pool.any((a) => a.id != self.id && (s.seen[a.id] ?? false));

/// Short label for the HUD / the deck.
String modLabel(EncounterMod m) {
  switch (m) {
    case EncounterMod.none:
      return '';
    case EncounterMod.twoStage:
      return 'TWO-STAGE';
    case EncounterMod.coupled:
      return 'COUPLED';
  }
}
