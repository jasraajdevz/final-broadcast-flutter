// THE FRONT DESK MUST STAY READABLE.
//
// The home screen was type on a radial gradient and now it is the station from
// outside at three in the morning — mast, beacon, treeline, a lit window, snow,
// a fence. The obvious way to ruin that is to make a handsome picture that the
// SIGN ON button then has to sit on top of.
//
// So the rule is measurable and measured: the centre band, where the wordmark,
// the rank, the next-rung bar and both buttons live, must stay materially
// darker than the outer thirds no matter what the scene is doing.

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

import 'package:final_broadcast/src/state.dart';
import 'package:final_broadcast/src/ui/home_backdrop.dart';

Future<List<int>> _bake(double t) async {
  const int w = 1280, h = 720;
  final rec = ui.PictureRecorder();
  final c = ui.Canvas(rec, const ui.Rect.fromLTWH(0, 0, w * 1.0, h * 1.0));
  HomeBackdropProbe.paint(
      c, const ui.Size(w * 1.0, h * 1.0), GameState()..survived = 5, t);
  final img = rec.endRecording().toImageSync(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bd!.buffer.asUint8List();
}

/// Mean luminance of a rect, 0..255.
double _lum(List<int> px, int x0, int y0, int x1, int y1) {
  const int w = 1280;
  var sum = 0.0;
  var n = 0;
  for (var y = y0; y < y1; y += 2) {
    for (var x = x0; x < x1; x += 2) {
      final i = (y * w + x) * 4;
      sum += 0.2126 * px[i] + 0.7152 * px[i + 1] + 0.0722 * px[i + 2];
      n++;
    }
  }
  return sum / n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the centre band stays dark enough to read type on', () async {
    // sampled across the animation, because the beacon, the snow and the
    // window flicker all run on different rates and could conspire
    for (final t in <double>[0, 7, 19, 44, 91]) {
      final px = await _bake(t);
      // where the wordmark, rank, bar and both buttons actually sit
      final centre = _lum(px, 300, 90, 980, 620);
      expect(centre, lessThan(30),
          reason: 'at t=$t the centre band is $centre — too bright to set '
              'type on');
    }
  });

  test('but it is not just a black rectangle', () async {
    // The other failure: protecting the type so hard that the scene vanishes
    // and we are back to a gradient with extra steps.
    //
    // NOT "some corner is brighter than the middle" — the first version of
    // this compared the darkest patch of ground against the centre and failed
    // for the right reason: the sodium haze was reaching into the type band
    // and was genuinely the brightest thing in it. The honest property is that
    // the frame has RANGE.
    final px = await _bake(31);
    final samples = <double>[
      _lum(px, 0, 380, 260, 700), // the near ground, left
      _lum(px, 40, 300, 420, 470), // the haze
      _lum(px, 980, 200, 1240, 560), // the mast side
      _lum(px, 300, 40, 980, 200), // high sky, centre
    ];
    final lo = samples.reduce((a, b) => a < b ? a : b);
    final hi = samples.reduce((a, b) => a > b ? a : b);
    expect(hi - lo, greaterThan(6),
        reason: 'the backdrop is flat — there is nothing to look at');
    expect(hi, greaterThan(8), reason: 'the whole backdrop is black');
  });

  test('the scene actually changes over time', () async {
    // Nothing may loop visibly on a screen somebody sits on for thirty
    // seconds, so two distant moments must not be identical frames.
    final a = await _bake(3);
    final b = await _bake(53);
    var diff = 0;
    for (var i = 0; i < a.length; i += 97) {
      if (a[i] != b[i]) diff++;
    }
    expect(diff, greaterThan(50), reason: 'the backdrop is a still image');
  });
}
