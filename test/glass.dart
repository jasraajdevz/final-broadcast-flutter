// HOW MUCH OF THE TUBE CAN THE PLAYER ACTUALLY NOT SEE THROUGH?
//
// Shared instrument, kept out of any one test file because more than one thing
// needs to ask this question and they must all ask it the same way.
//
// It is measured FROM RENDERED PIXELS, not from the model. That is deliberate
// and it is the whole point of the file: `glass.length` reported 26 for ten
// straight minutes and was read as "saturated" when it meant "capped", and
// every analytic estimate I could write instead would be a second model that
// can drift from the painter in exactly the same way. Pixels cannot drift from
// the painter — they are what the painter did.
//
// The cost is that this needs a real Flutter binding and a rasteriser, so it is
// too slow for a per-tick guard. Use the cheap model-side scalar for the shape
// of a curve; use this to prove the curve is about something the eye can see.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:final_broadcast/src/consts.dart';
import 'package:final_broadcast/src/paint/blood.dart';

/// Renders [b] and reports what fraction of the tube it covers.
///
/// Returns 0..1. A pixel counts as covered when the blood layer moved it by
/// more than [threshold] on any channel — i.e. when something the player was
/// trying to read is no longer the colour it should be.
///
/// The comparison is against the SAME scene with an empty blood layer rather
/// than against a flat background, so the number means "damage done by blood"
/// and not "how dark the booth is".
Future<double> tubeOcclusion(BloodLayer b, {int threshold = 10}) async {
  final Uint8List dirty = await _bake(b);
  final Uint8List clean = await _bake(BloodLayer());

  final int x0 = kScr.left.floor(), x1 = kScr.right.ceil();
  final int y0 = kScr.top.floor(), y1 = kScr.bottom.ceil();
  final int w = kRoom.width.toInt();

  var covered = 0, total = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final int i = (y * w + x) * 4;
      total++;
      final int dr = (dirty[i] - clean[i]).abs();
      final int dg = (dirty[i + 1] - clean[i + 1]).abs();
      final int db = (dirty[i + 2] - clean[i + 2]).abs();
      if (dr > threshold || dg > threshold || db > threshold) covered++;
    }
  }
  return total == 0 ? 0 : covered / total;
}

/// The same measure, but weighted by HOW MUCH each pixel moved rather than
/// whether it moved at all.
///
/// Coverage alone plateaus the moment the marks overlap the whole tube —
/// which is precisely the failure being fixed — so a mode that keeps getting
/// worse after full coverage (darker, more opaque, more layers of it) has to
/// be measurable after coverage has topped out. This keeps climbing when
/// coverage cannot.
Future<double> tubeDamage(BloodLayer b) async {
  final Uint8List dirty = await _bake(b);
  final Uint8List clean = await _bake(BloodLayer());

  final int x0 = kScr.left.floor(), x1 = kScr.right.ceil();
  final int y0 = kScr.top.floor(), y1 = kScr.bottom.ceil();
  final int w = kRoom.width.toInt();

  var sum = 0.0;
  var total = 0;
  for (var y = y0; y < y1; y++) {
    for (var x = x0; x < x1; x++) {
      final int i = (y * w + x) * 4;
      total++;
      final int dr = (dirty[i] - clean[i]).abs();
      final int dg = (dirty[i + 1] - clean[i + 1]).abs();
      final int db = (dirty[i + 2] - clean[i + 2]).abs();
      sum += (dr + dg + db) / (3 * 255);
    }
  }
  return total == 0 ? 0 : sum / total;
}

Future<Uint8List> _bake(BloodLayer b) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec, kRoom);
  drawBlood(c, b, 4.0);
  final ui.Image img = rec.endRecording().toImageSync(
      kRoom.width.toInt(), kRoom.height.toInt());
  final ByteData? d = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return d!.buffer.asUint8List();
}
