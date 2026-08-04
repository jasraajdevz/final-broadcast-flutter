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

  test('the pentatonic ladder is gone entirely', () {
    final src = File('lib/src/ui/audio_web.dart').readAsStringSync();
    expect(src, isNot(contains('_tuneRungs =')));
  });
}
