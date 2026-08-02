// FINAL BROADCAST — the top status strip (#status).
//
// SIGNAL / BROADCAST / SHIFT / QUOTA / DREAD / ON AIR.
// The readout logic is syncUI() from index.html, line for line — including the
// three-way SIGNAL rate line that makes the Test Card Girl's theft legible.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../bake.dart' show measureText;
import '../consts.dart';
import '../economy.dart';
import '../state.dart';
import 'ui_kit.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final a = runtime.active;

    // --- SIGNAL rate: theft first, then off-air transmitters, then normal ---
    String rateText;
    Color rateColor;
    if (runtime.sabOn('card') && a != null && a.held > 0) {
      rateText = '>> SHE HAS ${fmt(a.held)}';
      rateColor = K.heldPink;
    } else if (a != null && a.mute.isNotEmpty) {
      rateText = 'v ${fmt(sigRate(s, runtime))}/s  ${a.mute.length} OFF AIR';
      rateColor = K.toastBad;
    } else {
      rateText = '+${fmt(sigRate(s, runtime))}/s  '
          '×${sigMult(s).toStringAsFixed(2)}${s.sponsorEnd > 0 ? " +" : ""}';
      rateColor = K.subGreen;
    }

    final sg = segOf(s);
    final quotaP = sg.quota <= 0 ? 1.0 : math.min(1.0, s.segSig / sg.quota);

    return Container(
      decoration: vgrad(
        K.statusTop,
        K.statusBot,
        border: const Border(
            bottom: BorderSide(color: K.black, width: 2)),
        shadow: const <BoxShadow>[
          BoxShadow(
              color: Color(0xB3000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _Rdo(
            ui: s.ui,
            maxWidth: 185,
            label: 'SIGNAL',
            value: fmt(s.sig),
            valueColor: K.green,
            sub: rateText,
            subColor: rateColor,
          ),
          _Rdo(
            ui: s.ui,
            maxWidth: 160,
            label: 'BROADCAST',
            value: fmt(s.segSig),
            valueColor: K.cyan,
            valueGlowAlpha: 0.4,
            sub: 'THIS SEGMENT',
          ),
          _Rdo(
            ui: s.ui,
            minWidth: 136,
            maxWidth: 195,
            label: 'SHIFT ENDS 06:00',
            value: shiftClock(s),
            valueColor: s.stalled ? K.red : K.green,
            sub: '${s.stalled ? "HELD - " : ""}${sg.nm}',
          ),
          _Rdo(
            ui: s.ui,
            minWidth: 118,
            maxWidth: 175,
            label: 'QUOTA',
            value: '${fmt(math.min(s.segSig, sg.quota))} / ${fmt(sg.quota)}',
            valueColor: K.green,
            valueSize: 17,
            below: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _Meter(
                fraction: quotaP,
                height: 5,
                background: UX.qBarBg,
                border: UX.qBarBorder,
                fillA: K.greenDim,
                fillB: K.green,
              ),
            ),
          ),
          // --- DREAD ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('DREAD',
                        maxLines: 1,
                        softWrap: false,
                        style: t.at(12, K.dreadLbl, ls: 1.5)),
                  ),
                  _Meter(
                    fraction: (s.dread / 100).clamp(0.0, 1.0),
                    height: 16,
                    background: K.dreadTrack,
                    border: K.dreadBorder,
                    fillA: K.dreadFillA,
                    fillB: K.dreadFillB,
                    ticks: true,
                  ),
                ],
              ),
            ),
          ),
          _OnAir(s: s, runtime: runtime),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Rdo extends StatelessWidget {
  const _Rdo({
    required this.ui,
    required this.label,
    required this.value,
    required this.valueColor,
    this.sub,
    this.subColor,
    this.below,
    this.minWidth = 112,
    this.maxWidth = 185,
    this.valueSize = 24,
    this.valueGlowAlpha = 0.45,
  });

  final double ui;
  final String label;
  final String value;
  final Color valueColor;
  final String? sub;
  final Color? subColor;
  final Widget? below;
  final double minWidth;

  /// The CSS relied on flex-shrink to squeeze these blocks when the TEXT SIZE
  /// slider is pushed up. A Flex cannot shrink an inflexible child, so each
  /// readout is capped instead and its text clips. The caps are chosen so that
  /// nothing binds at the default 115% and the five blocks can never total
  /// more than the strip is wide.
  final double maxWidth;
  final double valueSize;
  final double valueGlowAlpha;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    final labelStyle = t.at(12, K.lbl, ls: 1.5);
    // The CSS block was shrink-to-fit, so the meter under the value inherited
    // the readout's own width. Nothing here has a bounded width to stretch
    // into, so it takes the wider of the label and the CSS min-width. The
    // label is a constant, so measuring it does not grow the text cache.
    final meterWidth = math.min(maxWidth - 24,
        math.max(minWidth - 24, measureText(label, labelStyle)));
    return Container(
      // .rdo is height:58 with overflow visible; a Flex cannot overflow
      // quietly, so the block is allowed to grow into the 82px strip instead
      // (at TEXT SIZE 115% the three lines come to ~61px).
      constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: maxWidth,
          minHeight: 58,
          maxHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: UX.rdoRule)),
      ),
      // The CSS let a .rdo overflow its 58px box; a Flex cannot, so an
      // oversized readout (TEXT SIZE 180%) scales down instead.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: labelStyle, maxLines: 1, softWrap: false),
          Text(
            value,
            maxLines: 1,
            softWrap: false,
            style: t.at(valueSize, valueColor,
                ls: 1, h: 1.15, sh: glow(valueColor, 8, valueGlowAlpha)),
          ),
          if (sub != null)
            Text(sub!,
                maxLines: 1,
                softWrap: false,
                style: t.at(13, subColor ?? K.subGreen)),
          if (below != null) SizedBox(width: meterWidth, child: below),
        ],
        ),
      ),
    );
  }
}

/// #dreadBar / #qBar — a bordered track with a horizontal gradient fill and,
/// for DREAD, the 20px black tick comb painted over the top.
class _Meter extends StatelessWidget {
  const _Meter({
    required this.fraction,
    required this.height,
    required this.background,
    required this.border,
    required this.fillA,
    required this.fillB,
    this.ticks = false,
  });

  final double fraction;
  final double height;
  final Color background;
  final Color border;
  final Color fillA;
  final Color fillB;
  final bool ticks;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
      ),
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: fraction.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: <Color>[fillA, fillB]),
                ),
              ),
            ),
            if (ticks) const CustomPaint(painter: _TickPainter()),
          ],
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  const _TickPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = K.black;
    for (double x = 19; x < size.width; x += 20) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) => false;
}

/// #onair — OFF AIR / ON AIR / ## INTRUSION / SIGNAL LOST.
/// The `live` state pulses on a 1.6s cycle (CSS @keyframes pulseair).
class _OnAir extends StatelessWidget {
  const _OnAir({required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    String text = 'OFF AIR';
    bool live = false;
    if (runtime.lost) {
      text = 'SIGNAL LOST';
    } else if (runtime.signedOn) {
      text = runtime.active != null ? '## INTRUSION' : 'ON AIR';
      live = true;
    }

    double opacity = 1;
    if (live) {
      final p = (runtime.tGlobal / 1.6) % 1.0;
      opacity = p < 0.5 ? 1 - 0.45 * (p * 2) : 0.55 + 0.45 * ((p - 0.5) * 2);
    }

    return Opacity(
      opacity: opacity,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: live ? K.onAirLiveBg : K.onAirOffBg,
          border: Border.all(
              color: live ? K.red : K.onAirOffBorder, width: 2),
        ),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: t.at(15, live ? K.onAirLive : K.onAirOff,
              ls: 2, sh: live ? glow(K.red, 10, 0.8) : null),
        ),
      ),
    );
  }
}
