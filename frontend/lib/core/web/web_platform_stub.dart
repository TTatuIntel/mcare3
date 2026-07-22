/// Non-web stub for [web_platform_web.dart]. Storage falls back to an
/// in-memory map; everything else is a no-op.
final Map<String, String> _memory = {};

void openWindow(String url, [String target = '_blank']) {}

String? localStorageGet(String key) => _memory[key];

void localStorageSet(String key, String value) => _memory[key] = value;

void localStorageRemove(String key) => _memory.remove(key);

void playSosWebTone() {}

void stopSosWebTone() {}
