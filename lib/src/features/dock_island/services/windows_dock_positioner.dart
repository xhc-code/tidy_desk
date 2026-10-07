import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';
import '../../../utils/windows_shell_helper.dart';
import 'dock_island_service.dart';

final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');
final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');

typedef _ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);
final _showWindow = _user32.lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');

typedef _SetForegroundWindowNative = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);
final _setForegroundWindow = _user32.lookupFunction<_SetForegroundWindowNative, _SetForegroundWindowDart>('SetForegroundWindow');

typedef _GetWindowThreadProcessIdNative = Uint32 Function(IntPtr hWnd, Pointer<Uint32> lpdwProcessId);
typedef _GetWindowThreadProcessIdDart = int Function(int hWnd, Pointer<Uint32> lpdwProcessId);
final _getWindowThreadProcessId = _user32.lookupFunction<_GetWindowThreadProcessIdNative, _GetWindowThreadProcessIdDart>('GetWindowThreadProcessId');

typedef _GetCurrentProcessIdNative = Uint32 Function();
typedef _GetCurrentProcessIdDart = int Function();
final _getCurrentProcessId = _kernel32.lookupFunction<_GetCurrentProcessIdNative, _GetCurrentProcessIdDart>('GetCurrentProcessId');

typedef _IsWindowVisibleNative = Int32 Function(IntPtr hWnd);
typedef _IsWindowVisibleDart = int Function(int hWnd);
final _isWindowVisible = _user32.lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>('IsWindowVisible');

typedef _GetClassNameNative = Int32 Function(IntPtr hWnd, Pointer<Utf16> lpClassName, Int32 nMaxCount);
typedef _GetClassNameDart = int Function(int hWnd, Pointer<Utf16> lpClassName, int nMaxCount);
final _getClassName = _user32.lookupFunction<_GetClassNameNative, _GetClassNameDart>('GetClassNameW');

typedef _GetParentNative = IntPtr Function(IntPtr hWnd);
typedef _GetParentDart = int Function(int hWnd);
final _getParent = _user32.lookupFunction<_GetParentNative, _GetParentDart>('GetParent');

typedef _EnumWindowsProc = Int32 Function(IntPtr hwnd, IntPtr lParam);
typedef _EnumWindowsNative = Int32 Function(Pointer<NativeFunction<_EnumWindowsProc>> lpEnumFunc, IntPtr lParam);
typedef _EnumWindowsDart = int Function(Pointer<NativeFunction<_EnumWindowsProc>> lpEnumFunc, int lParam);
final _enumWindows = _user32.lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');

typedef _SetWindowLongPtrNative = IntPtr Function(IntPtr hWnd, Int32 nIndex, IntPtr dwNewLong);
typedef _SetWindowLongPtrDart = int Function(int hWnd, int nIndex, int dwNewLong);
final _setWindowLongPtr = _user32.lookupFunction<_SetWindowLongPtrNative, _SetWindowLongPtrDart>('SetWindowLongPtrW');

typedef _SetWindowPosNative = Int32 Function(IntPtr hWnd, IntPtr hWndInsertAfter, Int32 X, Int32 Y, Int32 cx, Int32 cy, Uint32 uFlags);
typedef _SetWindowPosDart = int Function(int hWnd, int hWndInsertAfter, int X, int Y, int cx, int cy, int uFlags);
final _setWindowPos = _user32.lookupFunction<_SetWindowPosNative, _SetWindowPosDart>('SetWindowPos');

typedef _SetWindowRgnNative = Int32 Function(IntPtr hWnd, IntPtr hRgn, Int32 bRedraw);
typedef _SetWindowRgnDart = int Function(int hWnd, int hRgn, int bRedraw);
final _setWindowRgn = _user32.lookupFunction<_SetWindowRgnNative, _SetWindowRgnDart>('SetWindowRgn');

int _foundProcessHwnd = 0;
int _searchingPid = 0;

int _enumWindowsCallback(int hwnd, int lParam) {
  using((Arena arena) {
    final pidPtr = arena<Uint32>();
    _getWindowThreadProcessId(hwnd, pidPtr);
    if (pidPtr.value == _searchingPid) {
      if (_getParent(hwnd) != 0) return;
      final buf = arena<Uint16>(256);
      final len = _getClassName(hwnd, buf.cast(), 256);
      if (len > 0) {
        final className = buf.cast<Utf16>().toDartString();
        if (className == 'FLUTTER_RUNNER_WIN32_WINDOW') {
          _foundProcessHwnd = hwnd;
          return;
        }
      }
      if (_foundProcessHwnd == 0 && _isWindowVisible(hwnd) != 0) {
        _foundProcessHwnd = hwnd;
      }
    }
  });
  if (_foundProcessHwnd != 0) return 0;
  return 1;
}

/// 跨平台、高健壮性的 Dock 悬浮挂件位置与尺寸管理引擎
class WindowsDockPositioner {
  static const int _gwlStyle = -16;
  static const int _wsPopup = 0x80000000;
  static const int _wsVisible = 0x10000000;
  static const int _wsClipSiblings = 0x04000000;
  static const int _wsClipChildren = 0x02000000;

  static const int _hwndTopMost = -1;
  static const int _hwndNoTopMost = -2;
  static const int _swpFrameChanged = 0x0020;
  static const int _swpNoActivate = 0x0010;
  static const int _swpShowWindow = 0x0040;

  static int _cachedHwnd = 0;
  static Offset currentDockPos = Offset.zero;
  static Offset currentDockCardPos = Offset.zero;
  static Size currentDisplaySize = const Size(1920, 1080);
  static DockIslandPosition currentPosition = DockIslandPosition.bottomCenter;
  static double currentLogicalWidth = 400;
  static double currentLogicalHeight = 54;
  static double currentWindowWidth = 400;
  static double currentWindowHeight = 62;
  static Offset currentVisiblePos = Offset.zero;
  static Size currentVisibleSize = const Size(1920, 1080);
  static double currentScale = 1.0;
  static bool isDockHidden = false;

  static const double edgeMargin = 8.0;
  static const int _swpNoZOrder = 0x0004;

  /// 计算在屏幕边缘隐藏时的物理坐标 (贴着屏幕边缘收起，释放上方/内侧全部点击区域)
  /// [withIndicator] 为 true 时保留 8px 作为胶囊指示条展示区；为 false 时仅留 2px 极窄无感线
  static Offset getHiddenPosition({bool withIndicator = false}) {
    final double visibleThickness = withIndicator ? 8.0 : 2.0;
    switch (currentPosition) {
      case DockIslandPosition.bottomCenter:
        return Offset(currentDockPos.dx, currentVisiblePos.dy + currentVisibleSize.height - visibleThickness);
      case DockIslandPosition.topCenter:
        return Offset(currentDockPos.dx, currentVisiblePos.dy - currentWindowHeight + visibleThickness);
      case DockIslandPosition.leftCenter:
        return Offset(currentVisiblePos.dx - currentWindowWidth + visibleThickness, currentDockPos.dy);
      case DockIslandPosition.rightCenter:
        return Offset(currentVisiblePos.dx + currentVisibleSize.width - visibleThickness, currentDockPos.dy);
    }
  }

  /// 物理切换 Dock 窗口显示/边缘隐藏位置 (0毫秒 DWM 硬件合成移动，无画面重建与闪烁)
  static void setWindowHiddenState(bool hidden, {bool withIndicator = false}) {
    final hWnd = getOwnHwnd();
    if (hWnd == 0) return;

    isDockHidden = hidden;
    final targetOffset = hidden ? getHiddenPosition(withIndicator: withIndicator) : currentDockPos;
    final scale = currentScale <= 0 ? 1.0 : currentScale;
    final px = (targetOffset.dx * scale).round();
    final py = (targetOffset.dy * scale).round();

    _setWindowPos(
      hWnd,
      0,
      px,
      py,
      0,
      0,
      _swpNoSize | _swpNoZOrder | _swpNoActivate | _swpShowWindow,
    );
  }

  /// 检测鼠标光标当前是否移动到 Dock 对应的屏幕触发边缘 (严格限定在工作区贴边区域，避免深处任务栏干扰)
  static bool isCursorAtDockEdge() {
    final p = WindowsShellHelper.getCursorPos();
    final scale = currentScale <= 0 ? 1.0 : currentScale;
    final cursorX = p.x / scale;
    final cursorY = p.y / scale;

    const double triggerThickness = 12.0; // 屏幕边缘 12px 敏感触发区 (包含 8px 指示条 + 4px 缓冲区)
    const double spanMargin = 40.0;       // 宽度方向拓展感应区域

    switch (currentPosition) {
      case DockIslandPosition.bottomCenter:
        final bottomEdge = currentVisiblePos.dy + currentVisibleSize.height;
        return cursorY >= (bottomEdge - triggerThickness) &&
            cursorY <= (bottomEdge + 3) &&
            cursorX >= (currentDockPos.dx - spanMargin) &&
            cursorX <= (currentDockPos.dx + currentWindowWidth + spanMargin);
      case DockIslandPosition.topCenter:
        final topEdge = currentVisiblePos.dy;
        return cursorY <= (topEdge + triggerThickness) &&
            cursorY >= (topEdge - 3) &&
            cursorX >= (currentDockPos.dx - spanMargin) &&
            cursorX <= (currentDockPos.dx + currentWindowWidth + spanMargin);
      case DockIslandPosition.leftCenter:
        final leftEdge = currentVisiblePos.dx;
        return cursorX <= (leftEdge + triggerThickness) &&
            cursorX >= (leftEdge - 3) &&
            cursorY >= (currentDockPos.dy - spanMargin) &&
            cursorY <= (currentDockPos.dy + currentWindowHeight + spanMargin);
      case DockIslandPosition.rightCenter:
        final rightEdge = currentVisiblePos.dx + currentVisibleSize.width;
        return cursorX >= (rightEdge - triggerThickness) &&
            cursorX <= (rightEdge + 3) &&
            cursorY >= (currentDockPos.dy - spanMargin) &&
            cursorY <= (currentDockPos.dy + currentWindowHeight + spanMargin);
    }
  }

  /// 检测全局鼠标光标是否在当前 Dock 物理视窗及贴边过渡范围内 (彻底杜绝鼠标移到最底部时跌出视窗误触发隐藏)
  static bool isCursorInsideDockArea() {
    final p = WindowsShellHelper.getCursorPos();
    final scale = currentScale <= 0 ? 1.0 : currentScale;
    final cursorX = p.x / scale;
    final cursorY = p.y / scale;

    const double margin = 12.0;
    switch (currentPosition) {
      case DockIslandPosition.bottomCenter:
        final bottomEdge = currentVisiblePos.dy + currentVisibleSize.height;
        return cursorX >= (currentDockPos.dx - margin) &&
            cursorX <= (currentDockPos.dx + currentWindowWidth + margin) &&
            cursorY >= (currentDockPos.dy - margin) &&
            cursorY <= (bottomEdge + 3);
      case DockIslandPosition.topCenter:
        final topEdge = currentVisiblePos.dy;
        return cursorX >= (currentDockPos.dx - margin) &&
            cursorX <= (currentDockPos.dx + currentWindowWidth + margin) &&
            cursorY >= (topEdge - 3) &&
            cursorY <= (currentDockPos.dy + currentWindowHeight + margin);
      case DockIslandPosition.leftCenter:
        final leftEdge = currentVisiblePos.dx;
        return cursorX >= (leftEdge - 3) &&
            cursorX <= (currentDockPos.dx + currentWindowWidth + margin) &&
            cursorY >= (currentDockPos.dy - margin) &&
            cursorY <= (currentDockPos.dy + currentWindowHeight + margin);
      case DockIslandPosition.rightCenter:
        final rightEdge = currentVisiblePos.dx + currentVisibleSize.width;
        return cursorX >= (currentDockPos.dx - margin) &&
            cursorX <= (rightEdge + 3) &&
            cursorY >= (currentDockPos.dy - margin) &&
            cursorY <= (currentDockPos.dy + currentWindowHeight + margin);
    }
  }

  /// 获取当前独立 Dock 进程的真实 Flutter HWND
  static int getOwnHwnd() {
    if (_cachedHwnd != 0 && _isWindowVisible(_cachedHwnd) != 0) {
      return _cachedHwnd;
    }
    _foundProcessHwnd = 0;
    _searchingPid = _getCurrentProcessId();
    final enumProcPtr = Pointer.fromFunction<_EnumWindowsProc>(_enumWindowsCallback, 0);
    _enumWindows(enumProcPtr, 0);
    if (_foundProcessHwnd != 0) {
      _cachedHwnd = _foundProcessHwnd;
    }
    return _cachedHwnd;
  }

  /// 获取主程序进程的真实 Flutter HWND
  static int getParentHwnd(int parentPid) {
    if (parentPid <= 0) return 0;
    _foundProcessHwnd = 0;
    _searchingPid = parentPid;
    final enumProcPtr = Pointer.fromFunction<_EnumWindowsProc>(_enumWindowsCallback, 0);
    _enumWindows(enumProcPtr, 0);
    return _foundProcessHwnd;
  }

  /// 计算并绝对精确定位 Dock 窗口到屏幕工作区边缘中央
  static Future<void> applyDockBounds({
    required DockIslandPosition position,
    required double logicalWidth,
    required double logicalHeight,
    required bool alwaysOnTop,
    double? dpr,
  }) async {
    try {
      // 1. 获取主显示器真实可见工作区 (自动排除任务栏)
      final Display display = await screenRetriever.getPrimaryDisplay();
      final Offset visiblePos = display.visiblePosition ?? Offset.zero;
      final Size visibleSize = display.visibleSize ?? display.size;

      final bool isVertical = position.isVertical;
      // 视窗在靠近屏幕边缘的一侧增加 edgeMargin (8px) 透明延展区，彻底连接到屏幕工作区边缘
      final double windowWidth = isVertical ? logicalWidth + edgeMargin : logicalWidth;
      final double windowHeight = isVertical ? logicalHeight : logicalHeight + edgeMargin;

      // 2. 在逻辑像素坐标系下精确计算四方位居中坐标与卡片真实物理坐标
      double targetX = 0;
      double targetY = 0;
      double cardX = 0;
      double cardY = 0;

      switch (position) {
        case DockIslandPosition.topCenter:
          targetX = visiblePos.dx + (visibleSize.width - logicalWidth) / 2;
          targetY = visiblePos.dy; // 贴顶
          cardX = targetX;
          cardY = targetY + edgeMargin;
          break;
        case DockIslandPosition.bottomCenter:
          targetX = visiblePos.dx + (visibleSize.width - logicalWidth) / 2;
          targetY = visiblePos.dy + visibleSize.height - windowHeight; // 贴底
          cardX = targetX;
          cardY = targetY;
          break;
        case DockIslandPosition.leftCenter:
          targetX = visiblePos.dx; // 贴左
          targetY = visiblePos.dy + (visibleSize.height - logicalHeight) / 2;
          cardX = targetX + edgeMargin;
          cardY = targetY;
          break;
        case DockIslandPosition.rightCenter:
          targetX = visiblePos.dx + visibleSize.width - windowWidth; // 贴右
          targetY = visiblePos.dy + (visibleSize.height - logicalHeight) / 2;
          cardX = targetX;
          cardY = targetY;
          break;
      }

      // 3. 边界防溢出保护
      if (targetX + windowWidth > visiblePos.dx + visibleSize.width) {
        targetX = visiblePos.dx + visibleSize.width - windowWidth;
      }
      if (targetX < visiblePos.dx) {
        targetX = visiblePos.dx;
      }
      if (targetY + windowHeight > visiblePos.dy + visibleSize.height) {
        targetY = visiblePos.dy + visibleSize.height - windowHeight;
      }
      if (targetY < visiblePos.dy) {
        targetY = visiblePos.dy;
      }

      // 4. 同步状态变量与 windowManager
      currentPosition = position;
      currentLogicalWidth = logicalWidth;
      currentLogicalHeight = logicalHeight;
      currentWindowWidth = windowWidth;
      currentWindowHeight = windowHeight;
      currentVisiblePos = visiblePos;
      currentVisibleSize = visibleSize;
      currentScale = dpr ?? 1.0;
      currentDockPos = Offset(targetX, targetY);
      currentDockCardPos = Offset(cardX, cardY);
      currentDisplaySize = display.size;

      await windowManager.setSize(Size(windowWidth, windowHeight));
      await windowManager.setPosition(Offset(targetX, targetY));
      if (alwaysOnTop) {
        await windowManager.setAlwaysOnTop(true);
      }

      // 5. 原生层解除 WS_THICKFRAME 最小限制 (允许物理 HWND 真正缩小至超小尺寸)
      final hWnd = getOwnHwnd();
      if (hWnd != 0) {
        final scale = dpr ?? 1.0;
        final physicalW = (windowWidth * scale).round();
        final physicalH = (windowHeight * scale).round();
        final physicalX = (targetX * scale).round();
        final physicalY = (targetY * scale).round();

        // 切换为 WS_POPUP 纯净无边框样式 (彻底消除 Windows 对窗口的 136px 强制限制)
        _setWindowLongPtr(
          hWnd,
          _gwlStyle,
          _wsPopup | _wsVisible | _wsClipSiblings | _wsClipChildren,
        );

        final zOrder = alwaysOnTop ? _hwndTopMost : _hwndNoTopMost;
        _setWindowPos(
          hWnd,
          zOrder,
          physicalX,
          physicalY,
          physicalW,
          physicalH,
          _swpFrameChanged | _swpNoActivate | _swpShowWindow,
        );

        // 清除任何 GDI 1-bit 二进制裁剪区域，交由 Flutter Skia 引擎进行全抗锯齿 32-bit ARGB 平滑圆角渲染
        _setWindowRgn(hWnd, 0, 1);
      }
    } catch (e) {
      debugPrint('applyDockBounds 异常: $e');
    }
  }

  /// 唤醒主收纳盒大窗口 (从独立 Dock 点击一键召唤)
  static Future<void> summonMainWindow(int parentPid) async {
    try {
      // 通道 1: 优先通过本地 HTTP IPC 向主进程发送唤醒指令 (主程序执行 show + focus)
      final ipcSuccess = await DockIslandService.instance.sendSummonRequestToMainApp();

      // 通道 2: Win32 原生层前置激活并恢复主窗口 (SW_RESTORE + SetForegroundWindow)
      int parentHwnd = 0;
      if (parentPid > 0) {
        parentHwnd = getParentHwnd(parentPid);
        if (parentHwnd != 0) {
          _showWindow(parentHwnd, 9); // SW_RESTORE (9: 还原最小化并激活展示)
          _setForegroundWindow(parentHwnd);
        }
      }

      // 通道 3: 若主进程未在运行 (IPC 失败且未寻获窗口)，自启拉起主程序
      if (!ipcSuccess && parentHwnd == 0) {
        final exePath = Platform.resolvedExecutable;
        await Process.start(exePath, [], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      debugPrint('召唤主程序异常: $e');
    }
  }

  static const int _swpNoMove = 0x0002;
  static const int _swpNoSize = 0x0001;

  /// 动态调整独立 Dock 窗口置顶状态 (如在全屏视频播放时主动解除置顶让位，退出全屏后恢复置顶)
  static void setTopmost(bool topmost) {
    final hWnd = getOwnHwnd();
    if (hWnd != 0) {
      final zOrder = topmost ? _hwndTopMost : _hwndNoTopMost;
      _setWindowPos(
        hWnd,
        zOrder,
        0,
        0,
        0,
        0,
        _swpNoMove | _swpNoSize | _swpNoActivate | _swpShowWindow,
      );
    }
  }

  /// 检测当前系统最前台活动窗口是否处于全屏状态 (基于 Windows Shell 官方标准 API SHQueryUserNotificationState)
  static bool isForegroundWindowFullscreen() {
    return WindowsShellHelper.isSystemInFullscreenMode();
  }
}
