// THE RECORD.
//
// Everything in this game used to have consequences that lasted exactly one
// night. Take the carrier down and dread spikes; the night ends; forgotten.
// That is the difference between a scary game and a psychological one — a
// scary game frightens you in the moment, a psychological one makes you
// responsible for something and then remembers it.
//
// Two properties matter more than anything else here, and both are guarded:
// the record is built ONLY from things the player chose, and no combination of
// marks can ever compound into an unwinnable game.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/economy.dart';
import 'package:final_broadcast/src/record.dart';
import 'package:final_broadcast/src/state.dart';

import 'operator.dart';

GameState _s() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an incident is never judged — only a pattern is', () {
    // Being judged for one bad night is unfair. Being judged for a habit is
    // the point. Every mark has to survive well past a single use.
    final s = _s();
    for (final m in Mark.values) {
      addMark(s, m);
      expect(noticed(s, m), isFalse,
          reason: '${m.key} judged on the first occurrence');
    }
    expect(dominant(s), isNull);
    expect(recordLine(s), isNull);
    expect(verdictLine(s), isNull);
  });

  test('a habit is', () {
    final s = _s();
    addMark(s, Mark.hand, kMarkNotices[Mark.hand]!);
    expect(noticed(s, Mark.hand), isTrue);
    expect(dominant(s), Mark.hand);
    expect(recordLine(s), contains('carrier down'));
    expect(verdictLine(s), 'THE ONE WHO TURNS IT OFF');
  });

  test('the station names the thing you do MOST', () {
    final s = _s();
    addMark(s, Mark.hand, kMarkNotices[Mark.hand]!);
    addMark(s, Mark.debt, kMarkNotices[Mark.debt]! * 3);
    expect(dominant(s), Mark.debt);
    expect(verdictLine(s), 'THE ONE WHO TAKES THE MONEY');
  });

  test('every mark bends the game, not just the prose', () {
    final clean = _s();
    final marked = _s();
    for (final m in Mark.values) {
      addMark(marked, m, kMarkNotices[m]! * 5);
    }
    expect(recordGapMul(marked), lessThan(recordGapMul(clean)));
    expect(recordWindowMul(marked), lessThan(recordWindowMul(clean)));
    expect(recordRpMul(marked), lessThan(recordRpMul(clean)));
    expect(recordDecayMul(marked), lessThan(recordDecayMul(clean)));
    // and they reach the real dials
    expect(banishWindow(marked), lessThan(banishWindow(clean)));
    marked.lifetimeSig = 4e6;
    clean.lifetimeSig = 4e6;
    expect(rpGain(marked), lessThan(rpGain(clean)));
  });

  test('but the WORST possible record is still survivable', () {
    // The safety property. Four penalties compounding could trivially make a
    // career unplayable, which would punish a player for having played.
    expect(worstCase(), greaterThan(0.6),
        reason: 'a maxed record crosses into unwinnable');
    for (final f in <double Function(double)>[
      recordGapMulAt,
      recordWindowMulAt,
      recordRpMulAt,
      recordDecayMulAt,
    ]) {
      expect(f(1.0), greaterThan(0.6));
      expect(f(0.0), 1.0, reason: 'a clean operator must be untouched');
    }
    // and the window can never be driven under its own floor
    final worst = _s();
    for (final m in Mark.values) {
      addMark(worst, m, 10000);
    }
    expect(banishWindow(worst), greaterThanOrEqualTo(kWindowFloor));
  });

  test('it is only ever built from CHOICES', () {
    // Nothing the game does TO the player may mark them. Getting jumpscared,
    // losing a streak, a bad night card — none of these are decisions.
    seedRandom(4242);
    final s = _s();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    var t = 0.0;
    // never touch a key, never fight, never sign, never take money: just be
    // beaten up by the game for a whole night
    while (t < 21 * 60 && !r.lost) {
      mindTheDesk(r);
      r.tick(1 / 60.0);
      t += 1 / 60.0;
    }
    expect(s.stats.scared, greaterThan(0), reason: 'nothing happened to us');
    expect(markOf(s, Mark.hand), 0);
    expect(markOf(s, Mark.panic), 0);
    expect(markOf(s, Mark.debt), 0);
  });

  test('and it survives a save', () {
    final s = _s();
    addMark(s, Mark.panic, 44);
    addMark(s, Mark.hand, 3);
    final back = GameState()..readJson(s.toJson());
    expect(markOf(back, Mark.panic), 44);
    expect(markOf(back, Mark.hand), 3);
    expect(verdictLine(back), isNotNull);
  });

  test('the near miss keeps its margin, not just a count', () {
    final s = _s();
    expect(s.bestClutchMs, 0);
    s.bestClutchMs = 180;
    final back = GameState()..readJson(s.toJson());
    expect(back.bestClutchMs, 180,
        reason: 'the number a player retells has to survive the session');
  });
}
