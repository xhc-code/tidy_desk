import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

typedef _ShellExecuteC = IntPtr Function(
  IntPtr hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  Int32 nShowCmd,
);

typedef _ShellExecuteDart = int Function(
  int hwnd,
  Pointer<Utf16> lpOperation,
  Pointer<Utf16> lpFile,
  Pointer<Utf16> lpParameters,
  Pointer<Utf16> lpDirectory,
  int nShowCmd,
);

/// Win32 原生清空回收站函数签名
typedef _SHEmptyRecycleBinC = Int32 Function(
  IntPtr hwnd,
  Pointer<Utf16> pszRootPath,
  Uint32 dwFlags,
);

typedef _SHEmptyRecycleBinDart = int Function(
  int hwnd,
  Pointer<Utf16> pszRootPath,
  int dwFlags,
);

/// SHFILEOPSTRUCTW 结构体定义 (用于 SHFileOperationW 安全移入回收站)
final class _SHFILEOPSTRUCTW extends Struct {
  @IntPtr()
  external int hwnd;
  @Uint32()
  external int wFunc;
  external Pointer<Utf16> pFrom;
  external Pointer<Utf16> pTo;
  @Uint16()
  external int fFlags;
  @Int32()
  external int fAnyOperationsAborted;
  external Pointer<Void> hNameMappings;
  external Pointer<Utf16> lpszProgressTitle;
}

typedef _SHFileOperationC = Int32 Function(Pointer<_SHFILEOPSTRUCTW> lpFileOp);
typedef _SHFileOperationDart = int Function(Pointer<_SHFILEOPSTRUCTW> lpFileOp);

/// SHELLEXECUTEINFOW 结构体 (用于弹出 Windows 原生属性面板)
final class _SHELLEXECUTEINFOW extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  @IntPtr()
  external int hwnd;
  external Pointer<Utf16> lpVerb;
  external Pointer<Utf16> lpFile;
  external Pointer<Utf16> lpParameters;
  external Pointer<Utf16> lpDirectory;
  @Int32()
  external int nShow;
  @IntPtr()
  external int hInstApp;
  external Pointer<Void> lpIDList;
  external Pointer<Utf16> lpClass;
  @IntPtr()
  external int hkeyClass;
  @Uint32()
  external int dwHotKey;
  @IntPtr()
  external int hIcon;
  @IntPtr()
  external int hProcess;
}

typedef _ShellExecuteExC = Int32 Function(Pointer<_SHELLEXECUTEINFOW> pExecInfo);
typedef _ShellExecuteExDart = int Function(Pointer<_SHELLEXECUTEINFOW> pExecInfo);

typedef _CreatePopupMenuC = IntPtr Function();
typedef _CreatePopupMenuDart = int Function();

typedef _AppendMenuWC = Int32 Function(
  IntPtr hMenu,
  Uint32 uFlags,
  IntPtr uIDNewItem,
  Pointer<Utf16> lpNewItem,
);
typedef _AppendMenuWDart = int Function(
  int hMenu,
  int uFlags,
  int uIDNewItem,
  Pointer<Utf16> lpNewItem,
);

typedef _TrackPopupMenuExC = Int32 Function(
  IntPtr hMenu,
  Uint32 uFlags,
  Int32 x,
  Int32 y,
  IntPtr hWnd,
  Pointer<Void> lpTPM,
);
typedef _TrackPopupMenuExDart = int Function(
  int hMenu,
  int uFlags,
  int x,
  int y,
  int hWnd,
  Pointer<Void> lpTPM,
);

typedef _DestroyMenuC = Int32 Function(IntPtr hMenu);
typedef _DestroyMenuDart = int Function(int hMenu);

typedef _GetCursorPosC = Int32 Function(Pointer<Int32> lpPoint);
typedef _GetCursorPosDart = int Function(Pointer<Int32> lpPoint);

typedef _SetForegroundWindowC = Int32 Function(IntPtr hWnd);
typedef _SetForegroundWindowDart = int Function(int hWnd);

typedef _PostMessageWC = Int32 Function(
  IntPtr hWnd,
  Uint32 msg,
  IntPtr wParam,
  IntPtr lParam,
);
typedef _PostMessageWDart = int Function(
  int hWnd,
  int msg,
  int wParam,
  int lParam,
);

typedef _SHQueryUserNotificationStateC = Int32 Function(Pointer<Int32> pquns);
typedef _SHQueryUserNotificationStateDart = int Function(Pointer<Int32> pquns);

/// Win32 原生右键菜单项模型
class Win32MenuItem {
  final int id;
  final String text;
  final bool isSeparator;
  final VoidCallback? action;

  const Win32MenuItem({
    required this.id,
    required this.text,
    this.isSeparator = false,
    this.action,
  });

  const Win32MenuItem.separator()
      : id = 0,
        text = '',
        isSeparator = true,
        action = null;
}

/// Windows 原生 Shell API 极速交互助手 (基于 dart:ffi + shell32.dll + user32.dll)
///
/// 核心优势与规范：
/// 1. 直接调用 Windows 原生 ShellExecuteW，0 毫秒极速响应，杜绝 Process.run 带来的进程创建开销。
/// 2. 原生接管所有文件夹打开、文件关联程序启动、.lnk 快捷方式解析与资源管理器高亮定位。
/// 3. 完全兼容 Windows 10 与 Windows 11 的 Shell CLSID、系统虚拟文件夹与原生回收站 API。
/// 4. 提供 Win32 原生 SHFileOperationW 安全移入回收站（支持 Ctrl+Z 撤回）与 ShellExecuteExW 原生属性面板。
/// 5. 提供 Win32 原生 TrackPopupMenuEx 屏幕级上下文菜单（突破小窗口物理限制，永不被裁剪）。
class WindowsShellHelper {
  static final DynamicLibrary _shell32 = DynamicLibrary.open('shell32.dll');
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final _ShellExecuteDart _shellExecute = _shell32
      .lookup<NativeFunction<_ShellExecuteC>>('ShellExecuteW')
      .asFunction<_ShellExecuteDart>();

  static final _SHEmptyRecycleBinDart _shEmptyRecycleBin = _shell32
      .lookup<NativeFunction<_SHEmptyRecycleBinC>>('SHEmptyRecycleBinW')
      .asFunction<_SHEmptyRecycleBinDart>();

  static final _SHFileOperationDart _shFileOperation = _shell32
      .lookup<NativeFunction<_SHFileOperationC>>('SHFileOperationW')
      .asFunction<_SHFileOperationDart>();

  static final _ShellExecuteExDart _shellExecuteEx = _shell32
      .lookup<NativeFunction<_ShellExecuteExC>>('ShellExecuteExW')
      .asFunction<_ShellExecuteExDart>();

  static final _CreatePopupMenuDart _createPopupMenu = _user32
      .lookup<NativeFunction<_CreatePopupMenuC>>('CreatePopupMenu')
      .asFunction<_CreatePopupMenuDart>();

  static final _AppendMenuWDart _appendMenuW = _user32
      .lookup<NativeFunction<_AppendMenuWC>>('AppendMenuW')
      .asFunction<_AppendMenuWDart>();

  static final _TrackPopupMenuExDart _trackPopupMenuEx = _user32
      .lookup<NativeFunction<_TrackPopupMenuExC>>('TrackPopupMenuEx')
      .asFunction<_TrackPopupMenuExDart>();

  static final _DestroyMenuDart _destroyMenu = _user32
      .lookup<NativeFunction<_DestroyMenuC>>('DestroyMenu')
      .asFunction<_DestroyMenuDart>();

  static final _GetCursorPosDart _getCursorPos = _user32
      .lookup<NativeFunction<_GetCursorPosC>>('GetCursorPos')
      .asFunction<_GetCursorPosDart>();

  static final _SetForegroundWindowDart _setForegroundWindow = _user32
      .lookup<NativeFunction<_SetForegroundWindowC>>('SetForegroundWindow')
      .asFunction<_SetForegroundWindowDart>();

  static final _PostMessageWDart _postMessage = _user32
      .lookup<NativeFunction<_PostMessageWC>>('PostMessageW')
      .asFunction<_PostMessageWDart>();

  /// SW_SHOWNORMAL = 1 (正常激活并显示窗口)
  static const int _swShowNormal = 1;

  static const int _mfString = 0x0000;
  static const int _mfSeparator = 0x0800;
  static const int _tpmLeftAlign = 0x0000;
  static const int _tpmRightButton = 0x0002;
  static const int _tpmReturnCmd = 0x0100;
  static const int _wmNull = 0x0000;

  /// Win32 清空回收站标志位常量
  static const int _sherbNoConfirmation = 0x00000001; // 不弹出确认对话框
  static const int _sherbNoProgressUi = 0x00000002;   // 不显示进度条
  static const int _sherbNoSound = 0x00000004;        // 不播放清空音效

  /// SHFileOperation 常量
  static const int _foDelete = 0x0003;       // 删除操作
  static const int _fofAllowUndo = 0x0040;   // 移入回收站 (允许撤销)
  static const int _fofNoConfirmation = 0x0010; // 不显示确认对话框 (由应用 UI 确认)
  static const int _fofSilent = 0x0004;      // 静默执行

  /// ShellExecuteEx 常量
  static const int _seeMaskInvokeidlist = 0x0000000C; // 调用 Shell 属性

  /// 0 毫秒极速原生打开文件夹、应用程序、文件或快捷方式
  static bool openPath(String path) {
    if (path.isEmpty) return false;
    final opPtr = 'open'.toNativeUtf16();
    final pathPtr = path.toNativeUtf16();
    try {
      final result = _shellExecute(
        0,
        opPtr,
        pathPtr,
        nullptr,
        nullptr,
        _swShowNormal,
      );
      return result > 32;
    } catch (e) {
      debugPrint('WindowsShellHelper.openPath 失败: $e');
      return false;
    } finally {
      malloc.free(opPtr);
      malloc.free(pathPtr);
    }
  }

  /// 在 Windows 文件资源管理器中高亮定位并选中该文件 (explorer.exe /select,"path")
  static bool showInExplorer(String path) {
    if (path.isEmpty) return false;
    final opPtr = 'open'.toNativeUtf16();
    final explorerPtr = 'explorer.exe'.toNativeUtf16();
    final paramPtr = '/select,"$path"'.toNativeUtf16();
    try {
      final result = _shellExecute(
        0,
        opPtr,
        explorerPtr,
        paramPtr,
        nullptr,
        _swShowNormal,
      );
      return result > 32;
    } catch (e) {
      debugPrint('WindowsShellHelper.showInExplorer 失败: $e');
      return false;
    } finally {
      malloc.free(opPtr);
      malloc.free(explorerPtr);
      malloc.free(paramPtr);
    }
  }

  /// 极速打开 Windows「此电脑」(兼容 Win10 与 Win11)
  static bool openThisPC() {
    final opPtr = 'open'.toNativeUtf16();
    final explorerPtr = 'explorer.exe'.toNativeUtf16();
    final paramPtr = '::{20D04FE0-3AEA-1069-A2D8-08002B30309D}'.toNativeUtf16();
    try {
      final result = _shellExecute(
        0,
        opPtr,
        explorerPtr,
        paramPtr,
        nullptr,
        _swShowNormal,
      );
      return result > 32;
    } catch (e) {
      debugPrint('WindowsShellHelper.openThisPC 失败: $e');
      return false;
    } finally {
      malloc.free(opPtr);
      malloc.free(explorerPtr);
      malloc.free(paramPtr);
    }
  }

  /// 极速打开 Windows「回收站」(兼容 Win10 与 Win11)
  static bool openRecycleBin() {
    final opPtr = 'open'.toNativeUtf16();
    final explorerPtr = 'explorer.exe'.toNativeUtf16();
    final paramPtr = 'shell:RecycleBinFolder'.toNativeUtf16();
    try {
      final result = _shellExecute(
        0,
        opPtr,
        explorerPtr,
        paramPtr,
        nullptr,
        _swShowNormal,
      );
      return result > 32;
    } catch (e) {
      debugPrint('WindowsShellHelper.openRecycleBin 失败: $e');
      return false;
    } finally {
      malloc.free(opPtr);
      malloc.free(explorerPtr);
      malloc.free(paramPtr);
    }
  }

  /// 获取当前 Windows 用户的真实桌面物理路径
  ///
  /// 完美兼顾 Windows 10 与 Windows 11：
  /// 优先查询注册表 User Shell Folders，自动无缝适配用户开启 OneDrive 桌面云同步或手动重定向桌面的场景；
  /// 若注册表键值缺失或不可达，优雅回退至标准 %USERPROFILE%\Desktop。
  static String getActualDesktopPath() {
    try {
      final key = CURRENT_USER.open(r'Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders');
      try {
        final desktopVal = key.getString('Desktop') ?? key.getUnexpandedString('Desktop');
        if (desktopVal != null && desktopVal.isNotEmpty) {
          final userProfile = Platform.environment['USERPROFILE'] ?? '';
          final resolved = desktopVal.replaceAll('%USERPROFILE%', userProfile);
          if (Directory(resolved).existsSync()) {
            return resolved;
          }
        }
      } finally {
        key.close();
      }
    } catch (_) {}

    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.isNotEmpty) {
      final stdDesktop = Directory('$userProfile\\Desktop');
      if (stdDesktop.existsSync()) {
        return stdDesktop.path;
      }
    }
    return userProfile != null ? '$userProfile\\Desktop' : Directory.current.path;
  }

  /// 极速打开用户的真实「桌面」文件夹
  static bool openDesktopFolder(String? userDesktopPath) {
    if (userDesktopPath != null && userDesktopPath.isNotEmpty) {
      return openPath(userDesktopPath);
    }
    final actual = getActualDesktopPath();
    if (actual.isNotEmpty && Directory(actual).existsSync()) {
      return openPath(actual);
    }

    final opPtr = 'open'.toNativeUtf16();
    final explorerPtr = 'explorer.exe'.toNativeUtf16();
    final paramPtr = 'shell:Desktop'.toNativeUtf16();
    try {
      final result = _shellExecute(
        0,
        opPtr,
        explorerPtr,
        paramPtr,
        nullptr,
        _swShowNormal,
      );
      return result > 32;
    } catch (e) {
      debugPrint('WindowsShellHelper.openDesktopFolder 失败: $e');
      return false;
    } finally {
      malloc.free(opPtr);
      malloc.free(explorerPtr);
      malloc.free(paramPtr);
    }
  }

  /// 极速打开 Windows「终端 / 命令行」
  static bool openTerminal() {
    if (openPath('wt.exe')) {
      return true;
    }
    return openPath('cmd.exe');
  }

  /// 极速打开 Windows「控制面板」
  static bool openControlPanel() {
    final opPtr = 'open'.toNativeUtf16();
    final controlPtr = 'control.exe'.toNativeUtf16();
    try {
      final result = _shellExecute(
        0,
        opPtr,
        controlPtr,
        nullptr,
        nullptr,
        _swShowNormal,
      );
      return result > 32;
    } catch (e) {
      debugPrint('WindowsShellHelper.openControlPanel 失败: $e');
      return false;
    } finally {
      malloc.free(opPtr);
      malloc.free(controlPtr);
    }
  }

  /// 极速打开 Windows「显示设置」
  static bool openDisplaySettings() {
    return openPath('ms-settings:display');
  }

  /// 极速打开 Windows「个性化」
  static bool openPersonalizationSettings() {
    return openPath('ms-settings:personalization');
  }

  /// 在指定目录下极速打开 Windows 终端 / CMD
  static bool openTerminalInPath(String? path) {
    if (path != null && path.isNotEmpty) {
      final opPtr = 'open'.toNativeUtf16();
      final wtPtr = 'wt.exe'.toNativeUtf16();
      final paramPtr = '-d "$path"'.toNativeUtf16();
      try {
        final res = _shellExecute(0, opPtr, wtPtr, paramPtr, nullptr, _swShowNormal);
        if (res > 32) return true;
      } catch (_) {} finally {
        malloc.free(opPtr);
        malloc.free(wtPtr);
        malloc.free(paramPtr);
      }
    }
    return openTerminal();
  }

  /// 原生调用 Win32 SHEmptyRecycleBinW 清空所有驱动器的回收站
  static bool emptyRecycleBin({
    bool showConfirmation = true,
    bool playSound = true,
    bool showProgressUI = true,
  }) {
    int flags = 0;
    if (!showConfirmation) {
      flags |= _sherbNoConfirmation;
    }
    if (!playSound) {
      flags |= _sherbNoSound;
    }
    if (!showProgressUI) {
      flags |= _sherbNoProgressUi;
    }

    try {
      final hresult = _shEmptyRecycleBin(0, nullptr, flags);
      return hresult == 0 || hresult == -2147023673;
    } catch (e) {
      debugPrint('WindowsShellHelper.emptyRecycleBin 失败: $e');
      return false;
    }
  }

  /// Win32 原生安全将文件/文件夹移入回收站 (支持 Ctrl+Z 撤回)
  ///
  /// 调用 SHFileOperationW 并传入 FOF_ALLOWUNDO 标志。
  /// 返回 true 表示成功移入回收站。
  static bool moveToRecycleBin(String path) {
    if (path.isEmpty) return false;

    // SHFileOperation 要求字符串必须以双 null 结尾 (pFrom must be double-null terminated)
    final pathUnits = path.codeUnits;
    final buffer = malloc<Uint16>(pathUnits.length + 2);
    for (int i = 0; i < pathUnits.length; i++) {
      buffer[i] = pathUnits[i];
    }
    buffer[pathUnits.length] = 0;
    buffer[pathUnits.length + 1] = 0;

    final fileOpPtr = malloc<_SHFILEOPSTRUCTW>();
    try {
      final fileOp = fileOpPtr.ref;
      fileOp.hwnd = 0;
      fileOp.wFunc = _foDelete;
      fileOp.pFrom = buffer.cast<Utf16>();
      fileOp.pTo = nullptr;
      fileOp.fFlags = _fofAllowUndo | _fofNoConfirmation | _fofSilent;
      fileOp.fAnyOperationsAborted = 0;
      fileOp.hNameMappings = nullptr;
      fileOp.lpszProgressTitle = nullptr;

      final ret = _shFileOperation(fileOpPtr);
      return ret == 0;
    } catch (e) {
      debugPrint('WindowsShellHelper.moveToRecycleBin 失败: $e');
      return false;
    } finally {
      malloc.free(buffer);
      malloc.free(fileOpPtr);
    }
  }

  /// Win32 原生弹出 Windows 文件/文件夹属性面板 (Properties Dialog)
  ///
  /// 调用 ShellExecuteExW 传入 'properties' 动词与 SEE_MASK_INVOKEIDLIST 标志。
  static bool showProperties(String path) {
    if (path.isEmpty) return false;

    final execInfoPtr = malloc<_SHELLEXECUTEINFOW>();
    final verbPtr = 'properties'.toNativeUtf16();
    final filePtr = path.toNativeUtf16();

    try {
      final execInfo = execInfoPtr.ref;
      execInfo.cbSize = sizeOf<_SHELLEXECUTEINFOW>();
      execInfo.fMask = _seeMaskInvokeidlist;
      execInfo.hwnd = 0;
      execInfo.lpVerb = verbPtr;
      execInfo.lpFile = filePtr;
      execInfo.lpParameters = nullptr;
      execInfo.lpDirectory = nullptr;
      execInfo.nShow = _swShowNormal;
      execInfo.hInstApp = 0;
      execInfo.lpIDList = nullptr;
      execInfo.lpClass = nullptr;
      execInfo.hkeyClass = 0;
      execInfo.dwHotKey = 0;
      execInfo.hIcon = 0;
      execInfo.hProcess = 0;

      final ret = _shellExecuteEx(execInfoPtr);
      return ret != 0;
    } catch (e) {
      debugPrint('WindowsShellHelper.showProperties 失败: $e');
      return false;
    } finally {
      malloc.free(verbPtr);
      malloc.free(filePtr);
      malloc.free(execInfoPtr);
    }
  }

  /// 异步执行第三方命令行指令 (如第三方右键工具)
  static Future<bool> launchCommandLine(String commandLine, {String? workingDirectory}) async {
    try {
      if (commandLine.isEmpty) return false;
      await Process.start('cmd.exe', ['/c', commandLine], workingDirectory: workingDirectory, mode: ProcessStartMode.detached);
      return true;
    } catch (e) {
      debugPrint('WindowsShellHelper.launchCommandLine 失败: $e');
      return false;
    }
  }

  /// 弹出 Windows 屏幕原生上下文右键菜单 (不受小窗口画布/HWND物理尺寸裁剪约束，完全浮于桌面上层)
  static void showNativePopupMenu({
    required int hWnd,
    required List<Win32MenuItem> items,
  }) {
    if (items.isEmpty) return;

    final hMenu = _createPopupMenu();
    if (hMenu == 0) return;

    final pointPtr = malloc<Int32>(2);

    try {
      for (final item in items) {
        if (item.isSeparator) {
          _appendMenuW(hMenu, _mfSeparator, 0, nullptr);
        } else {
          final textPtr = item.text.toNativeUtf16();
          try {
            _appendMenuW(hMenu, _mfString, item.id, textPtr);
          } finally {
            malloc.free(textPtr);
          }
        }
      }

      _getCursorPos(pointPtr);
      final x = pointPtr[0];
      final y = pointPtr[1];

      if (hWnd != 0) {
        _setForegroundWindow(hWnd);
      }

      final cmd = _trackPopupMenuEx(
        hMenu,
        _tpmLeftAlign | _tpmRightButton | _tpmReturnCmd,
        x,
        y,
        hWnd,
        nullptr,
      );

      if (hWnd != 0) {
        _postMessage(hWnd, _wmNull, 0, 0);
      }

      if (cmd > 0) {
        for (final item in items) {
          if (!item.isSeparator && item.id == cmd) {
            item.action?.call();
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('showNativePopupMenu 失败: $e');
    } finally {
      _destroyMenu(hMenu);
      malloc.free(pointPtr);
    }
  }

  static final _SHQueryUserNotificationStateDart _shQueryUserNotificationState = _shell32
      .lookup<NativeFunction<_SHQueryUserNotificationStateC>>('SHQueryUserNotificationState')
      .asFunction<_SHQueryUserNotificationStateDart>();

  /// 通过 Windows Shell 官方标准 API (SHQueryUserNotificationState) 查询系统当前是否处于全屏/忙碌状态
  ///
  /// 该接口是微软官方为系统通知中心、DirectX 全屏游戏与全屏影音播放所设计的标准状态接口，
  /// 无需任何手动几何坐标猜测或窗口类名过滤，0 毫秒内核级直接响应。
  ///
  /// 返回值：
  /// - QUNS_BUSY (2): 存在全屏应用程序或处于演示/放映状态 (如浏览器全屏播放视频、PPT 放映)
  /// - QUNS_RUNNING_D3D_FULL_SCREEN (3): Direct3D 独占全屏 (如全屏 3D 游戏或硬件加速全屏播放器)
  /// - QUNS_PRESENTATION_MODE (4): 演示放映模式
  static bool isSystemInFullscreenMode() {
    final statePtr = malloc<Int32>();
    try {
      final hr = _shQueryUserNotificationState(statePtr);
      if (hr == 0) {
        final state = statePtr.value;
        // 2: QUNS_BUSY, 3: QUNS_RUNNING_D3D_FULL_SCREEN, 4: QUNS_PRESENTATION_MODE
        return state == 2 || state == 3 || state == 4;
      }
      return false;
    } catch (e) {
      debugPrint('SHQueryUserNotificationState 查询失败: $e');
      return false;
    } finally {
      malloc.free(statePtr);
    }
  }

  /// 获取当前鼠标光标在屏幕上的全局物理像素坐标
  static Point<int> getCursorPos() {
    final pointPtr = malloc<Int32>(2);
    try {
      _getCursorPos(pointPtr);
      return Point<int>(pointPtr[0], pointPtr[1]);
    } catch (e) {
      return const Point<int>(0, 0);
    } finally {
      malloc.free(pointPtr);
    }
  }
}
