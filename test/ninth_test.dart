// THE NINTH KEY.
//
// A. VOSS's roster entry has promised this since the ladder was written — "a
// ninth key, it is not on the deck yet" — and H. VANCE's records what it is
// for: "the only one who ever turned the carrier down. For nine seconds."
//
// The premise of the whole game is that the carrier is a lid. This is the
// handle on the lid. It has no label, no manual page, and nothing ever
// explains it.
//
// These guard the shape that keeps it from being either a trap or a rotation:
// it must WORK, it must be held rather than pressed, letting go must be safe,
// and every use must cost more than the last.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/career.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

({GameState s, AnomalyRuntime r}) _boot({int survived = 20, int seed = 11}) {
  seedRandom(seed);
  final s = GameState()..survived = survived;
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();
  return (s: s, r: r);
}

void _hold(AnomalyRuntime r, double seconds) {
  var t = 0.0;
  while (t < seconds) {
    mindTheDesk(r);
    r.tick(1 / 60.0);
    t += 1 / 60.0;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('it is not on the deck until A. VOSS', () {
    expect(unlocked(GameState()..survived = 15, 'ninth'), isFalse);
    expect(unlocked(GameState()..survived = 16, 'ninth'), isTrue);
    expect(gatekeeperOf('ninth')!.name, 'A. VOSS');
  });

  test('a new operator cannot touch it at all', () {
    final v = _boot(survived: 0);
    v.r.beginCarrier();
    _hold(v.r, 4);
    expect(v.r.carrierHold, 0);
    expect(v.r.carrierDrops, 0);
  });

  test('it is HELD, not pressed — a tap does nothing', () {
    final v = _boot();
    v.r.beginCarrier();
    _hold(v.r, 0.3);
    v.r.endCarrier();
    expect(v.r.carrierDrops, 0, reason: 'a tap took the station off air');
    _hold(v.r, 3);
    expect(v.r.carrierHold, 0, reason: 'the needle never came back up');
  });

  test('letting go in time is survivable, and it knows you nearly did it', () {
    final v = _boot();
    final before = v.s.dread;
    v.r.beginCarrier();
    _hold(v.r, AnomalyRuntime.kCarrierHoldSeconds * 0.7);
    v.r.endCarrier();
    expect(v.r.carrierDrops, 0);
    expect(v.s.dread, greaterThan(before),
        reason: 'nearly doing it should cost something');
    expect(v.s.dread - before, lessThan(15),
        reason: 'but not as much as doing it');
  });

  test('held long enough, the lid comes off', () {
    final v = _boot();
    v.r.beginCarrier();
    _hold(v.r, AnomalyRuntime.kCarrierHoldSeconds + 0.3);
    expect(v.r.carrierDrops, 1);
    expect(v.r.carrierHolding, isFalse);
    // and it lets something into the room
    expect(v.r.presence, greaterThan(0));
    expect(v.r.blood.splats, isNotEmpty);
  });

  test('it WORKS — whatever is on the tube leaves', () {
    // This is the half that stops it being a pure trap. It has to actually do
    // the thing, or nobody would ever use it twice.
    final v = _boot(seed: 4242);
    var t = 0.0;
    while (t < 21 * 60 && (v.r.active == null || v.r.active!.stage < 1)) {
      mindTheDesk(v.r);
      v.r.tick(1 / 60.0);
      t += 1 / 60.0;
    }
    expect(v.r.active, isNotNull, reason: 'nothing ever manifested');
    v.r.beginCarrier();
    _hold(v.r, AnomalyRuntime.kCarrierHoldSeconds + 0.3);
    expect(v.r.active, isNull, reason: 'it was still on the tube');
    expect(v.s.stats.scared, 0, reason: 'this must not count as being caught');
  });

  test('and every use costs more than the last, so it never becomes a rotation',
      () {
    final v = _boot();
    final costs = <double>[];
    for (var i = 0; i < 3; i++) {
      v.s.dread = 0;
      v.r.beginCarrier();
      _hold(v.r, AnomalyRuntime.kCarrierHoldSeconds + 0.2);
      costs.add(v.s.dread);
      // let the room clear
      v.r.presence = 0;
    }
    expect(v.r.carrierDrops, 3);
    expect(costs[1], greaterThan(costs[0]));
    expect(costs[2], greaterThan(costs[1]),
        reason: 'a flat price would make this a cooldown, not a decision');
  });

  test('it is never explained', () {
    // No counter carries it, so it can never appear in the manual or on a
    // bezel — the player finds out what it does by doing it.
    expect(kCounters.any((c) => c.key == '9'), isFalse);
    expect(kCounters.length, 8);
  });
}
