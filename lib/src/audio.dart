// FINAL BROADCAST — audio front door.
//
// The game only ever talks to `GameAudio` (declared in anomalies.dart). This
// file picks the implementation: real WebAudio on the web, a silent no-op
// everywhere else, so the simulation and its tests run headless.
//
//   runtime.audio = createGameAudio();
//
// The WebAudio port itself lives in ui/audio_web.dart — the only file in the
// project besides storage_web.dart that touches a browser API.

import 'anomalies.dart' show GameAudio;
import 'ui/audio_stub.dart' if (dart.library.js_interop) 'ui/audio_web.dart';

/// The best audio engine this platform can give you. Never null, never throws.
GameAudio createGameAudio() => makeGameAudio();
