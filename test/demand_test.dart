// HOW MUCH DOES THIS GAME ACTUALLY ASK OF THE PLAYER?
//
// The instrument that found the real defect. Everything else in this suite
// asserts that a mechanism works; this one asserts that the mechanisms
// ADD UP TO A GAME, which is a different question and the one that was missed.
//
// It exists because tempo_test.dart already measured the emptiness — its own
// header records "the tube had something on it for 2.3-4.1% of a night" — and
// then wrote a guard permitting anything above 6%. A threshold set just above
// the measured value does not catch a defect, it ratifies it. That is how a
// game ends up wooden with a green suite.
//
// MEASURED BASELINE, before the core redesign (8-minute nights, seeded):
//
//   time with anything on the tube ...... 15-24% passive, ~3% played well
//   arrivals ............................ one every 9-28s
//   median stretch with nothing to do ... ~20s AT EVERY NIGHT, 1 through 12
//   worst stretch ....................... 36-54s
//   player decisions .................... 2.6/min
//   game interruptions .................. 12.9/min  (one every 4.7s)
//   scares fired, nights 1-5 ............ 1 in total
//   time above dread 85, nights 1-5 ..... 0%
//
// The two numbers that matter most: the player acts 2.6 times a minute and is
// interrupted 12.9 times a minute, and the median gap between having anything
// to do is twenty seconds and DOES NOT SHRINK as the difficulty ramps. Harder
// nights add more isolated pokes; they never make a single moment busier.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

/// What one simulated night felt like from the player's side.
class Demand {
  Demand(this.seconds, this.decisions, this.interruptions, this.onTube,
      this.deadRuns);

  final double seconds;
  final int decisions;
  final int interruptions;

  /// Seconds with something actually live.
  final double onTube;

  /// Every stretch, in seconds, where there was nothing to do.
  final List<double> deadRuns;

  double get decisionsPerMin => decisions / (seconds / 60);
  double get interruptionsPerMin => interruptions / (seconds / 60);
  double get onTubeFrac => onTube / seconds;

  double get medianDead {
    if (deadRuns.isEmpty) return 0;
    final s = List<double>.from(deadRuns)..sort();
    return s[s.length ~/ 2];
  }

  double get worstDead =>
      deadRuns.isEmpty ? 0 : deadRuns.reduce((a, b) => a > b ? a : b);

  @override
  String toString() => 'decisions ${decisionsPerMin.toStringAsFixed(1)}/min  '
      'interruptions ${interruptionsPerMin.toStringAsFixed(1)}/min  '
      'onTube ${(onTubeFrac * 100).toStringAsFixed(0)}%  '
      'dead median ${medianDead.toStringAsFixed(1)}s worst '
      '${worstDead.toStringAsFixed(1)}s';
}

/// Plays a night the way a competent player does: answers everything, promptly,
/// with the right key. Deliberately NOT a perfect player — [reaction] is the
/// delay before answering, because a perfect player who clears every threat in
/// one frame measures the game as emptier than it is, which is a harness lie
/// this file has already told once.
Demand playNight(int night, {int seed = 20260803, double reaction = 1.2}) {
  seedRandom(seed + night);
  final s = GameState()..night = night;
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 40 * night;
  s.prod['dipole'] = 25 * night;

  var interruptions = 0;
  var lastLen = 0;
  s.toasts.addListener(() {
    if (s.toasts.items.isEmpty) return;
    if (s.toasts.items.length >= lastLen) interruptions++;
    lastLen = s.toasts.items.length;
  });

  final r = AnomalyRuntime(s);
  r.startBroadcast();

  var t = 0.0, onTube = 0.0, idle = 0.0, decisions = 0;
  final dead = <double>[];
  const dt = 1 / 30.0;
  while (t < 8 * 60 && !r.lost) {
    // DESK WORK IS WORK.
    //
    // The first version of this instrument counted only anomaly windows and
    // treated every other frame as dead air. That was a complete description
    // of the old game, where the only thing a player ever did was answer a
    // prompt — and it is why the baseline below reads twenty seconds of
    // nothing. Under the rig the operator is holding a machine inside its
    // limits continuously, and a measure that ignores that would report the
    // same twenty seconds while the player never takes their hands off.
    var acted = mindTheDesk(r);
    if (acted) decisions++;
    r.tick(dt);
    final a = r.active;
    if (a != null) {
      onTube += dt;
      if (a.t > reaction) {
        r.pressCounter(a.def.counter);
        decisions++;
        acted = true;
      }
    }
    if (acted) {
      if (idle > 0.05) {
        dead.add(idle);
        idle = 0;
      }
    } else {
      idle += dt;
    }
    t += dt;
  }
  if (idle > 0.05) dead.add(idle);
  return Demand(t, decisions, interruptions, onTube, dead);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('BASELINE — print what the game currently asks for', () {
    // Not an assertion. This is the instrument's readout, and it is here so
    // that anyone changing the core can see the shape move.
    for (final n in <int>[1, 2, 3, 5, 8]) {
      // ignore: avoid_print
      print('night $n: ${playNight(n)}');
    }
  });

  test('THE defect is gone: the player is never left with nothing to do', () {
    // Shipped: median 20s of nothing, at EVERY night from 1 to 12, and the
    // ramp never shortened it. Now 0.3-2.4s.
    for (final n in <int>[1, 2, 3, 5, 8]) {
      final d = playNight(n);
      expect(d.medianDead, lessThan(4.0),
          reason: 'night $n median dead ${d.medianDead.toStringAsFixed(1)}s');
    }
  });

  test('and the game no longer talks over them', () {
    // THE number. Shipped: 2.6 player decisions a minute against 12.9
    // interruptions — the game said five things for every one thing the player
    // did. It has to be the other way round.
    // Asserted across a span rather than per-night, because the night cards
    // are supposed to make nights differ: A QUIET NIGHT measures 13.9
    // decisions/min against 42.4 on a busy one, and a flat per-night floor
    // would either be set below the quiet card (and guard nothing) or would
    // forbid the deck from having a quiet card in it at all.
    final nights = <int>[1, 2, 3, 5, 8].map(playNight).toList();
    final mean = nights.map((d) => d.decisionsPerMin).reduce((a, b) => a + b) /
        nights.length;
    expect(mean, greaterThan(18),
        reason: 'the game asks for ${mean.toStringAsFixed(1)} decisions/min on '
            'average against a shipped 2.6');
    for (final d in nights) {
      expect(d.decisionsPerMin, greaterThan(12),
          reason: 'even the quietest night must ask for more than the shipped '
              'build did at every difficulty');
      expect(d.interruptionsPerMin, lessThan(d.decisionsPerMin),
          reason: 'the game interrupts '
              '${d.interruptionsPerMin.toStringAsFixed(1)}/min against '
              '${d.decisionsPerMin.toStringAsFixed(1)} decisions — it is still '
              'talking over the player');
    }
  });

  test('a harder night is busier', () {
    final a = playNight(1);
    final b = playNight(8);
    expect(b.decisionsPerMin, greaterThan(a.decisionsPerMin * 1.3),
        reason: 'night 8 asks ${b.decisionsPerMin.toStringAsFixed(1)}/min '
            'against night 1 ${a.decisionsPerMin.toStringAsFixed(1)}/min');
  });
}
