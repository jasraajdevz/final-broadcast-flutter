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
import '../story.dart';
import 'ui_kit.dart';

class LogSheet extends StatelessWidget {
  const LogSheet({
    super.key,
    required this.s,
    required this.page,
    required this.onDone,
  });

  final GameState s;
  final LogPage page;
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
              child: Text(page.head,
                  style: t.at(11, const Color(0xFFC9B98A), ls: 2)),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(page.body,
                        style: t.at(15, const Color(0xFFD8CDAC), h: 1.95)),
                    const SizedBox(height: 20),
                    Text(
                      '— found in the desk, night ${page.night}',
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
