// FINAL BROADCAST — derived economy, difficulty and the shift clock.
//
// Straight port of the "derived economy" / "sabotage" / "manual tuning" /
// "difficulty" blocks of index.html. Same constants, same order of operations,
// same floating-point shape. Do not retune anything here.
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

/// JS depth().
int depth(GameState s) => s.stats.banished + s.stats.scared * 2;

/// JS anomInterval(). Difficulty lives in the GAP, not in a shrinking window.
/// Randomised by rr(0.78,1.25) on every call — call it once per schedule.
double anomInterval(GameState s) {
  final d = depth(s);
  var base = math.max(8.0, 27 - d * 0.42);
  if (s.ups['failsafe'] ?? false) base += 1;
  if (s.stalled) base = math.max(6.5, base * 0.75);
  return base * rr(0.78, 1.25);
}

/// JS banishWindow(). 7.5s -> 6.0s floor, +1.2s with FERRITE CORE.
double banishWindow(GameState s) {
  final d = depth(s);
  var w = 7.5 - math.min(1.5, d * 0.02);
  if (s.ups['ferrite'] ?? false) w += 1.2;
  return w;
}

/// JS telegraph().
double telegraph(GameState s) => (s.ups['phosphor'] ?? false) ? 2.5 : 1.6;

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
