// THE LONG NIGHT.
//
// The last safe harbour in this game was that 06:00 always comes. Everything
// else has been withdrawn — the calm window turns, the presence comes round
// the front, the paperwork is about the player, the clock on the wall is the
// real one — but sunrise had never once failed to arrive, and a player can
// endure any amount of dread while knowing the night is finite.
//
// R. HALLORAN's roster entry has said what this is since the ladder was
// written: "did not sign off on the morning of the 1,115th night."
//
// These guard the two things that keep it a scare rather than a bug: it must
// END, and it must only ever happen once.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

({GameState s, AnomalyRuntime r}) _atDawn({required int survived, int seed = 7}) {
  seedRandom(seed);
  final s = GameState()
    ..survived = survived
    ..started = true;
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 400;
  s.prod['dipole'] = 300;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();
  // park the clock one minute from the end, quota met so it is not held
  s.shiftMin = kShiftMinutes - 1;
  s.segSig = 1e12;
  return (s: s, r: r);
}

void _run(AnomalyRuntime r, double seconds) {
  var t = 0.0;
  while (t < seconds && !r.lost) {
    r.tick(1 / 60.0);
    t += 1 / 60.0;
    final a = r.active;
    if (a != null && a.stage == 1 && a.p > 0.25) r.pressCounter(a.def.counter);
    r.s.segSig = 1e12;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a young operator always gets their sunrise', () {
    final v = _atDawn(survived: 3);
    _run(v.r, 20);
    expect(v.r.longNight, isFalse,
        reason: 'the shift failed to end for someone who has not earned it');
    expect(v.r.lost, isTrue, reason: 'dawn() should have fired');
    expect(v.s.longNightDone, isFalse);
  });

  test('deep enough in, 06:00 comes and the sheet does not', () {
    final v = _atDawn(survived: 14);
    _run(v.r, 20);
    expect(v.r.longNight, isTrue, reason: 'the night ended as normal');
    expect(v.r.lost, isFalse, reason: 'it signed off anyway');
    expect(v.s.longNightDone, isTrue);
    expect(v.r.overNeed, greaterThan(0));
  });

  test('and the clock keeps counting, because 06:01 IS the scare', () {
    final v = _atDawn(survived: 14);
    _run(v.r, 20);
    expect(v.r.longNight, isTrue);
    // NOT asserted to be exactly 06:00 — the 20s of setup above is already
    // ~7 shift-minutes of overtime, so it has legitimately moved on by the
    // time it is first sampled.
    final before = shiftClock(v.s);
    _run(v.r, 200);
    final after = shiftClock(v.s);
    expect(after, isNot(before),
        reason: 'a frozen clock reads as a bug, not as an hour that should '
            'not exist');
    // overtime runs 55-95 minutes, so it does NOT stay inside the 06:xx hour —
    // it walks on into 07:xx, which is worse and is the point.
    final hh = int.parse(after.split(':').first);
    expect(hh, greaterThanOrEqualTo(6), reason: 'got $after');
    expect(hh, lessThan(9), reason: 'got $after');
    // shiftMin is deliberately NOT clamped — on a normal night dawn() fires
    // the moment it reaches kShiftMinutes, so only a long night can ever get
    // past it, and the one clock reads the truth without special-casing.
    expect(v.s.shiftMin, greaterThan(kShiftMinutes));
  });

  test('it ENDS — an unwinnable night is a bug, not a scare', () {
    final v = _atDawn(survived: 14);
    _run(v.r, 20);
    expect(v.r.longNight, isTrue);
    // overNeed is in shift-minutes; kMinReal real seconds per minute
    _run(v.r, v.r.overNeed * kMinReal + 30);
    expect(v.r.longNight, isFalse, reason: 'the shift never ended at all');
    expect(v.r.lost, isTrue, reason: 'it did not sign off');
    expect(v.r.endScreen, EndScreen.dawn);
  });

  test('surviving it is a different morning', () {
    final v = _atDawn(survived: 14);
    _run(v.r, 20);
    _run(v.r, v.r.overNeed * kMinReal + 30);
    final m = v.r.endScreenModel!;
    expect(m.win, isTrue);
    expect(m.title, contains('EVENTUALLY'));
  });

  test('it can only ever happen once in a career', () {
    final v = _atDawn(survived: 14);
    _run(v.r, 20);
    expect(v.s.longNightDone, isTrue);

    // next night, same operator, same depth
    final r2 = AnomalyRuntime(v.s, audio: const NullAudio());
    r2.startBroadcast();
    v.s.shiftMin = kShiftMinutes - 1;
    v.s.segSig = 1e12;
    _run(r2, 20);
    expect(r2.longNight, isFalse,
        reason: 'it happened twice — the weight of it is that it cannot');
    expect(r2.lost, isTrue);
  });

  test('and the fact it happened survives a save', () {
    final s = GameState()..longNightDone = true;
    final back = GameState()..readJson(s.toJson());
    expect(back.longNightDone, isTrue);
  });
}
