// THE LAST-SECOND SAVE.
//
// A kill with 0.4s left and a kill with 4s left used to be the same event —
// same shake, same sting, same toast, same money. The moment worth clipping is
// the one you nearly lost, so it has to be measurably louder, not just a
// different word in a toast.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _seeded() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 40;
  s.prod['dipole'] = 30;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

/// A whole night answered at [at] of the way through each window.
({int clutch, int banished, double sig}) _play(double at) {
  final s = _seeded();
  final r = AnomalyRuntime(s);
  r.startBroadcast();
  var t = 0.0;
  const dt = 1 / 60.0;
  while (t < 21 * 60 && !r.lost) {
    mindTheDesk(r);
        r.tick(dt);
    t += dt;
    final a = r.active;
    if (a != null && a.stage == 1 && a.p >= at) {
      r.pressCounter(a.def.counter);
    }
  }
  return (clutch: s.stats.clutch, banished: s.stats.banished, sig: s.lifetimeSig);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('answering early never counts as a save', () {
    final early = _play(0.05);
    expect(early.banished, greaterThan(10));
    expect(early.clutch, 0,
        reason: 'a comfortable answer must never be dressed up as a save');
  });

  test('answering on the buzzer does', () {
    final late = _play(0.90);
    expect(late.banished, greaterThan(6));
    expect(late.clutch, greaterThan(4),
        reason: 'answering at 90% of the window produced no saves at all');
  });

  test('a save pays more than the partial kill it used to be', () {
    // Comparing two whole nights does NOT work: answering late means every
    // anomaly sabotages for longer, so total lifetime signal is LOWER at 90%
    // than at 55% even though each individual kill pays more. Measured, not
    // assumed. So alternate the press time WITHIN one night and compare the
    // per-kill payouts directly — which also controls for the station growing
    // over the shift.
    final s = _seeded();
    final r = AnomalyRuntime(s);
    r.startBroadcast();

    final late = <double>[], mid = <double>[];
    var manifest = 0;
    var wasActive = false;
    var prevSig = s.sig;
    var prevBanished = 0;
    var pendingLate = false;

    var t = 0.0;
    const dt = 1 / 60.0;
    while (t < 21 * 60 && !r.lost) {
      final before = s.sig;
      mindTheDesk(r);
            r.tick(dt);
      t += dt;

      final a = r.active;
      final now = a != null;
      if (now && !wasActive) {
        manifest++;
        pendingLate = manifest.isEven;
      }
      wasActive = now;

      if (s.stats.banished > prevBanished) {
        prevBanished = s.stats.banished;
        (pendingLate ? late : mid).add(s.sig - prevSig);
      }
      prevSig = before;

      if (a != null && a.stage == 1 && a.p >= (pendingLate ? 0.90 : 0.50)) {
        r.pressCounter(a.def.counter);
      }
    }

    expect(late.length, greaterThan(3), reason: 'not enough late kills');
    expect(mid.length, greaterThan(3), reason: 'not enough mid kills');

    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    expect(mean(late), greaterThan(mean(mid) * 1.15),
        reason: 'a save must be worth taking the risk for');
  });
}
