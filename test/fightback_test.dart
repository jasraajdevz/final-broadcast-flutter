// YOU CAN FIGHT BACK.
//
// Striking the tube used to pay identically whether the screen was empty or
// something was standing on it, so the instant a thing arrived the player's
// only available action was pressing the correct one of eight keys. Not
// knowing which meant watching it happen with nothing to do — a quiz, not an
// encounter, and the specific thing the player called "you can't fight back".
//
// These guard the two halves: that hitting it does something, and that it can
// never do enough to make knowing the counter optional.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _station() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

({GameState s, AnomalyRuntime r}) _withThingOnTube(int seed) {
  seedRandom(seed);
  final s = _station();
  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();
  var t = 0.0;
  while (t < 21 * 60 && (r.active == null || r.active!.stage < 1) && !r.lost) {
    mindTheDesk(r);
    r.tick(1 / 60.0);
    t += 1 / 60.0;
  }
  return (s: s, r: r);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('hitting the glass buys time off the window', () {
    final v = _withThingOnTube(4242);
    final a = v.r.active!;
    // let the window run a while so there is something to push back
    for (var i = 0; i < 120; i++) {
      mindTheDesk(v.r);
      v.r.tick(1 / 60.0);
    }
    final before = a.t;
    v.r.tuneStrike(kScr.center.dx, kScr.center.dy);
    expect(a.t, lessThan(before), reason: 'the blow did nothing to the window');
    expect(a.blows, 1);
    expect(a.bought, greaterThan(0));
  });

  test('it flinches, so the blow is something you DID', () {
    final v = _withThingOnTube(77);
    for (var i = 0; i < 60; i++) {
      mindTheDesk(v.r);
      v.r.tick(1 / 60.0);
    }
    v.r.shake = 0;
    for (var i = 0; i < AnomalyRuntime.kBlowsPerStagger; i++) {
      v.r.tuneStrike(kScr.center.dx, kScr.center.dy);
    }
    expect(v.r.shake, greaterThan(10),
        reason: 'four blows landed and nothing recoiled');
    expect(v.r.hitstop, greaterThan(0));
  });

  test('but it can NEVER replace knowing the counter', () {
    // The ceiling is the whole safety property. Mash it forever; the window
    // must still run out.
    final v = _withThingOnTube(31337);
    final a = v.r.active!;
    for (var i = 0; i < 400; i++) {
      v.r.tuneStrike(kScr.center.dx, kScr.center.dy);
    }
    expect(a.bought, lessThanOrEqualTo(AnomalyRuntime.kMaxBought + 0.001),
        reason: 'a player could stall an encounter indefinitely by mashing');

    // and with nothing but strikes, it still gets you
    var t = 0.0;
    while (t < 60 && v.r.active != null && !v.r.lost) {
      mindTheDesk(v.r);
      v.r.tick(1 / 60.0);
      v.r.tuneStrike(kScr.center.dx, kScr.center.dy);
      t += 1 / 60.0;
    }
    expect(v.s.stats.scared, greaterThan(0),
        reason: 'mashing the glass survived the encounter on its own');
  });

  test('fighting costs you — it is panic, not work', () {
    final v = _withThingOnTube(999);
    final beforeSig = v.s.sig;
    final beforeDread = v.s.dread;
    for (var i = 0; i < 5; i++) {
      v.r.tuneStrike(kScr.center.dx, kScr.center.dy);
    }
    expect(v.s.sig, beforeSig,
        reason: 'hitting it paid SIGNAL — you are fighting, not broadcasting');
    expect(v.s.dread, greaterThan(beforeDread));
  });

  test('with the tube clear, striking still pays as it always did', () {
    seedRandom(5);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    expect(r.active, isNull);
    final before = s.sig;
    r.tuneStrike(kScr.center.dx, kScr.center.dy);
    expect(s.sig, greaterThan(before),
        reason: 'the bootstrap action must be untouched when nothing is up');
  });
}
