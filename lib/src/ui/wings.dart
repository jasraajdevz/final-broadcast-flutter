// FINAL BROADCAST — THE WINGS.
//
// The cabinet is a fixed 1280x720 and every pixel of it is spoken for: booth,
// status strip, console, rack. On anything wider than 16:9 the leftover width
// was painted black and thrown away, which is the worst of both worlds — the
// console stays cramped AND the monitor is half empty.
//
// The wings are that width, used. They are not a second HUD: everything here
// is either something the cabinet had no room to show at all (the whole
// rundown, the loss conditions, the career) or something the cabinet shows in
// four characters and can afford to show properly out here (the meters).
//
// They render at the SAME logical scale as the cabinet, so type size matches,
// and they simply do not exist below a threshold width. Nothing load-bearing
// may ever live out here — a 16:9 player has to be playing the same game.

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../consts.dart';
import '../economy.dart';
import '../nights.dart';
import '../objective.dart';
import '../story.dart';
import '../state.dart';
import 'ui_kit.dart';

/// Below this logical width a wing is too narrow to say anything, so it is
/// not drawn at all.
const double kWingMin = 176;
const double kWingMax = 300;

/// LEFT WING — TRANSMISSION. The meters, at a size you can read from a chair.
class MeterWing extends StatelessWidget {
  const MeterWing({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final quota = segQuota(s);
    final met = quotaMet(s);
    final seg = segIndex(s);

    return _Panel(
      ui: s.ui,
      title: 'TRANSMISSION',
      children: <Widget>[
        _Big(
          ui: s.ui,
          v: '${fmt(sigRate(s, runtime))}/s',
          k: 'OUTPUT',
          c: K.green,
        ),
        const SizedBox(height: 2),
        _Big(ui: s.ui, v: fmt(s.sig), k: 'BANKED SIGNAL', c: K.ink),
        const SizedBox(height: 12),

        // --- this segment ---
        _Meter(
          ui: s.ui,
          label: 'SEGMENT QUOTA',
          value: quota <= 0 ? 1 : (s.segSig / quota).clamp(0.0, 1.0),
          right: met ? 'MET' : '${fmt(quotaShortfall(s))} SHORT',
          fill: met ? K.green : K.amber,
          warn: !met,
        ),
        const SizedBox(height: 10),

        // --- the carrier lock: the only meter the player drives by hand ---
        _Meter(
          ui: s.ui,
          label: s.tune.tier > 0 ? s.tune.tierName : 'CARRIER LOCK',
          value: s.tune.tier >= 4 ? 1.0 : s.tune.lockP.clamp(0.0, 1.0),
          right: s.tune.tier > 0
              ? 'x${s.tune.tierMult.toStringAsFixed(1)}'
              : 'STRIKE',
          fill: const Color(0xFF57E6FF),
        ),
        const SizedBox(height: 10),

        // THE BOOK. Drift is a continuous tax on a station nobody is tending,
        // and it is the only meter here the player fixes with a key rather
        // than with money.
        _Meter(
          ui: s.ui,
          label: runtime.checks.pending
              ? runtime.checks.active!.nm
              : 'THE BOOK',
          value: runtime.checks.pending
              ? runtime.checks.p
              : 1 - runtime.checks.drift.clamp(0.0, 1.0),
          right: runtime.checks.pending
              ? 'ENTER'
              : (runtime.checks.drift > 0.02
                  ? 'DRIFT ${(runtime.checks.drift * 100).round()}%'
                  : 'IN HAND'),
          fill: runtime.checks.pending
              ? const Color(0xFFFFC24A)
              : (runtime.checks.drift > 0.35 ? K.amber : K.greenDim),
          warn: runtime.checks.pending || runtime.checks.drift > 0.35,
        ),
        const SizedBox(height: 10),

        _Meter(
          ui: s.ui,
          label: 'DREAD',
          value: (s.dread / 100).clamp(0.0, 1.0),
          right: '${s.dread.round()}/100',
          fill: s.dread > 70
              ? const Color(0xFFFF3B2F)
              : (s.dread > 40 ? K.amber : const Color(0xFF8A3A3A)),
          warn: s.dread > 70,
        ),

        const SizedBox(height: 14),
        _Rule(),
        const SizedBox(height: 8),

        // --- THE RUNDOWN. The whole night, so it has a visible shape. The
        // cabinet only ever showed the segment you were standing in, which is
        // why night after night felt like the same minute repeated.
        Text('TONIGHT\'S RUNDOWN', style: t.at(9, K.lbl, ls: 2.5)),
        const SizedBox(height: 5),
        for (var i = 0; i < kRundown.length; i++)
          _SegRow(
            ui: s.ui,
            idx: i,
            nm: kRundown[i].nm,
            quota: quotaOf(s, i),
            state: i < seg
                ? _SegState.done
                : (i == seg ? _SegState.now : _SegState.ahead),
            met: i == seg ? met : null,
          ),
      ],
    );
  }
}

/// RIGHT WING — THE ORDER. Why you are here, and how this gets taken off you.
class OrderWing extends StatelessWidget {
  const OrderWing({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final d = primeDirective(s, runtime);
    final Color dc = switch (d.urgency) {
      Urgency.urgent => const Color(0xFFFF4A3A),
      Urgency.watch => K.amber,
      Urgency.calm => K.green,
    };

    return _Panel(
      ui: s.ui,
      title: 'NIGHT ${s.night}',
      children: <Widget>[
        // THE ORDER — fixed, and the reason the shift exists.
        Text('STANDING ORDER', style: t.at(9, K.lbl, ls: 2.5)),
        const SizedBox(height: 3),
        Text(nightOrder(s), style: t.at(11, K.ink, h: 1.5)),
        const SizedBox(height: 4),
        Text(
          '${shiftClock(s)}  ·  ${(nightProgress(s) * 100).round()}% OF THE NIGHT',
          style: t.at(10, K.greenDim, ls: 1.5),
        ),
        const SizedBox(height: 5),
        _Bar(
          value: nightProgress(s),
          fill: K.green,
          held: !quotaMet(s),
        ),

        // TONIGHT'S CONDITIONS. Live, because a card that changes the
        // window or the gap has to be re-readable mid-shift.
        if (s.night > 1) ...<Widget>[
          const SizedBox(height: 12),
          _Rule(),
          const SizedBox(height: 8),
          Text('CONDITIONS', style: t.at(9, K.lbl, ls: 2.5)),
          const SizedBox(height: 3),
          Text(cardOf(s).nm,
              style: t.at(11, K.amber, ls: 1.5, w: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(cardOf(s).ds, style: t.at(9.5, K.bootBody, h: 1.5)),
        ],

        const SizedBox(height: 14),
        _Rule(),
        const SizedBox(height: 8),

        // RIGHT NOW — the one thing. This is the line that makes the game
        // legible second to second; everything else out here is reference.
        Text('RIGHT NOW', style: t.at(9, K.lbl, ls: 2.5)),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0B0F10),
            border: Border(left: BorderSide(color: dc, width: 3)),
          ),
          child: Text(d.text, style: t.at(11, dc, h: 1.45)),
        ),

        const SizedBox(height: 14),
        _Rule(),
        const SizedBox(height: 8),

        // HOW YOU LOSE — stated, permanently, in the same words every night.
        Text('WHAT YOU ARE HOLDING', style: t.at(9, K.lbl, ls: 2.5)),
        const SizedBox(height: 3),
        Text(kPremise, style: t.at(9.5, K.amberDim, h: 1.5)),
        const SizedBox(height: 8),
        Text('HOW THE NIGHT ENDS', style: t.at(9, K.lbl, ls: 2.5)),
        const SizedBox(height: 4),
        for (final l in kLossConditions)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('- ', style: t.at(10, K.amberDim)),
                Expanded(
                  child: Text(l, style: t.at(10, K.bootBody, h: 1.5)),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),
        _Rule(),
        const SizedBox(height: 8),

        // THE CAREER — the goal above tonight.
        Text('WORKING TOWARD', style: t.at(9, K.lbl, ls: 2.5)),
        const SizedBox(height: 4),
        Text(careerLine(s), style: t.at(10.5, K.amber, h: 1.5)),

        const SizedBox(height: 12),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: <Widget>[
            _Tiny(ui: s.ui, k: 'STREAK', v: '${s.stats.streak}'),
            _Tiny(ui: s.ui, k: 'SAVES', v: '${s.stats.clutch}'),
            _Tiny(ui: s.ui, k: 'BANISHED', v: fmt(s.stats.banished)),
            _Tiny(ui: s.ui, k: 'RP TONIGHT', v: fmt(rpGain(s))),
          ],
        ),
      ],
    );
  }
}

// --- parts ------------------------------------------------------------------

class _Panel extends StatelessWidget {
  const _Panel({required this.ui, required this.title, required this.children});
  final double ui;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xFF07090A),
        border: Border(
          top: BorderSide(color: UX.tabDivider),
          bottom: BorderSide(color: UX.tabDivider),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: t.at(11, K.bootSig, ls: 4)),
              const SizedBox(height: 2),
              _Rule(),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: UX.tabDivider),
      );
}

class _Big extends StatelessWidget {
  const _Big(
      {required this.ui, required this.v, required this.k, required this.c});
  final double ui;
  final String v;
  final String k;
  final Color c;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(v,
              maxLines: 1,
              softWrap: false,
              style: t.at(22, c, ls: 0.5, w: FontWeight.bold)),
        ),
        Text(k, style: t.at(9, K.lbl, ls: 2)),
      ],
    );
  }
}

class _Tiny extends StatelessWidget {
  const _Tiny({required this.ui, required this.k, required this.v});
  final double ui;
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(v, style: t.at(13, K.ink, w: FontWeight.bold)),
        Text(k, style: t.at(8, K.lbl, ls: 1.5)),
      ],
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.ui,
    required this.label,
    required this.value,
    required this.right,
    required this.fill,
    this.warn = false,
  });

  final double ui;
  final String label;
  final double value;
  final String right;
  final Color fill;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: t.at(9.5, warn ? fill : K.lbl, ls: 1.6)),
            ),
            const SizedBox(width: 6),
            // the number wins the fight for space: a label you can guess is
            // survivable, a value you cannot read is not
            Text(right,
                maxLines: 1, softWrap: false, style: t.at(9.5, fill, ls: 0.5)),
          ],
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
        ),
        const SizedBox(height: 3),
        _Bar(value: value, fill: fill),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value, required this.fill, this.held = false});
  final double value;
  final Color fill;

  /// A held clock draws its remaining track hatched, because the bar is not
  /// going to move and the player needs to know that is a rule, not a stall.
  final bool held;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 8,
        width: double.infinity,
        child: CustomPaint(painter: _BarPainter(value, fill, held)),
      );
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.v, this.c, this.held);
  final double v;
  final Color c;
  final bool held;

  @override
  void paint(Canvas g, Size z) {
    g.drawRect(Offset.zero & z, Paint()..color = const Color(0xFF12181A));
    final double w = z.width * v.clamp(0.0, 1.0);
    if (w > 0) g.drawRect(Rect.fromLTWH(0, 0, w, z.height), Paint()..color = c);
    if (held) {
      final p = Paint()
        ..color = const Color(0x33FFB020)
        ..strokeWidth = 1;
      for (double x = w; x < z.width; x += 5) {
        g.drawLine(Offset(x, z.height), Offset(x + z.height, 0), p);
      }
    }
    g.drawRect(
      Offset.zero & z,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF243033),
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter o) =>
      o.v != v || o.c != c || o.held != held;
}

enum _SegState { done, now, ahead }

class _SegRow extends StatelessWidget {
  const _SegRow({
    required this.ui,
    required this.idx,
    required this.nm,
    required this.quota,
    required this.state,
    required this.met,
  });

  final double ui;
  final int idx;
  final String nm;
  final double quota;
  final _SegState state;
  final bool? met;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    final Color c = switch (state) {
      _SegState.done => K.greenDim,
      _SegState.now => K.ink,
      _SegState.ahead => K.lbl,
    };
    final String mark = switch (state) {
      _SegState.done => 'x',
      _SegState.now => '>',
      _SegState.ahead => ' ',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 12,
            child: Text(mark,
                style: t.at(10, state == _SegState.now ? K.amber : c)),
          ),
          Expanded(
            child: Text(
              nm,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: t.at(9.5, c,
                  ls: 1,
                  w: state == _SegState.now
                      ? FontWeight.bold
                      : FontWeight.normal),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            fmt(quota),
            style: t.at(9, state == _SegState.now && met == false
                ? K.amber
                : K.lbl),
          ),
        ],
      ),
    );
  }
}

/// How wide a wing may be given the leftover screen space each side, in
/// LOGICAL (pre-scale) units. Returns 0 when there is not enough to bother.
double wingWidthFor(double sideSpacePx, double scale) {
  if (scale <= 0) return 0;
  final double logical = sideSpacePx / scale;
  if (logical < kWingMin) return 0;
  return math.min<double>(kWingMax, logical);
}

/// The RIGHT NOW line, for cabinets with no wings.
///
/// A 16:9 or 16:10 viewport has no spare width, and the one thing out of the
/// whole wing that genuinely changes how the game plays is the directive. So
/// it gets a strip inside the room instead — the same text, the same colour
/// code, one line high.
class DirectiveStrip extends StatelessWidget {
  const DirectiveStrip({super.key, required this.s, required this.runtime});

  final GameState s;
  final AnomalyRuntime runtime;

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final d = primeDirective(s, runtime);
    final Color c = switch (d.urgency) {
      Urgency.urgent => const Color(0xFFFF4A3A),
      Urgency.watch => K.amber,
      Urgency.calm => K.green,
    };
    return IgnorePointer(
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              c.withValues(alpha: 0.16),
              const Color(0x00000000),
            ],
          ),
          border: Border(left: BorderSide(color: c, width: 3)),
        ),
        child: Text(
          d.text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: t.at(11, c, ls: 2),
        ),
      ),
    );
  }
}
