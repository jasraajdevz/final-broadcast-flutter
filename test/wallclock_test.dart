// THE STATION KNOWS WHAT TIME IT IS.
//
// Everything else in this game is made up, and a player can be unsettled by
// all of it and still — correctly — feel safe, because none of it has ever
// touched the room they are actually sitting in.
//
// This reads the wall clock, the date, and the gap since the last save. All of
// it is handed over freely by the browser and none of it leaves the machine.
// It is not a mechanic: it costs nothing and rewards nothing. It exists so
// that once, on a specific night, the game says something true.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/archive.dart';
import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/wallclock.dart';

GameState _deep() {
  final s = GameState()..survived = 14..started = true;
  s.stats
    ..banished = 118
    ..scared = 9
    ..wrong = 23
    ..bestStreak = 17;
  return s;
}

void _at(DateTime when) {
  gNow = () => when;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    gNow = DateTime.now;
  });

  test('it notices the small hours, and only the small hours', () {
    for (final h in <int>[0, 2, 3, 4]) {
      _at(DateTime(2026, 8, 3, h, 17));
      gSessionStart = gNow();
      expect(isSmallHours(), isTrue, reason: '${h}h should count');
      expect(wallClockLine(_deep()), contains(realClock()));
    }
    for (final h in <int>[5, 11, 17, 22, 23]) {
      _at(DateTime(2026, 8, 3, h, 17));
      gSessionStart = gNow();
      expect(isSmallHours(), isFalse, reason: '${h}h should not');
    }
  });

  test('the clock it prints is the REAL one', () {
    _at(DateTime(2026, 8, 3, 3, 4));
    expect(realClock(), '03:04');
    _at(DateTime(2026, 8, 3, 23, 59));
    expect(realClock(), '23:59');
  });

  test('it notices how long you have really been sitting there', () {
    // not airtime, not shift minutes — wall time of this sitting
    _at(DateTime(2026, 8, 3, 14, 0));
    gSessionStart = gNow();
    expect(wallClockLine(_deep()), isNull, reason: 'nothing true to say yet');

    _at(DateTime(2026, 8, 3, 15, 10)); // 70 minutes later
    final line = wallClockLine(_deep());
    expect(line, isNotNull);
    // 70 minutes reads as minutes; the hour form starts at 90, which is
    // correct — "1 hour and 10 minutes" is a stranger thing to write than
    // "70 minutes" and the paperwork would write the plainer one.
    expect(line, contains('70 minutes'));
    expect(line, contains('chair was warm'));

    _at(DateTime(2026, 8, 3, 16, 14)); // 2h14 later
    expect(wallClockLine(_deep()), contains('2 hours and 14 minutes'));
  });

  test('and it says at most ONE thing', () {
    // A paragraph of this reads as a gimmick. A single sentence buried in a
    // personnel record reads as an oversight, which is the only way it lands.
    _at(DateTime(2026, 8, 3, 3, 30));
    gSessionStart = DateTime(2026, 8, 3, 1, 0); // also a long session
    final line = wallClockLine(_deep())!;
    expect('\n'.allMatches(line).length, 0);
    expect(line.split('. ').length, lessThanOrEqualTo(3));
  });

  test('it lands inside the closed file, not as a popup', () {
    _at(DateTime(2026, 8, 3, 3, 12));
    gSessionStart = gNow();
    final d = personalFile(_deep());
    expect(d.body, contains('03:12'));
    // still a personnel record, not a jumpscare
    expect(d.head, contains('1987'));
    expect(d.body, contains('Held the post'));
  });

  test('it was on the whole time you were gone', () {
    final s = _deep();
    final now = DateTime(2026, 8, 3, 20, 0);
    _at(now);

    s.lastSave = now.subtract(const Duration(minutes: 20)).millisecondsSinceEpoch;
    expect(returnLine(s), isNull, reason: 'twenty minutes is not being gone');

    s.lastSave = now.subtract(const Duration(days: 4)).millisecondsSinceEpoch;
    final line = returnLine(s)!;
    expect(line, contains('4 DAYS'));
    expect(line, contains('IT WAS ON THE WHOLE TIME'));
    // and it never welcomes you back
    expect(line.toLowerCase(), isNot(contains('welcome')));
  });

  test('a first-time operator is never told any of this', () {
    final fresh = GameState(); // started == false
    _at(DateTime(2026, 8, 3, 3, 0));
    expect(returnLine(fresh), isNull);
  });

  test('durations are written the way the paperwork writes them', () {
    expect(plainDuration(40), '40 seconds');
    expect(plainDuration(20 * 60), '20 minutes');
    expect(plainDuration(2 * 3600), '2 hours');
    expect(plainDuration(2 * 3600 + 14 * 60), '2 hours and 14 minutes');
    expect(plainDuration(4 * 24 * 3600), '4 days');
  });
}
