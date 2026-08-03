// FINAL BROADCAST — THE HOME SCREEN.
//
// The boot screen was a one-shot splash: a title, three lines of prose and a
// button. It told a first-time player nothing they could act on and told a
// returning player nothing at all — no night count, no record, no way back to
// the manual, no sense that anything had happened before.
//
// This is the station's front desk. It is the same screen on night 1 and night
// 40, but it reads completely differently on each, because it is the one place
// the career is actually visible.

import 'package:flutter/widgets.dart';

import '../consts.dart';
import '../meta.dart';
import '../career.dart';
import '../nights.dart';
import '../story.dart';
import '../state.dart';
import 'ui_kit.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.s,
    required this.onSignOn,
    required this.onManual,
    required this.onSetup,
  });

  final GameState s;
  final VoidCallback onSignOn;
  final VoidCallback onManual;
  final VoidCallback onSetup;

  bool get _returning => s.started && (s.night > 1 || s.survived > 0);

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final logged = s.seen.values.where((v) => v).length;

    return ColoredBox(
      color: K.black,
      child: Stack(
        children: <Widget>[
          // the station's own vignette, so the screen is part of the room
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 0.95,
                  colors: <Color>[Color(0xFF0A0C0D), Color(0xFF000000)],
                ),
              ),
            ),
          ),
          // MUST be Positioned.fill, not a bare child. A Stack hands its
          // non-positioned children LOOSE constraints, so this Padding
          // shrink-wrapped the Column and the Stack pinned the result to its
          // top-LEFT: measured 1190.5 wide inside a 1280 cabinet, with the
          // wordmark sitting 45px left of centre and the whole desk riding
          // high. mainAxisAlignment.center was a no-op for the same reason —
          // an unbounded Column has no spare height to centre within.
          Positioned.fill(
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 26),
            // SCROLLS, and shrinks to fit before it does.
            //
            // Adding the rank, the standing line, the next-rung bar and the
            // "THEN:" payoff overflowed a 1280x720 cabinet by 96px — caught by
            // a widget test before it shipped, which is exactly the class of
            // layout regression that has bitten this screen twice now. The
            // FittedBox scales the whole desk down rather than clipping it,
            // and the scroll view is the backstop at 180% TEXT SIZE.
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) =>
                  SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: box.maxWidth,
                      child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(kBootStationLine,
                    textAlign: TextAlign.center,
                    style: t.at(11, K.bootSig, ls: 8)),
                const SizedBox(height: 14),
                _Title(ui: s.ui),
                const SizedBox(height: 18),

                // WHO YOU ARE. On night one this is a promise; later it is a record.
                if (_returning)
                  _Ledger(s: s, logged: logged)
                else
                  _Brief(ui: s.ui),

                const SizedBox(height: 16),
                // TONIGHT'S CARD. The answer to "night 6 is night 1 with
                // bigger numbers": every night after the first has a name and
                // a shape, and you know both before you sign on.
                if (s.night > 1) _Card(ui: s.ui, night: s.night),
                if (s.night > 1) const SizedBox(height: 16),
                if (s.night <= 1) const SizedBox(height: 6),
                _Big(
                  ui: s.ui,
                  label: _returning ? 'TAKE THE NIGHT SHIFT' : 'SIGN ON',
                  sub: _returning
                      ? 'NIGHT ${s.night}'
                      : 'YOUR FIRST SHIFT',
                  onTap: onSignOn,
                ),
                const SizedBox(height: 10),
                _Secondary(
                  ui: s.ui,
                  label: "OPERATOR'S MANUAL",
                  sub: _returning
                      ? '$logged OF ${kAnoms.length} CATALOGUED  ·  KEY M'
                      : 'READ IT FIRST  ·  KEY M',
                  onTap: onManual,
                ),
                const SizedBox(height: 8),
                _Tertiary(
                  ui: s.ui,
                  label: 'AUDIO / SCREEN CHECK',
                  onTap: onSetup,
                ),
                const SizedBox(height: 16),
                Text(
                  _returning
                      ? 'The eight keys under the tube are the only thing that '
                          'has ever worked.'
                      : 'Eight things live in the signal. '
                          'Each one dies to exactly one button.',
                  textAlign: TextAlign.center,
                  style: t.at(12, K.bootBody, h: 1.9),
                ),
                const SizedBox(height: 10),
                Text(kBootFine,
                    textAlign: TextAlign.center,
                    style: t.at(9, K.bootFine, ls: 2)),
              ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The wordmark, with the CRT's chromatic split.
class _Title extends StatelessWidget {
  const _Title({required this.ui});
  final double ui;

  @override
  Widget build(BuildContext context) {
    const txt = 'FINAL BROADCAST';
    // condensed broadcast signage — the wordmark was set in the same face as
    // the keycaps, so the title had no more weight than a meter label
    TextStyle st(Color c) =>
        display(46 * ui, c, letterSpacing: 10, weight: FontWeight.w700);
    return SizedBox(
      height: 58,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Transform.translate(
            offset: const Offset(-3, 0),
            child: Text(txt, style: st(const Color(0x59FF003C))),
          ),
          Transform.translate(
            offset: const Offset(3, 0),
            child: Text(txt, style: st(const Color(0x4D00C8FF))),
          ),
          Text(txt,
              style: st(K.bootTitle).copyWith(
                  shadows: glow(const Color(0xFF57E6FF), 24, 0.35))),
        ],
      ),
    );
  }
}

/// First-run: what the job is.
class _Brief extends StatelessWidget {
  const _Brief({required this.ui});
  final double ui;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Column(
        children: <Widget>[
          // THE COLD OPEN. Three lines, before anything else, because a
          // player who does not know WHY the carrier matters is playing a
          // spreadsheet with a skull on it.
          for (final l in kColdOpen)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(l,
                  textAlign: TextAlign.center,
                  style: t.at(13, K.bootBody, h: 1.75)),
            ),
          const SizedBox(height: 14),
          _RuleRow(ui: ui, k: 'STRIKE THE TUBE', v: 'to put signal out by hand'),
          _RuleRow(ui: ui, k: 'KEYS 1-8', v: 'each banishes exactly one thing'),
          _RuleRow(ui: ui, k: 'DREAD 100', v: 'and it comes out here instead'),
        ],
      ),
    );
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({required this.ui, required this.k, required this.v});
  final double ui;
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 190,
            child: Text(k,
                textAlign: TextAlign.right,
                style: t.at(12, K.amber, ls: 2, w: FontWeight.bold)),
          ),
          const SizedBox(width: 14),
          Text(v, style: t.at(12, K.bootBody)),
        ],
      ),
    );
  }
}

/// Returning: the record. This is the only place the career is legible.
class _Ledger extends StatelessWidget {
  const _Ledger({required this.s, required this.logged});
  final GameState s;
  final int logged;

  @override
  Widget build(BuildContext context) {
    final held = kStationNodes
        .where((n) => metaLevel(s, n.id) > 0)
        .map((n) => n.nm)
        .toList();
    return Column(
      children: <Widget>[
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 26,
          runSpacing: 8,
          children: <Widget>[
            _Stat(ui: s.ui, k: 'NIGHTS SURVIVED', v: '${s.survived}'),
            _Stat(ui: s.ui, k: 'BANISHED', v: fmt(s.stats.banished)),
            _Stat(ui: s.ui, k: 'BEST STREAK', v: '${s.stats.bestStreak}'),
            _Stat(ui: s.ui, k: 'CATALOGUED', v: '$logged/${kAnoms.length}'),
            _Stat(ui: s.ui, k: 'RATINGS PTS', v: fmt(s.rp), amber: true),
          ],
        ),
        // THE SPINE. Rank, standing, and the next name on the roster with a
        // bar that always starts empty and always fills — a bar stuck at 94%
        // for six nights tells the player nothing, so it measures from the
        // PREVIOUS rung rather than from zero.
        const SizedBox(height: 14),
        Text(rankOf(s),
            textAlign: TextAlign.center,
            style: display(20 * s.ui, K.ink, letterSpacing: 6)),
        const SizedBox(height: 2),
        Text(standingLine(s),
            textAlign: TextAlign.center,
            style: Sty(s.ui).at(9.5, K.lbl, ls: 2)),
        const SizedBox(height: 12),
        _NextRung(s: s),
        if (held.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Text(
              'ON THE BOOKS:  ${held.join('  ·  ')}',
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Sty(s.ui).at(10.5, K.greenDim, ls: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.ui, required this.k, required this.v, this.amber = false});
  final double ui;
  final String k;
  final String v;
  final bool amber;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(v,
            style: t.at(24, amber ? K.amber : K.green,
                ls: 1, w: FontWeight.bold)),
        Text(k, style: t.at(9.5, K.lbl, ls: 2)),
      ],
    );
  }
}

class _Big extends StatelessWidget {
  const _Big(
      {required this.ui,
      required this.label,
      required this.sub,
      required this.onTap});
  final double ui;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, pressed) => Container(
        width: 420,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: hover ? const Color(0xFF0E2A18) : const Color(0xFF0A1A10),
          border: Border.all(color: hover ? K.green : K.greenDim, width: 2),
          boxShadow: hover
              ? <BoxShadow>[
                  const BoxShadow(color: Color(0x476DFF9A), blurRadius: 26)
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label,
                textAlign: TextAlign.center,
                style: t.at(16, K.green, ls: 6, w: FontWeight.bold)),
            const SizedBox(height: 3),
            Text(sub, style: t.at(10, K.greenDim, ls: 3)),
          ],
        ),
      ),
    );
  }
}

class _Secondary extends StatelessWidget {
  const _Secondary(
      {required this.ui,
      required this.label,
      required this.sub,
      required this.onTap});
  final double ui;
  final String label;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, pressed) => Container(
        width: 420,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: hover ? const Color(0xFF1A1206) : const Color(0xFF120D05),
          border: Border.all(color: hover ? K.amber : K.amberDim),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(label, style: t.at(12.5, K.amber, ls: 3)),
            const SizedBox(height: 2),
            Text(sub, style: t.at(9.5, K.skeySub, ls: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// A quiet third option. The hardware check has to be reachable forever —
/// people plug headphones in halfway through a session.
class _Tertiary extends StatelessWidget {
  const _Tertiary({required this.ui, required this.label, required this.onTap});
  final double ui;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
        child: Text(label,
            style: t.at(10, hover ? K.ink : K.lbl, ls: 2.5)),
      ),
    );
  }
}

/// Tonight's standing conditions, on the front desk.
class _Card extends StatelessWidget {
  const _Card({required this.ui, required this.night});
  final double ui;
  final int night;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    final c = cardForNight(night);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 660),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
        decoration: BoxDecoration(
          color: const Color(0xFF120D05),
          border: Border.all(color: K.amberDim),
        ),
        child: Column(
          children: <Widget>[
            Text('TONIGHT', style: t.at(9, K.lbl, ls: 4)),
            const SizedBox(height: 4),
            Text(c.nm,
                textAlign: TextAlign.center,
                style: t.at(17, K.amber, ls: 4, w: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(c.ds,
                textAlign: TextAlign.center,
                style: t.at(11.5, K.bootBody, h: 1.7)),
          ],
        ),
      ),
    );
  }
}

/// The next name on the roster, with a distance and a bar. This is the single
/// most important element on the front desk: it is the answer to "what am I
/// working toward", and it is never absent — when the roster runs out the file
/// is still being assembled, and when that runs out you are told so.
class _NextRung extends StatelessWidget {
  const _NextRung({required this.s});
  final GameState s;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final g = nearestGoal(s);
    if (g == null) {
      return Text('THE FILE IS COMPLETE AND THE ROSTER IS SPENT.',
          textAlign: TextAlign.center, style: t.at(11, K.amber, ls: 2));
    }
    final next = nextOnRoster(s);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        children: <Widget>[
          // Flexible, not fixed: at 180% TEXT SIZE a fixed Row overflowed by
          // 191px to the right. The name gives way before the distance does —
          // "4 MORE NIGHTS" is the actionable half.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Flexible(
                child: Text(g.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.at(12, K.amber, ls: 2.5)),
              ),
              const SizedBox(width: 10),
              Text(g.detail,
                  maxLines: 1,
                  softWrap: false,
                  style: t.at(11, K.greenDim, ls: 1.5)),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 7,
            width: double.infinity,
            child: CustomPaint(painter: _RungBar(g.progress)),
          ),
          if (next != null && next.unlock != null) ...<Widget>[
            const SizedBox(height: 7),
            Text('THEN: ${next.unlock!}',
                textAlign: TextAlign.center,
                style: t.at(10, K.bootBody, h: 1.5)),
          ],
        ],
      ),
    );
  }
}

class _RungBar extends CustomPainter {
  _RungBar(this.v);
  final double v;

  @override
  void paint(Canvas g, Size z) {
    g.drawRect(Offset.zero & z, Paint()..color = const Color(0xFF14191B));
    g.drawRect(Rect.fromLTWH(0, 0, z.width * v.clamp(0.0, 1.0), z.height),
        Paint()..color = K.amber);
    g.drawRect(
      Offset.zero & z,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF2A3235),
    );
  }

  @override
  bool shouldRepaint(covariant _RungBar o) => o.v != v;
}
