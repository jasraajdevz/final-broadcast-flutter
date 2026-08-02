// FINAL BROADCAST — the AUTO tab of the equipment rack.
//
// Same furniture as the TRANSMIT / HARDWARE tabs: `.hd` heads, `.item` rows,
// the whole ladder always shown with locked machines greyed out, because
// hiding them hides the game. Each row adds two things a producer row does not
// have — the line that tells you HOW IT FAILS as the night turns, and a power
// switch, because a bot that spends your bank has to be something you can shut
// off.
//
// The rack's `_body()` calls [botsRackRows]; [BotsPanel] is the same rows in a
// standalone Column for anywhere else that wants them.

import 'package:flutter/material.dart';

import '../anomalies.dart';
import '../bots.dart';
import '../consts.dart';
import '../state.dart';
import 'ui_kit.dart';

/// The AUTO tab's rows, ready to drop into the rack's ListView.
List<Widget> botsRackRows(GameState s, AnomalyRuntime runtime) {
  final bots = BotRuntime.of(s, runtime);
  final t = Sty(s.ui);
  final out = <Widget>[
    RackHead('AUTOMATION RACK  ·  BOUGHT WITH SIGNAL', ui: s.ui),
    Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 6),
      child: Text(
        'Nine people used to work this shift. These are the machines that were '
        'left doing their jobs. Every one of them is worse at it than you are, '
        'and every one of them starts making mistakes as the dread comes up.',
        style: t.at(13, K.noteInk, h: 1.5),
      ),
    ),
    // RIG DEPTH, stated once at the top, because a ceiling the player cannot
    // see is indistinguishable from a bug.
    Padding(
      padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
      child: RichText(
        text: TextSpan(
          style: t.at(13, K.noteInk, h: 1.5),
          children: <InlineSpan>[
            TextSpan(
                text: 'RIG DEPTH ${rigDepth(s)}',
                style: t.at(13, K.amber, h: 1.5, w: FontWeight.bold)),
            TextSpan(
              text: '  —  the three machines that could work the desk without '
                  'you (${_deepNames()}) will not rig deeper than this '
                  'tonight, however rich you are. Depth is bought with nights '
                  'you took all the way to 06:00, and with ratings.',
            ),
          ],
        ),
      ),
    ),
  ];

  for (final b in kBots) {
    out.add(_BotRow(s: s, runtime: runtime, bots: bots, def: b));
  }

  out.add(RackHead('NOTES', ui: s.ui));
  out.add(Padding(
    padding: const EdgeInsets.only(left: 2, right: 2, bottom: 10),
    child: RichText(
      text: TextSpan(
        style: t.at(13, K.noteInk, h: 1.5),
        children: <InlineSpan>[
          const TextSpan(
              text: 'Automation is bolted in. It survives sign-off — the '
                  'transmitters do not.\n\n'),
          TextSpan(
              text: 'THE KEYING ARM',
              style: t.at(13, K.itemStat, h: 1.5, w: FontWeight.bold)),
          const TextSpan(
              text: ' pays into the bank only. It cannot make a quota and it '
                  'cannot earn you ratings points — striking the tube never '
                  'could.\n\n'),
          TextSpan(
              text: 'THE LIBRARIAN',
              style: t.at(13, K.itemStat, h: 1.5, w: FontWeight.bold)),
          TextSpan(
              text: ' has ${bots.beatenCount} of ${kAnoms.length} tapes. It '
                  'only files something after YOU have banished it, it waits '
                  'until the window is half gone, and it will not touch '
                  'anything still wearing a mask.\n\n'),
          const TextSpan(
              text: 'No machine in this rack can press a wrong key for you. '
                  'When they fail, they fail by doing nothing.'),
        ],
      ),
    ),
  ));
  out.add(RackHead('RACK LOG  ·  TONIGHT', ui: s.ui));
  out.add(Padding(
    padding: const EdgeInsets.only(left: 2, right: 2, bottom: 12),
    child: Text(bots.tally(), style: t.at(12, K.itemStat, h: 1.6)),
  ));

  return out;
}

String _deepNames() =>
    kBots.where((b) => b.deep).map((b) => b.nm).join(', ');

/// The AUTO tab as a standalone scrollable panel.
class BotsPanel extends StatelessWidget {
  const BotsPanel({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(8),
      children: botsRackRows(s, runtime),
    );
  }
}

// ---------------------------------------------------------------------------
// One machine
// ---------------------------------------------------------------------------

class _BotRow extends StatelessWidget {
  const _BotRow({
    required this.s,
    required this.runtime,
    required this.bots,
    required this.def,
  });

  final GameState s;
  final AnomalyRuntime runtime;
  final BotRuntime bots;
  final BotDef def;

  void _buy() {
    runtime.audio.init();
    if (!bots.buy(def)) {
      runtime.audio.env('square', 180, 0.08, 0.07, 140);
      s.bump();
      return;
    }
    runtime.audio.buy();
    final lvl = bots.levelOf(def);
    s.toast(
        lvl == 1
            ? 'PATCHED IN — ${def.nm}'
            : 'RE-RIGGED — ${def.nm} LVL $lvl',
        ToastKind.good);
  }

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final lvl = bots.levelOf(def);
    final unlocked = bots.unlocked(def);
    final maxed = bots.maxed(def);
    // Rigged as deep as tonight allows, but the machine has levels left. Reads
    // as "come back tomorrow", not as "finished".
    final capped = !maxed && bots.atRigCap(def);
    final cost = bots.costFor(def);
    final afford = unlocked && !maxed && !capped && s.sig >= cost;
    final on = bots.enabled(def);
    final running = lvl > 0 && on;

    final String costText = !unlocked
        ? 'SEALED'
        : (maxed ? 'RIGGED' : (capped ? 'RIG LIMIT' : fmt(cost)));

    // The line you own, and the line you would be buying.
    final String? nowLine =
        lvl > 0 ? 'LVL $lvl  ·  ${bots.effectAt(def, lvl)}' : null;
    final String? nextLine = (maxed || capped)
        ? null
        : 'LVL ${lvl + 1}  ·  ${bots.effectAt(def, lvl + 1)}';
    final String? rigNote = bots.rigNoteOf(def);
    final String? risk = bots.riskOf(def);
    final String status = bots.statusOf(def);

    final VoidCallback? onTap = (!unlocked || maxed || capped) ? null : _buy;

    final Widget row = Pressable(
      onTap: onTap,
      cursor:
          onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (_, hover, _) {
        final Color border = maxed
            ? K.itemOwned
            : (afford
                ? (hover ? K.greenDim : K.itemAfford)
                : (hover ? UX.itemHoverBorder : K.itemBorder));
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          decoration: vgrad(
            hover && onTap != null ? UX.itemHoverTop : K.itemTop,
            hover && onTap != null ? UX.itemHoverBot : K.itemBot,
            border: Border.all(color: border),
          ),
          child: Stack(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // --- name / cost ---
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: t.at(16, K.itemName, ls: 0.5),
                              children: <InlineSpan>[
                                TextSpan(text: def.nm),
                                if (lvl > 0 && !on)
                                  TextSpan(
                                    text: ' ## POWERED DOWN',
                                    style: t.at(16, UX.offAir, ls: 0.5),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            costText,
                            maxLines: 1,
                            softWrap: false,
                            style: t.at(
                                15,
                                !unlocked
                                    ? K.manUnk
                                    : (maxed || capped
                                        ? K.itemStat
                                        : (afford ? K.green : K.amber))),
                          ),
                        ),
                      ],
                    ),

                    // --- fiction ---
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child:
                          Text(def.ds, style: t.at(13.5, K.itemDesc, h: 1.35)),
                    ),

                    // --- what it does now / what the next level does ---
                    if (nowLine != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(nowLine,
                            style: t.at(13, K.itemStat, h: 1.35)),
                      ),
                    if (nextLine != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          nowLine == null ? nextLine : '> $nextLine',
                          style: t.at(
                              13, nowLine == null ? K.itemStat : K.headInk,
                              h: 1.35),
                        ),
                      ),

                    // --- the ceiling tonight, when that is what is stopping you ---
                    if (rigNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(rigNote,
                            style: t.at(13, K.amber, h: 1.35)),
                      ),

                    // --- how it fails ---
                    if (risk != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('! $risk',
                            style: t.at(12, K.dreadLbl, h: 1.3)),
                      ),

                    // --- lock note, or the live line + power switch ---
                    if (!unlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text('SEALED — ${def.reqNote}',
                            style: t.at(12, K.manUnk, ls: 1)),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 6, right: 36),
                        child: Row(
                          children: <Widget>[
                            if (lvl > 0) ...<Widget>[
                              _Power(
                                ui: s.ui,
                                on: on,
                                onTap: () {
                                  runtime.audio.click();
                                  bots.setEnabled(def, !on);
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                status,
                                maxLines: 1,
                                softWrap: false,
                                style: t.at(
                                    12,
                                    running ? K.subGreen : K.headInk,
                                    ls: 1),
                              ),
                            ),
                            if (!maxed && !capped && !afford)
                              Text('${bots.percentToward(def)}%',
                                  maxLines: 1,
                                  softWrap: false,
                                  style: t.at(12, K.itemStat)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // --- level, bottom-right, exactly where the producer count is ---
              Positioned(
                right: 8,
                bottom: 6,
                child: Text(
                  lvl == 0 ? '·' : '$lvl/${def.maxLvl}',
                  style: t.at(lvl == 0 ? 20 : 15, K.itemQty),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (unlocked) return row;
    return Opacity(opacity: 0.42, child: row);
  }
}

/// The little station power switch on each patched machine.
class _Power extends StatelessWidget {
  const _Power({required this.ui, required this.on, required this.onTap});

  final double ui;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: on ? K.amber : K.black,
              border: Border.all(
                  color: hover ? K.amber : UX.bigBtnBorder),
            ),
          ),
          const SizedBox(width: 5),
          Text(on ? 'ON' : 'OFF',
              style: t.at(12, on ? K.amber : K.headInk, ls: 1)),
        ],
      ),
    );
  }
}
