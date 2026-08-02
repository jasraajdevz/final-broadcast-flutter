// Web implementation of the tiny key/value store used by save()/load().
// Everything web-only in this project is quarantined here.
//
// Selected by the conditional import in state.dart when dart:js_interop exists.
// Uses dart:js_interop directly so no extra pub dependency is needed.

import 'dart:js_interop';

@JS('window')
external _Window get _window;

extension type _Window._(JSObject _) implements JSObject {
  external _Storage get localStorage;
  external _Location get location;
}

extension type _Storage._(JSObject _) implements JSObject {
  external JSString? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

extension type _Location._(JSObject _) implements JSObject {
  external void reload();
}

String? storageRead(String key) {
  try {
    return _window.localStorage.getItem(key)?.toDart;
  } catch (_) {
    return null;
  }
}

void storageWrite(String key, String value) {
  try {
    _window.localStorage.setItem(key, value);
  } catch (_) {
    // Private mode / quota exceeded — the JS original swallows this too.
  }
}

void storageRemove(String key) {
  try {
    _window.localStorage.removeItem(key);
  } catch (_) {}
}

/// `location.reload()` — used by ERASE ALL TAPES.
void storageReload() {
  try {
    _window.location.reload();
  } catch (_) {}
}
