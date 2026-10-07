import 'dart:async';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'src/core/hotkey/desktop_hotkey_service.dart';
import 'src/core/logging/app_logger.dart';
import 'src/core/tray/desktop_tray_service.dart';
import 'src/core/update/services/app_update_service.dart';
import 'src/core/window/window_manager_win32.dart';
import 'src/features/categories/services/category_manager.dart';
import 'src/features/desktop/controllers/desktop_controller.dart';
import 'src/features/desktop/views/desktop_main_view.dart';
import 'src/features/dock_island/services/dock_island_service.dart';
import 'src/features/dock_island/services/windows_dock_positioner.dart';
import 'src/features/dock_island/views/standalone_dock_island_view.dart';
import 'src/features/settings/views/widgets/app_update_dialog.dart';
import 'src/utils/windows_icon_extractor.dart';

/// 应用程序入口 (支持主收纳盒与独立常驻 Dock 挂件双模式启动)
Future<void> main(List<String> args) async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // 限制 Flutter 内存图像缓存上限
    PaintingBinding.instance.imageCache.maximumSize = 300;
    PaintingBinding.instance.imageCache.maximumSizeBytes = 30 * 1024 * 1024; // 30MB

    // 0. 初始化全局日志系统
    await AppLogger.initialize();
    AppLogger.i('tidy_desk 正在启动... (args: $args)');

    FlutterError.onError = (FlutterErrorDetails details) {
      final exceptionStr = details.exceptionAsString();
      // 过滤 Windows 平台 RawKeyboard 针对 Win(Meta)/修饰键按下的已知引擎层断言 (Flutter Bug #86790, #95697)
      if (exceptionStr.contains('event is! RawKeyDownEvent || _keysPressed.isNotEmpty')) {
        return;
      }
      FlutterError.presentError(details);
      AppLogger.e('Flutter 框架未捕获异常: $exceptionStr', details.exception, details.stack);
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      final errStr = error.toString();
      if (errStr.contains('event is! RawKeyDownEvent || _keysPressed.isNotEmpty')) {
        return true;
      }
      AppLogger.e('平台异步调度未捕获异常: $error', error, stack);
      return true;
    };

    // 1. 初始化材质引擎与窗口管理器
    await Window.initialize();
    await windowManager.ensureInitialized();

    // 2. 初始化分类引擎与 Dock 服务
    await CategoryManager.instance.initialize();
    await DockIslandService.instance.initialize();

    // 判断是否以独立 Dock 挂件模式启动
    if (args.any((a) => a.startsWith('--dock-island'))) {
      await _runStandaloneDockIsland(args);
    } else {
      await _runMainTidyDeskApp();
    }
  }, (error, stack) {
    AppLogger.fatal('runZonedGuarded 根级致命异常: $error', error, stack);
  });
}

/// 模式 A：启动独立桌面常驻 Dock 挂件 (支持 4 方位居中停靠、Acrylic 毛玻璃与父进程退出同步)
Future<void> _runStandaloneDockIsland(List<String> args) async {
  AppLogger.i('正在启动独立常驻 Dock 挂件窗口...');
  final dockService = DockIslandService.instance;
  final winManager = WindowManagerWin32.instance;
  await winManager.initializeForStandaloneDock();

  // 解析绑定的主程序 PID 并启动存活看门狗 (主程序退出时挂件必须同步退出)
  int? parentPid;
  for (final arg in args) {
    if (arg.startsWith('--parent-pid=')) {
      parentPid = int.tryParse(arg.substring('--parent-pid='.length));
    }
  }

  if (parentPid != null) {
    Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      try {
        final result = await Process.run(
          'tasklist',
          ['/FI', 'PID eq $parentPid', '/NH'],
        );
        final output = result.stdout.toString();
        if (!output.contains('$parentPid')) {
          AppLogger.i('主程序 (PID: $parentPid) 已退出，独立常驻 Dock 随之同步安全退出。');
          timer.cancel();
          exit(0);
        }
      } catch (_) {
        timer.cancel();
        exit(0);
      }
    });
  }

  final isVertical = dockService.position.isVertical;
  final double tileDim = switch (dockService.size) {
    DockIslandSize.compact => 46.0,
    DockIslandSize.large => 62.0,
    DockIslandSize.standard => 52.0,
  };

  // 读取已固定的项数，首帧即按完整项数精准计算，绝不缺图标或拉伸
  final prefs = await SharedPreferences.getInstance();
  final pinnedCount = prefs.getStringList('pref_dock_pinned_items')?.length ?? 0;
  final totalItems = 5 + pinnedCount + 1; // 5 系统项 + N 固定项 + 1 刷新项

  const double edgePadding = 10.0;
  const double dividerWidth = 7.0;
  final double estMainAxis = (edgePadding * 2) + (totalItems * (tileDim + 2.0)) + dividerWidth;
  final double estCrossAxis = dockService.size.height + 6.0;

  final dockWinWidth = isVertical ? estCrossAxis : estMainAxis;
  final dockWinHeight = isVertical ? estMainAxis : estCrossAxis;

  final windowOptions = WindowOptions(
    size: Size(dockWinWidth, dockWinHeight),
    backgroundColor: Colors.transparent,
    skipTaskbar: true, // 任务栏不占位
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: dockService.isAlwaysOnTop,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(false);
    await windowManager.setMinimumSize(const Size(1, 1));
    await windowManager.setAlwaysOnTop(dockService.isAlwaysOnTop);
    await windowManager.setBackgroundColor(Colors.transparent);

    // 独立常驻 Dock 采用纯净透视底层 (WindowEffect.transparent)，配合内部桌面壁纸高斯模糊层
    // 彻底根除 Windows 10 DWM 底层矩形灰三角与毛玻璃外溢，兼得真毛玻璃磨砂质感与无瑕圆角
    try {
      await Window.setEffect(
        effect: WindowEffect.transparent,
      );
    } catch (e) {
      debugPrint('设置独立 Dock 材质异常: $e');
    }

    final dpr = PlatformDispatcher.instance.views.isNotEmpty
        ? PlatformDispatcher.instance.views.first.devicePixelRatio
        : 1.0;

    // 先根据当前屏幕物理工作区精确定位，再展示窗口，杜绝任何视觉跳跃与频闪
    await WindowsDockPositioner.applyDockBounds(
      position: dockService.position,
      logicalWidth: dockWinWidth,
      logicalHeight: dockWinHeight,
      alwaysOnTop: dockService.isAlwaysOnTop,
      dpr: dpr,
    );

    await windowManager.show();
    AppLogger.i('独立 Dock 挂件窗口展示就绪: 方位=${dockService.position.label}');
  });

  runApp(StandaloneDockIslandApp(parentPid: parentPid ?? 0));
}

/// 模式 B：启动主桌面收纳盒程序
Future<void> _runMainTidyDeskApp() async {
  // 初始化全局召唤热键服务
  await DesktopHotkeyService.instance.initialize();

  // 初始化在线升级服务
  await AppUpdateService.instance.initialize();

  // 初始化应用级窗口管理器并注册退出联动清理钩子
  final winManager = WindowManagerWin32.instance;
  winManager.onBeforeExit = () {
    AppLogger.i('主程序正在退出，主动终止独立常驻 Dock 挂件进程...');
    DockIslandService.instance.stopMainIpcServer();
    DockIslandService.instance.terminateDockProcess();
  };
  await winManager.initialize();

  // 启动主程序 IPC 唤醒监听服务 (接收来自独立 Dock 的一键唤醒指令)
  await DockIslandService.instance.startMainIpcServer();

  final windowOptions = WindowOptions(
    size: Size(winManager.windowWidth, winManager.windowHeight),
    minimumSize: const Size(
      WindowManagerWin32.minWindowWidth,
      WindowManagerWin32.minWindowHeight,
    ),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(
      WindowManagerWin32.minWindowWidth,
      WindowManagerWin32.minWindowHeight,
    ));
    await windowManager.setSize(Size(winManager.windowWidth, winManager.windowHeight));
    await windowManager.show();
    await windowManager.focus();
    AppLogger.i('主窗口展示与焦点获取就绪');
  });

  // 如果用户开启了常驻 Dock，主程序启动时顺带拉起独立 Dock
  if (DockIslandService.instance.isEnabled) {
    DockIslandService.instance.launchDockProcess();
  }

  runApp(const TidyDeskApp());
}

/// 独立常驻 Dock 挂件根组件
class StandaloneDockIslandApp extends StatefulWidget {
  final int parentPid;

  const StandaloneDockIslandApp({
    super.key,
    this.parentPid = 0,
  });

  @override
  State<StandaloneDockIslandApp> createState() => _StandaloneDockIslandAppState();
}

class _StandaloneDockIslandAppState extends State<StandaloneDockIslandApp> {
  late final DesktopController _desktopController;

  @override
  void initState() {
    super.initState();
    _desktopController = DesktopController();
  }

  @override
  void dispose() {
    _desktopController.dispose();
    WindowsIconExtractor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;

    return ListenableBuilder(
      listenable: winManager,
      builder: (context, _) {
        final isLight = winManager.isLight;

        return FluentApp(
          title: '桌面常驻 Dock - Tidy Desk',
          debugShowCheckedModeBanner: false,
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
          theme: FluentThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.transparent,
            fontFamily: 'AlibabaPuHuiTi',
          ),
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.transparent,
            fontFamily: 'AlibabaPuHuiTi',
          ),
          home: ColoredBox(
            color: Colors.transparent,
            child: StandaloneDockIslandView(
              desktopController: _desktopController,
              parentPid: widget.parentPid,
            ),
          ),
        );
      },
    );
  }
}

/// 桌面收纳应用根组件 (主程序)
class TidyDeskApp extends StatefulWidget {
  const TidyDeskApp({super.key});

  @override
  State<TidyDeskApp> createState() => _TidyDeskAppState();
}

class _TidyDeskAppState extends State<TidyDeskApp> {
  late final DesktopController _desktopController;

  @override
  void initState() {
    super.initState();
    _desktopController = DesktopController();

    DesktopTrayService.instance.initialize(
      onRefreshDesktop: () => _desktopController.refreshItems(),
      onCheckUpdate: () => _triggerCheckUpdate(manual: true),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          _triggerCheckUpdate(manual: false);
        }
      });
    });
  }

  Future<void> _triggerCheckUpdate({required bool manual}) async {
    try {
      final updateInfo = manual
          ? await AppUpdateService.instance.checkForUpdate()
          : await AppUpdateService.instance.silentlyCheckOnStartup();

      if (!mounted) return;

      if (updateInfo != null) {
        await AppUpdateDialog.show(context, updateInfo);
      } else if (manual) {
        await showDialog(
          context: context,
          builder: (ctx) => ContentDialog(
            title: const Text('已是最新版本'),
            content: const Text(
              '当前已安装最新版本 (v${AppUpdateService.currentAppVersion})，暂无可用更新。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('好的'),
              ),
            ],
          ),
        );
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _desktopController.dispose();
    WindowsIconExtractor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;

    return ListenableBuilder(
      listenable: winManager,
      builder: (context, _) {
        final isLight = winManager.isLight;

        return FluentApp(
          title: '桌面收纳盒 - Tidy Desk',
          debugShowCheckedModeBanner: false,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [Locale('zh', 'CN')],
          themeMode: isLight ? ThemeMode.light : ThemeMode.dark,
          theme: FluentThemeData(
            brightness: Brightness.light,
            scaffoldBackgroundColor: Colors.transparent,
            accentColor: Colors.blue,
            visualDensity: VisualDensity.compact,
            fontFamily: 'AlibabaPuHuiTi',
            focusTheme: const FocusThemeData(
              glowColor: Colors.transparent,
              primaryBorder: BorderSide.none,
              secondaryBorder: BorderSide.none,
            ),
          ),
          darkTheme: FluentThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor: Colors.transparent,
            accentColor: Colors.blue,
            visualDensity: VisualDensity.compact,
            fontFamily: 'AlibabaPuHuiTi',
            focusTheme: const FocusThemeData(
              glowColor: Colors.transparent,
              primaryBorder: BorderSide.none,
              secondaryBorder: BorderSide.none,
            ),
          ),
          home: ColoredBox(
            color: Colors.transparent,
            child: DesktopMainView(
              desktopController: _desktopController,
            ),
          ),
        );
      },
    );
  }
}
