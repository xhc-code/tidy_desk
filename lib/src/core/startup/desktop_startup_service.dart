import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

/// Windows 开机自启动服务 (基于原生 Windows 注册表 Run 项)
class DesktopStartupService {
  DesktopStartupService._internal();
  static final DesktopStartupService instance = DesktopStartupService._internal();

  static const String _appName = 'tidy_desk';
  static const String _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';

  /// 检查当前是否已启用开机自启
  bool isStartupEnabled() {
    if (!Platform.isWindows) return false;

    try {
      final key = CURRENT_USER.open(_runKeyPath);
      try {
        final val = key.getValue(_appName);
        return val != null;
      } finally {
        key.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// 开启或关闭开机自启动
  Future<bool> setStartupEnabled(bool enable) async {
    if (!Platform.isWindows) return false;

    try {
      final key = CURRENT_USER.create(_runKeyPath);
      try {
        if (enable) {
          final exePath = Platform.resolvedExecutable;
          key.setValue(_appName, RegistryValue.string('"$exePath"'));
        } else {
          key.removeValue(_appName);
        }
        return true;
      } finally {
        key.close();
      }
    } catch (e) {
      debugPrint('DesktopStartupService setStartupEnabled error: $e');
      return false;
    }
  }
}
