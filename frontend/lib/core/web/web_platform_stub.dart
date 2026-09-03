/// Non-web stub for [web_platform_web.dart]. Storage falls back to an
/// in-memory map; everything else is a no-op.
final Map<String, String> _memory = {};
final Map<String, String> _sessionMemory = {};

void openWindow(String url, [String target = '_blank']) {}

String? localStorageGet(String key) => _memory[key];

void localStorageSet(String key, String value) => _memory[key] = value;

void localStorageRemove(String key) => _memory.remove(key);

String? sessionStorageGet(String key) => _sessionMemory[key];

void sessionStorageSet(String key, String value) => _sessionMemory[key] = value;

void sessionStorageRemove(String key) => _sessionMemory.remove(key);

void playSosWebTone() {}

void stopSosWebTone() {}
