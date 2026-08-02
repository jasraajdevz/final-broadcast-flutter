// FINAL BROADCAST — the sponsor break (#modalAd).
//
// An in-game commercial: no external anything, five spots, 6.5s long and
// skippable at 5s. Used by SPONSOR (×3 output for 60s) and by the EMERGENCY
// SPONSOR revive. Port of playAd() / adTick() / endAd() / drawAd().

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../bake.dart';
import '../consts.dart';
import '../state.dart';
import 'ui_kit.dart';

/// The running spot. `runtime.playAd` is wired to [play].
class AdController {
  AdController({required this.s, required this.runtime}) {
    unawaited(_bakeNoise());
  }

  final GameState s;
  final AnomalyRuntime runtime;

  Ad? ad;
  double t = 0;
  String label = 'PAID PROGRAMMING';
  void Function()? _done;
  final List<ui.Image> noise = <ui.Image>[];

  bool get active => ad != null;
  bool get canSkip => t >= kAdSkipAt;
  String get skipLabel =>
      canSkip ? 'CONTINUE' : 'SKIP IN ${(kAdSkipAt - t).ceil()}';

  /// JS playAd(done, label).
  ///
  /// The cue used to be three bare square blips — the same voice as a rack tab,
  /// which is the wrong voice for the one moment the station stops being yours.
  /// This is a CUT TO TAPE, and a 1987 station cutting to tape makes a specific
  /// noise: the room is yanked away, the splice goes through the gate, the
  /// telecine takes up, and only then does the ident ring.
  void play(String adLabel, void Function() done) {
    ad = pick(kAds);
    label = adLabel;
    t = 0;
    _done = done;
    runtime.adPlaying = true;
    _cutToTape();
  }

  void _cutToTape() {
    final a = runtime.audio;
    // the room goes, hard, and stays gone for the length of the ident
    a.duck(0.18, 1100);
    // the splice through the gate, then the telecine taking up
    a.burst(0.06, 0.30, 5400, 900);
    a.thump(0.24, 74);
    // the ident: a major triad with a tail on it, over a low pad. Same three
    // notes the old cue used, given a body so it reads as a station and not as
    // a menu.
    const notes = <double>[523, 659, 784];
    for (var i = 0; i < notes.length; i++) {
      final f = notes[i];
      final dur = i == notes.length - 1 ? 1.05 : 0.55;
      Timer(Duration(milliseconds: 90 + i * 150), () {
        a.env('triangle', f, dur, 0.105, f);
        a.env('sine', f * 2, dur * 0.7, 0.042, f * 2);
      });
    }
    Timer(const Duration(milliseconds: 90),
        () => a.env('sawtooth', 131, 1.25, 0.05, 131, 2));
  }

  /// Coming back off tape. The return used to be silent, so a spot ended by
  /// going quiet — indistinguishable from the audio having died. One transient
  /// and the room comes back up on its own as the duck releases.
  void _cutBack() {
    final a = runtime.audio;
    a.duck(0.30, 240);
    a.burst(0.05, 0.26, 4800, 700);
    a.env('square', 392, 0.10, 0.055, 262);
    a.thump(0.16, 62);
  }

  /// JS adTick(dt) — called from the main loop while a spot is up.
  void tick(double dt) {
    if (ad == null) return;
    t += dt;
    if (t >= kAdDuration) end();
  }

  /// JS endAd().
  void end() {
    if (ad == null) return;
    final d = _done;
    ad = null;
    _done = null;
    runtime.adPlaying = false;
    s.stats.ads++;
    _cutBack();
    d?.call();
  }

  /// The eight 180x135 white-noise tiles the grain overlay picks from.
  /// If the platform will not decode them the spot simply runs without grain.
  Future<void> _bakeNoise() async {
    try {
      await _bakeNoiseTiles();
    } catch (_) {
      noise.clear();
    }
  }

  Future<void> _bakeNoiseTiles() async {
    for (var k = 0; k < kNoiseTileCount; k++) {
      final px = Uint8List(kNoiseTileW * kNoiseTileH * 4);
      for (var i = 0; i < px.length; i += 4) {
        final v = (rand() * 255).floor();
        px[i] = v;
        px[i + 1] = v;
        px[i + 2] = v;
        px[i + 3] = 255;
      }
      final c = Completer<ui.Image>();
      ui.decodeImageFromPixels(
          px, kNoiseTileW, kNoiseTileH, ui.PixelFormat.rgba8888, c.complete);
      noise.add(await c.future);
    }
  }
}

// ---------------------------------------------------------------------------

class AdSheet extends StatelessWidget {
  const AdSheet({super.key, required this.s, required this.controller});

  final GameState s;
  final AdController controller;

  @override
  Widget build(BuildContext context) {
    final ad = controller.ad;
    if (ad == null) return const SizedBox.shrink();
    final t = Sty(s.ui);
    return ModalScrim(
      child: Container(
        width: kAdSheetSize.width,
        height: kAdSheetSize.height,
        decoration: BoxDecoration(
          color: K.black,
          border: Border.all(color: UX.adSheetBorder, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ClipRect(
                child: CustomPaint(
                  painter: _AdPainter(
                    ad: ad,
                    t: controller.t,
                    tiles: controller.noise,
                  ),
                ),
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: const BoxDecoration(
                color: UX.adBarBg,
                border: Border(top: BorderSide(color: UX.adBarRule)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Text(controller.label,
                        maxLines: 1,
                        softWrap: false,
                        style: t.at(13, UX.adBarInk, ls: 1.5)),
                  ),
                  Pressable(
                    enabled: controller.canSkip,
                    onTap: controller.end,
                    builder: (_, _, _) => Opacity(
                      opacity: controller.canSkip ? 1 : 0.35,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 7),
                        decoration: BoxDecoration(
                          color: UX.adSkipBg,
                          border: Border.all(color: UX.adSkipBorder),
                        ),
                        child: Text(controller.skipLabel,
                            style: t.at(14, K.amber, ls: 1.5)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// JS drawAd(ad, t) on the 480x360 buffer, stretched to the sheet.
class _AdPainter extends CustomPainter {
  const _AdPainter({required this.ad, required this.t, required this.tiles});

  final Ad ad;
  final double t;
  final List<ui.Image> tiles;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    const w = kAdCanvasW * 1.0, h = kAdCanvasH * 1.0;
    canvas.save();
    canvas.scale(size.width / w, size.height / h);
    canvas.clipRect(const ui.Rect.fromLTWH(0, 0, w, h));

    canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, w, h), fill(const ui.Color(0xFF05070A)));
    // rolling gradient bg
    canvas.drawRect(
      const ui.Rect.fromLTWH(0, 0, w, h),
      ui.Paint()
        ..shader = linear(
          ui.Offset.zero,
          const ui.Offset(0, h),
          <ui.Color>[const ui.Color(0xFF0B1424), const ui.Color(0xFF160A14)],
          <double>[0, 1],
        ),
    );

    // spinning sunburst
    canvas.save();
    canvas.translate(w / 2, h * 0.46);
    canvas.rotate(t * 0.6);
    final bright = fill(const ui.Color(0x09FFFFFF));
    final dim = fill(const ui.Color(0x03FFFFFF));
    for (var i = 0; i < 16; i++) {
      canvas.rotate(tau / 16);
      final p = ui.Path()
        ..moveTo(0, 0)
        ..arcTo(ui.Rect.fromCircle(center: ui.Offset.zero, radius: 340), 0,
            tau / 16, false)
        ..close();
      canvas.drawPath(p, i.isOdd ? bright : dim);
    }
    canvas.restore();

    // product box
    final bob = math.sin(t * 3) * 6;
    canvas.save();
    canvas.translate(w / 2, h * 0.44 + bob);
    canvas.drawRect(const ui.Rect.fromLTWH(-92, -62, 184, 124),
        fill(const ui.Color(0x80000000)));
    canvas.drawRect(
        const ui.Rect.fromLTWH(-92, -62, 184, 124), stroke(ad.c, 3));
    fillText(canvas, ad.t, const ui.Offset(0, -22),
        mono(19, ad.c, weight: FontWeight.bold),
        anchor: TextAnchor.center);
    fillText(canvas, ad.s, const ui.Offset(0, 14),
        mono(27, const ui.Color(0xFFFFFFFF), weight: FontWeight.bold),
        anchor: TextAnchor.center);
    fillText(canvas, '* * * * *', const ui.Offset(0, 42),
        mono(10, const ui.Color(0x99FFFFFF)),
        anchor: TextAnchor.center);
    canvas.restore();

    // tagline typewriter, 22 chars a second
    final n = (t * 22).floor().clamp(0, ad.l.length);
    fillText(canvas, ad.l.substring(0, n), const ui.Offset(w / 2, h - 56),
        mono(13, const ui.Color(0xFFE8F2EF)),
        anchor: TextAnchor.center);
    fillText(canvas, 'A KBLK-7 SPONSORED MESSAGE',
        const ui.Offset(w / 2, h - 26), mono(9, const ui.Color(0x59FFFFFF)),
        anchor: TextAnchor.center);

    // scanlines + grain
    final line = fill(const ui.Color(0x47000000));
    for (double y = 0; y < h; y += 3) {
      canvas.drawRect(ui.Rect.fromLTWH(0, y, w, 1), line);
    }
    if (tiles.isNotEmpty) {
      final tile = tiles[(t * 22).floor() % tiles.length];
      drawImageStretch(canvas, tile, const ui.Rect.fromLTWH(0, 0, w, h),
          nearestPaint(alpha: 0.06));
    }
    if (rand() < 0.05) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, rand() * h, w, rr(2, 10)),
        fill(const ui.Color(0x14FFFFFF)),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AdPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.ad != ad;
}
