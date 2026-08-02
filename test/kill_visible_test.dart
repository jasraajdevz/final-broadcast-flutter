// You have never seen the thing you killed.
//
// The corpse block ran above the act/lost/normal branch, and `act` is always
// null while a corpse exists, so the final `else` always ran — and
// drawFeedNormal's first operation is an opaque fill over the whole 320x240
// feed. Painted and erased in the same frame. Baking the feed with and without
// a corpse produced 0 of 307200 bytes differing, at every phase.
//
// This test is that measurement, kept.

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/paint/entities.dart';
import 'package:final_broadcast/src/paint/feed.dart';
import 'package:final_broadcast/src/state.dart';

Future<ui.Image> _bake(GameState s, AnomalyRuntime r, double t) async {
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, 320, 240));
  paintFeed(c, s, r, t);
  return rec.endRecording().toImage(320, 240);
}

Future<int> _bytesDiffering(ui.Image a, ui.Image b) async {
  final ba = await a.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bb = await b.toByteData(format: ui.ImageByteFormat.rawRgba);
  final x = ba!.buffer.asUint8List(), y = bb!.buffer.asUint8List();
  var n = 0;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initEntities();
  });

  test('the kill animation reaches the pixels at every phase', () async {
    for (final phase in <double>[0.10, 0.29, 0.50, 0.75]) {
      final s = GameState();
      for (final p in kProducers) {
        s.prod[p.id] = 0;
      }
      s.prod['rabbit'] = 20;
      final r = AnomalyRuntime(s);
      r.startBroadcast();
      // banishFx pinned off, so any difference is the BODY and not the wash
      r.banishFx = 0;

      final without = await _bake(s, r, 12.0);

      r.dying = ActiveAnom(
          def: kAnoms.first,
          window: 8,
          masked: false,
          stage: 1,
          intensity: 1,
          seed: 0.4);
      r.dyingSpan = kDyingSpan;
      r.dyingT = kDyingSpan * phase;
      r.banishFx = 0;
      final with_ = await _bake(s, r, 12.0);

      final diff = await _bytesDiffering(without, with_);
      expect(diff, greaterThan(0),
          reason: 'at phase $phase the corpse changed 0 of 307200 bytes — '
              'it is being painted and then erased in the same frame');
    }
  });
}
