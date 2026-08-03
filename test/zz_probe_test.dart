import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/bake.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/paint/blood.dart';
import 'package:final_broadcast/src/paint/booth.dart';
import 'package:final_broadcast/src/paint/entities.dart';
import 'package:final_broadcast/src/paint/feed.dart';
import 'package:final_broadcast/src/state.dart';

const dir =
    '/private/tmp/claude-501/-Users-jasdevz-Downloads-kablock-source/7864d927-0fa1-47cd-b4f0-b13f6ae5bb5c/scratchpad';

GameState _st() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  s.prod['dipole'] = 40;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('wash scanline', () async {
    final b = BloodLayer();
    for (final w in <double>[0.005, 0.55]) {
      b.clear();
      b.wash = w;
      final img = bakeImageSync(940, 720, (c) {
        c.drawRect(kRoom, fill(const ui.Color(0xFF808080)));
        drawBlood(c, b, 20.0);
      });
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final px = bd!.buffer.asUint8List();
      final row = <String>[];
      for (var x = 0; x < 940; x += 60) {
        final i = (324 * 940 + x) * 4;
        row.add('$x:${px[i]},${px[i + 1]},${px[i + 2]}');
      }
      print('wash=$w  y=324 row: ${row.join('  ')}');
      final col = <String>[];
      for (var y = 0; y < 720; y += 60) {
        final i = (y * 940 + 470) * 4;
        col.add('$y:${px[i]},${px[i + 1]},${px[i + 2]}');
      }
      print('wash=$w  x=470 col: ${col.join('  ')}');
    }
  });

  test('blood accumulation over a night, instrumented', () async {
    seedRandom(404);
    final s = _st();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    var last = 0;
    var t = 0.0;
    const dt = 1 / 60.0;
    double peakWash = 0;
    var washAbove = 0.0; // seconds with wash > 0.004
    while (t < 40 * 60 && !r.lost) {
      r.tick(dt);
      t += dt;
      if (r.blood.wash > 0.004) washAbove += dt;
      if (r.blood.wash > peakWash) peakWash = r.blood.wash;
      if (s.stats.scared != last) {
        last = s.stats.scared;
        print('scare #$last at ${t.toStringAsFixed(0)}s  '
            'splats=${r.blood.splats.length} wash=${r.blood.wash.toStringAsFixed(3)} '
            'night=${s.night}');
      }
    }
    print('END t=${t.toStringAsFixed(0)} lost=${r.lost} scared=${s.stats.scared} '
        'splats=${r.blood.splats.length} peakWash=${peakWash.toStringAsFixed(3)} '
        'washVisibleSecs=${washAbove.toStringAsFixed(0)} of ${t.toStringAsFixed(0)}');
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('jumpscare face frames, real entities', () async {
    seedRandom(3);
    final s = _st();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    await initEntities();
    for (final id in <String>['sleep', 'vert', 'niel', 'call']) {
      r.scare = 1.0;
      r.scareDef = kAnoms.firstWhere((a) => a.id == id);
      final feed = bakeImageSync(320, 240, (c) => paintFeed(c, s, r, 20.0));
      final big = bakeImageSync(960, 720, (c) {
        drawImageStretch(
            c, feed, const ui.Rect.fromLTWH(0, 0, 960, 720), nearestPaint());
      });
      final png = await big.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/f_$id.png').writeAsBytesSync(png!.buffer.asUint8List());
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
