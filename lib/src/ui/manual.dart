// FINAL BROADCAST — the operator's field manual (#modalManual).
//
// Eight entities plus the eight emergency-desk pages. An entity's page writes
// itself the first time the thing reaches the main monitor; until then it is
// blank, and so are you.

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../anomalies.dart';
import '../bake.dart' show fill;
import '../archive.dart';
import '../consts.dart';
import '../state.dart';
import 'scene_slot.dart';
import 'ui_kit.dart';

class ManualSheet extends StatefulWidget {
  const ManualSheet({
    super.key,
    required this.s,
    required this.runtime,
    required this.onClose,
  });

  final GameState s;
  final AnomalyRuntime runtime;
  final VoidCallback onClose;

  @override
  State<ManualSheet> createState() => _ManualSheetState();
}

class _ManualSheetState extends State<ManualSheet> {
  final ScrollController _list = ScrollController();
  final ScrollController _page = ScrollController();

  GameState get s => widget.s;

  @override
  void dispose() {
    _list.dispose();
    _page.dispose();
    super.dispose();
  }

  void _open(String page) {
    s.manPage = page;
    widget.runtime.audio.click();
    s.bump();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    return ModalScrim(
      child: Container(
        width: kSheetSize.width,
        constraints: BoxConstraints(maxHeight: kSheetSize.height),
        decoration: vgrad(K.sheetTop, K.sheetBot,
            border: Border.all(color: K.sheetBorder, width: 2)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                color: UX.sheetHeadBg,
                border: Border(bottom: BorderSide(color: UX.sheetHeadRule)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Flexible(
                    child: Text("KBLK-7  ·  OPERATOR'S FIELD MANUAL",
                        maxLines: 1,
                        softWrap: false,
                        style: t.at(17, K.amber, ls: 3)),
                  ),
                  Pressable(
                    onTap: widget.onClose,
                    builder: (_, hover, _) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text('[ESC]',
                          style: t.fixed(16, hover ? K.red : UX.closeInk)),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: kManListW,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: UX.scrollTrack,
                        border: Border(
                            right: BorderSide(color: UX.manListRule)),
                      ),
                      child: BoothScrollbar(
                        controller: _list,
                        child: ListView(
                          controller: _list,
                          padding: EdgeInsets.zero,
                          children: _rows(),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: BoothScrollbar(
                      controller: _page,
                      child: ListView(
                        controller: _page,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                        children: _pageBody(),
                      ),
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

  // --- the list -------------------------------------------------------------

  List<Widget> _rows() {
    final out = <Widget>[];
    for (final a in kAnoms) {
      final seen = s.seen[a.id] ?? false;
      out.add(_MRow(
        ui: s.ui,
        label: seen ? a.nm : 'UNCATALOGUED',
        tag: seen ? kCounterBy[a.counter]!.nm : '???',
        on: s.manPage == a.id,
        unknown: !seen,
        onTap: () => _open(a.id),
      ));
    }
    out.add(RackHead('EMERGENCY DESK', ui: s.ui, padLeft: 12));
    for (final c in kCounters) {
      out.add(_MRow(
        ui: s.ui,
        label: c.nm,
        tag: 'KEY ${c.key}',
        on: s.manPage == 'k_${c.id}',
        onTap: () => _open('k_${c.id}'),
      ));
    }

    // THE FILE. A collection you cannot re-read is not a collection, it is a
    // sequence of modals — so everything recovered from the desk is in here,
    // in order, with the gaps visible. The gaps are the point.
    out.add(RackHead('THE FILE  ·  ${foundCount(s)}/$archiveTotal',
        ui: s.ui, padLeft: 12));
    for (var i = 0; i < kArchive.length; i++) {
      final got = docFound(s, nightForDoc(i));
      out.add(_MRow(
        ui: s.ui,
        label: got ? kArchive[i].head : 'NOT RECOVERED',
        tag: got ? kArchive[i].kindLabel : 'NIGHT ${nightForDoc(i)}',
        on: s.manPage == 'd_$i',
        unknown: !got,
        onTap: got ? () => _open('d_$i') : () {},
      ));
    }

    return out;
  }

  // --- the page -------------------------------------------------------------

  List<Widget> _pageBody() {
    final t = Sty(s.ui);

    if (s.manPage.startsWith('d_')) {
      final i = int.tryParse(s.manPage.substring(2)) ?? 0;
      final d = kArchive[i.clamp(0, kArchive.length - 1)];
      return <Widget>[
        Text(d.kindLabel, style: t.at(11, K.manTag, ls: 3)),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 14),
          child: Text(d.head, style: t.at(17, K.manH3, ls: 1.5)),
        ),
        Text(d.body, style: t.at(14, K.manInkOn, h: 1.95)),
        if (d.sign != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(d.sign!, style: t.at(13, K.manTag, h: 1.7)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: Text('RECOVERED ON NIGHT ${nightForDoc(i)}',
              style: t.at(10, K.lbl, ls: 2)),
        ),
      ];
    }

    if (s.manPage.startsWith('k_')) {
      final c = kCounterBy[s.manPage.substring(2)] ?? kCounters[0];
      final kills = kAnoms
          .where((a) => a.counter == c.id && (s.seen[a.id] ?? false))
          .toList();
      return <Widget>[
        Text(c.nm, style: t.at(22, K.manH3, ls: 3)),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Text('EMERGENCY BROADCAST · KEY ${c.key}',
              style: t.at(12, K.manCls, ls: 2)),
        ),
        _Fld(ui: s.ui, k: 'FUNCTION', v: c.ds),
        _Fld(
          ui: s.ui,
          k: 'CONFIRMED EFFECTIVE AGAINST',
          v: kills.isEmpty
              ? 'Nothing catalogued yet.'
              : kills.map((a) => a.nm).join('\n'),
          vColor: kills.isEmpty ? UX.ctagUnkInk : null,
        ),
      ];
    }

    final a = kAnomBy[s.manPage] ?? kAnoms[0];
    if (!(s.seen[a.id] ?? false)) {
      return <Widget>[
        Text('UNCATALOGUED', style: t.at(22, K.manH3, ls: 3)),
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 12),
          child: Text('NO FIRST-HAND OBSERVATION',
              style: t.at(12, K.manCls, ls: 2)),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 11),
          child: Text(
            'This entry writes itself the first time the thing reaches the '
            'main monitor. Until then the page is blank, and so are you.',
            style: t.at(16, UX.dimNote, h: 1.65),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text('COUNTERMEASURE', style: t.at(12, K.fldKey, ls: 2)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _CTag(ui: s.ui, label: 'UNKNOWN', unknown: true),
        ),
      ];
    }

    final c = kCounterBy[a.counter]!;
    return <Widget>[
      Text(a.nm, style: t.at(22, K.manH3, ls: 3)),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 12),
        child: Text(a.cls, style: t.at(12, K.manCls, ls: 2)),
      ),
      // The CSS floated this 320x240 plate right and wrapped the copy around
      // it; Flutter has no float, so it sits on its own line at the right.
      Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 14),
          child: Container(
            width: kManualCanvasW.toDouble(),
            height: kManualCanvasH.toDouble(),
            decoration: BoxDecoration(
              color: K.black,
              border: Border.all(color: UX.previewBorder),
            ),
            child: CustomPaint(
              painter: _PreviewPainter(def: a, runtime: widget.runtime),
              size: Size(kManualCanvasW.toDouble(), kManualCanvasH.toDouble()),
            ),
          ),
        ),
      ),
      _Fld(ui: s.ui, k: 'HOW IT PRESENTS', v: a.tell),
      _Fld(ui: s.ui, k: 'STATION RECORD', v: a.lore),
      _Fld(ui: s.ui, k: 'PROCEDURE', v: a.method),
      _Fld(ui: s.ui, k: 'DO NOT', v: a.wrongNote, vColor: K.fldWarn),
      Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text('COUNTERMEASURE', style: t.at(12, K.fldKey, ls: 2)),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: _CTag(ui: s.ui, label: '${c.nm}  ·  KEY ${c.key}'),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------

class _MRow extends StatelessWidget {
  const _MRow({
    required this.ui,
    required this.label,
    required this.tag,
    required this.on,
    required this.onTap,
    this.unknown = false,
  });

  final double ui;
  final String label;
  final String tag;
  final bool on;
  final bool unknown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      builder: (_, hover, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on
              ? UX.mrowOnBg
              : (hover ? UX.mrowHoverBg : const Color(0x00000000)),
          border: Border(
            bottom: const BorderSide(color: UX.mrowRule),
            left: BorderSide(
                color: on ? K.amber : const Color(0x00000000), width: 3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: t.at(
                  15,
                  on
                      ? K.amber
                      : unknown
                          ? K.manUnk
                          : (hover ? K.manInkOn : K.manInk),
                  ls: 0.5,
                  italic: unknown ? FontStyle.italic : null,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(tag, style: t.at(11, K.manTag)),
          ],
        ),
      ),
    );
  }
}

/// `.fld` — a small caps key over a body-copy value.
class _Fld extends StatelessWidget {
  const _Fld({required this.ui, required this.k, required this.v, this.vColor});

  final double ui;
  final String k;
  final String v;
  final Color? vColor;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(k, style: t.at(12, K.fldKey, ls: 2)),
          ),
          Text(v, style: t.at(16, vColor ?? K.fldVal, h: 1.65)),
        ],
      ),
    );
  }
}

/// `.ctag`
class _CTag extends StatelessWidget {
  const _CTag({required this.ui, required this.label, this.unknown = false});

  final double ui;
  final String label;
  final bool unknown;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: unknown ? UX.ctagUnkBg : UX.ctagBg,
        border:
            Border.all(color: unknown ? UX.ctagUnkBorder : K.greenDim),
      ),
      child: Text(label,
          style: t.at(15, unknown ? UX.ctagUnkInk : K.green, ls: 2)),
    );
  }
}

/// The 320x240 plate. Black, then the registered drawAnom, then the 2px
/// scanline comb the HTML laid over it.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter({required this.def, required this.runtime})
      : super(repaint: runtime);

  final Anom def;
  final AnomalyRuntime runtime;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, size.width, size.height), fill(K.black));
    gAnomPreview?.call(canvas, def, runtime.tGlobal, 0.7);
    final line = fill(const ui.Color(0x40000000));
    for (double y = 0; y < size.height; y += 2) {
      canvas.drawRect(ui.Rect.fromLTWH(0, y, size.width, 1), line);
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter oldDelegate) =>
      oldDelegate.def.id != def.id;
}
