// FINAL BROADCAST — the toast column (#toasts).
//
// Anchored at left 0 / top 462 / width 940, centred, 4px gaps, three at most.
// Hold 2.6s then a 0.4s fade (ToastBus), plus the 0.3s slide-in the CSS did
// with @keyframes tin.

import 'package:flutter/widgets.dart';

import '../consts.dart';
import '../state.dart';
import 'ui_kit.dart';

class ToastLayer extends StatelessWidget {
  const ToastLayer({super.key, required this.s});

  final GameState s;

  static Color _borderOf(ToastKind k) {
    switch (k) {
      case ToastKind.good:
        return K.greenDim;
      case ToastKind.bad:
        return const Color(0xFF6B1A16);
      case ToastKind.gold:
        return const Color(0xFF6A4413);
      case ToastKind.plain:
        return K.sheetBorder;
    }
  }

  static Color _inkOf(ToastKind k) {
    switch (k) {
      case ToastKind.good:
        return K.green;
      case ToastKind.bad:
        return K.toastBad;
      case ToastKind.gold:
        return K.amber;
      case ToastKind.plain:
        return K.toastInk;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Sty(s.ui);
    final items = s.toasts.items;
    if (items.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          for (final toast in items) ...<Widget>[
            _one(toast, t),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _one(Toast toast, Sty t) {
    // @keyframes tin — 0.3s from opacity 0 / translateY(-8px)
    final entry = (toast.t / 0.3).clamp(0.0, 1.0);
    final alpha = s.toasts.opacityOf(toast) * entry;
    return Opacity(
      opacity: alpha.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -8 * (1 - entry)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: K.toastBg,
            border: Border.all(color: _borderOf(toast.kind)),
          ),
          child: Text(toast.msg,
              style: t.at(14, _inkOf(toast.kind), ls: 1.5)),
        ),
      ),
    );
  }
}
