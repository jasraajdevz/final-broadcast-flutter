// FINAL BROADCAST — derived economy, difficulty and the shift clock.
//
// Port of the "derived economy" / "sabotage" / "manual tuning" / "difficulty"
// blocks of index.html. The MONEY half is the original, number for number, and
// must stay that way — costOf/bulkCost/maxAfford/sigRate/rpGain/tuneYield are
// load-bearing against the save format and the rack's sticker prices.
//
// The PACING half (the "Difficulty" section below) has been deliberately
// retuned away from the original; see the block comments there for why and by
// how much. Everything the anomaly runtime needs to promise the player a safe
// window after a correct answer also lives there, and so does every
// night-over-night escalation, all of which read one dial: `nightPressure()`
// from encounter.dart.
//
// Everything is a top-level function taking the state explicitly. Functions
// whose JS original read the global `A` take the AnomalyRuntime as well.

import 'dart:math' as math;

import 'anomalies.dart';
import 'checks.dart';
import 'consts.dart';
import 'encounter.dart';
import 'nights.dart';
import 'meta.dart';
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

/// Spends RATINGS POINTS. The prestige counter was written in exactly one place
/// and decremented nowhere, which made it a score rather than a budget; this is
/// the debit side, for whoever spends it. Returns false and changes nothing
/// when the player cannot afford it.
bool spendRp(GameState s, int n) {
  if (n <= 0 || s.rp < n) return false;
  s.rp -= n;
  return true;
}

// ---------------------------------------------------------------------------
// Multipliers
// ---------------------------------------------------------------------------

// The original rpMult was `1 + rp*0.08` — dead linear, so prestige compounded
// without limit: 50 RP was x5, 200 RP was x17, 1000 RP was x81, and by then no
// quota in the rundown meant anything. The replacement is sub-linear, and pays
// the EARLY prestiges better than the original did:
//
//   rp    1 -> x1.26  (was 1.08)      rp   50 -> x3.86  (was  5.00)
//   rp    5 -> x1.70  (was 1.40)      rp  200 -> x7.62  (was 17.00)
//   rp   12 -> x2.20  (was 1.96)      rp 1000 -> x18.7  (was 81.00)

/// Coefficient on the sub-linear prestige curve.
const double kRpMultK = 0.26;

/// Exponent on the sub-linear prestige curve.
const double kRpMultExp = 0.62;

/// The permanent multiplier a given RP total is worth. Exposed separately from
/// [rpMult] so the end-of-run sheets can quote what a bank WOULD be worth.
double rpMultAt(int rp) =>
    rp <= 0 ? 1.0 : 1 + kRpMultK * math.pow(rp.toDouble(), kRpMultExp);

/// JS rpMult(), made sub-linear.
double rpMult(GameState s) => rpMultAt(s.rp);

/// JS sponsorMult().
double sponsorMult(GameState s) => s.sponsorEnd > 0 ? 3 : 1;

/// JS sigMult().
double sigMult(GameState s) {
  var m = rpMult(s) * sponsorMult(s);
  if (s.ups['preheat'] ?? false) m *= 1.3;
  if (s.ups['comp'] ?? false) m *= 2.2;
  // SILVER HALIDE's rack copy promises "+60% while a quota is unmet". Nothing
  // read the flag, so the one upgrade that exists to dig you out of a held
  // clock did nothing at all.
  if ((s.ups['halide'] ?? false) && !quotaMet(s)) m *= 1.6;
  m *= metaOutputMult(s); // NIGHT SHIFT PAY, permanent
  m *= cardOf(s).output; // tonight's standing conditions
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
    base += (s.prod[p.id] ?? 0) * p.sig * producerMarkMult(s.prod[p.id] ?? 0);
  }
  return base * sigMult(s);
}

/// JS sigRate() — what it is actually making right now.
double sigRate(GameState s, AnomalyRuntime a) {
  var base = 0.0;
  for (final p in kProducers) {
    if (prodLive(a, p.id)) base += (s.prod[p.id] ?? 0) * p.sig * producerMarkMult(s.prod[p.id] ?? 0);
  }
  // A station nobody is tending drifts out of alignment. See checks.dart —
  // the quiet used to be free, and free quiet is what a player experiences as
  // boredom. Neglecting the book costs up to 42% of output.
  return base * sigMult(s) * driftPenalty(a.checks);
}

/// JS rpGain().
int rpGain(GameState s) =>
    (math.pow(s.lifetimeSig / 2.5e5, 0.5) * cardOf(s).rp).floor();

/// JS tuneYield() — striking the set. The bootstrap and the thing to do
/// between anomalies.
///
/// The RP term is sub-linear for the same reason [rpMult] is: at a flat 1.5 per
/// point a deep career could hand-strike its way through the early rundown.
double tuneYield(GameState s, AnomalyRuntime a) {
  final base = 2 + 1.8 * math.pow(math.max(0, s.rp).toDouble(), 0.7);
  // CARRIER LOCK multiplies the payout 1.0 -> 3.0. It is the whole reason the
  // rhythm is worth holding, and the reason the most-repeated verb in the game
  // now has an arc instead of a flat rate.
  // THE COUPLING, BROKEN.
  //
  // The strike payout was DEFINED as a multiple of the rack's per-second
  // output, so its value relative to the rack was invariant to progression:
  // measured 0.871 strike-per-rack-second at a 195/s rack and 0.840 at a
  // 3.8M/s rack. Breakeven sat at 1.19 clicks/s at EVERY scale, CARRIER LOCK
  // tier 4 arrives 13.7s into a cold start, and at 3.5cps hand strikes were
  // 79.3% of a night's SIGNAL. The idle half of an idle game never took over,
  // which is a large part of why the whole thing felt thin.
  //
  // Two changes. The rack term now has diminishing returns, so the hand keeps
  // its early-game job and stops scaling with the machine you built; and the
  // LOCK multiplies only the flat term, so rhythm is rewarded on its own
  // merits instead of amplifying the rack you are supposed to be replacing it
  // with. The automation ceiling (1.06 effective cps) is deliberately just
  // under the old 1.19 breakeven — the intent was always rack-parity.
  final double rackTerm = 26 * math.pow(sigRate(s, a) / 26, 0.62).toDouble();
  return (s.tune.tierMult * base + rackTerm) *
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
// On top of that the NIGHT squeezes the whole curve by up to 20%, saturating,
// so a career that has stopped moving on depth still has somewhere to go. The
// gap is then rolled BIMODALLY — see rollGap() — which is what makes the ALL
// CLEAR window mechanically real rather than decorative.

/// The gap a fresh career gets, in seconds.
const double kGapOpen = 34;

/// The hard floor the gap approaches and never reaches.
const double kGapFloor = 19;

/// Career depth at which the gap has closed half the distance to the floor.
const double kGapHalfDepth = 40;

/// How much of the gap the worst night takes away, on top of depth.
const double kGapNightSqueeze = 0.20;

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

/// The expected gap in seconds — [anomInterval] without the jitter, and before
/// any surge. Exposed so the UI can draw a carrier-stability readout that does
/// not lie.
///
/// `nightIndex` is how many anomalies have already manifested this night.
double anomIntervalMean(GameState s, int nightIndex) {
  final d = depth(s);
  var base = kGapFloor + (kGapOpen - kGapFloor) / (1 + d / kGapHalfDepth);
  base *= 1 - kGapNightSqueeze * nightPressure(s);
  // FAILSAFE RELAY buys real quiet now, not a rounding error.
  if (s.ups['failsafe'] ?? false) base += 2.5;
  // A held clock still leans on you, but it may not spiral: being behind on
  // quota used to cut the gap by a quarter down to 6.5s, which is how a bad
  // segment turned into a dead run.
  if (s.stalled) base = math.max(15.0, base * 0.9);
  return base * openingEase(nightIndex) * cardOf(s).gap;
}

/// Seconds until the next telegraph, jittered but never surged. Randomised on
/// every call — call it once per schedule, never per frame.
///
/// The jitter is tighter than the original's rr(0.78,1.25) so the pacing is
/// legible: you can learn roughly how long you have, which is the only way the
/// ALL CLEAR window below can mean anything.
double anomInterval(GameState s, int nightIndex) =>
    anomIntervalMean(s, nightIndex) * rr(0.86, 1.18);

/// The real roll. Mostly the long legible interval; sometimes a SURGE — a quick
/// follow-up at [kSurgeMul] of it, never sooner than [kSurgeFloor].
///
/// This is the whole reason the ALL CLEAR window is worth anything. Before the
/// gap was bimodal, calm (5-24s) was always shorter than the gap (29-40s), so
/// the guaranteed-quiet window never once blocked an arrival and the lamp was
/// pure theatre. A surge is the thing it blocks.
GapRoll rollGap(
  GameState s,
  int nightIndex, {
  bool afterScare = false,
  bool afterBanish = false,
}) {
  final full = anomInterval(s, nightIndex);
  if (nightIndex < kSurgeGrace) return GapRoll(full, false);
  final c = surgeChance(s, afterScare: afterScare, afterBanish: afterBanish);
  if (rand() >= c) return GapRoll(full, false);
  return GapRoll(math.max(kSurgeFloor, full * kSurgeMul), true);
}

/// How much of the banish window the worst night takes away.
const double kWindowNightSqueeze = 0.10;

/// No window is ever shorter than this, whatever the career looks like.
const double kWindowFloor = 5.0;

/// JS banishWindow(). 7.5s -> 6.0s floor on depth, then squeezed by the night,
/// +1.2s with FERRITE CORE. Per-entity multipliers live in encounter.dart.
double banishWindow(GameState s) {
  final d = depth(s);
  var w = 7.5 - math.min(1.5, d * 0.02);
  w *= 1 - kWindowNightSqueeze * nightPressure(s);
  if (s.ups['ferrite'] ?? false) w += 1.2;
  w += metaWindowBonus(s); // FERRITE STOCK, permanent
  w *= cardOf(s).window;
  return math.max(kWindowFloor, w);
}

/// The roster-wide mean telegraph. Kept as a stable, jitter-free figure for
/// readouts and diagnostics; the real per-arrival length is `telegraphFor()` in
/// encounter.dart, which is per-entity, jittered, and shortened by both the
/// night and the dread bar.
double telegraph(GameState s) => telegraphMean(s);

// --- the ALL CLEAR ----------------------------------------------------------
//
// A correct counter has to actually make you safe, or the deck is just a slot
// machine. Every successful banish opens a window whose FIRST stretch — the
// GUARD — is an absolute, tested, nothing-can-manifest guarantee, and whose
// tail is a taper: the gap timer is live again, but an arrival inside it comes
// in softened (longer riser, longer window, half intensity).
//
//   scraped it at the buzzer, streak 1 ->  5.0s  ( 3.5 guaranteed + 1.5 taper)
//   instant kill, streak 1              -> 14.0s ( 8.7 guaranteed + 5.3 taper)
//   instant kill, streak 6              -> 22.5s (14.0 guaranteed + 8.5 taper)
//   instant kill, streak 7+             -> 24.0s (cap), +2s with FAILSAFE
//
// The guard is what a surge runs into. Being right buys real, felt protection;
// it just stops being an on/off switch at the very end of the window.

/// Floor of the calm window — what even a buzzer-beater buys.
const double kCalmBase = 5;

/// Extra seconds a perfectly clean kill adds on top of [kCalmBase].
const double kCalmClean = 9;

/// Seconds added per banish of streak, past the first.
const double kCalmStreakStep = 1.7;

/// Cap on the streak component, so calm never swallows the night whole.
const double kCalmStreakCap = 6;

/// The largest share of the CURRENT mean gap that an ALL CLEAR window may
/// occupy.
///
/// calm blocks a manifest but deliberately does NOT pause the countdown, so
/// the spacing between intrusions is max(gap, calm) — not gap + calm. With
/// calm paying up to 24s against a mean rolled gap of 13-18s, calm won 78-83%
/// of intervals, which meant the GAP dial was simply overwritten: STORM FRONT
/// (x0.75) and OPEN LINE (x0.70) advertised a busier night and delivered one
/// within 2-7% of a card with no gap dial at all, and the depth ramp was half
/// swallowed. Measured across 8 nights, the tube had something on it for 2.3%
/// to 4.1% of a night.
///
/// Holding calm under the gap hands the tempo back to the scheduler while
/// keeping the promise that a correct answer buys real, guaranteed quiet.
const double kCalmGapShare = 0.62;

/// Fraction of a calm window that is an ABSOLUTE guarantee.
const double kCalmGuardFrac = 0.62;

/// Seconds of absolute guarantee even the worst banish buys.
const double kCalmGuardMin = 3.5;

/// The guaranteed-quiet head of a calm window [span] seconds long.
double calmGuardOf(double span) => span <= 0
    ? 0
    : math.min(span, math.max(kCalmGuardMin, span * kCalmGuardFrac));

/// Length of the quiet window a successful banish opens.
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
  double? meanGap,
  int fumbles = 0,
}) {
  var w = kCalmBase + kCalmClean * clampD(cleanliness, 0, 1);
  w += math.min(kCalmStreakCap, math.max(0, streak - 1) * kCalmStreakStep);
  if (fumbles > 0) w *= math.max(0.55, 1 - fumbles * 0.18);
  if (s.ups['failsafe'] ?? false) w += 2;
  // Never longer than a share of the gap it has to fit inside. See
  // [kCalmGapShare] — without this the reward for a clean kill silently
  // becomes the game's tempo control, and every night runs at one speed.
  if (meanGap != null && meanGap > 0) {
    w = math.min(w, meanGap * kCalmGapShare);
  }
  return w;
}

/// Forced quiet after a jumpscare. Nothing may manifest during it, which is the
/// guarantee that a scare can never chain into a second one while you are still
/// reeling — and the reason the run is always recoverable.
double scareRecovery(GameState s) =>
    9.0 + ((s.ups['failsafe'] ?? false) ? 2.0 : 0.0);

/// JS unlockedAnoms(). Tier 1 at depth 6, tier 2 at depth 16 — but the NIGHT
/// opens them too, so a fresh career on night three does not have to re-earn
/// the roster it has already survived.
List<Anom> unlockedAnoms(GameState s) {
  final d = depth(s);
  final n = s.night;
  return kAnoms
      .where((a) =>
          a.tier == 0 ||
          (a.tier == 1 && (d >= 6 || n >= 2)) ||
          (a.tier == 2 && (d >= 16 || n >= 3)))
      .toList(growable: false);
}

// --- dread ------------------------------------------------------------------
//
// Measured before this section existed: perfect play across a whole night
// peaked at 0.9 DREAD out of 100. The bar was a report card, not a threat. Two
// things changed:
//
//   * a PER-SEGMENT FLOOR the decay cannot cross, and which dread creeps up to
//     when it is under it. 03:00 is heavier than 23:00 whatever you do.
//   * an ATMOSPHERIC INFLOW read from `AnomalyRuntime.lurkPressure`, which the
//     scene writes from the things standing in the field. The window stops
//     being scenery.
//
// Both are bounded well under 100, so neither can kill you on its own; they
// exist so that the anomaly inflow lands on a bar that is already warm.

/// Hard ceiling on the per-segment floor. Nothing atmospheric may push DREAD
/// past this on its own — SIGNAL LOST always has to be something you did.
const double kDreadFloorCap = 42;

/// How fast dread creeps UP toward the floor when it is under it.
const double kDreadFloorClimb = 0.20;

/// Dread per second at full [AnomalyRuntime.lurkPressure]. Deliberately about
/// half the idle decay rate, so a crowded field slows your recovery rather than
/// reversing it.
const double kLurkDread = 0.42;

/// Dread per second while the clock is held on an unmet quota.
const double kStallDread = 0.9;

/// Seconds between re-statements of the held-clock toast.
const double kStallRepeat = 8.5;

/// The floor DREAD decay may not cross in the current segment.
///
///   night 1, 23:00 ->  0.0      night  1, 05:00 -> 14.4
///   night 5, 05:00 -> 25.2      night 13, 05:00 -> 30.6
double dreadFloor(GameState s) {
  final seg = segIndex(s).toDouble();
  final base = seg * 2.4;
  return math.min(
      kDreadFloorCap, base * (1 + 1.5 * nightPressure(s)) * cardOf(s).dread);
}

// --- the revive -------------------------------------------------------------
//
// The emergency sponsor used to reset dread to a flat 45 and hand out a flat
// 45s of x3 output every time, so the fifth revive of a night was as good as
// the first and SIGNAL LOST stopped meaning anything. It escalates now, and the
// SIGNAL LOST sheet quotes the next one's terms before you take it.

/// Where DREAD lands after the `n`-th revive of a night (1-based).
double reviveDread(int n) => math.min(76.0, 34.0 + (n - 1) * 14.0);

/// Seconds of sponsored x3 output the `n`-th revive is worth.
double reviveSponsor(int n) => math.max(18.0, 48.0 - (n - 1) * 10.0);

/// Multiplier on the forced-quiet window the `n`-th revive opens.
double reviveGrace(int n) => math.max(0.45, 1.0 - (n - 1) * 0.18);

// ---------------------------------------------------------------------------
// The shift clock
// ---------------------------------------------------------------------------

/// JS segIndex().
int segIndex(GameState s) =>
    math.min(kRundown.length - 1, (s.shiftMin / 60).floor());

/// JS segOf().
RundownSeg segOf(GameState s) => kRundown[segIndex(s)];

/// How much harder tonight's quotas are than the printed table.
///
///   night 1 -> x1.00   night 3 -> x1.18   night 9 -> x1.37
///   night 2 -> x1.11   night 5 -> x1.28   night ∞ -> x1.55
///
/// Night one is exactly the printed number, so the tutorial shift is the game
/// as documented.
double quotaScale(GameState s) =>
    (1 + 0.55 * nightPressure(s)) * cardOf(s).quota;

/// Tonight's quota for segment [i].
double quotaOf(GameState s, int i) {
  final j = i < 0 ? 0 : (i >= kRundown.length ? kRundown.length - 1 : i);
  return kRundown[j].quota * quotaScale(s);
}

/// Tonight's quota for the CURRENT segment. Everything that displays or reasons
/// about a quota should read this rather than `segOf(s).quota`, which is the
/// printed night-one figure.
double segQuota(GameState s) => quotaOf(s, segIndex(s));

/// JS quotaMet().
bool quotaMet(GameState s) => s.segSig >= segQuota(s);

/// How much output the current segment is still short. 0 once it is met.
double quotaShortfall(GameState s) => math.max(0, segQuota(s) - s.segSig);

/// JS shiftClock() — "23:00" .. "05:59".
String shiftClock(GameState s) {
  final h = (23 + (s.shiftMin / 60).floor()) % 24;
  final m = (s.shiftMin % 60).floor();
  return '${pad2(h)}:${pad2(m)}';
}
