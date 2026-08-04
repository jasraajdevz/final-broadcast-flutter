// TEMPO. Every night used to run at exactly one speed.
//
// calm blocks a manifest but does not pause the countdown, so spacing is
// max(gap, calm). calm paid up to 24s against a mean rolled gap of 13-18s, so
// it won 78-83% of intervals and the GAP dial was overwritten: measured across
// 8 nights, A QUIET NIGHT (gap x1.40), a card-less night (x1.00) and OPEN LINE
// (x0.70) all landed within 7% of each other, and the tube had something on it
// for 2.3-4.1% of a night.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/nights.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

({double secPerIntrusion, double onTubeFrac, int manifests}) _tempo(int night) {
  seedRandom(night * 7717 + 3);
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.night = night;
  s.prod['rabbit'] = 60;
  s.prod['dipole'] = 45;
  s.prod['vhf'] = 30;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  final r = AnomalyRuntime(s);
  r.startBroadcast();

  var t = 0.0;
  var frames = 0, onTube = 0, manifests = 0;
  var wasActive = false;
  const dt = 1 / 60.0;
  while (t < 21 * 60 && !r.lost) {
    mindTheDesk(r);
        r.tick(dt);
    t += dt;
    frames++;
    final a = r.active;
    final now = a != null;
    if (now) onTube++;
    if (now && !wasActive) manifests++;
    wasActive = now;
    if (a != null && a.stage == 1 && a.p > 0.3) r.pressCounter(a.def.counter);
  }
  return (
    secPerIntrusion: manifests == 0 ? 9999 : t / manifests,
    onTubeFrac: onTube / frames,
    manifests: manifests,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an ALL CLEAR window can never outrun the gap it sits inside', () {
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    // the most generous window the game can pay: perfect kill, long streak
    final w = calmWindow(s,
        cleanliness: 1.0,
        streak: 40,
        fumbles: 0,
        meanGap: anomIntervalMean(s, 12));
    expect(w, lessThan(anomIntervalMean(s, 12)),
        reason: 'calm still overwrites the scheduler');
    // and it must still be worth something
    expect(w, greaterThan(4), reason: 'a clean kill has to buy real quiet');
  });

  test('the three gap dials produce three different nights', () {
    // A QUIET NIGHT gap x1.40 (night 3), FRESH CORES x1.00 (night 6),
    // OPEN LINE x0.70 (night 4).
    final quiet = _tempo(3);
    final flat = _tempo(6);
    final busy = _tempo(4);
    debugPrint('QUIET(x1.40) ${quiet.secPerIntrusion.toStringAsFixed(1)}s/int  '
        'onTube ${(quiet.onTubeFrac * 100).toStringAsFixed(1)}%');
    debugPrint('FLAT (x1.00) ${flat.secPerIntrusion.toStringAsFixed(1)}s/int  '
        'onTube ${(flat.onTubeFrac * 100).toStringAsFixed(1)}%');
    debugPrint('BUSY (x0.70) ${busy.secPerIntrusion.toStringAsFixed(1)}s/int  '
        'onTube ${(busy.onTubeFrac * 100).toStringAsFixed(1)}%');

    expect(cardForNight(3).gap, greaterThan(cardForNight(6).gap));
    expect(cardForNight(4).gap, lessThan(cardForNight(6).gap));
    // the dials have to be VISIBLE, not within measurement noise
    expect(busy.secPerIntrusion, lessThan(quiet.secPerIntrusion * 0.85),
        reason: 'OPEN LINE is not measurably busier than A QUIET NIGHT');
  });

  test('the tube is not empty for the whole night', () {
    // measured at 2.3-4.1% before the calm cap
    for (final night in <int>[1, 4, 6]) {
      final r = _tempo(night);
      expect(r.onTubeFrac, greaterThan(0.06),
          reason: 'night $night had something on the tube for only '
              '${(r.onTubeFrac * 100).toStringAsFixed(1)}% of the shift');
    }
  });
}
