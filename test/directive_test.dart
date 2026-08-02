// The directive is the loudest element on screen. It must never be wrong.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/objective.dart';
import 'package:final_broadcast/src/state.dart';

GameState _fresh() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('frame one of a fresh night is not an alarm', () {
    // It used to open with "THE CLOCK IS HELD", which is false at 23:00 — the
    // clock only holds at :59 — about a state that is simply the start of a
    // segment. A warning that is on by default is not a warning.
    final s = _fresh();
    final r = AnomalyRuntime(s);
    r.startBroadcast();
    r.tick(1 / 60.0);

    expect(s.stalled, isFalse, reason: 'nothing is held at 23:00');
    final d = primeDirective(s, r);
    expect(d.text, isNot(contains('HELD')));
    expect(d.text, isNot(contains('BEHIND')));
    expect(d.urgency, Urgency.calm,
        reason: 'second zero must read as an instruction, not an alarm');
    expect(d.text, contains('STRIKE THE TUBE'),
        reason: 'the true first action, since 15 SIGNAL is unaffordable at 0');
  });

  test('it does say HELD once the clock actually is', () {
    final s = _fresh();
    s.stalled = true;
    s.segSig = 0;
    final r = AnomalyRuntime(s);
    final d = primeDirective(s, r);
    expect(d.text, contains('THE CLOCK IS HELD'));
    expect(d.urgency, Urgency.urgent);
  });

  test('being behind late in a segment does warn', () {
    final s = _fresh();
    s.prod['rabbit'] = 1; // a station that HAS started, and is still short
    s.shiftMin = 55; // 5 minutes of segment left
    expect(onPaceForQuota(s), isFalse);
    final d = primeDirective(s, AnomalyRuntime(s));
    expect(d.text, contains('BEHIND THE QUOTA'));
  });

  test('a station that will clearly make it is left alone', () {
    final s = _fresh();
    s.prod['rabbit'] = 400; // miles ahead of the night-one quota
    s.shiftMin = 2;
    expect(onPaceForQuota(s), isTrue);
    expect(primeDirective(s, AnomalyRuntime(s)).urgency, Urgency.calm);
  });

  test('a telegraph is never green', () {
    // Measured on the shipped build: 65-72% of telegraph frames showed a calm
    // green directive while the ON AIR lamp two dozen pixels above pulsed red
    // "!! DISTURBANCE". primeDirective only ever inspected r.active, which is
    // null for the whole riser.
    seedRandom(31337);
    final s = _fresh();
    s.prod['rabbit'] = 40;
    final r = AnomalyRuntime(s);
    r.startBroadcast();

    var t = 0.0, warnFrames = 0, calmDuringWarn = 0;
    const dt = 1 / 60.0;
    while (t < 21 * 60 && !r.lost && warnFrames < 400) {
      r.tick(dt);
      t += dt;
      if (r.warn > 0 && r.active == null) {
        warnFrames++;
        if (primeDirective(s, r).urgency != Urgency.urgent) calmDuringWarn++;
      }
      final a = r.active;
      if (a != null && a.stage == 1 && a.p > 0.3) r.pressCounter(a.def.counter);
    }
    expect(warnFrames, greaterThan(60), reason: 'no telegraph was observed');
    expect(calmDuringWarn, 0,
        reason: '\$calmDuringWarn of \$warnFrames telegraph frames read calm');
  });

  test('the directive names the keycap and the digit, not the raw id', () {
    final s = _fresh();
    for (final a in kAnoms) {
      s.seen[a.id] = true;
    }
    final r = AnomalyRuntime(s);
    r.startBroadcast();
    var t = 0.0;
    const dt = 1 / 60.0;
    while (t < 21 * 60 && (r.active == null || r.active!.stage < 1) && !r.lost) {
      r.tick(dt);
      t += dt;
    }
    final a = r.active!;
    final c = kCounterBy[a.liveKeys.first]!;
    final d = primeDirective(s, r);
    expect(d.text, contains(c.nm),
        reason: 'the strip must say what the keycap says');
    expect(d.text, contains('KEY ' + c.key));
    // and it must name a key that is actually LIVE
    expect(a.liveKeys, contains(c.id));
  });

  test('the panel goes quiet once the night is over', () {
    final s = _fresh();
    final r = AnomalyRuntime(s);
    r.startBroadcast();
    r.signalLost();
    expect(primeDirective(s, r).text, 'THE NIGHT IS OVER');
  });

  test('the stall toast and the HUD quote the same figure', () {
    // Both used to read segOf(s).quota, the printed night-one table, while the
    // game enforced quotaScale(). Fixed in the status bar first; the toast and
    // the EMP floor were still on the old figure.
    final s = _fresh();
    // NOT "a later night is always a bigger quota" — measured, night 7 draws
    // SKELETON CREW, whose whole deal is a 30% smaller rundown (111.7 vs the
    // printed 120). What must hold is that every consumer reads the SAME
    // figure, whichever way the card pushed it.
    for (final n in <int>[1, 2, 5, 7, 8, 14]) {
      s.night = n;
      s.segSig = 0;
      expect(quotaShortfall(s), closeTo(segQuota(s), 0.01),
          reason: 'night $n disagrees with itself');
    }
    s.night = 8; // THE ENGINEER'S STANDING BOUNTY — quota x1.25
    expect(segQuota(s), greaterThan(kRundown[0].quota));
  });
}
