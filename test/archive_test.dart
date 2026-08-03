// THE FILE.
//
// "it aint still addictive" — after sign-off there was nothing pulling you
// back. The night card gave tomorrow a NAME, which is a start, but a name is
// not a reason. Nothing in the game was ever unfinished in a way you wanted to
// finish.
//
// One document a night, in a fixed authored order, with the count of what is
// still missing on the front desk. That count IS the hook, so these guard it:
// an archive with a hole in it, or a document nobody can reach, is a broken
// promise rather than a missing page.

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/archive.dart';
import 'package:final_broadcast/src/state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('there is a document waiting on every night, with no gaps', () {
    for (var i = 0; i < archiveTotal; i++) {
      final night = nightForDoc(i);
      final d = docForNight(night);
      expect(d, isNotNull, reason: 'night $night hands over nothing');
      expect(identical(d, kArchive[i]), isTrue,
          reason: 'night $night hands over the wrong page');
    }
  });

  test('night one hands over nothing — the first shift is the game alone', () {
    expect(docForNight(1), isNull);
    expect(docForNight(0), isNull);
  });

  test('the file runs out cleanly rather than crashing', () {
    expect(docForNight(nightForDoc(archiveTotal)), isNull);
    expect(docForNight(9999), isNull);
  });

  test('every document is actually written', () {
    for (var i = 0; i < kArchive.length; i++) {
      final d = kArchive[i];
      expect(d.head.trim(), isNotEmpty, reason: 'doc $i has no dateline');
      expect(d.body.trim().length, greaterThan(60),
          reason: 'doc $i (${d.head}) is a stub');
      expect(d.kindLabel, isNotEmpty);
    }
  });

  test('the archive is a mix of voices, not one man talking', () {
    final kinds = kArchive.map((d) => d.kind).toSet();
    expect(kinds.length, greaterThanOrEqualTo(4),
        reason: 'a single register for the whole file reads as one long note');
    // and the operator log is still the spine
    final logs = kArchive.where((d) => d.kind == DocKind.log).length;
    expect(logs, greaterThanOrEqualTo(5));
  });

  test('no two documents are the same page twice', () {
    final heads = kArchive.map((d) => d.head).toList();
    expect(heads.toSet().length, heads.length, reason: 'a duplicate dateline');
    final bodies = kArchive.map((d) => d.body).toSet();
    expect(bodies.length, kArchive.length, reason: 'a duplicated page');
  });

  test('the count on the front desk tracks what has been recovered', () {
    final s = GameState();
    expect(foundCount(s), 0);
    expect(archiveLine(s), contains('0 OF $archiveTotal'));

    s.log[nightForDoc(0)] = true;
    s.log[nightForDoc(1)] = true;
    expect(foundCount(s), 2);
    expect(found(s).first.head, kArchive[0].head,
        reason: 'the file must read in order, not in the order found');

    for (var i = 0; i < archiveTotal; i++) {
      s.log[nightForDoc(i)] = true;
    }
    expect(foundCount(s), archiveTotal);
    expect(archiveLine(s), contains('COMPLETE'));
  });

  group('the personal file', () {
    GameState _deep() {
      final s = GameState()..survived = 14..revives = 2;
      s.stats
        ..banished = 118
        ..scared = 9
        ..wrong = 23
        ..bestStreak = 17
        ..clutch = 6;
      return s;
    }

    test('is not in the drawer until you are deep enough', () {
      expect(personalFileOpen(GameState()..survived = 11), isFalse);
      expect(personalFileOpen(GameState()..survived = 12), isTrue);
      final shallow = fileRows(GameState()..survived = 3);
      expect(shallow.any((r) => r.isSelf), isFalse);
      expect(shallow.length, archiveTotal);
    });

    test('is filed AMONG the others, not bolted on the end', () {
      final rows = fileRows(_deep());
      final i = rows.indexWhere((r) => r.isSelf);
      expect(i, greaterThan(0));
      expect(i, lessThan(rows.length - 1),
          reason: 'appended at the end it reads as a reward screen');
      expect(rows.length, archiveTotal + 1);
    });

    test('it is about the reader, in their own numbers', () {
      final s = _deep();
      final d = personalFile(s);
      for (final n in <String>['14', '118', '9', '23', '17', '6', '2']) {
        expect(d.body, contains(n), reason: 'missing the number $n');
      }
      expect(d.head, contains('1987'));
      // and it never announces what it is
      expect(d.body.toLowerCase(), isNot(contains('you ')));
    });

    test('and it is written in the PAST', () {
      // The whole effect. Present tense would read as a scoreboard; past tense
      // about things done an hour ago leaves exactly one reading, and the game
      // never states it.
      final d = personalFile(_deep());
      expect(d.body, contains('Held the post'));
      expect(d.sign, contains('BEFORE HE APPLIED'));
    });

    test('it is never "recovered" — it was already there', () {
      final rows = fileRows(_deep());
      final self = rows.firstWhere((r) => r.isSelf);
      expect(self.found, isTrue);
      expect(self.night, -1, reason: 'it must not claim a recovery night');
    });

    test('it is regenerated, so it follows you', () {
      final s = _deep();
      final before = personalFile(s).body;
      s.stats.banished += 40;
      final after = personalFile(s).body;
      expect(after, isNot(before),
          reason: 'a frozen copy would go stale and stop being about you');
    });

    test('splicing it never mislabels the pages after it', () {
      // The failure this refactor exists to prevent: index arithmetic around
      // the spliced row shifting every night label past it by one.
      final rows = fileRows(_deep());
      for (final r in rows.where((x) => !x.isSelf)) {
        final i = kArchive.indexOf(r.doc);
        expect(r.night, nightForDoc(i),
            reason: '\${r.doc.head} is labelled the wrong night');
      }
    });
  });

  test('what you have recovered survives a save round-trip', () {
    final s = GameState();
    s.log[nightForDoc(3)] = true;
    s.log[nightForDoc(7)] = true;
    final restored = GameState()..readJson(s.toJson());
    expect(docFound(restored, nightForDoc(3)), isTrue);
    expect(docFound(restored, nightForDoc(7)), isTrue);
    expect(docFound(restored, nightForDoc(4)), isFalse);
    expect(foundCount(restored), 2);
  });
}

// --- appended: the page about the reader ----------------------------------
