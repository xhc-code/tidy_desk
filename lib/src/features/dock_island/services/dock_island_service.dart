import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/window/window_manager_win32.dart';

/// 独立 Dock 停靠位置模式 (固定四个居中方位)
enum DockIslandPosition {
  /// 屏幕底部居中 (水平横向)
  bottomCenter('底部居中', '固定在屏幕底部中央'),

  /// 屏幕顶部居中 (水平横向)
  topCenter('顶部居中', '固定在屏幕顶部中央'),

  /// 屏幕左侧居中 (垂直竖向)
  leftCenter('左侧居中', '垂直停靠在屏幕左侧中央'),

  /// 屏幕右侧居中 (垂直竖向)
  rightCenter('右侧居中', '垂直停靠在屏幕右侧中央');

  final String label;
  final String description;

  const DockIslandPosition(this.label, this.description);

  bool get isVertical => this == DockIslandPosition.leftCenter || this == DockIslandPosition.rightCenter;

  static DockIslandPosition fromString(String? val) {
    if (val == null) return DockIslandPosition.bottomCenter;
    return DockIslandPosition.values.firstWhere(
      (e) => e.name == val,
      orElse: () => DockIslandPosition.bottomCenter,
    );
  }
}

/// 独立 Dock 尺寸规格
enum DockIslandSize {
  /// 紧凑微型 (44px)
  compact('紧凑精致', 44.0, 18.0, 9.0),

  /// 标准适中 (52px)
  standard('标准平衡', 52.0, 22.0, 10.0),

  /// 舒适大号 (62px)
  large('大号醒目', 62.0, 26.0, 11.5);

  final String label;
  final double height;
  final double iconSize;
  final double fontSize;

  const DockIslandSize(this.label, this.height, this.iconSize, this.fontSize);

  static DockIslandSize fromString(String? val) {
    if (val == null) return DockIslandSize.standard;
    return DockIslandSize.values.firstWhere(
      (e) => e.name == val,
      orElse: () => DockIslandSize.standard,
    );
  }
}

/// 桌面独立 Dock 挂件全局配置、生命周期与 IPC 高速通信服务 (ChangeNotifier 单例)
class DockIslandService extends ChangeNotifier {
  DockIslandService._internal();
  static final DockIslandService instance = DockIslandService._internal();

  static const String _prefEnabledKey = 'pref_dock_island_enabled';
  static const String _prefPositionKey = 'pref_dock_island_position';
  static const String _prefSizeKey = 'pref_dock_island_size';
  static const String _prefAlwaysOnTopKey = 'pref_dock_island_always_on_top';
  static const String _prefAutoHideKey = 'pref_dock_island_auto_hide';
  static const String _prefShowEdgeIndicatorKey = 'pref_dock_island_show_edge_indicator';
  static const String _prefOpacityKey = 'pref_dock_island_opacity';
  static const String _prefDockPinnedItemsKey = 'pref_dock_pinned_items';
  static const String _prefUseWallpaperBackdropKey = 'pref_dock_island_use_wallpaper_backdrop';

  /// 独立 Dock 进程 IPC 端口记录文件路径
  String get _ipcPortFilePath => p.join(Directory.systemTemp.path, 'tidy_desk_dock_ipc.port');

  /// 主程序 IPC 端口记录文件路径
  String get _mainIpcPortFilePath => p.join(Directory.systemTemp.path, 'tidy_desk_main_ipc.port');

  HttpServer? _mainIpcServer;

  /// 是否启用独立桌面常驻 Dock 挂件
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  /// 停靠位置
  DockIslandPosition _position = DockIslandPosition.bottomCenter;
  DockIslandPosition get position => _position;

  /// 尺寸规格
  DockIslandSize _size = DockIslandSize.standard;
  DockIslandSize get size => _size;

  /// 是否始终置顶
  bool _isAlwaysOnTop = true;
  bool get isAlwaysOnTop => _isAlwaysOnTop;
  bool get alwaysOnTop => _isAlwaysOnTop;

  /// 是否自动隐藏 (鼠标移至屏幕边缘时才滑出)
  bool _autoHide = false;
  bool get autoHide => _autoHide;

  /// 是否在收起时显示边缘感应指示条 (胶囊提示条，让人清晰看出感应唤醒区域)
  bool _showEdgeIndicator = true;
  bool get showEdgeIndicator => _showEdgeIndicator;

  /// 不透明度 (0.50 ~ 1.0，默认 1.0 / 100% 完全不透明)
  double _opacity = 1.0;
  double get opacity => _opacity;

  /// 是否采样桌面壁纸作为毛玻璃背景
  bool _useWallpaperBackdrop = true;
  bool get useWallpaperBackdrop => _useWallpaperBackdrop;

  /// 后台运行的独立 Dock 子进程实例 (主程序持有)
  Process? _dockProcess;
  HttpServer? _ipcServer;

  /// 初始化并装载本地持久化配置
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefEnabledKey) ?? false;
      _position = DockIslandPosition.fromString(prefs.getString(_prefPositionKey));
      _size = DockIslandSize.fromString(prefs.getString(_prefSizeKey));
      _isAlwaysOnTop = prefs.getBool(_prefAlwaysOnTopKey) ?? true;
      _autoHide = prefs.getBool(_prefAutoHideKey) ?? false;
      _showEdgeIndicator = prefs.getBool(_prefShowEdgeIndicatorKey) ?? true;
      _opacity = prefs.getDouble(_prefOpacityKey) ?? 1.0;
      _useWallpaperBackdrop = prefs.getBool(_prefUseWallpaperBackdropKey) ?? true;
      AppLogger.i('DockIslandService 初始化装载完成: 启用=$_isEnabled, 位置=${_position.label}, 尺寸=${_size.label}, 自动隐藏=$_autoHide, 感应提示条=$_showEdgeIndicator, 壁纸毛玻璃=$_useWallpaperBackdrop');
    } catch (e, stack) {
      AppLogger.e('DockIslandService 初始化装载异常: $e', e, stack);
    }
  }

  /// 启动独立 Dock 进程的 IPC 本地高速通信服务端 (0 毫秒通信，杜绝重启闪烁)
  Future<void> startIpcServer({required void Function(Map<String, dynamic> json) onConfigUpdated}) async {
    try {
      await _ipcServer?.close(force: true);
      _ipcServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _ipcServer!.port;
      final file = File(_ipcPortFilePath);
      await file.writeAsString('$port');
      AppLogger.i('Dock 挂件 IPC 服务已启动在端口: $port');

      _ipcServer!.listen((HttpRequest req) async {
        try {
          if (req.method == 'POST') {
            final content = await utf8.decoder.bind(req).join();
            if (content.isNotEmpty) {
              final json = jsonDecode(content) as Map<String, dynamic>;
              _applyRemoteConfig(json);
              onConfigUpdated(json);
            }
            req.response.statusCode = HttpStatus.ok;
            req.response.write('ok');
            await req.response.close();
          } else {
            req.response.statusCode = HttpStatus.methodNotAllowed;
            await req.response.close();
          }
        } catch (e) {
          debugPrint('处理 IPC 请求异常: $e');
        }
      });
    } catch (e, stack) {
      AppLogger.e('启动 Dock IPC 服务失败: $e', e, stack);
    }
  }

  /// 应用主进程下发过来的最新配置
  void _applyRemoteConfig(Map<String, dynamic> json) {
    if (json.containsKey('position')) {
      _position = DockIslandPosition.fromString(json['position'] as String?);
    }
    if (json.containsKey('size')) {
      _size = DockIslandSize.fromString(json['size'] as String?);
    }
    if (json.containsKey('opacity')) {
      _opacity = (json['opacity'] as num).toDouble().clamp(0.50, 1.0);
    }
    if (json.containsKey('alwaysOnTop')) {
      _isAlwaysOnTop = json['alwaysOnTop'] as bool;
    }
    if (json.containsKey('autoHide')) {
      _autoHide = json['autoHide'] as bool;
    }
    if (json.containsKey('showEdgeIndicator')) {
      _showEdgeIndicator = json['showEdgeIndicator'] as bool;
    }
    if (json.containsKey('useWallpaperBackdrop')) {
      _useWallpaperBackdrop = json['useWallpaperBackdrop'] as bool;
    }
    notifyListeners();
  }

  /// 向独立 Dock 子进程发送 IPC 配置更新 (无需重启进程，毫秒级响应)
  Future<bool> sendIpcConfig({List<String>? pinnedItems, bool? useWallpaperBackdrop}) async {
    try {
      final file = File(_ipcPortFilePath);
      if (!file.existsSync()) return false;
      final portStr = await file.readAsString();
      final port = int.tryParse(portStr.trim());
      if (port == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final currentPinned = pinnedItems ?? prefs.getStringList(_prefDockPinnedItemsKey) ?? [];

      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 200);
      final req = await client.post('127.0.0.1', port, '/update');
      req.headers.contentType = ContentType.json;
      final payload = {
        'position': _position.name,
        'size': _size.name,
        'opacity': _opacity,
        'alwaysOnTop': _isAlwaysOnTop,
        'autoHide': _autoHide,
        'showEdgeIndicator': _showEdgeIndicator,
        'pinnedItems': currentPinned,
        'useWallpaperBackdrop': useWallpaperBackdrop ?? _useWallpaperBackdrop,
      };
      req.write(jsonEncode(payload));
      final resp = await req.close();
      client.close();
      return resp.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  /// 启动主程序 IPC 通信服务 (供独立 Dock 挂件一键召唤/前置展示主收纳盒大窗口)
  Future<void> startMainIpcServer() async {
    try {
      await _mainIpcServer?.close(force: true);
      _mainIpcServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _mainIpcServer!.port;
      final file = File(_mainIpcPortFilePath);
      await file.writeAsString('$port');

      _mainIpcServer!.listen((HttpRequest req) async {
        try {
          if (req.uri.path == '/summon' || req.uri.path == '/show') {
            WindowManagerWin32.instance.show();
            req.response.statusCode = HttpStatus.ok;
            req.response.write('ok');
          } else {
            req.response.statusCode = HttpStatus.notFound;
          }
          await req.response.close();
        } catch (_) {}
      });
      AppLogger.i('主程序 IPC 唤醒监听服务已就绪，端口: $port');
    } catch (e) {
      debugPrint('启动主程序 IPC 异常: $e');
    }
  }

  /// 停止主程序 IPC 服务并清理端口文件
  Future<void> stopMainIpcServer() async {
    try {
      await _mainIpcServer?.close(force: true);
      final file = File(_mainIpcPortFilePath);
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  /// 从独立 Dock 向主程序发起召唤唤起请求
  Future<bool> sendSummonRequestToMainApp() async {
    try {
      final file = File(_mainIpcPortFilePath);
      if (!file.existsSync()) return false;
      final portStr = await file.readAsString();
      final port = int.tryParse(portStr.trim());
      if (port == null || port <= 0) return false;

      final client = HttpClient()..connectionTimeout = const Duration(milliseconds: 300);
      final req = await client.post('127.0.0.1', port, '/summon');
      final resp = await req.close();
      client.close();
      return resp.statusCode == HttpStatus.ok;
    } catch (_) {
      return false;
    }
  }

  /// 切换常驻 Dock 开启/关闭
  Future<void> setEnabled(bool enabled) async {
    if (_isEnabled == enabled) return;
    _isEnabled = enabled;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabledKey, enabled);

    if (enabled) {
      await launchDockProcess();
    } else {
      await terminateDockProcess();
    }
  }

  /// 设置停靠位置 (IPC 实时通信，零重启)
  Future<void> setPosition(DockIslandPosition newPos) async {
    if (_position == newPos) return;
    _position = newPos;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefPositionKey, newPos.name);

    if (_isEnabled) {
      final ok = await sendIpcConfig();
      if (!ok) await launchDockProcess();
    }
  }

  /// 设置尺寸规格 (IPC 实时通信，零重启)
  Future<void> setSize(DockIslandSize newSize) async {
    if (_size == newSize) return;
    _size = newSize;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSizeKey, newSize.name);

    if (_isEnabled) {
      final ok = await sendIpcConfig();
      if (!ok) await launchDockProcess();
    }
  }

  /// 设置是否始终置顶 (IPC 实时通信，零重启)
  Future<void> setAlwaysOnTop(bool onTop) async {
    if (_isAlwaysOnTop == onTop) return;
    _isAlwaysOnTop = onTop;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAlwaysOnTopKey, onTop);

    if (_isEnabled) {
      final ok = await sendIpcConfig();
      if (!ok) await launchDockProcess();
    }
  }

  /// 设置是否自动隐藏 (鼠标移动到屏幕边缘才弹出，IPC 实时通信，零重启)
  Future<void> setAutoHide(bool val) async {
    if (_autoHide == val) return;
    _autoHide = val;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefAutoHideKey, val);

    if (_isEnabled) {
      final ok = await sendIpcConfig();
      if (!ok) await launchDockProcess();
    }
  }

  /// 设置收起时是否显示边缘感应提示条 (胶囊提示条，让人看出感应唤醒区域，IPC 实时通信，零重启)
  Future<void> setShowEdgeIndicator(bool val) async {
    if (_showEdgeIndicator == val) return;
    _showEdgeIndicator = val;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefShowEdgeIndicatorKey, val);

    if (_isEnabled) {
      final ok = await sendIpcConfig();
      if (!ok) await launchDockProcess();
    }
  }

  /// 设置不透明度 (IPC 实时通信，零重启)
  Future<void> setOpacity(double val) async {
    _opacity = val.clamp(0.50, 1.0);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_prefOpacityKey, _opacity);

    if (_isEnabled) {
      final ok = await sendIpcConfig();
      if (!ok) await launchDockProcess();
    }
  }

  /// 设置是否采样桌面壁纸作为毛玻璃底色 (IPC 实时通信，零重启)
  Future<void> setUseWallpaperBackdrop(bool val) async {
    if (_useWallpaperBackdrop == val) return;
    _useWallpaperBackdrop = val;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefUseWallpaperBackdropKey, val);

    if (_isEnabled) {
      final ok = await sendIpcConfig(useWallpaperBackdrop: val);
      if (!ok) await launchDockProcess();
    }
  }

  /// 由主程序拉起独立常驻 Dock 挂件子进程
  Future<void> launchDockProcess() async {
    try {
      await terminateDockProcess(); // 先杀死残留旧进程

      final exePath = Platform.resolvedExecutable;
      final mainPid = pid;
      _dockProcess = await Process.start(
        exePath,
        ['--dock-island', '--parent-pid=$mainPid'],
        mode: ProcessStartMode.detached,
      );
      AppLogger.i('成功拉起独立常驻 Dock 子进程: PID=${_dockProcess?.pid}, 绑定的主程序 PID=$mainPid');
    } catch (e, stack) {
      AppLogger.e('拉起独立常驻 Dock 进程失败: $e', e, stack);
    }
  }

  /// 终止正在运行的独立 Dock 子进程
  Future<void> terminateDockProcess() async {
    try {
      await _ipcServer?.close(force: true);
      _ipcServer = null;

      final file = File(_ipcPortFilePath);
      if (file.existsSync()) {
        try { file.deleteSync(); } catch (_) {}
      }

      if (_dockProcess != null) {
        _dockProcess!.kill();
        _dockProcess = null;
      }
    } catch (e) {
      debugPrint('终止 Dock 进程异常: $e');
    }
  }
}
