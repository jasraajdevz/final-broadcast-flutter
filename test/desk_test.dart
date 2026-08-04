// THE DESK, SIMULATED.
//
// The whole point of the rewrite is a number: the median stretch where the
// player has nothing to do. It was twenty seconds, at every difficulty. These
// assert it is now about one, and that the ramp actually shortens it.
//
// The operator below is deliberately NOT omniscient. The first version of it
// read all four gauges perfectly and reacted in 0.30s, and under omniscience
// the design measured as balanced while producing NO DREAD AT ALL on nights 1
// through 8 — a game tuned for a player who cannot exist. Divided attention is
// not a detail of this design, it IS the design, and a harness without it
// would have signed off on a game nobody can play.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/desk.dart';

/// What one simulated night looked like from the operator's side.
class Night {
  Night(this.desk, this.actions, this.dead, this.peakDread, this.meanDread,
      this.mix);

  final Desk desk;
  final int actions;
  final List<double> dead;
  final double peakDread;
  final double meanDread;
  final Map<String, int> mix;

  double get actionsPerMin => actions / (desk.t / 60);

  double get medianDead {
    if (dead.isEmpty) return 0;
    final s = List<double>.from(dead)..sort();
    return s[s.length ~/ 2];
  }

  double get worstDead =>
      dead.isEmpty ? 0 : dead.reduce((a, b) => a > b ? a : b);

  double share(String k) => (mix[k] ?? 0) / actions;

  @override
  String toString() => 'acts ${actionsPerMin.toStringAsFixed(1)}/min  '
      'dead med ${medianDead.toStringAsFixed(2)}s worst '
      '${worstDead.toStringAsFixed(1)}s  dread peak '
      '${peakDread.toStringAsFixed(0)} mean ${meanDread.toStringAsFixed(0)}  '
      '${mix.entries.map((e) => "${e.key} ${e.value}").join(" ")}  '
      '${desk.s.lost ? "LOST ${desk.s.lostTo!.name} @${desk.t.toStringAsFixed(0)}s" : "survived"}';
}

/// Deterministic arrivals, so tuning runs compare.
class _Rng {
  _Rng(this._s);
  int _s;
  double next() {
    _s = (_s * 1103515245 + 12345) & 0x7FFFFFFF;
    return _s / 0x7FFFFFFF;
  }
}

/// What each entity chews on while it is up. The desk on its own is only half
/// the game: without anything biting the rails, dread flatlined at 0-8 across
/// every night and night 12 was survivable on autopilot. An entity is not a
/// prompt with a key any more, it is a thing eating a named part of the
/// machine, and the desk must be tuned against that load rather than clean.
const Map<String, (Rail, double)> kBites = <String, (Rail, double)>{
  'snow': (Rail.carrier, 2.6),
  'sleep': (Rail.modulation, 9.0),
  'vert': (Rail.plate, 7.0),
  'card': (Rail.carrier, 1.8),
};

/// A competent operator with human hands and one pair of eyes.
Night playNight(int night, {double seconds = 8 * 60, int seed = 7717}) {
  final d = Desk(night);
  final rng = _Rng(seed + night * 31);
  var nextArrival = 8.0;
  String? live;
  var liveFor = 0.0;
  final dead = <double>[];
  final mix = <String, int>{};
  var actions = 0, idle = 0.0, cooldown = 0.0, notice = 0.0;
  var peak = 0.0, dreadSum = 0.0;
  const dt = 1 / 30.0;

  void mark(String k) => mix[k] = (mix[k] ?? 0) + 1;

  while (d.t < seconds && !d.s.lost) {
    // whatever is on the air is chewing on its rail
    d.bite.clear();
    if (live != null) {
      final b = kBites[live]!;
      d.bite[b.$1] = b.$2;
      liveFor += dt;
    } else {
      nextArrival -= dt;
      if (nextArrival <= 0) {
        live = kBites.keys.elementAt((rng.next() * 4).floor() % 4);
        liveFor = 0;
        // Short gaps, because the desk carries the tension between arrivals
        // and the entity is a spike on top rather than the only content.
        nextArrival = 11 + rng.next() * 9 - night * 0.35;
      }
    }
    d.tick(dt, handsCommitted: cooldown > 0);
    if (d.s.lost) break;
    if (d.s.dread > peak) peak = d.s.dread;
    dreadSum += d.s.dread * dt;

    var acted = false;
    if (cooldown > 0) {
      cooldown -= dt;
    } else {
      // Spotting the next problem takes longer when the desk is already busy.
      if (d.wrongCount > 0 && notice > 0) {
        notice -= dt;
      } else {
        notice = 0.35 + 0.42 * (d.wrongCount - 1).clamp(0, 4);
        if (live != null && liveFor > 0.9) {
          live = null;
          mark('entity');
          cooldown = 0.30;
          acted = true;
        } else if (d.s.logDue <= 0) {
          d.sign();
          mark('log');
          // Signing is a real two-second commitment with both hands off the
          // desk — it is the one interruption you can SEE coming, and at 0.55s
          // it cost so little that a competent operator survived night 12 on
          // autopilot. The dread of a scheduled interruption is the price it
          // charges everywhere else.
          cooldown = 1.9;
          acted = true;
        } else if (d.s.plate > kVentAt) {
          d.vent();
          mark('vent');
          cooldown = 0.30;
          acted = true;
        } else if (d.s.modulation < 38) {
          d.nudge(1);
          mark('mod');
          cooldown = 0.30;
          acted = true;
        } else if (d.s.modulation > 62) {
          d.nudge(-1);
          mark('mod');
          cooldown = 0.30;
          acted = true;
        } else if (d.s.carrier < 55) {
          d.push();
          mark('push');
          cooldown = 0.30;
          acted = true;
        }
      }
    }

    if (acted) {
      actions++;
      if (idle > 0.05) {
        dead.add(idle);
        idle = 0;
      }
    } else {
      idle += dt;
    }
  }
  if (idle > 0.05) dead.add(idle);
  return Night(d, actions, dead, peak, dreadSum / d.t, mix);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('READOUT', () {
    for (final n in <int>[1, 3, 5, 8, 12, 16, 20, 24]) {
      // ignore: avoid_print
      print('night ${n.toString().padLeft(2)}: ${playNight(n)}');
    }
  });

  test('THE defect is gone: there is no dead air, at any difficulty', () {
    // Shipped build: median 20s at every night, worst 36-54s.
    for (final n in <int>[1, 2, 3, 5, 8, 12]) {
      final r = playNight(n);
      expect(r.medianDead, lessThan(3.0),
          reason: 'night $n median dead ${r.medianDead.toStringAsFixed(1)}s');
      expect(r.worstDead, lessThan(6.0),
          reason: 'night $n worst dead ${r.worstDead.toStringAsFixed(1)}s');
    }
  });

  test('a harder night is BUSIER, not merely louder', () {
    // The shipped ramp added more isolated pokes and left the median gap at
    // twenty seconds from night 1 to night 12. This is the thing it never did.
    final a = playNight(1);
    final b = playNight(12);
    expect(b.medianDead, lessThan(a.medianDead),
        reason: 'night 12 (${b.medianDead.toStringAsFixed(2)}s) is not busier '
            'than night 1 (${a.medianDead.toStringAsFixed(2)}s)');
    expect(b.actionsPerMin, greaterThan(a.actionsPerMin * 1.4),
        reason: 'night 12 asks ${b.actionsPerMin.toStringAsFixed(1)}/min '
            'against night 1 ${a.actionsPerMin.toStringAsFixed(1)}/min');
  });

  test('the player is asked for something roughly every two seconds', () {
    // Shipped: 2.6/min. Too few and it is wooden; too many and it is not a
    // horror game, it is a typing test.
    for (final n in <int>[1, 5, 12]) {
      final r = playNight(n);
      expect(r.actionsPerMin, greaterThan(20),
          reason: 'night $n asks only ${r.actionsPerMin.toStringAsFixed(1)}/min');
      expect(r.actionsPerMin, lessThan(75),
          reason: 'night $n asks ${r.actionsPerMin.toStringAsFixed(1)}/min, '
              'which is a typing test');
    }
  });

  test('pushing harder is sometimes the WRONG answer', () {
    // The one that caught the design failing its own brief. With a flat plate
    // cost the vent never fired once in twelve nights and push was 51-68% of
    // every action and rising — clicking with a new name. The dilemma has to
    // arrive as the nights get harder.
    expect(playNight(2).share('vent'), lessThan(0.02),
        reason: 'the plate should not bind on an early night');
    final late = playNight(12);
    expect(late.share('vent'), greaterThan(0.04),
        reason: 'night 12 spends only ${(late.share("vent") * 100).round()}% '
            'of its actions venting — the carrier/plate tension is decorative '
            'and this is a clicker again');
  });

  test('dread breathes rather than pinning at either end', () {
    // Set wrong twice in tuning, in opposite directions: above a competent
    // player's peak it pinned at 0, below their mean it pinned at 100. Both
    // are the shipped defect reached from either side.
    final easy = playNight(1);
    expect(easy.meanDread, lessThan(20),
        reason: 'night 1 should not be terrifying');
    final mid = playNight(5);
    expect(mid.peakDread, greaterThan(25),
        reason: 'night 5 never frightens anybody: peak '
            '${mid.peakDread.toStringAsFixed(0)}');
    expect(mid.meanDread, lessThan(mid.peakDread * 0.75),
        reason: 'dread sits at its peak instead of recovering — mean '
            '${mid.meanDread.toStringAsFixed(0)} against peak '
            '${mid.peakDread.toStringAsFixed(0)}');
  });

  test('a night can actually be lost, and lost late', () {
    // Dying at three quarters of the way through is the near-miss the whole
    // "one more night" hook depends on, and it falls out of the mechanics
    // rather than being scripted.
    final r = playNight(12);
    expect(r.desk.s.lost, isTrue, reason: 'night 12 is survivable on autopilot');
    expect(r.desk.t, greaterThan(8 * 60 * 0.45),
        reason: 'night 12 died at ${r.desk.t.toStringAsFixed(0)}s — that is a '
            'beating, not a near miss');
  });
}
