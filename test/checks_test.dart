// THE QUIET HAD NOTHING IN IT.
//
// Measured: the tube has something on it for 6.5-11.8% of a night. Nine
// tenths of a shift was watching a number rise and clicking a screen — and an
// empty quiet reads as boredom no matter how good the loud part is.
//
// The station checks are a job you do in that gap. One key, always the same,
// because it is an ATTENTION test and not a memory test: it competes with the
// eight banish keys for the only resource the player has.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/checks.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

GameState _station() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  s.prod['dipole'] = 45;
  s.prod['vhf'] = 30;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

/// A night. [sign] false means the operator never touches the book.
({GameState s, AnomalyRuntime r, int busyFrames, int frames}) _night({
  required bool sign,
  int seed = 4242,
}) {
  seedRandom(seed);
  final s = _station();
  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();
  var t = 0.0;
  var frames = 0, busy = 0;
  var react = 0.0;
  const dt = 1 / 60.0;
  while (t < 21 * 60 && !r.lost) {
    r.tick(dt);
    t += dt;
    frames++;
    // "busy" = the player has something they must act on THIS frame.
    //
    // The player must NOT be modelled as answering in the same frame the
    // station asks: that made every check pending for exactly one frame and
    // the metric measured the harness rather than the game. 0.7s is a fair
    // human notice-and-reach.
    if (r.active != null || r.warn > 0 || r.checks.pending) busy++;
    final a = r.active;
    if (a != null && a.stage == 1 && a.p > 0.3) r.pressCounter(a.def.counter);
    // notice it, put a hand on the book, and hold it there
    if (r.checks.pending) {
      react += dt;
      if (sign && react >= 0.7 && !r.checks.signing) r.pressCheck();
    } else {
      react = 0;
    }
  }
  return (s: s, r: r, busyFrames: busy, frames: frames);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the quiet now has a job in it', () {
    final n = _night(sign: true);
    expect(n.r.checks.signed, greaterThan(12),
        reason: 'the station barely asked for anything');
    final busy = n.busyFrames / n.frames;
    // the tube alone was 6.5-11.8%
    expect(busy, greaterThan(0.20),
        reason: 'only ${(busy * 100).toStringAsFixed(1)}% of the night asked '
            'anything of the player');
  });

  test('the book and the tube collide, because that is the point', () {
    seedRandom(99);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    var t = 0.0, collisions = 0;
    const dt = 1 / 60.0;
    var wasBoth = false;
    while (t < 21 * 60 && !r.lost) {
      r.tick(dt);
      t += dt;
      final both = r.active != null && r.checks.pending;
      if (both && !wasBoth) collisions++;
      wasBoth = both;
      final a = r.active;
      if (a != null && a.stage == 1 && a.p > 0.55) r.pressCounter(a.def.counter);
      if (r.checks.pending && r.active == null) r.pressCheck();
    }
    expect(collisions, greaterThan(0),
        reason: 'the two loops never once overlapped — no attention conflict');
  });

  test('neglecting the book costs output and dread', () {
    final kept = _night(sign: true, seed: 7);
    final left = _night(sign: false, seed: 7);
    expect(left.r.checks.missed, greaterThan(8));
    expect(left.r.checks.drift, greaterThan(kept.r.checks.drift + 0.3),
        reason: 'ignoring every check did not drift the station');
    expect(driftPenalty(left.r.checks), lessThan(0.85),
        reason: 'drift costs no output, so neglect is free');
  });

  test('the book cannot be mashed', () {
    seedRandom(5);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    final before = s.dread;
    for (var i = 0; i < 6; i++) {
      r.pressCheck(); // nothing has been asked for
    }
    expect(r.checks.falseEntries, 6);
    expect(s.dread, greaterThan(before),
        reason: 'signing a book nobody opened has to cost something');
  });

  test('a signed check is worth signing', () {
    seedRandom(11);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    r.checks.drift = 0.5;
    var t = 0.0;
    while (t < 120 && !r.checks.pending) {
      r.tick(1 / 60.0);
      t += 1 / 60.0;
    }
    expect(r.checks.pending, isTrue, reason: 'nothing was ever asked');
    final before = r.checks.drift;
    r.pressCheck();
    // a signature takes time to lay down
    expect(r.checks.signed, 0, reason: 'it completed instantly');
    var held = 0.0;
    while (held < kSignSeconds + 0.1) {
      r.tick(1 / 60.0);
      held += 1 / 60.0;
    }
    expect(r.checks.signed, 1);
    expect(r.checks.drift, lessThan(before));
  });

  group('the room does not go back', () {
    test('a scare leaves a mark, and marks accumulate', () {
      seedRandom(303);
      final s = _station();
      final r = AnomalyRuntime(s, audio: const NullAudio());
      r.startBroadcast();
      expect(r.scars, isEmpty);

      var t = 0.0, guard = 0;
      const dt = 1 / 60.0;
      // never answer anything: let it hit us repeatedly
      while (t < 21 * 60 && !r.lost && r.scars.length < 3 && guard < 200000) {
        r.tick(dt);
        t += dt;
        guard++;
      }
      expect(r.scars.length, greaterThanOrEqualTo(2),
          reason: 'the room went back to normal after every scare');
      // each kind lands at most once
      final kinds = r.scars.map((x) => x.kind).toList();
      expect(kinds.toSet().length, kinds.length,
          reason: 'the same scar was applied twice');
    });

    test('a fresh night starts clean', () {
      seedRandom(303);
      final s = _station();
      final r = AnomalyRuntime(s, audio: const NullAudio());
      r.startBroadcast();
      r.scars.add(Scar(ScarKind.camGhost, kAnoms.first));
      r.checks.drift = 0.7;
      r.startBroadcast();
      expect(r.scars, isEmpty);
      expect(r.checks.drift, 0);
    });
  });
}
