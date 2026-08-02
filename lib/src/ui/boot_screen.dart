// FINAL BROADCAST — the sign-on screen (#boot).
//
// Always shown at startup, returning operator or not: pressing SIGN ON is what
// unlocks the browser's audio context. Type here is deliberately NOT scaled by
// the TEXT SIZE setting — the CSS wrote these as plain px.

import 'package:flutter/widgets.dart';

import '../consts.dart';
import 'ui_kit.dart';

class BootScreen extends StatelessWidget {
  const BootScreen({super.key, required this.onSignOn});

  final VoidCallback onSignOn;

  @override
  Widget build(BuildContext context) {
    const t = Sty(1);
    final em = t.fixed(12, K.ink, h: 2);
    return ColoredBox(
        color: K.black,
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(kBootStationLine,
                  textAlign: TextAlign.center,
                  style: t.fixed(11, K.bootSig, ls: 8)),
              const SizedBox(height: 22),
              Text(
                kBootTitle,
                textAlign: TextAlign.center,
                style: t.fixed(44, K.bootTitle, ls: 14, sh: const <Shadow>[
                  Shadow(color: Color(0x5957E6FF), blurRadius: 24),
                  Shadow(color: Color(0x59FF003C), offset: Offset(3, 0)),
                  Shadow(color: Color(0x4D00C8FF), offset: Offset(-3, 0)),
                ]),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 640,
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: t.fixed(12, K.bootBody, h: 2),
                    children: _emphasise(
                      kBootBody1,
                      'something gets into the feed',
                      em,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 640,
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: t.fixed(11, UX.bootBody2, h: 2),
                    children: <InlineSpan>[
                      TextSpan(text: '$kBootBody2a\n'),
                      ..._emphasise(kBootBody2b, 'Press M any time.',
                          t.fixed(11, K.ink, h: 2)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Pressable(
                onTap: onSignOn,
                builder: (_, hover, _) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 44, vertical: 16),
                  decoration: BoxDecoration(
                    color: hover ? UX.bootBtnHover : UX.bootBtnBg,
                    border: Border.all(color: UX.bootBtnBorder),
                    boxShadow: hover
                        ? <BoxShadow>[
                            BoxShadow(
                                color: K.green.withValues(alpha: 0.28),
                                blurRadius: 26),
                          ]
                        : null,
                  ),
                  child:
                      Text('SIGN ON', style: t.fixed(14, K.green, ls: 6)),
                ),
              ),
              const SizedBox(height: 22),
              Text(kBootFine,
                  textAlign: TextAlign.center,
                  style: t.fixed(9, K.bootFine, ls: 2)),
            ],
          ),
        ));
  }

  /// `<em>` inside the boot copy — the same text, one shade brighter.
  static List<InlineSpan> _emphasise(
      String text, String phrase, TextStyle emStyle) {
    final i = text.indexOf(phrase);
    if (i < 0) return <InlineSpan>[TextSpan(text: text)];
    return <InlineSpan>[
      TextSpan(text: text.substring(0, i)),
      TextSpan(text: phrase, style: emStyle),
      TextSpan(text: text.substring(i + phrase.length)),
    ];
  }
}

/// #rot — only nags when rotating actually helps.
class RotateNag extends StatelessWidget {
  const RotateNag({super.key});

  @override
  Widget build(BuildContext context) {
    const t = Sty(1);
    return ColoredBox(
      color: K.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(kRotateNag,
                  textAlign: TextAlign.center,
                  style: t.fixed(15, K.bootBody, ls: 3, h: 2)),
              Text(kRotateSub,
                  textAlign: TextAlign.center,
                  style: t.fixed(10, UX.rotSub, ls: 3, h: 2)),
            ],
          ),
        ),
      ),
    );
  }
}
