// FINAL BROADCAST — non-web audio.
//
// Selected by the conditional import in audio.dart when dart:js_interop is not
// available (the Dart VM, i.e. flutter_test). The whole game runs headless on
// this: every GameAudio call is a no-op and nothing throws.
//
// A portable PCM implementation would slot in here without touching a single
// call site — GameAudio is the only surface the game uses.

import '../anomalies.dart' show GameAudio, NullAudio;

/// Selected by the conditional import in audio.dart.
GameAudio makeGameAudio() => const NullAudio();
