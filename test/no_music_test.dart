// NOTHING IN THIS GAME MAY BE MUSIC.
//
// The player heard "a chain of ASMR sound" while clicking, and they were
// describing something real: tune() — the single most-repeated action in the
// game, several hundred times a night — played a triangle wave at pitches
// drawn from 440, 494, 554, 659, 740, 831, 988, 1109. A pentatonic scale,
// stepping UP as the carrier lock tightened. It was an instrument, and it was
// rewarding the player with an ascending arpeggio in a horror game.
//
// It was not alone. The lock promotion played G-C-E, milestones played major
// triads with octave doubling, sunrise played C-E-G ascending, and a purchase
// played two squares a fifth apart. A whole family of arcade reward jingles.
//
// This guards the class of bug rather than the instances: the source is
// scanned for consonant intervals and named scale pitches in cue code, because
// the next pleasant sound will be added by someone who has never read this
// comment.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Equal-tempered pitches for A440 across the audible cue range. A cue built
/// on these is, by construction, playing notes.
const List<int> kScalePitches = <int>[
  262, 277, 294, 311, 330, 349, 370, 392, 415, 440, 466, 494,
  523, 554, 587, 622, 659, 698, 740, 784, 831, 880, 932, 988,
  1046, 1109, 1174, 1244, 1318, 1396, 1480, 1568, 1760, 1976,
];

/// MR. SLEEPWELL's music box is deliberately a lullaby — a children's TV
/// presenter singing you to sleep is diegetic horror, not a reward. It is the
/// only sanctioned melody in the build.
const List<int> kSanctioned = <int>[880, 784, 659, 587];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no cue is built out of scale pitches', () {
    final files = <String>[
      'lib/src/ui/audio_web.dart',
      'lib/src/anomalies.dart',
    ];
    final offenders = <String>[];

    for (final path in files) {
      final lines = File(path).readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // comments explain the history on purpose
        final trimmed = line.trimLeft();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (!RegExp(r'\b(env|boxNote|frequency)\b').hasMatch(line)) continue;

        for (final p in kScalePitches) {
          if (kSanctioned.contains(p) && path.endsWith('anomalies.dart')) {
            continue; // the music box
          }
          if (RegExp('\\b$p\\b').hasMatch(line)) {
            offenders.add('$path:${i + 1}  $p  ${line.trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'these cues are playing notes:\n${offenders.join("\n")}');
  });

  test('the strike is never the same twice', () {
    // A run of identical strikes is a rhythm and a rhythm is music. The impact
    // and the flyback are both randomised per hit, so consecutive blows can
    // never form an interval.
    final src = File('lib/src/ui/audio_web.dart').readAsStringSync();
    final tune = src.substring(src.indexOf('void tune(double p)'));
    final body = tune.substring(0, tune.indexOf('\n  }'));
    expect(body, contains('rand()'),
        reason: 'the strike is deterministic — repeated hits will form a '
            'melody the way the old pentatonic ladder did');
    expect(body, isNot(contains('_tuneRungs')),
        reason: 'the scale ladder is back');
  });

  test('the click is a contact, not a tone', () {
    // click() fires on every key press, every rack row and every panel button.
    // It was env('square', 900, ..., 420) — a pitched blip sweeping down — so
    // touching anything repeatedly produced a chain of clean descending tones.
    // With the strike fixed this was the loudest remaining pleasant thing.
    final src = File('lib/src/ui/audio_web.dart').readAsStringSync();
    final i = src.indexOf('void click()');
    final body = src.substring(i, src.indexOf('\n  }', i));
    expect(body, isNot(contains("env('square'")),
        reason: 'the click is a pitched blip again');
    expect(body, contains('rand()'),
        reason: 'every key press is identical — a chain of them is a rhythm');
  });

  test('the room bed is inharmonic and never repeats', () {
    // The bed is what the player is inside all night, so what it does when
    // nothing is happening IS the baseline mood. It was three resonant modes
    // near F#3/C#4/A4 breathing on a clean 18-second sine: near-harmonic,
    // high-Q and perfectly periodic, which is a meditation track.
    final src = File('lib/src/ui/audio_web.dart').readAsStringSync();
    final i = src.indexOf('const modes = <List<double>>[');
    final block = src.substring(i, src.indexOf('];', i));
    final freqs = RegExp(r'<double>\[([0-9.]+),')
        .allMatches(block)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(freqs.length, 3);

    // no two modes may sit near a simple ratio (an octave, fifth or fourth),
    // because that is what makes a drone read as a chord
    for (var a = 0; a < freqs.length; a++) {
      for (var b = a + 1; b < freqs.length; b++) {
        final r = freqs[b] / freqs[a];
        for (final simple in <double>[1.5, 2.0, 1.3333, 1.25, 3.0]) {
          expect((r - simple).abs(), greaterThan(0.06),
              reason: 'modes ${freqs[a]} and ${freqs[b]} form a $simple '
                  'ratio — the room is humming a chord');
        }
      }
    }
  });

  test('the pentatonic ladder is gone entirely', () {
    final src = File('lib/src/ui/audio_web.dart').readAsStringSync();
    expect(src, isNot(contains('_tuneRungs =')));
  });
}
