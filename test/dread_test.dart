// DREAD IS THE GAME. It has to move.
//
// Measured on the build before this: over a competently played night, DREAD
// sat under 1.0/100 for 96.4% of frames on night 1 and 99.6% on night 6, while
// the anomaly was on the tube for 2.3-4.1% of the night. The horror meter, the
// canteen, the red room wash, the lights going out and the bot failure rate
// all hang off that number, so all of them were unreachable — the player was
// shown the furniture of a horror game running a flat idle clicker underneath.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _station(int night) {
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
  return s;
}

/// A competently played night: answer every anomaly correctly, promptly.
({double peak, double flatFrac, double belowFloorFrac, int banished, bool lost})
    _competentNight(int night) {
  seedRandom(night * 104729 + 7);
  final s = _station(night);
  final r = AnomalyRuntime(s);
  r.startBroadcast();

  var t = 0.0, peak = 0.0;
  var frames = 0, flat = 0, belowFloor = 0;
  const dt = 1 / 60.0;
  while (t < 21 * 60 && !r.lost) {
    // the window is part of the sim now: stand in for the painter that
    // normally writes lurkPressure each frame
    r.lurkPressure = 0.35;
    mindTheDesk(r);
        r.tick(dt);
    t += dt;
    frames++;
    if (s.dread > peak) peak = s.dread;
    if (s.dread < 1.0) flat++;
    if (s.dread < dreadFloor(s) - 0.5) belowFloor++;
    final a = r.active;
    if (a != null && a.stage == 1 && a.p > 0.3) r.pressCounter(a.def.counter);
  }
  return (
    peak: peak,
    flatFrac: flat / frames,
    belowFloorFrac: belowFloor / frames,
    banished: s.stats.banished,
    lost: r.lost,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the floor is a real function with real values', () {
    final s = _station(5);
    s.shiftMin = 6 * 60; // 05:00
    expect(dreadFloor(s), greaterThan(15),
        reason: 'late on night 5 the room must already be warm');
    expect(dreadFloor(s), lessThanOrEqualTo(kDreadFloorCap));
  });

  test('atmosphere alone can never reach SIGNAL LOST', () {
    // The floor exists so the anomaly inflow lands on a warm bar, NOT so the
    // room can kill you. Every value it can take must stay well under 100.
    for (final night in <int>[1, 5, 20, 60]) {
      final s = _station(night);
      for (var seg = 0; seg < kRundown.length; seg++) {
        s.shiftMin = seg * 60.0;
        expect(dreadFloor(s), lessThanOrEqualTo(kDreadFloorCap),
            reason: 'night $night segment $seg breaks the cap');
      }
    }
  });

  group('a played night keeps the meter alive', () {
    for (final night in <int>[1, 3, 6]) {
      test('night $night', () {
        final r = _competentNight(night);
        expect(r.banished, greaterThan(6), reason: 'the night must be played');
        // was 96.4% / 91.9% / 99.6% before the floor was wired
        expect(r.flatFrac, lessThan(0.40),
            reason: 'night $night sat at empty for '
                '${(r.flatFrac * 100).toStringAsFixed(1)}% of frames');
        expect(r.peak, greaterThan(18),
            reason: 'night $night peaked at only ${r.peak.toStringAsFixed(1)}');
      });
    }
  });

  test('dread does not sit below its own floor', () {
    final r = _competentNight(4);
    expect(r.belowFloorFrac, lessThan(0.25),
        reason: 'decay is still clamping past the floor');
  });

  test('a deep career does not slam 0 to 100 in one encounter', () {
    // The encounter inflow was the only depth() consumer without a ceiling.
    // With the floor live, an unsaturated one would end every deep night on
    // the first anomaly.
    seedRandom(4242);
    final s = _station(30);
    for (final p in kProducers) {
      s.prod[p.id] = 600;
    }
    final r = AnomalyRuntime(s);
    r.startBroadcast();
    var t = 0.0;
    const dt = 1 / 60.0;
    var firstResolved = false;
    while (t < 300 && !firstResolved && !r.lost) {
      mindTheDesk(r);
            r.tick(dt);
      t += dt;
      final a = r.active;
      if (a != null && a.stage == 1 && a.p > 0.5) {
        r.pressCounter(a.def.counter);
        firstResolved = true;
      }
    }
    expect(r.lost, isFalse,
        reason: 'a deep night died before its first answered anomaly');
    expect(s.dread, lessThan(95));
  });
}
