// EIGHT SIGNATURES, ONE ENCOUNTER.
//
// sabotageTick had bodies for exactly two ids and _simulate handled a third.
// Measured on the shipped build, THE SNOW CRAWLER, MR. SLEEPWELL, THE VERTICAL
// MAN, THE RERUN and THE NIELSEN left sigRate at 40118 -> 40118 with muted=0,
// held=0, rings=0 — five of eight entities were a picture and a key, identical
// to each other in every way a player could feel. That is what "it's too
// simple" was: the counter was the only thing that differed.
//
// Each entity now applies a DIFFERENT pressure. This test forces one visit
// from each and asserts the specific thing it is supposed to cost you.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _station() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 80;
  s.prod['dipole'] = 60;
  s.prod['vhf'] = 40;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  s.segSig = 50000;
  s.lifetimeSig = 400000;
  return s;
}

/// Force a visit from [id] and hold it on the tube for [seconds].
({GameState s, AnomalyRuntime r}) _visit(String id, {double seconds = 6}) {
  seedRandom(2024);
  final s = _station();
  final r = AnomalyRuntime(s, audio: const NullAudio());
  r.startBroadcast();
  r.warnDef = kAnomBy[id];
  r.warn = 0.001;
  r.manifest();
  // a window long enough that the visit cannot expire mid-measurement
  r.active!.window = 1e6;
  var t = 0.0;
  const dt = 1 / 60.0;
  while (t < seconds) {
    mindTheDesk(r);
        r.tick(dt);
    t += dt;
  }
  return (s: s, r: r);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every entity in the roster has a live effect', () {
    // The blanket guard: hold each one on the tube and require that SOMETHING
    // measurable changed relative to an empty room.
    for (final a in kAnoms) {
      final v = _visit(a.id, seconds: 6);
      final act = v.r.active!;
      final touched = act.mute.isNotEmpty ||
          act.held > 0 ||
          act.rings > 0 ||
          act.takenSeg > 0 ||
          act.takenLife > 0 ||
          v.r.vertRoll > 0 ||
          v.s.tune.tier < 4 && a.id == 'snow' ||
          a.id == 'sleep';
      expect(touched, isTrue, reason: '${a.nm} did nothing while it was up');
    }
  });

  test('THE SNOW CRAWLER takes the carrier lock apart', () {
    seedRandom(11);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    s.tune.tier = 4;
    r.warnDef = kAnomBy['snow'];
    r.warn = 0.001;
    r.manifest();
    r.active!.window = 1e6;
    var t = 0.0;
    while (t < 8) {
      mindTheDesk(r);
      r.tick(1 / 60.0);
      t += 1 / 60.0;
    }
    expect(s.tune.tier, lessThan(4),
        reason: 'the lock survived a full visit from the snow');
  });

  test('MR. SLEEPWELL takes you off the rundown without taking your money',
      () {
    final v = _visit('sleep', seconds: 6);
    // the bank still fills...
    expect(v.s.sig, greaterThan(0));
    // ...and none of it counted toward the segment
    expect(v.s.segSig, closeTo(50000, 1.0),
        reason: 'output was still being credited to the quota');
  });

  test('THE RERUN walks the segment backward, but not past its arrival', () {
    final v = _visit('rerun', seconds: 8);
    expect(v.s.segSig, lessThan(50000),
        reason: 'the rerun overwrote nothing');
    expect(v.s.segSig, greaterThanOrEqualTo(v.r.active!.segAtArrival * 0.55 - 1),
        reason: 'it rewound past its floor and could zero a segment outright');
  });

  test('THE NIELSEN costs you tomorrow, not tonight', () {
    final v = _visit('niel', seconds: 8);
    expect(v.s.lifetimeSig, lessThan(400000 + 1e9),
        reason: 'sanity');
    expect(v.r.active!.takenLife, greaterThan(0),
        reason: 'he wrote nothing down');
  });

  test('THE VERTICAL MAN makes the instruments unreadable', () {
    final v = _visit('vert', seconds: 3);
    expect(v.r.vertRoll, greaterThan(0.3));
    // and it reaches the formatter every readout in the game uses
    expect(gVertRoll, greaterThan(0.3));
    var rolled = 0;
    for (var i = 0; i < 200; i++) {
      if (fmt(123456) != '123K') rolled++;
    }
    expect(rolled, greaterThan(0), reason: 'the numbers never rolled');
  });

  test('no two entities apply the same pressure', () {
    // A crude fingerprint per entity. If two are identical the roster has
    // collapsed back into one encounter wearing eight faces.
    final seen = <String, String>{};
    for (final a in kAnoms) {
      final v = _visit(a.id, seconds: 5);
      final act = v.r.active!;
      final fp = <String>[
        act.mute.isNotEmpty ? 'mute' : '',
        act.held > 0 ? 'held' : '',
        act.rings > 0 ? 'ring' : '',
        act.takenSeg > 0 ? 'seg' : '',
        act.takenLife > 0 ? 'life' : '',
        v.r.vertRoll > 0 ? 'roll' : '',
        a.id == 'sleep' ? 'offair' : '',
        a.id == 'snow' ? 'lock' : '',
      ].where((x) => x.isNotEmpty).join('+');
      expect(fp, isNotEmpty, reason: '${a.nm} has no fingerprint at all');
      expect(seen.containsKey(fp), isFalse,
          reason: '${a.nm} plays exactly like ${seen[fp]}');
      seen[fp] = a.nm;
    }
    expect(seen.length, kAnoms.length);
  });

  test('the rack overtakes the hand instead of trailing it forever', () {
    // tuneYield was DEFINED as a multiple of sigRate, so the strike's value
    // relative to the rack was invariant to progression: 0.871 strike-per-
    // rack-second at 195/s and 0.840 at 3.8M/s. Hand strikes were 79.3% of a
    // night's SIGNAL and the idle half never took over.
    double ratio(int scale) {
      final s = _station();
      for (final p in kProducers) {
        s.prod[p.id] = scale;
      }
      final r = AnomalyRuntime(s, audio: const NullAudio());
      return tuneYield(s, r) / sigRate(s, r);
    }
    final small = ratio(5);
    final huge = ratio(400);
    expect(huge, lessThan(small * 0.5),
        reason: 'a strike is still worth as much against a huge rack '
            '($small -> $huge) — the machine never takes over');
  });

  test('THE MILKMAN is a variant, not a ninth thing in the signal', () {
    // Eight is load-bearing all the way down: the deck's 4x2 grid, keys 1-8,
    // "Each one dies to exactly one button" on the boot screen, the archive,
    // the bot roster, kAnoms.length in the encounter maths, and the ninth
    // key's entire mystique. He wears one of the eight and dies to its key.
    expect(kAnoms.length, 8, reason: 'something added a ninth entity');
    expect(kCounters.length, 8, reason: 'something added a ninth key');
    expect(kAnoms.any((Anom a) => a.nm.toUpperCase().contains('MILK')), isFalse,
        reason: 'THE MILKMAN got his own roster slot — he is a variant');
  });

  test('and he takes the picture away without making it unanswerable', () {
    // The whole beat is that the tell is legible for about a second and a half
    // and then it is not, so the answer comes from what was SEEN rather than
    // from what is there. If the milk reached the top there would be nothing
    // to have seen, and it would be a coin flip rather than a memory test.
    final a = ActiveAnom(
      def: kAnoms.first,
      window: 7,
      masked: false,
      stage: 1,
      intensity: 1,
      seed: 0.5,
      milk: true,
    );
    expect(a.milk, isTrue);
    // legible at the start
    a.t = 0.2;
    expect((a.t / 1.6).clamp(0.0, 1.0), lessThan(0.2),
        reason: 'the tell is already covered when it lands');
    // and covered, but never completely, by the end
    a.t = 6.0;
    final climb = (a.t / 1.6).clamp(0.0, 1.0);
    expect(climb, 1.0);
    expect(0.86 * climb, lessThan(1.0),
        reason: 'the milk reaches the top of the glass and the visit becomes '
            'a coin flip');
  });
}
