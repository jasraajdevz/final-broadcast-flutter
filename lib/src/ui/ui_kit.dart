// FINAL BROADCAST — shared widget plumbing for the cabinet UI.
//
// The HTML's chrome is a stylesheet; this is that stylesheet. Every colour,
// size, letter-spacing and gap below is transcribed from the <style> block of
// index.html. Anything that looked odd there looks odd here too.
//
// Sizes that the original wrote as `calc(Npx * var(--ui))` go through
// [Sty.at], which multiplies by GameState.ui — the TEXT SIZE slider in the
// STATION tab. Sizes written as plain px (the boot screen, the .key base font)
// are NOT scaled, exactly as in the CSS.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../bake.dart' show mono;
import '../consts.dart' show K;

// ---------------------------------------------------------------------------
// Colours that are not in K — the one-off literals from the stylesheet.
// ---------------------------------------------------------------------------

class UX {
  UX._();

  // status strip
  static const Color rdoRule = Color(0xFF1E2628); // .rdo border-right
  static const Color qBarBg = Color(0xFF0E1A16);
  static const Color qBarBorder = Color(0xFF1D3A2C);

  // rack
  static const Color tabRule = Color(0xFF232C2E); // #tabs border-bottom
  static const Color tabDivider = Color(0xFF1A2223); // .tab border-right
  static const Color itemHoverBorder = Color(0xFF3A4A4D);
  static const Color itemHoverTop = Color(0xFF182022);
  static const Color itemHoverBot = Color(0xFF0E1415);
  static const Color bigBtnBg = Color(0xFF1A0F04);
  static const Color bigBtnBorder = Color(0xFF6A4413);
  static const Color bigBtnHover = Color(0xFF2A1806);
  static const Color bigBtnOff = Color(0xFF12100C);
  static const Color scrollTrack = Color(0xFF080B0C);
  static const Color scrollThumb = Color(0xFF243032);

  // deck
  static const Color keyTopEdge = Color(0xFF3D4A4D);
  static const Color keyShadow = Color(0xFF050708);
  static const Color keyHoverTop = Color(0xFF2B3436);
  static const Color keyHoverBot = Color(0xFF1A2122);
  static const Color keyHoverInk = Color(0xFFCFE0DE);
  static const Color keyGoodEdge = Color(0xFF2F8A55);
  static const Color keyBadEdge = Color(0xFF8A2F2F);
  static const Color skeyTopEdge = Color(0xFF5A4416);
  static const Color skeyHoverTop = Color(0xFF332409);
  static const Color skeyHoverBot = Color(0xFF1C1305);

  // modals
  static const Color scrim = Color(0xDB000000); // rgba(0,0,0,.86)
  static const Color sheetHeadBg = Color(0xFF0A0E0F);
  static const Color sheetHeadRule = Color(0xFF26302F);
  static const Color closeInk = Color(0xFF5C6E70);
  static const Color manListRule = Color(0xFF202A2B);
  static const Color mrowRule = Color(0xFF131A1B);
  static const Color mrowHoverBg = Color(0xFF111819);
  static const Color mrowOnBg = Color(0xFF161E1F);
  static const Color previewBorder = Color(0xFF263031);
  static const Color ctagBg = Color(0xFF04180D);
  static const Color ctagUnkBorder = Color(0xFF3A3A3A);
  static const Color ctagUnkInk = Color(0xFF4A5456);
  static const Color ctagUnkBg = Color(0xFF0D0F10);
  static const Color dimNote = Color(0xFF5C6E70);

  // ad break
  static const Color adSheetBorder = Color(0xFF3A2A0A);
  static const Color adBarBg = Color(0xFF0A0E0F);
  static const Color adBarRule = Color(0xFF2A2418);
  static const Color adBarInk = Color(0xFF7A6A44);
  static const Color adSkipBg = Color(0xFF1A1206);
  static const Color adSkipBorder = Color(0xFF5A4416);

  // signal lost / sign-off
  static const Color lostTopA = Color(0xFF140606);
  static const Color lostTopB = Color(0xFF080303);
  static const Color lostHeadBg = Color(0xFF0D0303);
  static const Color lostHeadRule = Color(0xFF3A1010);
  static const Color reviveBg = Color(0xFF1A1206);
  static const Color reviveBorder = Color(0xFF6A4413);
  static const Color reviveHover = Color(0xFF2A1C08);
  static const Color acceptBg = Color(0xFF140606);
  static const Color acceptInk = Color(0xFFC46B63);
  static const Color acceptHover = Color(0xFF200909);
  static const Color winTopA = Color(0xFF06140B);
  static const Color winTopB = Color(0xFF030803);
  static const Color winHeadBg = Color(0xFF040C07);
  static const Color winHeadRule = Color(0xFF1B3A26);
  static const Color winAcceptBg = Color(0xFF06210F);

  // boot
  static const Color bootBtnBg = Color(0xFF0A1A10);
  static const Color bootBtnBorder = Color(0xFF2F7A4C);
  static const Color bootBtnHover = Color(0xFF0E2A18);
  static const Color bootBody2 = Color(0xFF6B7D80);
  static const Color rotSub = Color(0xFF4A5A5C);

  // misc
  static const Color offAir = Color(0xFFFF6B60);
  static const Color wrapBgInner = Color(0xFF0A0C0D); // #wrap radial-gradient
}

// ---------------------------------------------------------------------------
// Type
// ---------------------------------------------------------------------------

/// `calc(Npx * var(--ui))`. Build one per widget build from `GameState.ui`.
// ---------------------------------------------------------------------------
// TYPE
//
// The body of this game is a bundled monospace (Courier Prime, registered as
// 'Courier New' because CanvasKit does not resolve system families). That stays
// — it IS the aesthetic, and every readout, key cap and meter is measured in
// it.
//
// What was missing was a SECOND and THIRD voice. Everything from the wordmark
// to a 1974 viewer letter to a keycap was set in one face at one width, so
// nothing had any hierarchy and the documents did not read as documents.
//
// Two faces, each doing a job the mono cannot:
//   display() — condensed broadcast signage, for titles and ranks. Authority.
//   typed()   — a distressed typewriter, for the archive. These are supposed
//               to be pages somebody typed on a machine in 1974, and setting
//               them in the same face as the HUD made them read as UI copy.
//
// google_fonts fetches at runtime, so both degrade to the bundled mono if the
// network is not there. Nothing load-bearing is ever set in them: no keycap,
// no meter, no number.
// ---------------------------------------------------------------------------

/// Condensed signage. Titles, ranks, sheet headers.
TextStyle display(double size, Color c,
    {FontWeight weight = FontWeight.w600, double? letterSpacing, double? height}) {
  try {
    return GoogleFonts.oswald(
      fontSize: size,
      color: c,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
  } catch (_) {
    // never let a font failure take the screen down
    return mono(size, c, weight: weight, letterSpacing: letterSpacing, height: height);
  }
}

/// A typewriter with a worn ribbon. The archive, and only the archive.
TextStyle typed(double size, Color c,
    {FontWeight weight = FontWeight.normal, double? letterSpacing, double? height}) {
  try {
    return GoogleFonts.specialElite(
      fontSize: size,
      color: c,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
    );
  } catch (_) {
    return mono(size, c, weight: weight, letterSpacing: letterSpacing, height: height);
  }
}

class Sty {
  const Sty(this.ui);

  /// GameState.ui — the TEXT SIZE slider, 0.85 .. 1.8.
  final double ui;

  TextStyle at(
    double px,
    Color c, {
    double? ls,
    FontWeight w = FontWeight.normal,
    double? h,
    List<Shadow>? sh,
    FontStyle? italic,
  }) {
    final base =
        mono(px * ui, c, weight: w, letterSpacing: ls, height: h);
    if (sh == null && italic == null) return base;
    return base.copyWith(shadows: sh, fontStyle: italic);
  }

  /// A size the stylesheet wrote as a plain px value (unscaled).
  TextStyle fixed(
    double px,
    Color c, {
    double? ls,
    FontWeight w = FontWeight.normal,
    double? h,
    List<Shadow>? sh,
  }) {
    final base = mono(px, c, weight: w, letterSpacing: ls, height: h);
    if (sh == null) return base;
    return base.copyWith(shadows: sh);
  }
}

/// `text-shadow: 0 0 Npx rgba(...)`.
List<Shadow> glow(Color c, double blur, double alpha) => <Shadow>[
      Shadow(color: c.withValues(alpha: alpha), blurRadius: blur),
    ];

// ---------------------------------------------------------------------------
// Interaction
// ---------------------------------------------------------------------------

/// A hover + press aware region. The CSS leans on :hover and :active for
/// nearly every control, so every control in the port goes through this.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.enabled = true,
    this.forceDown = false,
    this.tooltip,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed)
      builder;
  final VoidCallback? onTap;
  final bool enabled;

  /// Keyboard-driven depress (the deck keys get `.down` for 90ms).
  final bool forceDown;
  final String? tooltip;
  final MouseCursor cursor;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onTap != null;
    Widget child = widget.builder(
        context, on && _hover, (on && _down) || widget.forceDown);
    if (widget.tooltip != null) {
      child = Tooltip(
        message: widget.tooltip!,
        waitDuration: const Duration(milliseconds: 500),
        child: child,
      );
    }
    return MouseRegion(
      cursor: on ? widget.cursor : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() {
        _hover = false;
        _down = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: on ? (_) => setState(() => _down = true) : null,
        onTapUp: on ? (_) => setState(() => _down = false) : null,
        onTapCancel: on ? () => setState(() => _down = false) : null,
        onTap: on ? widget.onTap : null,
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Panels
// ---------------------------------------------------------------------------

/// `background: linear-gradient(#top, #bottom)`.
BoxDecoration vgrad(Color top, Color bottom,
        {BoxBorder? border, List<BoxShadow>? shadow}) =>
    BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[top, bottom],
      ),
      border: border,
      boxShadow: shadow,
    );

/// The `.hd` rule used all through the rack and the manual list.
class RackHead extends StatelessWidget {
  const RackHead(this.text,
      {super.key, required this.ui, this.onTap, this.padLeft = 2});

  final String text;
  final double ui;
  final VoidCallback? onTap;
  final double padLeft;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    final label = Container(
      margin: EdgeInsets.fromLTRB(padLeft, 10, padLeft, 6),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: K.headRule)),
      ),
      width: double.infinity,
      child: Text(text, style: t.at(12, K.headInk, ls: 2)),
    );
    if (onTap == null) return label;
    return Pressable(onTap: onTap, builder: (_, _, _) => label);
  }
}

// ---------------------------------------------------------------------------
// Modals
// ---------------------------------------------------------------------------

/// `.modal` — a full-cabinet scrim with the sheet centred on it. Wrap it in a
/// Positioned.fill at the call site; it does not position itself.
///
/// The CSS also had `backdrop-filter: blur(2px)`; under an 86%-black scrim it
/// is invisible, and a per-frame BackdropFilter over the live scene is not
/// free, so it is not reproduced.
class ModalScrim extends StatelessWidget {
  const ModalScrim({super.key, required this.child, this.onTapOutside});

  final Widget child;
  final VoidCallback? onTapOutside;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTapOutside,
      child: ColoredBox(
        color: UX.scrim,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: child,
          ),
        ),
      ),
    );
  }
}

/// The browser `confirm()` the HTML used for SIGN OFF and ERASE ALL TAPES.
/// Rendered inside the cabinet so it scales with everything else.
class ConfirmSheet extends StatelessWidget {
  const ConfirmSheet({
    super.key,
    required this.ui,
    required this.message,
    required this.onYes,
    required this.onNo,
    this.danger = false,
  });

  final double ui;
  final String message;
  final VoidCallback onYes;
  final VoidCallback onNo;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final t = Sty(ui);
    return Container(
      width: 520,
      decoration: vgrad(K.sheetTop, K.sheetBot,
          border: Border.all(color: K.sheetBorder, width: 2)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: UX.sheetHeadBg,
              border: Border(bottom: BorderSide(color: UX.sheetHeadRule)),
            ),
            child: Text('CONFIRM', style: t.at(17, K.amber, ls: 3)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
            child: Text(message, style: t.at(15, K.fldVal, h: 1.6)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 20),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Pressable(
                    onTap: onYes,
                    builder: (_, hover, _) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: danger
                            ? (hover ? UX.acceptHover : UX.acceptBg)
                            : (hover ? UX.bigBtnHover : UX.bigBtnBg),
                        border: Border.all(
                            color: danger ? K.lostBorder : UX.bigBtnBorder),
                      ),
                      child: Text('OK',
                          style: t.at(14, danger ? UX.acceptInk : K.amber,
                              ls: 1.5)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Pressable(
                    onTap: onNo,
                    builder: (_, hover, _) => Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: hover ? UX.mrowHoverBg : UX.sheetHeadBg,
                        border: Border.all(color: K.sheetBorder),
                      ),
                      child:
                          Text('CANCEL', style: t.at(14, K.ink, ls: 1.5)),
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
}

// ---------------------------------------------------------------------------
// Rich text
// ---------------------------------------------------------------------------

/// Builds a paragraph out of chunks that alternate normal / bold, starting
/// normal — the shape EndScreenModel uses.
TextSpan alternating(
  List<String> chunks,
  TextStyle normal,
  TextStyle bold,
) {
  final spans = <TextSpan>[];
  for (var i = 0; i < chunks.length; i++) {
    if (chunks[i].isEmpty) continue;
    spans.add(TextSpan(text: chunks[i], style: i.isOdd ? bold : normal));
  }
  return TextSpan(children: spans);
}

// ---------------------------------------------------------------------------
// Scrolling
// ---------------------------------------------------------------------------

/// `#rackBody::-webkit-scrollbar` — an 8px track in station colours.
class BoothScrollbar extends StatelessWidget {
  const BoothScrollbar({super.key, required this.controller, required this.child});

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(UX.scrollThumb),
        trackColor: WidgetStateProperty.all(UX.scrollTrack),
        trackBorderColor: WidgetStateProperty.all(UX.scrollTrack),
        thickness: WidgetStateProperty.all(8),
        radius: Radius.zero,
        thumbVisibility: WidgetStateProperty.all(true),
        trackVisibility: WidgetStateProperty.all(true),
      ),
      child: Scrollbar(controller: controller, child: child),
    );
  }
}
