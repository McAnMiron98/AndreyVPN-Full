import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

class Win32TrayFocusFix {
  Win32TrayFocusFix._();

  static DynamicLibrary? _user32;
  static int? _lastHwnd;

  static const int _wmNull = 0x0000;

  static DynamicLibrary get _user32Library {
    final existing = _user32;
    if (existing != null) return existing;
    final loaded = DynamicLibrary.open('user32.dll');
    _user32 = loaded;
    return loaded;
  }

  static int _findWindow({required String? className, required String? windowName}) {
    final findWindow = _user32Library.lookupFunction<
        IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName),
        int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName)>('FindWindowW');

    final Pointer<Utf16> classPtr = className == null ? nullptr : className.toNativeUtf16();
    final Pointer<Utf16> windowPtr = windowName == null ? nullptr : windowName.toNativeUtf16();
    try {
      return findWindow(classPtr, windowPtr);
    } finally {
      if (className != null) calloc.free(classPtr);
      if (windowName != null) calloc.free(windowPtr);
    }
  }

  static String prepareForNativeTrayMenu({required String expectedTitle}) {
    if (!Platform.isWindows) return 'skipped platform=${Platform.operatingSystem}';
    try {
      var hwnd = _findWindow(
        className: 'FLUTTER_RUNNER_WIN32_WINDOW',
        windowName: expectedTitle,
      );
      var source = 'class_and_title';

      if (hwnd == 0) {
        hwnd = _findWindow(
          className: 'FLUTTER_RUNNER_WIN32_WINDOW',
          windowName: null,
        );
        source = 'class_only';
      }

      if (hwnd == 0) {
        _lastHwnd = null;
        return 'hwnd_not_found expectedTitle=$expectedTitle';
      }

      final setForegroundWindow = _user32Library.lookupFunction<
          Int32 Function(IntPtr hWnd),
          int Function(int hWnd)>('SetForegroundWindow');
      final ok = setForegroundWindow(hwnd);
      _lastHwnd = hwnd;
      return 'hwnd=0x${hwnd.toRadixString(16)} source=$source setForeground=$ok';
    } catch (error) {
      _lastHwnd = null;
      return 'failed errorType=${error.runtimeType} error=$error';
    }
  }

  static String postMenuMessagePumpNudge() {
    if (!Platform.isWindows) return 'skipped platform=${Platform.operatingSystem}';
    final hwnd = _lastHwnd;
    if (hwnd == null || hwnd == 0) return 'skipped no_hwnd';
    try {
      final postMessage = _user32Library.lookupFunction<
          Int32 Function(IntPtr hWnd, Uint32 msg, IntPtr wParam, IntPtr lParam),
          int Function(int hWnd, int msg, int wParam, int lParam)>('PostMessageW');
      final ok = postMessage(hwnd, _wmNull, 0, 0);
      return 'hwnd=0x${hwnd.toRadixString(16)} wm_null_posted=$ok';
    } catch (error) {
      return 'failed errorType=${error.runtimeType} error=$error';
    }
  }
}
