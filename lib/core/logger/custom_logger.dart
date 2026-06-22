// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:loggy/loggy.dart';

class ConsolePrinter extends LoggyPrinter {
  const ConsolePrinter({this.showColors = false});

  final bool showColors;

  static final _levelColors = {
    LogLevel.debug: AnsiColor(foregroundColor: AnsiColor.grey(0.5), italic: true),
    LogLevel.info: AnsiColor(foregroundColor: 35),
    LogLevel.warning: AnsiColor(foregroundColor: 214),
    LogLevel.error: AnsiColor(foregroundColor: 196),
  };

  @override
  void onLog(LogRecord record) {
    final colorize = showColors && stdout.supportsAnsiEscapes;
    final time = record.time.toIso8601String().split('T')[1];
    final callerFrame = record.callerFrame == null ? ' ' : ' (${record.callerFrame?.location}) ';

    final String logLevel;
    if (colorize) {
      logLevel = record.level.name.toUpperCase().padRight(8);
    } else {
      logLevel = "[${record.level.name.toUpperCase()}]".padRight(10);
    }

    final color = showColors ? levelColor(record.level) ?? AnsiColor() : AnsiColor();

    print(color('$time $logLevel [${record.loggerName}]$callerFrame${record.message}'));

    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  }

  AnsiColor? levelColor(LogLevel level) {
    return _levelColors[level];
  }
}

class FileLogPrinter extends LoggyPrinter {
  FileLogPrinter(String filePath, {this.minLevel = LogLevel.debug}) : _logFile = File(filePath);

  final File _logFile;
  final LogLevel minLevel;
  StringBuffer _buffer = StringBuffer();
  Timer? _flushTimer;

  @override
  void onLog(LogRecord record) {
    final time = record.time.toIso8601String().split('T')[1];
    _buffer.writeln("$time - $record");
    if (record.error != null) {
      _buffer.writeln(record.error);
    }
    if (record.stackTrace != null) {
      _buffer.writeln(record.stackTrace);
    }

    if (_buffer.length >= 64 * 1024) {
      _flush();
    } else {
      _flushTimer ??= Timer(const Duration(milliseconds: 500), _flush);
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _flush();
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final content = _buffer.toString();
    _buffer = StringBuffer();
    unawaited(RotatingFileLog.append(_logFile, content).catchError((_) {}));
  }
}
