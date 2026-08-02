// FINAL BROADCAST — the right-hand equipment rack (#rack).
//
// TRANSMIT / HARDWARE / STATION, straight out of renderRack(). The whole
// producer ladder is always shown, locked tiers included with their % bar —
// the JS comment is explicit that hiding them hid most of the game.

import 'package:flutter/material.dart';

import '../anomalies.dart';
import '../consts.dart';
import '../economy.dart';
import '../meta.dart';
import '../state.dart';
import 'bots_panel.dart';
import 'ui_kit.dart';

/// Asks the shell to put a confirm sheet up inside the cabinet.
typedef ConfirmFn = void Function(String message, VoidCallback onYes,
    {bool danger});

class Rack extends StatefulWidget {
  const Rack({
    super.key,
    required this.s,
    required this.runtime,
    required this.confirm,
  });

  final GameState s;
  final AnomalyRuntime runtime;
  final ConfirmFn confirm;

  @override
  State<Rack> createState() => _RackState();
}

class _RackState extends State<Rack> {
  final ScrollController _scroll = ScrollController();

  GameState get s => widget.s;
  AnomalyRuntime get runtime => widget.runtime;
  GameAudio get audio => widget.runtime.audio;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _setTab(String tab) {
    if (s.tab == tab) return;
    s.tab = tab;
    audio.click();
    s.bump();
  }

  void _cycleBuyMode() {
    s.buyMode = s.buyMode == 1
        ? 10
        : (s.buyMode == 10 ? GameState.buyModeMax : 1);
    audio.click();
    s.bump();
  }

  void _buy(Producer p, int n) {
    audio.init();
    final before = s.prod[p.id] ?? 0;
    if (!buyProducer(s, p, n)) {
      audio.env('square', 180, 0.08, 0.07, 140);
      s.bump();
      return;
    }
    audio.buy();
    // Buying the 1st and the 500th used to be the same event. Crossing a mark
    // is now its own moment, with a permanent multiplier behind it.
    final after = s.prod[p.id] ?? 0;
    for (final mark in marksCrossed(before, after)) {
      audio.milestone('producer', mark);
      s.toast('${p.nm} x$mark — OUTPUT x${producerMarkMult(after).toStringAsFixed(2)}',
          ToastKind.gold);
    }
    s.save();
    s.bump();
  }

  void _buyUp(Upgrade u) {
    audio.init();
    if (!buyUpgrade(s, u)) {
      audio.env('square', 180, 0.08, 0.07, 140);
      s.bump();
      return;
    }
    audio.buy();
    s.toast('INSTALLED — ${u.nm}', ToastKind.good);
    s.save();
    s.bump();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: vgrad(K.rackTop, K.rackBot, shadow: const <BoxShadow>[
        BoxShadow(
            color: Color(0xB3000000), blurRadius: 24, offset: Offset(-8, 0)),
      ]),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // border-left:3px solid #000 + inset 3px 0 0 #2c3739
          const SizedBox(width: 3, child: ColoredBox(color: K.black)),
          const SizedBox(width: 3, child: ColoredBox(color: K.statusInset)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _tabs(),
                Expanded(
                  child: BoothScrollbar(
                    controller: _scroll,
                    child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.all(8),
                      children: _body(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------

  Widget _tabs() {
    const labels = <List<String>>[
      <String>['tx', 'TRANSMIT'],
      <String>['hw', 'HARDWARE'],
      <String>['bot', 'AUTO'],
      <String>['st', 'STATION'],
    ];
    final t = Sty(s.ui);
    return Container(
      decoration: const BoxDecoration(
        color: UX.sheetHeadBg,
        border: Border(bottom: BorderSide(color: UX.tabRule)),
      ),
      child: Row(
        children: <Widget>[
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Pressable(
                onTap: () => _setTab(labels[i][0]),
                builder: (_, hover, _) {
                  final on = s.tab == labels[i][0];
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on ? K.tabOnBg : UX.sheetHeadBg,
                      border: Border(
                        right: BorderSide(
                            color: i == labels.length - 1
                                ? const Color(0x00000000)
                                : UX.tabDivider),
                        bottom: BorderSide(
                            color: on ? K.amber : const Color(0x00000000),
                            width: 2),
                      ),
                    ),
                    // Four tabs share 334px, i.e. ~83px each; "TRANSMIT" in
                    // Courier at 13*ui with ls 1.5 is already 84px at the
                    // default ui of 1.15 and 124px at 1.8. softWrap:false stops
                    // it breaking to two lines, and FittedBox then shrinks it
                    // instead of overflowing.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        labels[i][1],
                        maxLines: 1,
                        softWrap: false,
                        style: t.at(
                            13,
                            on
                                ? K.amber
                                : (hover ? UX.itemHoverBorder : K.tabInk),
                            ls: 1.5),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _body() {
    switch (s.tab) {
      case 'hw':
        return _hardware();
      case 'bot':
        return botsRackRows(s, runtime);
      case 'st':
        return _station();
      default:
        return _transmit();
    }
  }

  // --- TRANSMIT ------------------------------------------------------------

  List<Widget> _transmit() {
    final mode = s.buyMode == 1
        ? '1'
        : (s.buyMode == 10 ? '10' : 'MAX');
    final out = <Widget>[
      RackHead('TRANSMISSION HARDWARE   ·   BUY x$mode',
          ui: s.ui, onTap: _cycleBuyMode),
    ];
    for (var i = 0; i < kProducers.length; i++) {
      final p = kProducers[i];
      final owned = s.prod[p.id] ?? 0;
      if (!producerUnlocked(s, i)) {
        // show the WHOLE ladder, always
        final pct = (s.sig / p.cost * 100).floor().clamp(0, 99);
        out.add(Opacity(
          opacity: 0.42,
          child: _Item(
            ui: s.ui,
            name: p.nm,
            cost: fmt(p.cost),
            afford: false,
            desc: p.ds,
            statLeft: '+${fmt(p.sig)} sig/s each',
            statRight: '$pct%',
          ),
        ));
        continue;
      }
      final n = resolveBuyCount(s, p);
      final c = bulkCost(s, p, n);
      final live = prodLive(runtime, p.id);
      Widget item = _Item(
        ui: s.ui,
        name: p.nm,
        offAir: !live,
        cost: fmt(c),
        afford: s.sig >= c,
        desc: p.ds,
        statLeft: '+${fmt(p.sig * n * sigMult(s))} sig/s',
        statRight: 'x$n',
        qty: '$owned',
        onTap: () => _buy(p, n),
      );
      if (!live) {
        item = Opacity(
          opacity: 0.38,
          child: ColorFiltered(
            colorFilter: const ColorFilter.matrix(<double>[
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0.2126, 0.7152, 0.0722, 0, 0, //
              0, 0, 0, 1, 0,
            ]),
            child: item,
          ),
        );
      }
      out.add(item);
    }
    return out;
  }

  // --- HARDWARE ------------------------------------------------------------

  List<Widget> _hardware() {
    final t = Sty(s.ui);
    final out = <Widget>[
      RackHead('STATION EQUIPMENT · ONE-TIME', ui: s.ui),
    ];
    var any = false;
    for (final u in kUpgrades) {
      final owned = s.ups[u.id] ?? false;
      if (!upgradeVisible(u, s)) continue;
      any = true;
      out.add(Opacity(
        opacity: owned ? 0.5 : 1,
        child: _Item(
          ui: s.ui,
          name: u.nm,
          cost: owned ? 'INSTALLED' : fmt(u.cost),
          afford: !owned && s.sig >= u.cost,
          owned: owned,
          desc: u.ds,
          onTap: owned ? null : () => _buyUp(u),
        ),
      ));
    }
    if (!any) {
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Text(
          'No equipment available yet. Survive some anomalies and the '
          'catalogue opens up.',
          style: t.at(13, K.noteInk, h: 1.5),
        ),
      ));
    }
    return out;
  }

  // --- STATION -------------------------------------------------------------

  List<Widget> _station() {
    final t = Sty(s.ui);
    final g = rpGain(s);
    final note = t.at(13, K.noteInk, h: 1.5);
    final b = note.copyWith(fontWeight: FontWeight.bold);

    // THE STATION BOARD — the sink RATINGS POINTS never had. It goes ABOVE
    // sign-off deliberately: the player should see what the points buy before
    // being asked whether to earn more.
    final board = <Widget>[
      RackHead('STATION — ${fmt(s.rp)} RP ON THE BOOKS', ui: s.ui),
      for (final n in kStationNodes)
        Builder(builder: (_) {
          final lvl = metaLevel(s, n.id);
          final cost = metaCost(s, n.id);
          final maxed = cost == null;
          return _Item(
            ui: s.ui,
            name: n.maxLvl > 1 ? '${n.nm}  ${'I' * lvl}' : n.nm,
            cost: maxed ? 'HELD' : '$cost RP',
            afford: !maxed && s.rp >= cost,
            desc: n.ds,
            owned: maxed,
            qty: n.maxLvl > 1 ? '$lvl/${n.maxLvl}' : null,
            onTap: maxed || s.rp < cost
                ? null
                : () {
                    if (buyMeta(s, n.id)) {
                      runtime.audio.buy();
                      s.toast('${n.nm} — SIGNED OFF ON', ToastKind.gold);
                      s.save();
                      s.bump();
                    }
                  },
          );
        }),
    ];

    return <Widget>[
      RackHead('SIGN-OFF', ui: s.ui),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: RichText(
          text: TextSpan(style: note, children: <InlineSpan>[
            const TextSpan(
                text: 'Ending the broadcast wipes your transmitters and '
                    'signal, and converts lifetime output into '),
            TextSpan(
                text: 'RATINGS POINTS',
                style: b.copyWith(color: K.amber)),
            TextSpan(
                text: ' — a permanent ×${(1 + s.rp * 0.08).toStringAsFixed(2)}'
                    ' to everything, forever.\n\nLifetime output: '),
            TextSpan(text: fmt(s.lifetimeSig), style: b),
            const TextSpan(text: '\nSign off now for: '),
            TextSpan(
                text: '${fmt(g)} RP', style: b.copyWith(color: K.green)),
          ]),
        ),
      ),
      _BigBtn(
        ui: s.ui,
        label: 'SIGN OFF — BANK ${fmt(g)} RP',
        enabled: g >= 1,
        onTap: () => widget.confirm(
          'Sign off? You keep ${fmt(s.rp + g)} ratings points and lose '
          'everything else.',
          runtime.signOff,
        ),
      ),
      ...board,

      RackHead('LOGBOOK', ui: s.ui),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: RichText(
          text: TextSpan(style: note, children: <InlineSpan>[
            const TextSpan(text: 'Banished: '),
            TextSpan(text: '${s.stats.banished}', style: b),
            const TextSpan(text: '   Clean kills: '),
            TextSpan(text: '${s.stats.perfect}', style: b),
            const TextSpan(text: '\nGot through: '),
            TextSpan(
                text: '${s.stats.scared}',
                style: b.copyWith(color: K.toastBad)),
            const TextSpan(text: '   Wrong keys: '),
            TextSpan(text: '${s.stats.wrong}', style: b),
            const TextSpan(text: '\nBest streak: '),
            TextSpan(text: '${s.stats.bestStreak}', style: b),
            const TextSpan(text: '   Sponsors watched: '),
            TextSpan(text: '${s.stats.ads}', style: b),
            const TextSpan(text: '\nNights: '),
            TextSpan(text: '${s.night}', style: b),
            const TextSpan(text: '   Catalogued: '),
            TextSpan(text: '${s.seen.length}/8', style: b),
          ]),
        ),
      ),
      RackHead('TRANSMITTER SETTINGS', ui: s.ui),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: RichText(
                text: TextSpan(style: note, children: <InlineSpan>[
                  const TextSpan(text: 'TEXT SIZE  '),
                  TextSpan(
                      text: '${(s.ui * 100).round()}%',
                      style: b.copyWith(color: K.amber)),
                ]),
              ),
            ),
            _slider(
              value: s.ui.clamp(0.85, 1.8),
              min: 0.85,
              max: 1.8,
              divisions: 19,
              onChanged: (v) {
                s.ui = v;
                s.bump();
              },
              onEnd: (_) => s.save(),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('VOLUME', style: note),
            ),
            _slider(
              value: s.sfx.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              divisions: 20,
              onChanged: (v) {
                s.sfx = v;
                audio.setVol(v);
                s.bump();
              },
              onEnd: (_) => s.save(),
            ),
            Pressable(
              onTap: () {
                s.flash = !s.flash;
                s.save();
                s.bump();
              },
              builder: (_, _, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 14,
                      height: 14,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: s.flash ? K.amber : K.black,
                        border: Border.all(color: UX.bigBtnBorder),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('HARSH FLASHING / RGB TEARING', style: note),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      _BigBtn(
        ui: s.ui,
        label: 'ERASE ALL TAPES (HARD RESET)',
        danger: true,
        onTap: () => widget.confirm(
          'Erase everything, including ratings points?',
          s.eraseAllTapes,
          danger: true,
        ),
      ),
    ];
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onEnd,
  }) {
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: K.amber,
        inactiveTrackColor: UX.bigBtnBg,
        thumbColor: K.amber,
        overlayColor: K.amber.withValues(alpha: 0.15),
        showValueIndicator: ShowValueIndicator.never,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      child: SizedBox(
        height: 26,
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          onChangeEnd: onEnd,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// .item
// ---------------------------------------------------------------------------

class _Item extends StatelessWidget {
  const _Item({
    required this.ui,
    required this.name,
    required this.cost,
    required this.afford,
    required this.desc,
    this.statLeft,
    this.statRight,
    this.qty,
    this.onTap,
    this.owned = false,
    this.offAir = false,
  });

  final double ui;
  final String name;
  final String cost;
  final bool afford;
  final String desc;
  final String? statLeft;
  final String? statRight;
  final String? qty;
  final VoidCallback? onTap;
  final bool owned;
  final bool offAir;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      onTap: onTap,
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (_, hover, _) {
        final Color border = owned
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: t.at(16, K.itemName, ls: 0.5),
                              children: <InlineSpan>[
                                TextSpan(text: name),
                                if (offAir)
                                  TextSpan(
                                    text: ' ## OFF AIR',
                                    style: t.at(16, UX.offAir, ls: 0.5),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(cost,
                              maxLines: 1,
                              softWrap: false,
                              style:
                                  t.at(15, afford ? K.green : K.amber)),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child:
                          Text(desc, style: t.at(13.5, K.itemDesc, h: 1.35)),
                    ),
                    if (statLeft != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 30),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Flexible(
                              child: Text(statLeft!,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: t.at(13, K.itemStat)),
                            ),
                            if (statRight != null)
                              Flexible(
                                child: Text(statRight!,
                                    maxLines: 1,
                                    softWrap: false,
                                    style: t.at(13, K.itemStat)),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (qty != null)
                Positioned(
                  right: 8,
                  bottom: 6,
                  child: Text(qty!, style: t.at(20, K.itemQty)),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// `.bigbtn`
class _BigBtn extends StatelessWidget {
  const _BigBtn({
    required this.ui,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
  });

  final double ui;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Pressable(
      enabled: enabled,
      onTap: onTap,
      builder: (_, hover, _) => Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: !enabled
                ? UX.bigBtnOff
                : danger
                    ? UX.acceptBg
                    : (hover ? UX.bigBtnHover : UX.bigBtnBg),
            border: Border.all(
                color: danger ? K.lostBorder : UX.bigBtnBorder),
          ),
          child: Text(label,
              style: t.at(14, danger ? UX.acceptInk : K.amber, ls: 2)),
        ),
      ),
    );
  }
}
