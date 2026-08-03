// FINAL BROADCAST — A PAGE FROM THE DESK.
//
// The scariest thing a horror game owns is not the monster, it is the evidence
// that someone was here first and did everything right. R. HALLORAN held this
// chair for 1,114 nights. He was better at this than you are. There is one
// page a night and the last one is dated tonight.
//
// Shown between taking the shift and the shift starting, so it is read in the
// one moment the player is not being asked to do anything.

import 'package:flutter/widgets.dart';

import '../consts.dart';
import '../state.dart';
import '../archive.dart';
import 'ui_kit.dart';

class LogSheet extends StatelessWidget {
  const LogSheet({
    super.key,
    required this.s,
    required this.page,
    required this.night,
    required this.onDone,
  });

  final GameState s;
  final StationDoc page;
  final int night;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    return ModalScrim(
      child: Container(
        width: 620,
        constraints: BoxConstraints(maxHeight: kSheetSize.height),
        decoration: BoxDecoration(
          // paper, not a terminal — this is the one thing in the game that is
          // not made of light
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF17150F), Color(0xFF0E0D09)],
          ),
          border: Border.all(color: const Color(0xFF4A4230), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: const BoxDecoration(
                color: Color(0xFF221E14),
                border: Border(
                    bottom: BorderSide(color: Color(0xFF4A4230))),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(page.head,
                        maxLines: 2,
                        style: typed(12 * s.ui, const Color(0xFFC9B98A),
                            letterSpacing: 1.2)),
                  ),
                  const SizedBox(width: 10),
                  Text(page.kindLabel,
                      style: t.at(9, const Color(0xFF7A7055), ls: 2)),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // typed on a machine in 1974, not written by a HUD
                    Text(page.body,
                        style: typed(15 * s.ui, const Color(0xFFD8CDAC),
                            height: 1.85)),
                    if (page.sign != null) ...<Widget>[
                      const SizedBox(height: 14),
                      Text(page.sign!,
                          style: typed(13 * s.ui, const Color(0xFFB6A87E),
                              height: 1.6)),
                    ],
                    const SizedBox(height: 20),
                    Text(
                      '— recovered on night $night   ·   '
                      '${foundCount(s)} OF $archiveTotal',
                      textAlign: TextAlign.right,
                      style: t.at(10, const Color(0xFF7A7055), ls: 1.5),
                    ),
                  ],
                ),
              ),
            ),
            Pressable(
              onTap: onDone,
              builder: (_, hover, __) => Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  color: hover
                      ? const Color(0xFF2A2418)
                      : const Color(0xFF1C1810),
                  border: const Border(
                      top: BorderSide(color: Color(0xFF4A4230))),
                ),
                child: Text('PUT IT BACK IN THE DRAWER',
                    textAlign: TextAlign.center,
                    style: t.at(12, const Color(0xFFC9B98A), ls: 4)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
