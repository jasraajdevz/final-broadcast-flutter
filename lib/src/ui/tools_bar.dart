// FINAL BROADCAST — the tool strip (#tools).
//
// A 24px rail across the top of the deck, above the eight emergency keys. Five
// chips, one per consumable, each showing its key cap, its name and its charge
// pips. Always visible, never scrolls, never moves.
//
//   [Q] FLARE   ▪▪▫ +
//
// Left-click the body FIRES it. The `+` on the right BUYS a charge (SHIFT plus
// the key does the same from the keyboard). A chip with no charges shows its
// price instead of pips, in amber if you can afford it and in dead red if you
// cannot — so the bar doubles as the shop and there is nowhere else to look.
//
// Three chips take over their own name line while they are doing something,
// because a charge you have already spent needs to be legible at a glance in
// the middle of a panic:
//   FLARE  -> HELD 1.8   (the freeze, counting down)
//   SPLICE -> >BARS      (the counter it read off the tape)
//   MIRROR -> ARMED      (standing against the glass, pulsing)
//
// The hairline along the bottom is the stock room filling the next free charge.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../consts.dart';
import '../state.dart';
import '../tools.dart';
import 'ui_kit.dart';

/// Height of the rail. The deck reserves exactly this.
const double kToolsBarH = 28;

const double _kChipGap = 5;
const double _kCapW = 16;
const double _kBuyW = 15;

class ToolsBar extends StatelessWidget {
  const ToolsBar({super.key, required this.s, required this.tools});

  final GameState s;
  final Tools tools;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < kTools.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(width: _kChipGap),
                Expanded(child: _Chip(s: s, tools: tools, def: kTools[i])),
              ],
            ],
          ),
        ),
        // the stock room, trickling. heightFactor is load-bearing: without it
        // the ColoredBox has no child, takes the smallest height it is offered
        // and the hairline is invisible.
        SizedBox(
          height: 1,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: tools.cribP,
              heightFactor: 1,
              child: const ColoredBox(color: K.amberDim),
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.s, required this.tools, required this.def});

  final GameState s;
  final Tools tools;
  final ToolDef def;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final have = tools.chargesOf(def.id);
    final full = have >= def.cap;
    final price = tools.priceOf(def);
    final afford = s.sig >= price;
    final flash = tools.flashOf(def.id).clamp(0.0, 1.0);
    final onTube = tools.runtime.active != null;

    // A chip is HOT when it has a charge and there is something to use it on.
    // The MIRROR is the exception — it is armed in advance, so it is hot
    // whenever it is loaded and not already standing.
    final hot = have > 0 &&
        tools.ready &&
        (def.needsTarget ? onTube : !tools.mirrorArmed);

    // Working state takes over the name line.
    String label = def.nm;
    Color labelInk = have > 0 ? K.ink : K.keySub;
    var busy = false;
    if (def.id == 'flare' && tools.stunned) {
      label = 'HELD ${tools.stunLeft.toStringAsFixed(1)}';
      labelInk = K.green;
      busy = true;
    } else if (def.id == 'mirror' && tools.mirrorArmed) {
      label = 'ARMED';
      labelInk = K.cyan;
      busy = true;
    } else if (def.id == 'splice' && tools.revealedCounter != null) {
      label = '>${tools.revealedCounter!.nm}';
      labelInk = K.green;
      busy = true;
    }

    // .skey.ready — the same 2.2s glow cycle the SPONSOR key uses.
    final pulse = busy || hot
        ? 0.5 - 0.5 * math.cos(tools.runtime.tGlobal / 2.2 * tau)
        : 0.0;

    final Color edge = flash > 0
        ? K.green
        : busy
            ? (def.id == 'mirror' ? K.cyan : K.green)
            : hot
                ? K.amberDim
                : K.itemBorder;

    return Pressable(
      tooltip: '${def.ds}\n\n'
          'KEY ${def.keyCap}  ·  $have/${def.cap} CHARGES  ·  '
          'SHIFT+${def.keyCap} BUYS ONE FOR ${fmt(price)} SIG',
      onTap: () {
        tools.runtime.audio.init();
        tools.runtime.audio.resume();
        // An empty chip is useless; clicking one obviously means "restock it".
        if (have <= 0) {
          tools.buy(def.id);
        } else {
          tools.fire(def.id);
        }
      },
      builder: (_, hover, pressed) => Transform.translate(
        offset: Offset(0, pressed ? 1 : 0),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                flash > 0
                    ? Color.lerp(K.keyTop, K.keyGoodTop, flash)!
                    : (hover ? UX.keyHoverTop : K.keyTop),
                flash > 0
                    ? Color.lerp(K.keyBot, K.keyGoodBot, flash)!
                    : (hover ? UX.keyHoverBot : K.keyBot),
              ],
            ),
            border: Border(
              top: BorderSide(color: hot || busy ? edge : UX.keyTopEdge),
              left: BorderSide(color: edge),
              right: BorderSide(color: edge),
              bottom: BorderSide(color: edge),
            ),
            boxShadow: <BoxShadow>[
              const BoxShadow(color: UX.keyShadow, offset: Offset(0, 1)),
              if (pulse > 0)
                BoxShadow(
                  color: (busy ? edge : K.amber).withValues(alpha: 0.28 * pulse),
                  blurRadius: 10,
                ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            children: <Widget>[
              _cap(t, hot || busy),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: t.at(11.5, labelInk, ls: 1),
                ),
              ),
              const SizedBox(width: 3),
              if (have > 0)
                _pips(have)
              else
                Text(
                  fmt(price),
                  maxLines: 1,
                  softWrap: false,
                  style: t.at(10.5, afford ? K.amber : K.lostDim, ls: 0.5),
                ),
              const SizedBox(width: 3),
              _buy(t, full, afford),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cap(Sty t, bool lit) => Container(
        width: _kCapW,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: K.black,
          border: Border.all(color: lit ? K.amberDim : K.edge),
        ),
        child: Text(
          def.keyCap,
          maxLines: 1,
          softWrap: false,
          style: t.at(11, lit ? K.amber : K.keySub, ls: 0),
        ),
      );

  Widget _pips(int have) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (var i = 0; i < def.cap; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: i < have ? K.amber : K.black,
                border: Border.all(color: i < have ? K.amber : K.edge),
              ),
            ),
          ],
        ],
      );

  Widget _buy(Sty t, bool full, bool afford) => Pressable(
        enabled: !full,
        onTap: () {
          tools.runtime.audio.init();
          tools.runtime.audio.resume();
          tools.buy(def.id);
        },
        builder: (_, hover, pressed) => Container(
          width: _kBuyW,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hover && !full ? UX.bigBtnHover : K.black,
            border: Border.all(
                color: full
                    ? K.edge
                    : (afford ? UX.bigBtnBorder : K.itemBorder)),
          ),
          child: Transform.translate(
            offset: Offset(0, pressed ? 1 : 0),
            child: Text(
              full ? '·' : '+',
              maxLines: 1,
              softWrap: false,
              style: t.at(
                  10,
                  full
                      ? K.keySub
                      : (afford ? K.amber : K.lostDim),
                  ls: 0),
            ),
          ),
        ),
      );
}
