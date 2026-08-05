// FINAL BROADCAST — the bottom console (#deck).
//
// Eight emergency keys in a 4x2 grid plus the SPONSOR / MANUAL side keys.
// Once a thing has been catalogued its key says what it kills — discovery is
// preserved, recall is not a memory test (the label logic is syncUI()'s).

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../career.dart';
import '../consts.dart';
import '../state.dart';
import '../tools.dart';
import 'tools_bar.dart';
import 'ui_kit.dart';

class Deck extends StatelessWidget {
  const Deck({
    super.key,
    required this.s,
    required this.runtime,
    required this.tools,
    required this.onManual,
    this.kbDown,
  });

  final GameState s;
  final AnomalyRuntime runtime;
  final Tools tools;
  final VoidCallback onManual;

  /// Counter id currently depressed by the keyboard (`.key.down`, 90ms).
  final String? kbDown;

  /// The sub-label under each key: the names of everything it is known to
  /// kill, with a leading "THE " / "MR. " stripped, else "KEY n".
  static final RegExp _article = RegExp(r'^THE |^MR\. ');

  static String subLabel(GameState s, Counter c) {
    final known = kAnoms
        .where((a) => a.counter == c.id && (s.seen[a.id] ?? false))
        .map((a) => a.nm.replaceFirst(_article, ''))
        .toList();
    return known.isEmpty ? 'KEY ${c.key}' : known.join(' / ');
  }

  /// Everything this key is known to kill, or the empty string. Unlike
  /// [subLabel] this never falls back to the digit — the digit is now printed
  /// separately and unconditionally, so it can never be traded away.
  static String killList(GameState s, Counter c) {
    final known = kAnoms
        .where((a) => a.counter == c.id && (s.seen[a.id] ?? false))
        .map((a) => a.nm.replaceFirst(_article, ''))
        .toList();
    return known.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // R. OKONKWO's rung. Until then the deck is the eight keys, which
          // is enough to learn and few enough to remember.
          if (unlocked(s, 'tools'))
            SizedBox(height: kToolsBarH, child: ToolsBar(s: s, tools: tools)),
          const SizedBox(height: 3),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(child: _keys()),
                const SizedBox(width: 8),
                SizedBox(width: kSideKeysW, child: _sideKeys()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _keys() {
    Widget row(int from) => Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = from; i < from + 4; i++) ...<Widget>[
                if (i > from) const SizedBox(width: 6),
                Expanded(child: _key(kCounters[i])),
              ],
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        row(0),
        const SizedBox(height: 6),
        row(4),
        // THE NINTH KEY. A. VOSS's rung. No label, no manual page, no tooltip,
        // and no toast when you touch it. It is not pressed, it is HELD.
        if (unlocked(s, 'ninth')) ...<Widget>[
          const SizedBox(height: 6),
          SizedBox(height: 26, child: _ninth()),
        ],
      ],
    );
  }

  Widget _ninth() {
    final t = Sty(s.ui);
    final double h = runtime.carrierHold;
    return Listener(
      onPointerDown: (_) => runtime.beginCarrier(),
      onPointerUp: (_) => runtime.endCarrier(),
      onPointerCancel: (_) => runtime.endCarrier(),
      child: CustomPaint(
        painter: _NinthPainter(h),
        child: Center(
          child: Text(
            // deliberately not a name. The cap was scratched out.
            h > 0.02 ? '${(h * 100).round()}%' : '\u2014',
            style: t.at(10, h > 0.02 ? K.red : const Color(0xFF4A3A3A), ls: 6),
          ),
        ),
      ),
    );
  }

  Widget _key(Counter c) {
    final t = Sty(s.ui);
    final flash = runtime.keyFlashOf(c.id);
    final good = flash != null && flash.good;
    final bad = flash != null && !flash.good;
    final hot = runtime.keysHot;
    final sub = subLabel(s, c);
    final known = sub != 'KEY ${c.key}';

    return Pressable(
      forceDown: kbDown == c.id,
      tooltip: c.ds,
      // The deck sits over the picture for the whole shift, and the key
      // already prints what it answers underneath.
      tooltipInPlay: false,
      onTap: () {
        runtime.audio.init();
        runtime.audio.resume();
        runtime.pressCounter(c.id);
      },
      builder: (_, hover, pressed) {
        final Color top = good
            ? K.keyGoodTop
            : bad
                ? K.keyBadTop
                : (hover ? UX.keyHoverTop : K.keyTop);
        final Color bot = good
            ? K.keyGoodBot
            : bad
                ? K.keyBadBot
                : (hover ? UX.keyHoverBot : K.keyBot);
        final Color ink = good
            ? K.keyGoodInk
            : bad
                ? K.keyBadInk
                : hot
                    ? K.keyHotInk
                    : (hover ? UX.keyHoverInk : K.keyInk);
        final Color side = hot ? K.keyHotBorder : K.black;
        final Color edge = good
            ? UX.keyGoodEdge
            : bad
                ? UX.keyBadEdge
                : hot
                    ? K.keyHotBorder
                    : UX.keyTopEdge;
        return Transform.translate(
          offset: Offset(0, pressed ? 3 : 0),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[top, bot],
              ),
              border: Border(
                top: BorderSide(color: edge),
                left: BorderSide(color: side),
                right: BorderSide(color: side),
                bottom: BorderSide(color: side),
              ),
              boxShadow: pressed
                  ? const <BoxShadow>[
                      BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 4,
                          offset: Offset(0, 1)),
                    ]
                  : const <BoxShadow>[
                      BoxShadow(color: UX.keyShadow, offset: Offset(0, 3)),
                      BoxShadow(
                          color: Color(0x99000000),
                          blurRadius: 8,
                          offset: Offset(0, 5)),
                    ],
            ),
            // The CSS let an oversized label spill out of the keycap; scaling
            // it down instead keeps the deck readable at TEXT SIZE 180%.
            // The digit sits in a Stack OVER the cap so it is present whether
            // or not the entity name has taken the sub-line.
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 3,
                  top: 1,
                  child: Text(
                    c.key,
                    maxLines: 1,
                    softWrap: false,
                    style: t.at(12, bad ? K.keyBadInk : K.keySub, ls: 0),
                  ),
                ),
                Positioned.fill(
                  child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(c.nm,
                      maxLines: 1,
                      softWrap: false,
                      style: t.at(20, ink, ls: 2)),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      sub,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: t.at(13, known ? K.keySubKnown : K.keySub, ls: 1),
                    ),
                  ),
                ],
              ),
                ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sideKeys() {
    final ready = runtime.sponsorReady;
    String sub;
    if (s.sponsorEnd > 0) {
      sub = 'ACTIVE ${s.sponsorEnd.ceil()}s';
    } else if (s.sponsorCd > 0) {
      sub = 'COOL ${s.sponsorCd.ceil()}s';
    } else {
      sub = '×3 · 60s';
    }
    // .skey.ready — a 2.2s glow cycle
    final bool signDue = runtime.checks.active != null;
    final pulse = ready
        ? 0.5 - 0.5 * math.cos(runtime.tGlobal / 2.2 * tau)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: _SKey(
            ui: s.ui,
            label: 'SPONSOR',
            sub: sub,
            enabled: ready,
            glow: pulse,
            onTap: () {
              runtime.audio.init();
              runtime.audio.resume();
              runtime.takeSponsor();
            },
          ),
        ),
        const SizedBox(height: 6),
        // THE BOOK, AS A THING YOU CAN PUT A FINGER ON.
        //
        // Signing was ENTER and nothing else, and the hour comes due every
        // sixty seconds and costs twenty seconds of licence when it is missed.
        // On a touch screen that made the book a guaranteed loss condition
        // reachable by no control on the device.
        //
        // It lights and pulses only while a check is actually open, so it is
        // the one key on the deck that tells you when to press it — which is
        // right, because it is the one action in the game whose timing is
        // scheduled rather than reactive.
        Expanded(
          child: _SKey(
            ui: s.ui,
            label: 'SIGN',
            sub: signDue ? 'THE BOOK IS OPEN' : 'KEY: ENTER',
            enabled: signDue,
            glow: signDue
                ? 0.5 - 0.5 * math.cos(runtime.tGlobal / 1.6 * tau)
                : 0.0,
            onTap: () {
              runtime.audio.init();
              runtime.audio.resume();
              runtime.pressCheck();
              runtime.rig.sign();
            },
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: _SKey(
            ui: s.ui,
            label: 'MANUAL',
            sub: 'KEY: M',
            onTap: onManual,
          ),
        ),
      ],
    );
  }
}

class _SKey extends StatelessWidget {
  const _SKey({
    required this.ui,
    required this.label,
    required this.sub,
    required this.onTap,
    this.enabled = true,
    this.glow = 0,
  });

  final double ui;
  final String label;
  final String sub;
  final VoidCallback onTap;
  final bool enabled;
  final double glow;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      builder: (_, hover, pressed) => Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                hover ? UX.skeyHoverTop : K.skeyTop,
                hover ? UX.skeyHoverBot : K.skeyBot,
              ],
            ),
            border: const Border(
              top: BorderSide(color: UX.skeyTopEdge),
              left: BorderSide(color: K.black),
              right: BorderSide(color: K.black),
              bottom: BorderSide(color: K.black),
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: UX.keyShadow, offset: Offset(0, 3)),
              if (glow > 0)
                BoxShadow(
                    color: K.amber.withValues(alpha: 0.5 * glow),
                    blurRadius: 18),
            ],
          ),
          child: Transform.translate(
            offset: Offset(0, pressed ? 3 : 0),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(label,
                      maxLines: 1,
                      softWrap: false,
                      style: t.at(14, K.amber, ls: 1.5)),
                  Text(sub,
                      maxLines: 1,
                      softWrap: false,
                      style: t.at(11, K.skeySub, ls: 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// The ninth key. A worn brass switch guard with nothing written under it.
class _NinthPainter extends CustomPainter {
  _NinthPainter(this.h);
  final double h;

  @override
  void paint(Canvas g, Size z) {
    g.drawRect(Offset.zero & z, Paint()..color = const Color(0xFF120C0C));
    // it fills red as the carrier comes down
    if (h > 0.001) {
      g.drawRect(Rect.fromLTWH(0, 0, z.width * h, z.height),
          Paint()..color = const Color(0xFF4A0A0C));
    }
    // hatched guard, so it reads as something you are not meant to touch
    final p = Paint()
      ..color = const Color(0x2EFF6A5A)
      ..strokeWidth = 1;
    for (double x = -z.height; x < z.width; x += 9) {
      g.drawLine(Offset(x, z.height), Offset(x + z.height, 0), p);
    }
    g.drawRect(
      Offset.zero & z,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = h > 0.001 ? const Color(0xFF8A1418) : const Color(0xFF3A2A2A),
    );
  }

  @override
  bool shouldRepaint(covariant _NinthPainter o) => o.h != h;
}
