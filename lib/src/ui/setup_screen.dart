// FINAL BROADCAST — HARDWARE CHECK.
//
// This game is an audio game wearing a picture. The tells that matter — a drone
// creeping in on one side, the room tone thinning, a heartbeat that starts
// before you have consciously noticed anything — are inaudible on a laptop
// speaker and invisible on mute. Played that way it IS just a static screen.
//
// So the station checks the gear before it hands you the shift: line up the
// stereo field, set a level you can actually hear the floor at, and confirm the
// screen is the right shape. It is diegetic — an engineer's line-up card, not a
// settings dialog — and it is skippable, because a wall between a player and
// the game is worse than a bad mix.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../consts.dart';
import '../state.dart';
import 'ui_kit.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.s,
    required this.runtime,
    required this.onDone,
  });

  final GameState s;
  final AnomalyRuntime runtime;
  final VoidCallback onDone;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _heard = 0; // bitmask: 1 = left, 2 = right, 4 = floor
  bool _tested = false;

  GameState get s => widget.s;
  AnomalyRuntime get r => widget.runtime;

  void _ping(double pan, int bit, String label) {
    r.audio.init();
    r.audio.resume();
    r.audio.setVol(s.sfx);
    r.audio.pan(pan);
    r.audio.env('sine', pan < 0 ? 420 : 560, 0.55, 0.16, pan < 0 ? 300 : 400);
    setState(() {
      _heard |= bit;
      _tested = true;
    });
  }

  /// The floor test: the quietest thing the game ever asks you to notice.
  /// If you cannot hear this, you cannot play the game as designed.
  void _floor() {
    r.audio.init();
    r.audio.resume();
    r.audio.setVol(s.sfx);
    r.audio.pan(0);
    r.audio.setDrone(0.11, 34);
    Future<void>.delayed(const Duration(milliseconds: 2200), () {
      r.audio.setDrone(0, 42);
    });
    setState(() {
      _heard |= 4;
      _tested = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final bool full = _heard == 7;

    return ColoredBox(
      color: K.black,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 26),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text('LINE-UP CARD', style: t.at(13, K.bootSig, ls: 9)),
            const SizedBox(height: 8),
            Text('HARDWARE CHECK',
                style: t.at(30, K.ink, ls: 10, w: FontWeight.bold)),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 700),
              child: Text(
                'This is an audio game with a picture on it. Half of what warns '
                'you arrives in one ear before it arrives on the tube.\n'
                'On a laptop speaker, or on mute, you are just watching static.',
                textAlign: TextAlign.center,
                style: t.at(13, K.bootBody, h: 1.9),
              ),
            ),
            const SizedBox(height: 22),

            // --- the stereo field ---
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _Check(
                  ui: s.ui,
                  label: 'LEFT',
                  sub: 'PLAY TONE',
                  done: _heard & 1 != 0,
                  onTap: () => _ping(-1, 1, 'LEFT'),
                ),
                const SizedBox(width: 12),
                _Check(
                  ui: s.ui,
                  label: 'RIGHT',
                  sub: 'PLAY TONE',
                  done: _heard & 2 != 0,
                  onTap: () => _ping(1, 2, 'RIGHT'),
                ),
                const SizedBox(width: 12),
                _Check(
                  ui: s.ui,
                  label: 'THE FLOOR',
                  sub: 'QUIETEST CUE',
                  done: _heard & 4 != 0,
                  onTap: _floor,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              _heard == 0
                  ? 'Put headphones on, then play all three.'
                  : full
                      ? 'If the third one was audible, your level is right.'
                      : 'Play the rest.',
              style: t.at(11.5, full ? K.green : K.lbl, ls: 1.5),
            ),
            const SizedBox(height: 20),

            // --- level ---
            SizedBox(
              width: 520,
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text('MONITOR LEVEL', style: t.at(11, K.lbl, ls: 2.5)),
                      Text('${(s.sfx * 100).round()}%',
                          style: t.at(12, K.amber, ls: 1)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _Slider(
                    value: s.sfx,
                    onChanged: (v) {
                      setState(() => s.sfx = v);
                      r.audio.setVol(v);
                    },
                    onDone: () {
                      r.audio.pan(0);
                      r.audio.env('sine', 660, 0.2, 0.14, 660);
                      s.save();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            _Advice(ui: s.ui),
            const SizedBox(height: 22),

            Pressable(
              onTap: () {
                r.audio.pan(0);
                s.hardwareChecked = true;
                s.save();
                widget.onDone();
              },
              builder: (_, hover, _) => Container(
                width: 420,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: hover
                      ? const Color(0xFF0E2A18)
                      : const Color(0xFF0A1A10),
                  border: Border.all(
                      color: _tested ? K.green : K.greenDim, width: 2),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(_tested ? 'LINED UP — CONTINUE' : 'SKIP THE CHECK',
                        textAlign: TextAlign.center,
                        style:
                            t.at(15, K.green, ls: 5, w: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(
                        _tested
                            ? 'YOU CAN RUN IT AGAIN FROM THE STATION TAB'
                            : 'THE GAME WILL BE HARDER TO READ',
                        style: t.at(9.5, K.greenDim, ls: 2)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.ui,
    required this.label,
    required this.sub,
    required this.done,
    required this.onTap,
  });

  final double ui;
  final String label;
  final String sub;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, _) => Container(
        width: 165,
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: done ? const Color(0xFF08210F) : const Color(0xFF0C1112),
          border: Border.all(
              color: done ? K.greenDim : (hover ? K.edge : UX.tabDivider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(done ? '$label  OK' : label,
                style: t.at(13, done ? K.green : K.ink, ls: 2.5)),
            const SizedBox(height: 2),
            Text(sub, style: t.at(9, K.lbl, ls: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// A slider with no Material dependency, so it matches the cabinet.
class _Slider extends StatelessWidget {
  const _Slider(
      {required this.value, required this.onChanged, required this.onDone});

  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints box) {
        void setFrom(double dx) =>
            onChanged((dx / box.maxWidth).clamp(0.0, 1.0));
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => setFrom(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => setFrom(d.localPosition.dx),
          onHorizontalDragEnd: (_) => onDone(),
          onTapUp: (_) => onDone(),
          child: SizedBox(
            height: 22,
            child: CustomPaint(
              painter: _SliderPainter(value),
              size: Size(box.maxWidth, 22),
            ),
          ),
        );
      },
    );
  }
}

class _SliderPainter extends CustomPainter {
  _SliderPainter(this.v);
  final double v;

  @override
  void paint(Canvas c, Size z) {
    final double y = z.height / 2;
    c.drawRect(Rect.fromLTWH(0, y - 3, z.width, 6),
        Paint()..color = const Color(0xFF160C0C));
    c.drawRect(Rect.fromLTWH(0, y - 3, z.width * v, 6),
        Paint()..color = K.amber);
    // tick marks, so a level is a position rather than a feeling
    for (var i = 0; i <= 10; i++) {
      final double x = z.width * (i / 10);
      c.drawRect(Rect.fromLTWH(x - 0.5, y + 5, 1, i % 5 == 0 ? 5 : 3),
          Paint()..color = const Color(0xFF3A4A4C));
    }
    c.drawRect(Rect.fromLTWH(z.width * v - 2, y - 9, 4, 18),
        Paint()..color = K.ink);
  }

  @override
  bool shouldRepaint(covariant _SliderPainter old) => old.v != v;
}

/// The two things that most often make this game unreadable, stated plainly.
class _Advice extends StatelessWidget {
  const _Advice({required this.ui});
  final double ui;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final h = MediaQuery.of(context).size.height;
    final bool wide = w / math.max(1, h) >= 1.5;
    return Column(
      children: <Widget>[
        _Line(
          ui: ui,
          ok: true,
          k: 'HEADPHONES',
          v: 'Strongly recommended. The stereo field is a game mechanic here, '
              'not decoration.',
        ),
        _Line(
          ui: ui,
          ok: wide,
          k: 'SCREEN',
          v: wide
              ? 'Widescreen detected — the meters and counters will all fit.'
              : 'This is a widescreen console. Turn the device, or widen the '
                  'window, or the meters will be cramped.',
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(
      {required this.ui, required this.ok, required this.k, required this.v});
  final double ui;
  final bool ok;
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 130,
              child: Text(k,
                  textAlign: TextAlign.right,
                  style: t.at(11, ok ? K.green : K.amber, ls: 2)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(v, style: t.at(11.5, K.bootBody, h: 1.6)),
            ),
          ],
        ),
      ),
    );
  }
}
