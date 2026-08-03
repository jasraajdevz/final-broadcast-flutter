// FINAL BROADCAST — the SIGNAL LOST / 06:00 SIGN-OFF sheet (#lostSheet).
//
// The prose is not re-derived here: signalLost() and dawn() freeze it into
// runtime.endScreenModel at the moment the sheet opens, so the numbers on it
// cannot drift while the operator reads. Each paragraph's chunks alternate
// normal/bold starting normal.

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../consts.dart';
import '../state.dart';
import 'ui_kit.dart';

class EndSheet extends StatelessWidget {
  const EndSheet({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final m = runtime.endScreenModel;
    if (m == null) return const SizedBox.shrink();
    final t = Sty(s.ui);
    final win = m.win;

    final body = t.at(15, win ? K.winInk : K.lostInk, h: 1.75);
    final bold = body.copyWith(
        color: win ? K.green : K.lostBold, fontWeight: FontWeight.bold);
    final dim = t.at(15, K.lostDim, h: 1.75);
    final dimBold = dim.copyWith(
        color: win ? K.green : K.lostBold, fontWeight: FontWeight.bold);
    final fine = t.at(11, K.bootBody, h: 1.75);

    return ModalScrim(
      child: Container(
        width: kLostSheetW,
        // .sheet caps at 640; the copy scrolls if TEXT SIZE pushes past it.
        constraints: BoxConstraints(maxHeight: kSheetSize.height),
        decoration: vgrad(
          win ? UX.winTopA : UX.lostTopA,
          win ? UX.winTopB : UX.lostTopB,
          border: Border.all(
              color: win ? UX.bootBtnBorder : K.lostBorder, width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: win ? UX.winHeadBg : UX.lostHeadBg,
                border: Border(
                    bottom: BorderSide(
                        color: win ? UX.winHeadRule : UX.lostHeadRule)),
              ),
              child: Text(m.title,
                  style: t.at(17, win ? K.green : K.red, ls: 3)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var i = 0; i < m.body.length; i++) ...<Widget>[
                    if (i > 0) SizedBox(height: 15 * s.ui),
                    RichText(
                      text: alternating(
                        m.body[i].chunks,
                        switch (m.body[i].style) {
                          ParaStyle.body => body,
                          ParaStyle.dim => dim,
                          ParaStyle.fine => fine,
                        },
                        switch (m.body[i].style) {
                          ParaStyle.body => bold,
                          ParaStyle.dim => dimBold,
                          ParaStyle.fine => fine,
                        },
                      ),
                    ),
                  ],
                ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(26, 0, 26, 22),
              child: Row(
                children: <Widget>[
                  if (m.reviveLabel != null) ...<Widget>[
                    Expanded(
                      child: _EndBtn(
                        ui: s.ui,
                        label: m.reviveLabel!,
                        background: UX.reviveBg,
                        hoverBackground: UX.reviveHover,
                        border: UX.reviveBorder,
                        ink: K.amber,
                        onTap: () {
                          runtime.audio.init();
                          runtime.revive();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _EndBtn(
                      ui: s.ui,
                      label: m.acceptLabel,
                      background: win ? UX.winAcceptBg : UX.acceptBg,
                      hoverBackground: win ? UX.winAcceptBg : UX.acceptHover,
                      border: win ? UX.bootBtnBorder : K.lostBorder,
                      ink: win ? K.green : UX.acceptInk,
                      // straight back on air. Three acts between wanting
                      // another night and having one is where "one more"
                      // goes to die.
                      onTap: win ? runtime.signOffAndBack : runtime.signOff,
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

class _EndBtn extends StatelessWidget {
  const _EndBtn({
    required this.ui,
    required this.label,
    required this.background,
    required this.hoverBackground,
    required this.border,
    required this.ink,
    required this.onTap,
  });

  final double ui;
  final String label;
  final Color background;
  final Color hoverBackground;
  final Color border;
  final Color ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, _) => Container(
        padding: const EdgeInsets.all(14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hover ? hoverBackground : background,
          border: Border.all(color: border),
          boxShadow: hover
              ? <BoxShadow>[
                  BoxShadow(
                      color: ink.withValues(alpha: 0.25), blurRadius: 16),
                ]
              : null,
        ),
        child: Text(label,
            textAlign: TextAlign.center, style: t.at(14, ink, ls: 1.5)),
      ),
    );
  }
}
