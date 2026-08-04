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
import '../desk.dart';
import '../economy.dart';
import '../state.dart';
import 'ui_kit.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final rig = runtime.rig;
    final t = Sty(s.ui);

    // The SIGNAL rate line, the segment quota and its bar all went with the
    // readouts they belonged to. Nothing on this strip is a bank any more.
    final sg = segOf(s);

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
          // --- THE RIG ---
          // What replaced SIGNAL / BROADCAST / QUOTA. Those three were the
          // Cookie Clicker readout: a bank, a running total and a target, and
          // not one of them was ever a thing the operator had to DO something
          // about from one second to the next.
          //
          // These are. CARRIER shows where the needle is and where the dial is
          // set; the gap between them is the night getting harder. PLATE is
          // the price of closing that gap.
          _Rdo(
            ui: s.ui,
            minWidth: 104,
            maxWidth: 150,
            label: 'CARRIER',
            value: rig.carrier.toStringAsFixed(0),
            valueColor: rig.lowPower ? K.red : K.green,
            valueSize: 17,
            sub: 'DRIVE ${rig.drive.toStringAsFixed(0)}  UP/DN',
            subColor: K.lbl,
            below: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _Meter(
                fraction: (rig.carrier / 100).clamp(0.0, 1.0),
                height: 5,
                background: UX.qBarBg,
                border: UX.qBarBorder,
                fillA: rig.lowPower ? K.red : K.greenDim,
                fillB: rig.lowPower ? K.red : K.green,
              ),
            ),
          ),
          _Rdo(
            ui: s.ui,
            minWidth: 76,
            maxWidth: 108,
            label: 'PLATE',
            value: rig.plate.toStringAsFixed(0),
            valueColor:
                rig.plate > 84 ? K.red : (rig.plate > 66 ? K.amber : K.green),
            valueSize: 17,
            sub: rig.lockout > 0
                ? 'CONTACTOR OUT'
                : (rig.trips > 0 ? 'RECYCLES ${rig.trips}' : 'NOMINAL'),
            subColor: rig.lockout > 0 ? K.red : K.lbl,
            below: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _Meter(
                fraction: (rig.plate / 100).clamp(0.0, 1.0),
                height: 5,
                background: UX.qBarBg,
                border: UX.qBarBorder,
                fillA: rig.plate > 84 ? K.red : K.greenDim,
                fillB: rig.plate > 84 ? K.red : K.amber,
              ),
            ),
          ),
          // MOD is two-sided, so its meter is marked at the CENTRE rather than
          // filled from the left. A bar that fills one way teaches the player
          // to maximise it, and this is the one gauge in the game where
          // maximising is a failure.
          _Rdo(
            ui: s.ui,
            minWidth: 84,
            maxWidth: 118,
            label: 'MODULATION',
            value: (rig.modulation - 50).toStringAsFixed(0),
            valueColor:
                (rig.modulation - 50).abs() > kModGreen ? K.red : K.green,
            valueSize: 17,
            sub: '< >',
            subColor: K.lbl,
            below: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: _CentreMeter(value: (rig.modulation - 50) / 50),
            ),
          ),
          // THE DRUMS. The score, and it only ever counts up.
          _Rdo(
            ui: s.ui,
            minWidth: 96,
            maxWidth: 126,
            label: 'LICENCE',
            value: '${rig.offAir.toStringAsFixed(1)}/'
                '${rig.ceiling.toStringAsFixed(0)}',
            valueColor: rig.offAir > rig.ceiling * 0.8 ? K.red : K.amber,
            valueSize: 15,
            sub: rig.allGreen ? 'IN SPEC' : 'SEC OFF AIR',
            subColor: rig.allGreen ? K.green : K.lbl,
          ),
          _Rdo(
            ui: s.ui,
            minWidth: 112,
            maxWidth: 168,
            // The label is a promise, and during the long night the game is
            // no longer making it.
            label: runtime.longNight ? 'THE SHIFT HAS NOT ENDED' : 'SHIFT ENDS 06:00',
            value: shiftClock(s),
            valueColor: runtime.longNight
                ? K.red
                : (s.stalled ? K.red : K.green),
            sub: runtime.longNight
                ? 'NO SEGMENT'
                : '${s.stalled ? "HELD - " : ""}${sg.nm}',
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
                ls: 1, h: 1.15, sh: glow(valueColor, 8, 0.45)),
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
    // The lamp is now the readout for the whole air state, including ALL CLEAR —
    // "safe if you get it right" is worthless if the player cannot see it.
    final AirState air = runtime.airState;
    final String text = runtime.airLabel;
    final bool safe = air == AirState.allClear;
    final bool live = air != AirState.off && air != AirState.lost;

    double opacity = 1;
    // ALL CLEAR holds STEADY. The pulse is the alarm; a steady lamp is the point.
    if (live && !safe) {
      final p = (runtime.tGlobal / 1.6) % 1.0;
      opacity = p < 0.5 ? 1 - 0.45 * (p * 2) : 0.55 + 0.45 * ((p - 0.5) * 2);
    }

    return Opacity(
      opacity: opacity,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: safe
              ? const Color(0xFF131B24)
              : (live ? K.onAirLiveBg : K.onAirOffBg),
          border: Border.all(
              color: safe
                  ? K.greenDim
                  : (live ? K.red : K.onAirOffBorder),
              width: 2),
        ),
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          style: t.at(
              15,
              safe ? K.green : (live ? K.onAirLive : K.onAirOff),
              ls: 2,
              sh: safe
                  ? glow(K.green, 10, 0.8)
                  : (live ? glow(K.red, 10, 0.8) : null)),
        ),
      ),
    );
  }
}


/// A meter marked at its CENTRE rather than filled from the left.
///
/// Modulation is the one gauge in this game where more is not better — too low
/// is dead air, too high is splatter across the band — and a bar that fills
/// from one end teaches exactly the wrong reflex. This one grows out of the
/// middle in whichever direction the needle has gone.
class _CentreMeter extends StatelessWidget {
  const _CentreMeter({required this.value});

  /// -1..1, zero being on the mark.
  final double value;

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(-1.0, 1.0);
    final bad = v.abs() > kModGreen / 50;
    return SizedBox(
      height: 5,
      child: LayoutBuilder(
        builder: (_, c) {
          final half = c.maxWidth / 2;
          final w = (half * v.abs()).clamp(0.0, half);
          return Stack(
            children: <Widget>[
              Container(
                decoration: BoxDecoration(
                  color: UX.qBarBg,
                  border: Border.all(color: UX.qBarBorder, width: 0.5),
                ),
              ),
              Positioned(
                left: v < 0 ? half - w : half,
                width: w,
                top: 0,
                bottom: 0,
                child: ColoredBox(color: bad ? K.red : K.green),
              ),
              Positioned(
                left: half - 0.5,
                width: 1,
                top: 0,
                bottom: 0,
                child: const ColoredBox(color: Color(0x99FFFFFF)),
              ),
            ],
          );
        },
      ),
    );
  }
}
