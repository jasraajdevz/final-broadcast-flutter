// FINAL BROADCAST — derived economy, difficulty and the shift clock.
//
// Port of the "derived economy" / "sabotage" / "manual tuning" / "difficulty"
// blocks of index.html. The MONEY half is the original, number for number, and
// must stay that way — costOf/bulkCost/maxAfford/sigRate/rpGain/tuneYield are
// load-bearing against the save format and the rack's sticker prices.
//
// The PACING half (the "Difficulty" section below) has been deliberately
// retuned away from the original; see the block comment there for why and by
// how much. Everything the anomaly runtime needs to promise the player a safe
// window after a correct answer also lives there.
//
// Everything is a top-level function taking the state explicitly. Functions
// whose JS original read the global `A` take the AnomalyRuntime as well.

import 'dart:math' as math;

import 'anomalies.dart';
import 'consts.dart';
import 'state.dart';

// ---------------------------------------------------------------------------
// Costs
// ---------------------------------------------------------------------------

/// JS costOf(p).
double costOf(GameState s, Producer p) =>
    p.cost * math.pow(p.mul, s.prod[p.id] ?? 0);

/// JS bulkCost(p,n).
double bulkCost(GameState s, Producer p, int n) {
  final c = costOf(s, p);
  return c * (math.pow(p.mul, n) - 1) / (p.mul - 1);
}

/// JS maxAfford(p).
int maxAfford(GameState s, Producer p) {
  final c = costOf(s, p);
  if (s.sig < c) return 0;
  final v =
      (math.log(1 + (s.sig / c) * (p.mul - 1)) / math.log(p.mul)).floor();
  return v < 1 ? 1 : v;
}

/// The rack's buy-mode resolved to a count: 1, 10, or max-affordable.
int resolveBuyCount(GameState s, Producer p) {
  if (s.buyMode == GameState.buyModeMax) {
    final n = maxAfford(s, p);
    return n < 1 ? 1 : n;
  }
  return s.buyMode;
}

/// The rack's visibility rule: index 0, or the tier below is owned, or you are
/// within 25% of the sticker price. Locked rows are still SHOWN (greyed).
bool producerUnlocked(GameState s, int index) {
  if (index == 0) return true;
  final prev = kProducers[index - 1];
  if ((s.prod[prev.id] ?? 0) > 0) return true;
  return s.sig >= kProducers[index].cost * 0.25;
}

/// JS `u.req()` — the upgrade's unlock predicate, plus the "owned is always
/// shown" rule from renderRack().
bool upgradeVisible(Upgrade u, GameState s) =>
    (s.ups[u.id] ?? false) || u.req(s);

/// Spends and grants. Returns false (and changes nothing) if unaffordable.
bool buyProducer(GameState s, Producer p, int n) {
  final c = bulkCost(s, p, n);
  if (s.sig < c) return false;
  s.sig -= c;
  s.prod[p.id] = (s.prod[p.id] ?? 0) + n;
  return true;
}

/// Spends and installs. Returns false (and changes nothing) if unaffordable.
bool buyUpgrade(GameState s, Upgrade u) {
  if (s.sig < u.cost) return false;
  s.sig -= u.cost;
  s.ups[u.id] = true;
  return true;
}

// ---------------------------------------------------------------------------
// Multipliers
// ---------------------------------------------------------------------------


/// JS rpMult().
double rpMult(GameState s) => 1 + s.rp * 0.08;

/// JS sponsorMult().
double sponsorMult(GameState s) => s.sponsorEnd > 0 ? 3 : 1;

/// JS sigMult().
double sigMult(GameState s) {
  var m = rpMult(s) * sponsorMult(s);
  if (s.ups['preheat'] ?? false) m *= 1.3;
  if (s.ups['comp'] ?? false) m *= 2.2;
  return m;
}

// ---------------------------------------------------------------------------
// Rates
// ---------------------------------------------------------------------------

/// DEAD AIR eats transmitters off the air. JS prodLive(id).
bool prodLive(AnomalyRuntime a, String id) {
  final act = a.active;
  return !(act != null && act.mute.contains(id));
}

/// JS sigRateRaw() — what the station WOULD make. Payouts use this.
double sigRateRaw(GameState s) {
  var base = 0.0;
  for (final p in kProducers) {
    base += (s.prod[p.id] ?? 0) * p.sig;
  }
  return base * sigMult(s);
}

/// JS sigRate() — what it is actually making right now.
double sigRate(GameState s, AnomalyRuntime a) {
  var base = 0.0;
  for (final p in kProducers) {
    if (prodLive(a, p.id)) base += (s.prod[p.id] ?? 0) * p.sig;
  }
  return base * sigMult(s);
}


/// JS rpGain().
int rpGain(GameState s) => math.pow(s.lifetimeSig / 2.5e5, 0.5).floor();

/// JS tuneYield() — striking the set. The bootstrap and the thing to do
/// between anomalies.
double tuneYield(GameState s, AnomalyRuntime a) {
  final base = 2 + s.rp * 1.5;
  return (base + sigRate(s, a) * 0.28) *
      ((s.ups['preheat'] ?? false) ? 1.3 : 1) *
      sponsorMult(s);
}

/// TAPE VAULT offline accrual. Returns 0 when it does not apply.
/// JS: away<60s does nothing, capped at 4h, 35% efficiency, uses sigRateRaw().
double offlineGrant(GameState s) {
  if (!s.started || !(s.ups['vault'] ?? false)) return 0;
  final away =
      (DateTime.now().millisecondsSinceEpoch - s.lastSave) / 1000.0;
  if (away < 60) return 0;
  final cap = math.min(away, 4 * 3600);
  return sigRateRaw(s) * cap * 0.35;
}

// ---------------------------------------------------------------------------
// Difficulty
// ---------------------------------------------------------------------------

/// JS depth(). NOTE: `stats` is never wiped by resetForNewNight(), so depth is
/// a CAREER counter, not a per-night one — it only ever goes up. Anything that
/// scales on it therefore has to saturate, or night four is unplayable.
int depth(GameState s) => s.stats.banished + s.stats.scared * 2;

// --- pacing -----------------------------------------------------------------
//
// The original ramp was `max(8, 27 - depth*0.42)`: linear, and because depth is
// a career counter it hit the 8s floor at depth 45 — roughly two nights in —
// and stayed there forever. With a ~7.5s window and a ~1.6s telegraph that is a
// 17s cycle of which 9s is an emergency. That is the "relentless" the player is
// describing, and it never stops getting worse.
//
// The replacement is a saturating curve that can never close past kGapFloor:
//
//     gap(d) = kGapFloor + (kGapOpen - kGapFloor) / (1 + d / kGapHalfDepth)
//
//   depth   0 -> 34.0s      depth  80 -> 24.0s
//   depth  20 -> 29.0s      depth 200 -> 21.5s
//   depth  40 -> 26.5s      depth  inf -> 19.0s
//
// A 21-minute night at ~34s + 2.0s telegraph + ~7.5s window is ~24 intrusions;
// deep in a career it tops out near ~44. The old curve was pushing 70+. The
// late game is now tense (a fifth of the time is an emergency) rather than
// spammy (a half of it was).

/// The gap a fresh career gets, in seconds.
const double kGapOpen = 34;

/// The hard floor the gap approaches and never reaches.
const double kGapFloor = 19;

/// Career depth at which the gap has closed half the distance to the floor.
const double kGapHalfDepth = 40;

/// Per-night ease-in. A night has to have room to breathe before it bites, so
/// the first four intrusions of a shift are spaced out on top of everything
/// else. At depth 0 that is 70s / 55s / 45s / 39s, then the steady 34s.
const List<double> kNightOpening = <double>[2.05, 1.62, 1.34, 1.15];

/// The multiplier applied to the gap before the `nightIndex`-th intrusion of
/// the night (0-based). 1.0 from the fifth onward.
double openingEase(int nightIndex) {
  if (nightIndex < 0) return kNightOpening.first;
  if (nightIndex >= kNightOpening.length) return 1;
  return kNightOpening[nightIndex];
}

/// The expected gap in seconds — [anomInterval] without the jitter. Exposed so
/// the UI can draw a carrier-stability readout that does not lie.
///
/// `nightIndex` is how many anomalies have already manifested this night.
double anomIntervalMean(GameState s, int nightIndex) {
  final d = depth(s);
  var base = kGapFloor + (kGapOpen - kGapFloor) / (1 + d / kGapHalfDepth);
  // FAILSAFE RELAY buys real quiet now, not a rounding error.
  if (s.ups['failsafe'] ?? false) base += 2.5;
  // A held clock still leans on you, but it may not spiral: being behind on
  // quota used to cut the gap by a quarter down to 6.5s, which is how a bad
  // segment turned into a dead run.
  if (s.stalled) base = math.max(15.0, base * 0.9);
  return base * openingEase(nightIndex);
}

/// Seconds until the next telegraph. Randomised on every call — call it once
/// per schedule, never per frame.
///
/// The jitter is tighter than the original's rr(0.78,1.25) so the pacing is
/// legible: you can learn roughly how long you have, which is the only way the
/// ALL CLEAR window below can mean anything.
double anomInterval(GameState s, int nightIndex) =>
    anomIntervalMean(s, nightIndex) * rr(0.86, 1.18);

/// JS banishWindow(). 7.5s -> 6.0s floor, +1.2s with FERRITE CORE.
double banishWindow(GameState s) {
  final d = depth(s);
  var w = 7.5 - math.min(1.5, d * 0.02);
  if (s.ups['ferrite'] ?? false) w += 1.2;
  return w;
}

/// JS telegraph(), lengthened by 0.4s at both ends. PHOSPHOR MASK is still
/// worth exactly the +0.9s its rack copy promises.
double telegraph(GameState s) => (s.ups['phosphor'] ?? false) ? 2.9 : 2.0;

// --- the ALL CLEAR ----------------------------------------------------------
//
// A correct counter has to actually make you safe, or the deck is just a slot
// machine. Every successful banish opens a window in which NOTHING can
// manifest, its length set by how clean the kill was and compounded by the
// streak. Missing one resets the streak, so the compounding is earned.
//
//   scraped it at the buzzer, streak 1 ->  5.0s
//   instant kill, streak 1              -> 14.0s
//   instant kill, streak 6              -> 22.5s
//   instant kill, streak 7+             -> 24.0s (cap), +2s with FAILSAFE
//
// Against a ~19-34s gap that is a guaranteed third-to-half of the downtime,
// on top of the gap rather than inside it.

/// Floor of the calm window — what even a buzzer-beater buys.
const double kCalmBase = 5;

/// Extra seconds a perfectly clean kill adds on top of [kCalmBase].
const double kCalmClean = 9;

/// Seconds added per banish of streak, past the first.
const double kCalmStreakStep = 1.7;

/// Cap on the streak component, so calm never swallows the night whole.
const double kCalmStreakCap = 10;

/// Length of the guaranteed-quiet window a successful banish opens.
///
/// * [cleanliness] 0..1 — 1 when the key was hit the instant it manifested,
///   0 at the last frame of the window.
/// * [streak] — consecutive successful banishes INCLUDING this one.
/// * [fumbles] — wrong keys pressed during this visit; panicking costs you
///   some of the reward, but never all of it.
double calmWindow(
  GameState s, {
  required double cleanliness,
  required int streak,
  int fumbles = 0,
}) {
  var w = kCalmBase + kCalmClean * clampD(cleanliness, 0, 1);
  w += math.min(kCalmStreakCap, math.max(0, streak - 1) * kCalmStreakStep);
  if (fumbles > 0) w *= math.max(0.55, 1 - fumbles * 0.18);
  if (s.ups['failsafe'] ?? false) w += 2;
  return w;
}

/// Forced quiet after a jumpscare. Nothing may manifest during it, which is the
/// guarantee that a scare can never chain into a second one while you are still
/// reeling — and the reason the run is always recoverable.
double scareRecovery(GameState s) =>
    9.0 + ((s.ups['failsafe'] ?? false) ? 2.0 : 0.0);

/// JS unlockedAnoms(). tier 1 at depth 6, tier 2 at depth 16.
List<Anom> unlockedAnoms(GameState s) {
  final d = depth(s);
  return kAnoms
      .where((a) =>
          a.tier == 0 || (a.tier == 1 && d >= 6) || (a.tier == 2 && d >= 16))
      .toList(growable: false);
}

// ---------------------------------------------------------------------------
// The shift clock
// ---------------------------------------------------------------------------

/// JS segIndex().
int segIndex(GameState s) =>
    math.min(kRundown.length - 1, (s.shiftMin / 60).floor());

/// JS segOf().
RundownSeg segOf(GameState s) => kRundown[segIndex(s)];

/// JS quotaMet().
bool quotaMet(GameState s) => s.segSig >= segOf(s).quota;

/// JS shiftClock() — "23:00" .. "05:59".
String shiftClock(GameState s) {
  final h = (23 + (s.shiftMin / 60).floor()) % 24;
  final m = (s.shiftMin % 60).floor();
  return '${pad2(h)}:${pad2(m)}';
}
