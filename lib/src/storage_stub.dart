// Non-web fallback for the tiny key/value store used by save()/load().
// Keeps the game runnable (and testable) off the web without dart:js_interop.
//
// This file is selected by the conditional import in state.dart on any target
// that does NOT have dart:js_interop (the Dart VM, flutter_test).

final Map<String, String> _mem = <String, String>{};

String? storageRead(String key) => _mem[key];

void storageWrite(String key, String value) {
  _mem[key] = value;
}

void storageRemove(String key) {
  _mem.remove(key);
}

/// Web-only: reloads the page. No-op elsewhere.
void storageReload() {}
