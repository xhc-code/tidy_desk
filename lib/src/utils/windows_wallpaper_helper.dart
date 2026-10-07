import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

typedef _SystemParametersInfoNative = Int32 Function(
  Uint32 uiAction,
  Uint32 uiParam,
  Pointer<Utf16> pvParam,
  Uint32 fWinIni,
);
typedef _SystemParametersInfoDart = int Function(
  int uiAction,
  int uiParam,
  Pointer<Utf16> pvParam,
  int fWinIni,
);
final _systemParametersInfo = _user32.lookupFunction<_SystemParametersInfoNative, _SystemParametersInfoDart>('SystemParametersInfoW');

/// Windows 桌面壁纸智能获取引擎 (支持 Win32 SPI_GETDESKWALLPAPER 与 TranscodedWallpaper 多级回退)
class WindowsWallpaperHelper {
  static const int _spiGetDeskWallpaper = 0x0073;
  static String? _cachedWallpaperPath;

  /// 获取当前 Windows 桌面壁纸文件的真实本地绝对路径
  static String? getWallpaperPathSync({bool forceRefresh = false}) {
    if (!forceRefresh && _cachedWallpaperPath != null && File(_cachedWallpaperPath!).existsSync()) {
      return _cachedWallpaperPath;
    }

    try {
      // 1. 优先通过 Win32 SystemParametersInfoW(SPI_GETDESKWALLPAPER) 获取
      final path = using((Arena arena) {
        final buffer = arena<Uint16>(512);
        final result = _systemParametersInfo(_spiGetDeskWallpaper, 512, buffer.cast(), 0);
        if (result != 0) {
          final str = buffer.cast<Utf16>().toDartString().trim();
          if (str.isNotEmpty && File(str).existsSync()) {
            return str;
          }
        }
        return null;
      });

      if (path != null) {
        _cachedWallpaperPath = path;
        return path;
      }
    } catch (e) {
      debugPrint('SystemParametersInfoW 获取壁纸异常: $e');
    }

    // 2. 回退机制：读取 Windows 系统默认壁纸缓存 TranscodedWallpaper
    try {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        final transcoded = File('$appData\\Microsoft\\Windows\\Themes\\TranscodedWallpaper');
        if (transcoded.existsSync()) {
          _cachedWallpaperPath = transcoded.path;
          return transcoded.path;
        }
      }
    } catch (_) {}

    return null;
  }
}
