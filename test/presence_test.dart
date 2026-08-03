// SOMETHING IS BEHIND YOU.
//
// Every piece of horror vocabulary this game owned happened on a 422x278
// screen the player is already staring straight at. Nothing had ever happened
// in the ROOM — which, in a fixed first-person shot, is the one place a person
// physically cannot look.
//
// The presence has no counter, takes nothing, cannot be banished, and is named
// by no readout in the game. It arrives, it stands there, it goes. These guard
// that it stays exactly that: unanswerable, and never a punishment.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/state.dart';

class _Rec implements GameAudio {
  final List<double> hearts = <double>[];
  @override
  void setHeart(double bpm, double vol) {
    if (vol > 0.01) hearts.add(bpm);
  }
  @override
  void noSuchMethod(Invocation i) {}
}

({GameState s, AnomalyRuntime r, _Rec a, int visits, double peak}) _night(
    int seed) {
  seedRandom(seed);
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  final a = _Rec();
  final r = AnomalyRuntime(s, audio: a);
  r.startBroadcast();

  var t = 0.0, visits = 0, peak = 0.0;
  var was = false;
  const dt = 1 / 60.0;
  while (t < 21 * 60 && !r.lost) {
    r.tick(dt);
    t += dt;
    final now = r.presence > 0;
    if (now && !was) visits++;
    was = now;
    if (r.presence > peak) peak = r.presence;
    final act = r.active;
    if (act != null && act.stage == 1 && act.p > 0.3) {
      r.pressCounter(act.def.counter);
    }
  }
  return (s: s, r: r, a: a, visits: visits, peak: peak);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('it comes into the room, more than once a night', () {
    final n = _night(2024);
    expect(n.visits, greaterThan(2),
        reason: 'nothing ever came into the room');
    expect(n.peak, greaterThan(0.9));
  });

  test('it never arrives on top of something already on the tube', () {
    // Two threats at once would read as a bug. The room is for the quiet.
    seedRandom(88);
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    var t = 0.0, overlaps = 0;
    var was = false;
    while (t < 21 * 60 && !r.lost) {
      r.tick(1 / 60.0);
      t += 1 / 60.0;
      final now = r.presence > 0;
      if (now && !was && r.active != null) overlaps++;
      was = now;
    }
    expect(overlaps, 0);
  });

  test('it takes NOTHING — it is not a penalty', () {
    // The whole point. A thing you cannot answer must also not punish you, or
    // it is just an unfair mechanic wearing a costume.
    seedRandom(5150);
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    // drive to a visit
    var t = 0.0;
    while (t < 21 * 60 && r.presence <= 0 && !r.lost) {
      r.tick(1 / 60.0);
      t += 1 / 60.0;
    }
    expect(r.presence, greaterThan(0), reason: 'nothing ever arrived');

    final sig = s.sig, dread = s.dread, seg = s.segSig;
    // one frame of it standing there
    r.presence = 1;
    r.tick(1 / 60.0);
    expect(s.sig, greaterThanOrEqualTo(sig), reason: 'it took SIGNAL');
    expect(s.segSig, greaterThanOrEqualTo(seg), reason: 'it took output');
    expect(s.dread - dread, lessThan(0.05),
        reason: 'it charged dread — that makes it a penalty, not a presence');
  });

  test('your own heartbeat is the only tell', () {
    final n = _night(31337);
    expect(n.a.hearts, isNotEmpty);
    final fast = n.a.hearts.where((b) => b > 90).length;
    expect(fast, greaterThan(0),
        reason: 'the heart never came up — there is no tell at all');
  });

  test('it is merciful first, and only then is it not', () {
    // A presence that is GUARANTEED harmless is frightening for about three
    // nights and is weather after that. The odds of it turning climb with how
    // many times it has already let you go — but never on the first two, so
    // the player is allowed to learn it is safe before that is taken away.
    seedRandom(4242);
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();

    // force the first two visits and confirm neither can turn
    for (var v = 0; v < 2; v++) {
      r.presenceIn = 0;
      var t = 0.0;
      while (t < 5 && r.presence <= 0) {
        r.tick(1 / 60.0);
        t += 1 / 60.0;
      }
      expect(r.presenceTurning, isFalse,
          reason: 'visit ${v + 1} could turn — too early to break the promise');
      var u = 0.0;
      while (u < 30 && r.presence > 0) {
        r.tick(1 / 60.0);
        u += 1 / 60.0;
      }
    }
    expect(r.presenceVisits, 2);
  });

  test('a scare can come from the room, with no anomaly behind it', () {
    // jumpscare() operates on `active` and returns immediately without one, so
    // until now literally nothing could frighten the player except a missed
    // anomaly. This one has no window, no counter and nothing to press.
    seedRandom(31);
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    for (final a in kAnoms) {
      s.seen[a.id] = true;
    }
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    expect(r.active, isNull);
    final dread = s.dread;

    r.jumpscareFromRoom();
    expect(r.scare, greaterThan(0), reason: 'nothing happened');
    expect(r.scareDef, isNotNull);
    expect(s.dread, greaterThan(dread));
    // it did not rob you — it just came round
    expect(s.stats.streak, 0);
  });

  test('the booth turns up on a camera, in the quiet only', () {
    seedRandom(909);
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    var t = 0.0, sightings = 0, whileBusy = 0;
    var was = false;
    while (t < 21 * 60 && !r.lost) {
      r.tick(1 / 60.0);
      t += 1 / 60.0;
      final now = r.mirrorCam >= 0;
      if (now && !was) {
        sightings++;
        if (r.active != null || r.presence > 0) whileBusy++;
      }
      was = now;
      final a = r.active;
      if (a != null && a.stage == 1 && a.p > 0.3) r.pressCounter(a.def.counter);
    }
    expect(sightings, greaterThan(1), reason: 'the booth never appeared');
    expect(whileBusy, 0,
        reason: 'it needs the quiet — nobody notices a monitor mid-encounter');
    expect(r.mirrorTurn, lessThanOrEqualTo(0.85),
        reason: 'it must never finish turning round');
  });

  test('and it always leaves', () {
    // NOT "presence is 0 when the night ends" — a night can end mid-visit and
    // that is fine. The invariant is that a visit TERMINATES: it can never get
    // stuck standing there for the rest of the shift.
    seedRandom(777);
    final s = GameState();
    for (final p in kProducers) {
      s.prod[p.id] = 0;
    }
    s.prod['rabbit'] = 60;
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();

    var t = 0.0;
    while (t < 21 * 60 && r.presence <= 0 && !r.lost) {
      r.tick(1 / 60.0);
      t += 1 / 60.0;
    }
    expect(r.presence, greaterThan(0), reason: 'nothing ever arrived');

    // the longest a visit may last is 20s; give it 30 and it must be gone
    var u = 0.0;
    while (u < 30 && r.presence > 0) {
      r.tick(1 / 60.0);
      u += 1 / 60.0;
    }
    expect(r.presence, 0, reason: 'it never left — a visit can get stuck on');
    expect(u, lessThan(25));
  });
}
