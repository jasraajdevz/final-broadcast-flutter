// WHAT IS ON THE GLASS.
//
// Every scare in this build was a SYSTEM: a number went up, a meter turned
// red, a face flashed for a second and the room went back to normal. Nothing
// in the booth had ever been TOUCHED by anything.
//
// These guard the layer that has: that it marks, that it accumulates across a
// night, that it is bounded so a bad night is not a frame-rate bug, that it
// reaches actual pixels, and that sunrise is the only thing that cleans it.

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/anomalies.dart';
import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/paint/blood.dart';
import 'package:final_broadcast/src/state.dart';

GameState _station() {
  final s = GameState();
  for (final p in kProducers) {
    s.prod[p.id] = 0;
  }
  s.prod['rabbit'] = 60;
  for (final a in kAnoms) {
    s.seen[a.id] = true;
  }
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a scare puts something on the glass, and it stays', () {
    seedRandom(808);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    expect(r.blood.isEmpty, isTrue, reason: 'the booth starts clean');

    var t = 0.0;
    const dt = 1 / 60.0;
    // never answer anything
    while (t < 21 * 60 && !r.lost && s.stats.scared < 1) {
      r.tick(dt);
      t += dt;
    }
    expect(s.stats.scared, greaterThan(0), reason: 'nothing ever landed');
    expect(r.blood.splats, isNotEmpty);

    // and it is still there a long time later
    final int marked = r.blood.splats.length;
    var u = 0.0;
    while (u < 60 && !r.lost) {
      r.tick(dt);
      u += dt;
    }
    expect(r.blood.splats.length, greaterThanOrEqualTo(marked),
        reason: 'the glass cleaned itself');
  });

  test('it accumulates — a bad night is visibly worse than a bad minute', () {
    seedRandom(99);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    var t = 0.0;
    const dt = 1 / 60.0;
    var afterFirst = 0;
    while (t < 21 * 60 && !r.lost) {
      r.tick(dt);
      t += dt;
      if (s.stats.scared == 1 && afterFirst == 0) {
        afterFirst = r.blood.splats.length;
      }
    }
    expect(s.stats.scared, greaterThan(1));
    expect(r.blood.splats.length, greaterThan(afterFirst),
        reason: 'the second scare left nothing the first had not');
  });

  test('the runs keep moving after the scare is over', () {
    final b = BloodLayer();
    seedRandom(3);
    b.add(1.0, ox: 200, oy: 200, count: 12);
    final heavy = b.splats.where((x) => x.heavy).toList();
    expect(heavy, isNotEmpty, reason: 'nothing ran at full force');
    final before = heavy.first.run;
    for (var i = 0; i < 600; i++) {
      b.tick(1 / 60.0);
    }
    expect(heavy.first.run, greaterThan(before),
        reason: 'it stopped moving the instant it landed');
    expect(heavy.first.run, lessThanOrEqualTo(1.0));
  });

  test('it is bounded, so the worst night is not a frame-rate bug', () {
    final b = BloodLayer();
    seedRandom(1);
    for (var i = 0; i < 400; i++) {
      b.add(1.0, ox: 100, oy: 100);
      b.addHand(50, 50);
    }
    expect(b.splats.length, lessThanOrEqualTo(90));
    expect(b.hands.length, lessThanOrEqualTo(8));
  });

  test('sunrise is the only thing that cleans it', () {
    seedRandom(7);
    final s = _station();
    final r = AnomalyRuntime(s, audio: const NullAudio());
    r.startBroadcast();
    r.blood.add(1.0, ox: 300, oy: 200);
    r.blood.addHand(740, 200);
    expect(r.blood.isEmpty, isFalse);
    r.startBroadcast(); // taking the next shift
    expect(r.blood.isEmpty, isTrue, reason: 'a fresh night starts clean');
  });

  test('it actually reaches the pixels', () async {
    ui.Image bake(BloodLayer b) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec, kRoom);
      drawBlood(c, b, 4.0);
      return rec.endRecording().toImageSync(
          kRoom.width.toInt(), kRoom.height.toInt());
    }

    final empty = BloodLayer();
    final marked = BloodLayer();
    seedRandom(21);
    marked.add(0.9, ox: kRoom.width / 2, oy: kRoom.height / 2, count: 8);
    marked.addHand(kWin.center.dx, kWin.center.dy);
    for (var i = 0; i < 300; i++) {
      marked.tick(1 / 60.0);
    }

    final a = await bake(empty).toByteData(format: ui.ImageByteFormat.rawRgba);
    final z = await bake(marked).toByteData(format: ui.ImageByteFormat.rawRgba);
    final x = a!.buffer.asUint8List(), y = z!.buffer.asUint8List();
    var diff = 0;
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) diff++;
    }
    expect(diff, greaterThan(2000),
        reason: 'the blood layer changed almost nothing on screen');
  });
}
