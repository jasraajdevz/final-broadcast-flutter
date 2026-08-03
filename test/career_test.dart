// THE PROGRESSION SPINE.
//
// The game had currencies — SIGNAL, RATINGS POINTS, night cards, 28 documents
// — and no spine: nothing you could look at and read "this is what I am
// working toward and this is how close I am". Currencies are not a progression
// loop.
//
// The roster is that spine: 22 named operators, outlasted one at a time. These
// guard the two things that make it work — that the early rungs land fast
// enough to teach the shape of the climb, and that every rung pays something.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/archive.dart';
import 'package:final_broadcast/src/career.dart';
import 'package:final_broadcast/src/state.dart';

GameState _at(int survived) => GameState()..survived = survived;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the roster only ever climbs, and every entry is written', () {
    var last = 0;
    final names = <String>{};
    for (final o in kRoster) {
      expect(o.nights, greaterThan(last), reason: '${o.name} is out of order');
      last = o.nights;
      expect(names.add(o.name), isTrue, reason: '${o.name} is on it twice');
      expect(o.rank.trim(), isNotEmpty);
      expect(o.fate.trim().length, greaterThan(25),
          reason: '${o.name} has no fate written');
    }
    expect(kRoster.length, 22, reason: 'the payroll memo says 22 names');
  });

  test('the first rungs land fast enough to teach the shape of the climb', () {
    // Research on incremental pacing is consistent: if the first rungs are far
    // apart the player never learns there IS a ladder. Four inside ten nights.
    final early = kRoster.where((o) => o.nights <= 10).length;
    expect(early, greaterThanOrEqualTo(4),
        reason: 'only $early rungs inside the first ten nights');
    expect(kRoster.first.nights, 1,
        reason: 'the very first shift must pay a rung');
  });

  test('and then they stretch, so the climb has a shape', () {
    final firstGap = kRoster[1].nights - kRoster[0].nights;
    final lateGap = kRoster[19].nights - kRoster[18].nights;
    expect(lateGap, greaterThan(firstGap * 20),
        reason: 'the ladder is linear — it has no late game');
  });

  test('rank, standing and progress agree with each other', () {
    expect(rankOf(_at(0)), 'RELIEF OPERATOR');
    expect(passedCount(_at(0)), 0);
    expect(rankOf(_at(1)), kRoster.first.rank);
    expect(passedCount(_at(1)), 1);
    expect(nextOnRoster(_at(1))!.name, kRoster[1].name);
    // the last name on the list
    final done = _at(99999);
    expect(nextOnRoster(done), isNull);
    expect(passedCount(done), kRoster.length);
    expect(standingLine(done), contains('NOBODY LEFT'));
  });

  test('the bar always starts empty and always fills', () {
    // A bar measured from zero sits at 94% for six nights and tells the player
    // nothing. It has to measure from the PREVIOUS rung.
    for (var n = 0; n < 60; n++) {
      final p = rosterProgress(_at(n));
      expect(p, inInclusiveRange(0.0, 1.0));
    }
    // immediately after passing someone, the bar is near empty again
    final justPassed = rosterProgress(_at(kRoster[3].nights));
    expect(justPassed, lessThan(0.35),
        reason: 'the bar did not reset after a rung was passed');
  });

  test('there is ALWAYS a next goal — the answer is never "nothing"', () {
    for (final n in <int>[0, 1, 3, 12, 40, 300, 1200]) {
      final s = _at(n);
      final g = nearestGoal(s);
      if (n < 1200) {
        expect(g, isNotNull, reason: 'nothing to work toward at $n nights');
        expect(g!.detail.trim(), isNotEmpty);
        expect(g.progress, inInclusiveRange(0.0, 1.0));
      }
    }
  });

  test('every gated feature is opened by a real name on the roster', () {
    for (final entry in kUnlockAt.entries) {
      final o = gatekeeperOf(entry.key);
      expect(o, isNotNull,
          reason: '${entry.key} is gated at ${entry.value} with nobody there');
      expect(o!.unlock, isNotNull,
          reason: '${o.name} opens ${entry.key} but does not say so');
      // locked before, open after
      expect(unlocked(_at(entry.value - 1), entry.key), isFalse);
      expect(unlocked(_at(entry.value), entry.key), isTrue);
      expect(lockedLine(_at(0), entry.key), contains(o.name));
    }
  });

  test('night one is the tube and the keys, and nothing else', () {
    // Everything at once is the same as nothing.
    final fresh = _at(0);
    expect(unlocked(fresh, 'canteen'), isFalse);
    expect(unlocked(fresh, 'archive'), isFalse);
    expect(unlocked(fresh, 'board'), isFalse);
    expect(unlocked(fresh, 'tools'), isFalse);
    expect(unlocked(fresh, 'bots'), isFalse);
  });

  test('passing a rung is detected exactly once', () {
    expect(passedBetween(0, 1).length, 1);
    expect(passedBetween(1, 1).length, 0);
    expect(passedBetween(0, 4).length, 3, reason: 'nights 1, 2 and 4');
    expect(passedBetween(1113, 1114).single.name, 'R. HALLORAN');
  });

  test('the file keeps giving after the early rungs are gone', () {
    // The roster stretches hard after night 20; the archive has to carry the
    // player through the gaps or the middle game has nothing in it.
    final s = _at(20);
    for (var i = 0; i < 6; i++) {
      s.log[nightForDoc(i)] = true;
    }
    final g = goals(s);
    expect(g.any((x) => x.kind == GoalKind.archive), isTrue);
  });
}
