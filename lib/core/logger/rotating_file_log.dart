import 'dart:async';
import 'dart:convert';
import 'dart:io';

class RotatingFileLog {
  RotatingFileLog._();

  static const int maxBytes = 5 * 1024 * 1024;
  static const int backupCount = 3;

  static bool detailedEnabled = false;

  static final Map<String, Future<void>> _writes = {};

  static Future<void> initializeDetailedFlag(File preferencesFile) async {
    try {
      if (!await preferencesFile.exists()) return;
      final decoded = jsonDecode(await preferencesFile.readAsString());
      if (decoded is Map) {
        detailedEnabled =
            decoded['flutter.detailed_diagnostics'] == true || decoded['detailed_diagnostics'] == true;
      }
    } catch (_) {
      detailedEnabled = false;
    }
  }

  static Future<void> append(
    File file,
    String message, {
    bool detailed = false,
  }) {
    if (detailed && !detailedEnabled) return Future.value();
    final rawText = message.endsWith('\n') ? message : '$message\n';
    final rawBytes = utf8.encode(rawText);
    final text = rawBytes.length <= maxBytes
        ? rawText
        : utf8.decode(rawBytes.sublist(rawBytes.length - maxBytes), allowMalformed: true);
    return _enqueue(file.path, () async {
      await file.parent.create(recursive: true);
      await _rotateIfNeeded(file, utf8.encode(text).length);
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    });
  }

  static Future<void> write(
    File file,
    String content, {
    bool detailed = false,
  }) {
    if (detailed && !detailedEnabled) return Future.value();
    return _enqueue(file.path, () async {
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        await _rotate(file);
      }
      final bytes = utf8.encode(content);
      final limitedBytes = bytes.length <= maxBytes ? bytes : bytes.sublist(bytes.length - maxBytes);
      await file.writeAsString(utf8.decode(limitedBytes, allowMalformed: true), flush: true);
    });
  }

  static Future<void> rotateIfNeeded(File file) => _enqueue(file.path, () => _rotateIfNeeded(file, 0));

  static Future<void> _enqueue(String path, Future<void> Function() operation) {
    final previous = _writes[path] ?? Future.value();
    final next = previous.catchError((_) {}).then((_) => operation());
    late final Future<void> tracked;
    tracked = next.whenComplete(() {
      if (identical(_writes[path], tracked)) {
        _writes.remove(path);
      }
    });
    _writes[path] = tracked;
    return tracked;
  }

  static Future<void> _rotateIfNeeded(File file, int incomingBytes) async {
    if (!await file.exists()) return;
    final currentBytes = await file.length();
    if (currentBytes + incomingBytes <= maxBytes) return;
    await _rotate(file);
  }

  static Future<void> _rotate(File file) async {
    final oldest = File('${file.path}.$backupCount');
    if (await oldest.exists()) {
      await oldest.delete();
    }

    for (var index = backupCount - 1; index >= 1; index--) {
      final source = File('${file.path}.$index');
      if (!await source.exists()) continue;
      await source.rename('${file.path}.${index + 1}');
    }

    if (await file.exists()) {
      await file.rename('${file.path}.1');
    }
  }
}
