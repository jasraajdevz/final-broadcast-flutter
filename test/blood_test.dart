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

import 'package:fake_async/fake_async.dart';
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
    // fakeAsync, because the staged scare beats (BLACKOUT, FALSE CLEAR) land
    // their hit — and therefore their blood — on a Timer. A plain test never
    // runs those, so whether this passed depended on which beat the RNG drew,
    // which made it quietly seed-fragile.
    fakeAsync((async) {
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
        async.elapse(const Duration(milliseconds: 16));
      }
      expect(s.stats.scared, greaterThan(0), reason: 'nothing ever landed');
      // let any staged beat finish landing
      async.elapse(const Duration(seconds: 3));
      for (var i = 0; i < 180; i++) {
        r.tick(dt);
      }
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

  test('it dries, and drying is visible', () async {
    // The single biggest realism cue available. Every mark being one flat
    // colour is why the first pass read as paint: paint does not change, and
    // the eye knows that. A fresh mark and a ten-minute-old one have to be
    // obviously different or the layer is wallpaper.
    final b = BloodLayer();
    seedRandom(5);
    b.add(0.9, ox: 300, oy: 200, count: 6);
    final s = b.splats.first;
    expect(s.dry, lessThan(0.05), reason: 'it started dry');
    for (var i = 0; i < 60 * 240; i++) {
      b.tick(1 / 60.0);
    }
    expect(s.dry, greaterThan(0.85), reason: 'it never dried');

    // and the difference reaches the screen
    ui.Image bake(BloodLayer x) {
      final rec = ui.PictureRecorder();
      final c = ui.Canvas(rec, kRoom);
      drawBlood(c, x, 4.0);
      return rec.endRecording()
          .toImageSync(kRoom.width.toInt(), kRoom.height.toInt());
    }
    final fresh = BloodLayer();
    seedRandom(5);
    fresh.add(0.9, ox: 300, oy: 200, count: 6);
    final af = await bake(fresh).toByteData(format: ui.ImageByteFormat.rawRgba);
    final ad = await bake(b).toByteData(format: ui.ImageByteFormat.rawRgba);
    final xf = af!.buffer.asUint8List(), xd = ad!.buffer.asUint8List();
    var diff = 0;
    for (var i = 0; i < xf.length; i++) {
      if (xf[i] != xd[i]) diff++;
    }
    expect(diff, greaterThan(2000),
        reason: 'a dried mark looks identical to a fresh one');
  });

  test('runs shed beads, and each one is a sound with a place', () {
    final b = BloodLayer();
    seedRandom(17);
    // a big mark, so it is fat enough to bead at all
    b.add(1.0, ox: 700, oy: 120, count: 10);
    for (var i = 0; i < 60 * 200; i++) {
      b.tick(1 / 60.0);
    }
    expect(b.drips, isNotEmpty, reason: 'nothing ever dripped');
    for (final d in b.drips) {
      final pan = (d.x / kRoom.width) * 2 - 1;
      expect(pan, inInclusiveRange(-1.0, 1.0));
      expect(d.size, inInclusiveRange(0.0, 1.0));
    }
    // marks on the right of the glass drip on the right
    final right = b.drips.where((d) => d.x > kRoom.width * 0.6).length;
    expect(right, greaterThan(0),
        reason: 'a drip must carry the position of the mark that shed it');
  });

  test('a travelling run leaves a broken trail, bounded', () {
    final b = BloodLayer();
    seedRandom(23);
    for (var i = 0; i < 30; i++) {
      b.add(1.0, ox: 300, oy: 100);
    }
    for (var i = 0; i < 60 * 400; i++) {
      b.tick(1 / 60.0);
    }
    expect(b.trail, isNotEmpty, reason: 'runs slid cleanly, like a stripe');
    expect(b.trail.length, lessThanOrEqualTo(160));
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
