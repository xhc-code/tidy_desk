import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import '../startup/desktop_startup_service.dart';
import '../window/window_manager_win32.dart';

/// 系统任务栏托盘常驻服务
class DesktopTrayService with TrayListener {
  DesktopTrayService._internal() {
    trayManager.addListener(this);
  }
  static final DesktopTrayService instance = DesktopTrayService._internal();

  VoidCallback? _onRefreshDesktop;
  VoidCallback? _onCheckUpdate;

  /// 初始化托盘图标与上下文菜单
  Future<void> initialize({
    VoidCallback? onRefreshDesktop,
    VoidCallback? onCheckUpdate,
  }) async {
    _onRefreshDesktop = onRefreshDesktop;
    _onCheckUpdate = onCheckUpdate;

    try {
      // 1. 设置托盘图标
      final iconPath = Platform.isWindows
          ? 'assets/icons/app_icon.ico'
          : 'assets/icons/app_icon.png';
      await trayManager.setIcon(iconPath);

      // 2. 设置鼠标悬停提示词
      await trayManager.setToolTip('桌面收纳盒 - 智能桌面整理');

      // 3. 构建并注入托盘右键菜单
      await updateContextMenu();
    } catch (e) {
      debugPrint('DesktopTrayService initialize error: $e');
    }
  }

  /// 刷新托盘上下文菜单 (同步自启等勾选状态)
  Future<void> updateContextMenu() async {
    try {
      final isStartup = DesktopStartupService.instance.isStartupEnabled();

      final menu = Menu(
        items: [
          MenuItem(
            key: 'toggle',
            label: '显示 / 隐藏桌面收纳盒',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'refresh',
            label: '重新扫描桌面文件',
          ),
          MenuItem.checkbox(
            key: 'startup',
            label: '开机自动启动',
            checked: isStartup,
          ),
          MenuItem(
            key: 'check_update',
            label: '检查版本更新...',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'exit',
            label: '彻底退出程序',
          ),
        ],
      );

      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('updateContextMenu error: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    // 单击托盘左键：极速切换收纳抽屉显隐
    WindowManagerWin32.instance.toggleVisibility();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 单击托盘右键：弹出上下文菜单
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'toggle':
        WindowManagerWin32.instance.toggleVisibility();
        break;
      case 'refresh':
        _onRefreshDesktop?.call();
        break;
      case 'startup':
        final current = DesktopStartupService.instance.isStartupEnabled();
        await DesktopStartupService.instance.setStartupEnabled(!current);
        await updateContextMenu();
        break;
      case 'check_update':
        _onCheckUpdate?.call();
        break;
      case 'exit':
        WindowManagerWin32.instance.closeApp();
        break;
    }
  }
}
