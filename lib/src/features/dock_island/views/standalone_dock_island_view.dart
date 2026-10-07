import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:window_manager/window_manager.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/window/window_manager_win32.dart';
import '../../../utils/file_type_helper.dart';
import '../../../utils/windows_icon_extractor.dart';
import '../../../utils/windows_shell_helper.dart';
import '../../../utils/windows_wallpaper_helper.dart';
import '../../desktop/controllers/desktop_controller.dart';
import '../../desktop/models/desktop_item.dart';
import '../services/dock_island_service.dart';
import '../services/windows_dock_positioner.dart';

/// 桌面独立常驻 macOS / Fluent 风格 Dock 悬浮挂件视图 (Standalone Dock Island Window)
class StandaloneDockIslandView extends StatefulWidget {
  final DesktopController desktopController;
  final int parentPid;

  const StandaloneDockIslandView({
    super.key,
    required this.desktopController,
    this.parentPid = 0,
  });

  @override
  State<StandaloneDockIslandView> createState() => _StandaloneDockIslandViewState();
}

class _StandaloneDockIslandViewState extends State<StandaloneDockIslandView> with WindowListener {
  final DockIslandService _dockService = DockIslandService.instance;
  final WindowManagerWin32 _winManager = WindowManagerWin32.instance;

  int _lastItemCount = -1;
  DockIslandPosition? _lastPosition;
  DockIslandSize? _lastSize;

  Timer? _fullscreenAvoidTimer;
  bool _isFullscreenActive = false;

  bool _isDockPoppedUp = true;
  bool _isPoppingUp = false;
  bool _isWindowPhysicallyHidden = false;
  bool _isDockHovered = false;
  Timer? _leaveDelayTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    // 注入 Windows DWM 硬件级毛玻璃特效 (仅启动时注入一次，彻底杜绝调节透明度时的黑白频闪)
    _initNativeBackdrop();

    // 初次打开时：若配置了自动隐藏，则初始保持收起状态并让指示条就位
    _isDockPoppedUp = !_dockService.autoHide;
    _isWindowPhysicallyHidden = _dockService.autoHide;

    // 启动本地 IPC 服务端，接收主程序零重启实时下发指令
    _dockService.startIpcServer(onConfigUpdated: (json) {
      if (mounted) {
        // 同步主程序下发的新固定/取消固定项目列表
        if (json.containsKey('pinnedItems') && json['pinnedItems'] is List) {
          final list = (json['pinnedItems'] as List).map((e) => e.toString()).toList();
          widget.desktopController.updatePinnedPathsFromRemote(list);
        }
        // 仅触发 Flutter 界面重绘与位置微调，不破坏底层 DWM 模糊帧合成
        setState(() {});
        _syncWindowBounds();
        if (_dockService.autoHide && !_isDockPoppedUp && !_isFullscreenActive) {
          WindowsDockPositioner.setWindowHiddenState(true, withIndicator: _dockService.showEdgeIndicator);
          setState(() {
            _isWindowPhysicallyHidden = true;
          });
        }
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncWindowBounds();
    });

    // 启动全屏活动检测定时器 (如浏览器全屏播放视频/游戏/PPT放映时，Dock 自动让位避让，退出全屏自动恢复)
    _fullscreenAvoidTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _checkFullscreenAvoidance();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _fullscreenAvoidTimer?.cancel();
    _leaveDelayTimer?.cancel();
    super.dispose();
  }

  @override
  void onWindowBlur() {
    // 纯事件驱动：当 Dock 处于展开状态，而用户点击了其他应用程序窗口、桌面或使用了 Alt+Tab 时，立刻触发平滑收起
    if (_dockService.autoHide && _isDockPoppedUp && !_DockIslandTileState._isAnyMenuShowing && !_isPoppingUp) {
      _isDockHovered = false;
      _retractDock(force: true);
    }
  }

  /// 展开 Dock 挂件：先将指示条彻底刷空抹除，待 GPU 交换链提交完全透明帧后再移动视窗，彻底消除跳动
  void _popupDock() {
    if (_isFullscreenActive || _isPoppingUp || _isDockPoppedUp) return;
    _leaveDelayTimer?.cancel();
    _leaveDelayTimer = null;

    _isPoppingUp = true;
    // 关键防跳动 1：先在边缘当前位置将指示条瞬间从 Flutter 视图树中移除 (SizedBox.shrink)
    _isWindowPhysicallyHidden = false;
    setState(() {});

    // 关键防跳动 2：等待 Flutter 栅格化线程将全透明帧提交至 DirectX 交换链 (35ms，保证 1-2 帧完全刷空)
    Future.delayed(const Duration(milliseconds: 35), () {
      if (!mounted) {
        _isPoppingUp = false;
        return;
      }
      // 关键防跳动 3：此时 GPU 交换链中为 100% 透明像素，移动物理视窗 100% 不会有任何画面残留跳动！
      WindowsDockPositioner.setWindowHiddenState(false);

      // 物理视窗到位后，主 Dock 开始平滑向上滑入
      setState(() {
        _isDockPoppedUp = true;
        _isPoppingUp = false;
      });
    });
  }

  /// 收起 Dock 挂件：先平滑滑动淡出，完成后再收缩物理窗口并就地呈现指示条
  void _retractDock({bool force = false}) {
    if (!mounted || !_dockService.autoHide || _DockIslandTileState._isAnyMenuShowing || _isPoppingUp) {
      return;
    }
    if (!force) {
      if (_isDockHovered) {
        return;
      }
    }
    _leaveDelayTimer?.cancel();
    _leaveDelayTimer = null;

    // 关键防跳动 4：先让主 Dock 播放滑动淡出退出动画 (220ms)，此时指示条绝对不提前渲染在半空
    setState(() {
      _isDockPoppedUp = false;
      _isWindowPhysicallyHidden = false;
    });

    // 在 220ms 滑动退出动画彻底完成、主 Dock 彻底隐形后，再将视窗物理收缩至屏幕边缘
    Future.delayed(const Duration(milliseconds: 230), () {
      if (mounted && !_isDockPoppedUp && _dockService.autoHide && !_isPoppingUp) {
        final withIndicator = !_isFullscreenActive && _dockService.showEdgeIndicator;
        WindowsDockPositioner.setWindowHiddenState(true, withIndicator: withIndicator);

        // 关键防跳动 5：视窗物理就位后，缓冲 35ms 再渲染指示条，杜绝视窗移动瞬态抖动
        Future.delayed(const Duration(milliseconds: 35), () {
          if (mounted && !_isDockPoppedUp && _dockService.autoHide && !_isPoppingUp) {
            setState(() {
              _isWindowPhysicallyHidden = true;
            });
          }
        });
      }
    });
  }

  void _onDockPointerEnter() {
    if (_isFullscreenActive) return;
    _isDockHovered = true;
    _leaveDelayTimer?.cancel();
    _leaveDelayTimer = null;
    if (!_isDockPoppedUp && !_isPoppingUp) {
      _popupDock();
    }
  }

  void _onDockPointerExit() {
    _isDockHovered = false;
    if (!_dockService.autoHide) return;
    if (_DockIslandTileState._isAnyMenuShowing) return;

    _leaveDelayTimer?.cancel();
    _leaveDelayTimer = Timer(const Duration(milliseconds: 550), () {
      _retractDock();
    });
  }

  /// 周期性检测前台窗口是否全屏，自动调整 Dock 置顶与可见性
  void _checkFullscreenAvoidance() {
    if (!mounted) return;
    // 若未开启置顶且当前未处于全屏避让状态，普通窗口层叠即可，无需额外避让
    if (!_dockService.isAlwaysOnTop && !_isFullscreenActive) return;

    final isFs = WindowsDockPositioner.isForegroundWindowFullscreen();
    if (isFs != _isFullscreenActive) {
      setState(() {
        _isFullscreenActive = isFs;
      });
      // 全屏时主动让出置顶 (HWND_NOTOPMOST)，退出全屏后若开启了置顶则恢复置顶 (HWND_TOPMOST)
      WindowsDockPositioner.setTopmost(!isFs && _dockService.isAlwaysOnTop);
      if (isFs) {
        // 进入全屏模式 (视频播放/演示/游戏): 无论是否开启感应条，全屏下均彻底隐藏，零遮挡
        _leaveDelayTimer?.cancel();
        _leaveDelayTimer = null;
        _isDockHovered = false;
        _isPoppingUp = false;
        WindowsDockPositioner.setWindowHiddenState(true, withIndicator: false);
        _isWindowPhysicallyHidden = false;
      } else {
        // 退出全屏后：必须无条件、100% 恢复物理视窗与可见性！
        if (_dockService.autoHide) {
          // 若开启了自动隐藏，恢复到收起待命状态 (若配置了指示条则正常呈现指示条)
          _isDockPoppedUp = false;
          _isWindowPhysicallyHidden = false;
          final withIndicator = _dockService.showEdgeIndicator;
          WindowsDockPositioner.setWindowHiddenState(true, withIndicator: withIndicator);
          setState(() {
            _isWindowPhysicallyHidden = true;
          });
        } else {
          // 常驻模式 (非自动隐藏)：将物理视窗立即移回屏幕内显示
          _isDockPoppedUp = true;
          _isWindowPhysicallyHidden = false;
          WindowsDockPositioner.setWindowHiddenState(false);
        }
        // 重新同步边界与显示器工作区 (防范全屏游戏改变屏幕分辨率或工作区)
        _syncWindowBounds();
      }
    }
  }

  /// 初始化独立 Dock 原生视窗 (全透底层，由内部桌面壁纸高斯模糊层呈现无瑕疵毛玻璃)
  Future<void> _initNativeBackdrop() async {
    try {
      await Window.setEffect(
        effect: WindowEffect.transparent,
      );
    } catch (e) {
      debugPrint('设置独立 Dock 材质特效异常: $e');
    }
  }

  /// 构建高斯模糊壁纸磨砂底层 (Wallpaper Frosted Glass)
  Widget _buildWallpaperBackdrop() {
    final wallpaperPath = WindowsWallpaperHelper.getWallpaperPathSync();
    if (wallpaperPath == null || !File(wallpaperPath).existsSync()) {
      return const SizedBox.shrink();
    }

    final dockPos = WindowsDockPositioner.currentDockCardPos;
    final screenSize = WindowsDockPositioner.currentDisplaySize;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 25.0, sigmaY: 25.0, tileMode: TileMode.clamp),
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: screenSize.width,
        maxWidth: screenSize.width,
        minHeight: screenSize.height,
        maxHeight: screenSize.height,
        child: Transform.translate(
          offset: Offset(-dockPos.dx, -dockPos.dy),
          child: Image.file(
            File(wallpaperPath),
            width: screenSize.width,
            height: screenSize.height,
            fit: BoxFit.cover,
            cacheWidth: 960,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// 动态计算并通过 Win32 SPI_GETWORKAREA 物理定位独立 Dock 窗口到屏幕工作区边缘中央
  void _syncWindowBounds() {
    if (!mounted) return;

    final isVertical = _dockService.position.isVertical;
    final sizeConfig = _dockService.size;
    final pinnedCount = widget.desktopController.dockPinnedItems.length;
    final totalItems = 5 + pinnedCount + 1; // 5 系统项 + N 固定项 + 1 刷新项

    final double tileDim = switch (sizeConfig) {
      DockIslandSize.compact => 46.0,
      DockIslandSize.large => 62.0,
      DockIslandSize.standard => 52.0,
    };

    // 主轴尺寸紧致且左右/上下绝对对称 (两端对称边距 + 元素总宽/高 + 分割线)
    const double edgePadding = 10.0;
    const double dividerWidth = 7.0;
    final double contentMainAxis = (edgePadding * 2) + (totalItems * (tileDim + 2.0)) + dividerWidth;
    final double contentCrossAxis = sizeConfig.height + 6.0;

    final double winWidth = isVertical ? contentCrossAxis : contentMainAxis;
    final double winHeight = isVertical ? contentMainAxis : contentCrossAxis;

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ??
        (PlatformDispatcher.instance.views.isNotEmpty
            ? PlatformDispatcher.instance.views.first.devicePixelRatio
            : 1.0);

    WindowsDockPositioner.applyDockBounds(
      position: _dockService.position,
      logicalWidth: winWidth,
      logicalHeight: winHeight,
      alwaysOnTop: _dockService.isAlwaysOnTop,
      dpr: dpr,
    ).then((_) {
      if (!mounted) return;
      if (_isFullscreenActive) {
        // 全屏模式下保持彻底隐藏
        WindowsDockPositioner.setWindowHiddenState(true, withIndicator: false);
        _isWindowPhysicallyHidden = false;
      } else if (_dockService.autoHide && !_isDockPoppedUp) {
        final withIndicator = _dockService.showEdgeIndicator;
        WindowsDockPositioner.setWindowHiddenState(true, withIndicator: withIndicator);
        setState(() {
          _isWindowPhysicallyHidden = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _dockService,
        _winManager,
        widget.desktopController,
      ]),
      builder: (context, _) {
        final isLight = _winManager.isLight;
        final sizeConfig = _dockService.size;
        final isVertical = _dockService.position.isVertical;
        final pinnedItems = widget.desktopController.dockPinnedItems;

        // 如果项目数量、停靠方位或尺寸改变，自动重新计算窗口自适应尺寸与居中位置
        final currentItemCount = pinnedItems.length;
        if (currentItemCount != _lastItemCount ||
            _dockService.position != _lastPosition ||
            _dockService.size != _lastSize) {
          _lastItemCount = currentItemCount;
          _lastPosition = _dockService.position;
          _lastSize = _dockService.size;
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncWindowBounds());
        }

        final double tileDim = switch (sizeConfig) {
          DockIslandSize.compact => 46.0,
          DockIslandSize.large => 62.0,
          DockIslandSize.standard => 52.0,
        };

        final islandTiles = [
          // 0. 主程序一键召唤入口按钮
          _DockIslandTile(
            title: '收纳盒',
            sizeConfig: sizeConfig,
            tileDim: tileDim,
            isVertical: isVertical,
            iconWidget: const Icon(
              FluentIcons.all_apps,
              size: 20,
              color: Color(0xFF0078D4),
            ),
            onTap: () {
              AppLogger.i('从常驻 Dock 召唤主收纳盒');
              _summonMainWindow();
            },
            onSecondaryTap: _showSummonNativeContextMenu,
          ),

          // 1. 系统项: 此电脑
          _DockIslandTile(
            title: '此电脑',
            sizeConfig: sizeConfig,
            tileDim: tileDim,
            isVertical: isVertical,
            iconWidget: const Icon(
              FluentIcons.devices3,
              size: 20,
              color: Color(0xFF0078D4),
            ),
            onTap: () => WindowsShellHelper.openThisPC(),
            onSecondaryTap: _showThisPCNativeContextMenu,
          ),

          // 2. 系统项: 回收站
          _DockIslandTile(
            title: '回收站',
            sizeConfig: sizeConfig,
            tileDim: tileDim,
            isVertical: isVertical,
            iconWidget: const Icon(
              FluentIcons.delete,
              size: 20,
              color: Color(0xFFD83B01),
            ),
            onTap: () => WindowsShellHelper.openRecycleBin(),
            onSecondaryTap: _showRecycleBinNativeContextMenu,
          ),

          // 3. 系统项: 桌面
          _DockIslandTile(
            title: '桌面',
            sizeConfig: sizeConfig,
            tileDim: tileDim,
            isVertical: isVertical,
            iconWidget: const Icon(
              FluentIcons.folder_horizontal,
              size: 20,
              color: Color(0xFFFFB900),
            ),
            onTap: () => WindowsShellHelper.openDesktopFolder(
              widget.desktopController.userDesktopPath,
            ),
            onSecondaryTap: _showDesktopNativeContextMenu,
          ),

          // 4. 系统项: 终端
          _DockIslandTile(
            title: '终端',
            sizeConfig: sizeConfig,
            tileDim: tileDim,
            isVertical: isVertical,
            iconWidget: const Icon(
              FluentIcons.command_prompt,
              size: 20,
              color: Color(0xFF107C41),
            ),
            onTap: () => WindowsShellHelper.openTerminal(),
            onSecondaryTap: _showTerminalNativeContextMenu,
          ),
        ];

        final double userOpacity = _dockService.opacity.clamp(0.20, 1.0);
        final bool useWallpaper = _dockService.useWallpaperBackdrop;

        // 当调节到 100% (1.0) 时，透明度达到完全不透明 (1.0)，彻底遮挡底层文本！
        final double effectiveAlpha = userOpacity >= 0.99 ? 1.0 : userOpacity;

        // 现代 Fluent Glassmorphism 拟态亚克力玻璃光影与渐变配色
        final gradientColors = isLight
            ? (useWallpaper
                ? [
                    const Color(0xFFFFFFFF).withValues(alpha: effectiveAlpha >= 0.99 ? 1.0 : (0.80 * effectiveAlpha).clamp(0.20, 1.0)),
                    const Color(0xFFF8FAFC).withValues(alpha: effectiveAlpha >= 0.99 ? 1.0 : (0.70 * effectiveAlpha).clamp(0.15, 1.0)),
                    const Color(0xFFEDF2F7).withValues(alpha: effectiveAlpha >= 0.99 ? 1.0 : (0.75 * effectiveAlpha).clamp(0.18, 1.0)),
                  ]
                : [
                    // 不采样壁纸时：采用高质感微沉灰白渐变，在纯白背景 (如编辑器/浏览器) 下也拥有清晰的轮廓反差与实体感
                    const Color(0xFFFAFBFE).withValues(alpha: effectiveAlpha),
                    const Color(0xFFECEFF4).withValues(alpha: effectiveAlpha),
                    const Color(0xFFDEE3EB).withValues(alpha: effectiveAlpha),
                  ])
            : (useWallpaper
                ? [
                    const Color(0xFF2C323D).withValues(alpha: effectiveAlpha >= 0.99 ? 1.0 : (0.85 * effectiveAlpha).clamp(0.25, 1.0)),
                    const Color(0xFF1E222A).withValues(alpha: effectiveAlpha >= 0.99 ? 1.0 : (0.75 * effectiveAlpha).clamp(0.20, 1.0)),
                    const Color(0xFF15181F).withValues(alpha: effectiveAlpha >= 0.99 ? 1.0 : (0.80 * effectiveAlpha).clamp(0.22, 1.0)),
                  ]
                : [
                    const Color(0xFF2C313C).withValues(alpha: effectiveAlpha),
                    const Color(0xFF1E2128).withValues(alpha: effectiveAlpha),
                    const Color(0xFF16181E).withValues(alpha: effectiveAlpha),
                  ]);

        // 强化清晰有力的边界感 (特别在白底背景下提供清晰有质感的分界线)
        final borderColor = isLight
            ? (useWallpaper
                ? const Color(0x30000000)
                : const Color(0x50000000))
            : (useWallpaper
                ? const Color(0x30FFFFFF)
                : const Color(0x45FFFFFF));
        final double borderWidth = isLight && !useWallpaper ? 1.2 : 1.0;

        Offset slideOffset = Offset.zero;
        if (_dockService.autoHide && !_isDockPoppedUp) {
          switch (_dockService.position) {
            case DockIslandPosition.bottomCenter:
              slideOffset = const Offset(0, 1.2);
              break;
            case DockIslandPosition.topCenter:
              slideOffset = const Offset(0, -1.2);
              break;
            case DockIslandPosition.leftCenter:
              slideOffset = const Offset(-1.2, 0);
              break;
            case DockIslandPosition.rightCenter:
              slideOffset = const Offset(1.2, 0);
              break;
          }
        }

        final double opacity = _isFullscreenActive
            ? 0.0
            : (_dockService.autoHide && !_isDockPoppedUp ? 0.0 : 1.0);

        final bool isInteractingDisabled = _isFullscreenActive ||
            (_dockService.autoHide && !_isDockPoppedUp);

        final double cardWidth = isVertical
            ? (sizeConfig.height + 6.0)
            : ((10.0 * 2) + ((5 + pinnedItems.length + 1) * (tileDim + 2.0)) + 7.0);
        final double cardHeight = isVertical
            ? ((10.0 * 2) + ((5 + pinnedItems.length + 1) * (tileDim + 2.0)) + 7.0)
            : (sizeConfig.height + 6.0);

        Alignment cardAlignment;
        switch (_dockService.position) {
          case DockIslandPosition.bottomCenter:
            cardAlignment = Alignment.topCenter;
            break;
          case DockIslandPosition.topCenter:
            cardAlignment = Alignment.bottomCenter;
            break;
          case DockIslandPosition.leftCenter:
            cardAlignment = Alignment.centerRight;
            break;
          case DockIslandPosition.rightCenter:
            cardAlignment = Alignment.centerLeft;
            break;
        }

        return MouseRegion(
          onEnter: (_) => _onDockPointerEnter(),
          onExit: (_) => _onDockPointerExit(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 0. 全透明命中底衬：确保视窗内所有区域（包括贴边透明延展带）均能稳定捕获鼠标进入/移出事件
              const Positioned.fill(
                child: ColoredBox(color: Colors.transparent),
              ),
              Align(
                alignment: cardAlignment,
                child: SizedBox(
                  width: cardWidth,
                  height: cardHeight,
                  child: AnimatedSlide(
                    offset: slideOffset,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: opacity,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      child: IgnorePointer(
                        ignoring: isInteractingDisabled,
                        child: SizedBox.expand(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              // 1. 底层与内容层：严格由 ClipRRect 裁切圆角
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16.0),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // 1.1 底层：桌面壁纸切片高斯模糊层 (Wallpaper Frosted Glass，在完全不透明 1.0 时跳过以节省 GPU)
                                    if (useWallpaper && effectiveAlpha < 0.99)
                                      _buildWallpaperBackdrop(),

                                    // 1.2 中层：半透明拟态亚克力渐变光影 / 实体底色
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: gradientColors,
                                          stops: const [0.0, 0.5, 1.0],
                                        ),
                                      ),
                                    ),

                                    // 1.3 上层：可滚动的 Dock 单元项卡片 (两端绝对对称间距)
                                    Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isVertical ? 3.0 : 10.0,
                                        vertical: isVertical ? 10.0 : 3.0,
                                      ),
                                      child: SingleChildScrollView(
                                        scrollDirection: isVertical ? Axis.vertical : Axis.horizontal,
                                        physics: isVertical ? _winManager.scrollPhysics : _winManager.horizontalScrollPhysics,
                                        child: isVertical
                                            ? Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  ...islandTiles,
                                                  // 竖向分割线
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(vertical: 3.0),
                                                    child: Container(
                                                      width: sizeConfig.height * 0.50,
                                                      height: 1.0,
                                                      color: isLight
                                                          ? Colors.black.withValues(alpha: 0.12)
                                                          : Colors.white.withValues(alpha: 0.16),
                                                    ),
                                                  ),
                                                  // 用户自定义固定项
                                                  for (final item in pinnedItems)
                                                    _DockIslandTile(
                                                      title: item.displayName,
                                                      sizeConfig: sizeConfig,
                                                      tileDim: tileDim,
                                                      isVertical: isVertical,
                                                      iconWidget: _buildItemIcon(item, sizeConfig.iconSize),
                                                      onTap: () => widget.desktopController.openItem(item),
                                                      onSecondaryTap: () => _showItemNativeContextMenu(item),
                                                    ),
                                                  // 刷新按钮
                                                  _DockIslandTile(
                                                    title: '刷新',
                                                    sizeConfig: sizeConfig,
                                                    tileDim: tileDim,
                                                    isVertical: isVertical,
                                                    iconWidget: Icon(
                                                      FluentIcons.refresh,
                                                      size: sizeConfig.iconSize - 2,
                                                      color: isLight ? Colors.grey[140] : Colors.grey[80],
                                                    ),
                                                    onTap: () => widget.desktopController.refresh(),
                                                    onSecondaryTap: _showSummonNativeContextMenu,
                                                  ),
                                                ],
                                              )
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: [
                                                  ...islandTiles,
                                                  // 横向分割线
                                                  Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 3.0),
                                                    child: Container(
                                                      width: 1.0,
                                                      height: sizeConfig.height * 0.50,
                                                      color: isLight
                                                          ? Colors.black.withValues(alpha: 0.12)
                                                          : Colors.white.withValues(alpha: 0.16),
                                                    ),
                                                  ),
                                                  // 用户自定义固定项
                                                  for (final item in pinnedItems)
                                                    _DockIslandTile(
                                                      title: item.displayName,
                                                      sizeConfig: sizeConfig,
                                                      tileDim: tileDim,
                                                      isVertical: isVertical,
                                                      iconWidget: _buildItemIcon(item, sizeConfig.iconSize),
                                                      onTap: () => widget.desktopController.openItem(item),
                                                      onSecondaryTap: () => _showItemNativeContextMenu(item),
                                                    ),
                                                  // 刷新按钮
                                                  _DockIslandTile(
                                                    title: '刷新',
                                                    sizeConfig: sizeConfig,
                                                    tileDim: tileDim,
                                                    isVertical: isVertical,
                                                    iconWidget: Icon(
                                                      FluentIcons.refresh,
                                                      size: sizeConfig.iconSize - 2,
                                                      color: isLight ? Colors.grey[140] : Colors.grey[80],
                                                    ),
                                                    onTap: () => widget.desktopController.refresh(),
                                                    onSecondaryTap: _showSummonNativeContextMenu,
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // 2. 顶层边框高光层：独立置顶绘制，永不被底层渐变背景覆盖，确保全圆角 360 度圆润无死角清晰勾勒
                              IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(16.0),
                                    border: Border.all(
                                      color: borderColor,
                                      width: borderWidth,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _buildEdgeIndicator(isLight),
            ],
          ),
        );
      },
    );
  }

  /// 构建自动隐藏收起时的边缘感应引导胶囊提示条 (清晰指示感应唤醒区域，全屏播放视频/游戏时彻底隐藏)
  Widget _buildEdgeIndicator(bool isLight) {
    final isVertical = _dockService.position.isVertical;
    final double pillWidth = isVertical ? 4.5 : 56.0;
    final double pillHeight = isVertical ? 56.0 : 4.5;

    final Alignment alignment;
    final EdgeInsets margin;
    switch (_dockService.position) {
      case DockIslandPosition.bottomCenter:
        alignment = Alignment.topCenter;
        margin = const EdgeInsets.only(top: 1.5);
        break;
      case DockIslandPosition.topCenter:
        alignment = Alignment.bottomCenter;
        margin = const EdgeInsets.only(bottom: 1.5);
        break;
      case DockIslandPosition.leftCenter:
        alignment = Alignment.centerRight;
        margin = const EdgeInsets.only(right: 1.5);
        break;
      case DockIslandPosition.rightCenter:
        alignment = Alignment.centerLeft;
        margin = const EdgeInsets.only(left: 1.5);
        break;
    }

    // 仅在物理视窗就位、已收起、非全屏、未处于滑出过渡中、开启自动隐藏且开启了指示条配置时显示
    final bool shouldShow = _dockService.autoHide &&
        !_isDockPoppedUp &&
        !_isPoppingUp &&
        _isWindowPhysicallyHidden &&
        _dockService.showEdgeIndicator &&
        !_isFullscreenActive;

    // 当 Dock 处于收起状态时，仅在靠近工作区边缘的 12px 窄条上响应鼠标进入，唤醒 Dock；
    // 其余悬挂在任务栏/屏幕外的透明区域完全不拦截鼠标，杜绝误触与循环抖动
    final double triggerW = isVertical ? 12.0 : double.infinity;
    final double triggerH = isVertical ? double.infinity : 12.0;

    return Align(
      alignment: alignment,
      child: MouseRegion(
        onEnter: (_) => _onDockPointerEnter(),
        child: SizedBox(
          width: triggerW,
          height: triggerH,
          child: ColoredBox(
            color: Colors.transparent,
            child: shouldShow
                ? Align(
                  alignment: alignment,
                  child: Container(
                    margin: margin,
                    width: pillWidth,
                    height: pillHeight,
                    decoration: BoxDecoration(
                      color: isLight
                          ? const Color(0xFF1E293B).withValues(alpha: 0.65)
                          : const Color(0xFFF8FAFC).withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: [
                        BoxShadow(
                          color: isLight
                              ? Colors.white.withValues(alpha: 0.45)
                              : Colors.black.withValues(alpha: 0.55),
                          blurRadius: 3.0,
                          spreadRadius: 0.5,
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }

  /// 弹出自定义固定项的 Windows 屏幕原生上下文右键菜单 (浮于桌面上层，永不被小窗口裁剪，无滚动条)
  void _showItemNativeContextMenu(DesktopItem item) {
    final hWnd = WindowsDockPositioner.getOwnHwnd();
    WindowsShellHelper.showNativePopupMenu(
      hWnd: hWnd,
      items: [
        Win32MenuItem(
          id: 1,
          text: '打开',
          action: () => widget.desktopController.openItem(item),
        ),
        Win32MenuItem(
          id: 2,
          text: '在资源管理器中定位',
          action: () => WindowsShellHelper.showInExplorer(item.path),
        ),
        const Win32MenuItem.separator(),
        Win32MenuItem(
          id: 3,
          text: '从常驻 Dock 移除',
          action: () => widget.desktopController.toggleDockPin(item),
        ),
      ],
    );
  }

  void _showSummonNativeContextMenu() {
    final hWnd = WindowsDockPositioner.getOwnHwnd();
    final items = <Win32MenuItem>[
      Win32MenuItem(
        id: 1,
        text: '召唤主收纳盒',
        action: () => _summonMainWindow(),
      ),
      const Win32MenuItem.separator(),
      Win32MenuItem(
        id: 2,
        text: _dockService.autoHide ? '✓ 自动隐藏 Dock (触碰边缘弹出)' : '自动隐藏 Dock (触碰边缘弹出)',
        action: () {
          final nextVal = !_dockService.autoHide;
          _dockService.setAutoHide(nextVal);
          if (!nextVal) {
            _popupDock();
          } else {
            _retractDock();
          }
        },
      ),
    ];

    if (_dockService.autoHide) {
      items.add(
        Win32MenuItem(
          id: 4,
          text: _dockService.showEdgeIndicator ? '✓ 显示边缘感应指示条' : '显示边缘感应指示条',
          action: () {
            final nextVal = !_dockService.showEdgeIndicator;
            _dockService.setShowEdgeIndicator(nextVal);
            if (_dockService.autoHide && !_isDockPoppedUp && !_isFullscreenActive) {
              WindowsDockPositioner.setWindowHiddenState(true, withIndicator: nextVal);
              setState(() {
                _isWindowPhysicallyHidden = true;
              });
            }
          },
        ),
      );
    }

    items.addAll([
      const Win32MenuItem.separator(),
      Win32MenuItem(
        id: 3,
        text: '刷新 Dock',
        action: () => widget.desktopController.refresh(),
      ),
    ]);

    WindowsShellHelper.showNativePopupMenu(
      hWnd: hWnd,
      items: items,
    );
  }

  void _showThisPCNativeContextMenu() {
    final hWnd = WindowsDockPositioner.getOwnHwnd();
    WindowsShellHelper.showNativePopupMenu(
      hWnd: hWnd,
      items: [
        Win32MenuItem(
          id: 1,
          text: '打开此电脑',
          action: () => WindowsShellHelper.openThisPC(),
        ),
        Win32MenuItem(
          id: 2,
          text: '打开控制面板',
          action: () => WindowsShellHelper.openControlPanel(),
        ),
      ],
    );
  }

  void _showRecycleBinNativeContextMenu() {
    final hWnd = WindowsDockPositioner.getOwnHwnd();
    WindowsShellHelper.showNativePopupMenu(
      hWnd: hWnd,
      items: [
        Win32MenuItem(
          id: 1,
          text: '打开回收站',
          action: () => WindowsShellHelper.openRecycleBin(),
        ),
        const Win32MenuItem.separator(),
        Win32MenuItem(
          id: 2,
          text: '清空回收站',
          action: () => WindowsShellHelper.emptyRecycleBin(showConfirmation: true, playSound: true),
        ),
      ],
    );
  }

  void _showDesktopNativeContextMenu() {
    final hWnd = WindowsDockPositioner.getOwnHwnd();
    WindowsShellHelper.showNativePopupMenu(
      hWnd: hWnd,
      items: [
        Win32MenuItem(
          id: 1,
          text: '打开桌面文件夹',
          action: () => WindowsShellHelper.openDesktopFolder(widget.desktopController.userDesktopPath),
        ),
      ],
    );
  }

  void _showTerminalNativeContextMenu() {
    final hWnd = WindowsDockPositioner.getOwnHwnd();
    WindowsShellHelper.showNativePopupMenu(
      hWnd: hWnd,
      items: [
        Win32MenuItem(
          id: 1,
          text: '启动终端',
          action: () => WindowsShellHelper.openTerminal(),
        ),
      ],
    );
  }

  /// 一键召唤并前置激活主收纳盒大窗口
  void _summonMainWindow() {
    try {
      WindowsDockPositioner.summonMainWindow(widget.parentPid);
    } catch (e) {
      debugPrint('召唤主程序异常: $e');
    }
  }

  /// 渲染自定义固定项图标 (支持动画加载占位与无缝淡入)
  Widget _buildItemIcon(DesktopItem item, double size) {
    return _DockItemAnimatedIcon(
      item: item,
      size: size,
    );
  }
}

/// 具有平滑加载过渡与呼吸微光占位的 Dock 图标组件
class _DockItemAnimatedIcon extends StatefulWidget {
  final DesktopItem item;
  final double size;

  const _DockItemAnimatedIcon({
    required this.item,
    required this.size,
  });

  @override
  State<_DockItemAnimatedIcon> createState() => _DockItemAnimatedIconState();
}

class _DockItemAnimatedIconState extends State<_DockItemAnimatedIcon> {
  ImageProvider? _imageProvider;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoadIcon();
  }

  @override
  void didUpdateWidget(covariant _DockItemAnimatedIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _imageProvider = null;
      _checkAndLoadIcon();
    }
  }

  void _checkAndLoadIcon() {
    if (widget.item.isDirectory) return;

    final cached = WindowsIconExtractor.getImageProvider(widget.item.path);
    if (cached != null) {
      _imageProvider = cached;
      _isLoading = false;
      return;
    }

    _isLoading = true;
    WindowsIconExtractor.extractIconToPng(widget.item.path).then((pngPath) {
      if (mounted) {
        final provider = WindowsIconExtractor.getImageProvider(widget.item.path);
        setState(() {
          _imageProvider = provider;
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;

    if (widget.item.isDirectory) {
      return Icon(
        FluentIcons.folder,
        size: widget.size,
        color: const Color(0xFFFFB900),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      child: _imageProvider != null
          ? Image(
              key: ValueKey('icon_${widget.item.path}'),
              image: _imageProvider!,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildFallback(isLight),
            )
          : (_isLoading
              ? _DockIconShimmerPlaceholder(
                  key: ValueKey('shimmer_${widget.item.path}'),
                  item: widget.item,
                  size: widget.size,
                )
              : _buildFallback(isLight)),
    );
  }

  Widget _buildFallback(bool isLight) {
    final iconData = FileTypeHelper.getIconForExtension(widget.item.extension, false);
    final color = FileTypeHelper.getAccentColor(widget.item.extension, false, isLight);
    return Icon(
      iconData,
      size: widget.size,
      color: color,
    );
  }
}

/// 呼吸式微光加载占位组件
class _DockIconShimmerPlaceholder extends StatefulWidget {
  final DesktopItem item;
  final double size;

  const _DockIconShimmerPlaceholder({
    super.key,
    required this.item,
    required this.size,
  });

  @override
  State<_DockIconShimmerPlaceholder> createState() => _DockIconShimmerPlaceholderState();
}

class _DockIconShimmerPlaceholderState extends State<_DockIconShimmerPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.35, end: 0.90).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final iconData = FileTypeHelper.getIconForExtension(widget.item.extension, false);
    final baseColor = FileTypeHelper.getAccentColor(widget.item.extension, false, isLight);

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        return Opacity(
          opacity: _pulseAnimation.value,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor.withValues(alpha: 0.12 * _pulseAnimation.value),
                ),
              ),
              Icon(
                iconData,
                size: widget.size,
                color: baseColor.withValues(alpha: 0.85),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 独立 Dock 单元项卡片 (macOS 原生轻量高亮交互)
class _DockIslandTile extends StatefulWidget {
  final String title;
  final Widget iconWidget;
  final VoidCallback onTap;
  final VoidCallback? onSecondaryTap;
  final DockIslandSize sizeConfig;
  final double tileDim;
  final bool isVertical;

  const _DockIslandTile({
    required this.title,
    required this.iconWidget,
    required this.onTap,
    this.onSecondaryTap,
    required this.sizeConfig,
    required this.tileDim,
    this.isVertical = false,
  });

  @override
  State<_DockIslandTile> createState() => _DockIslandTileState();
}

class _DockIslandTileState extends State<_DockIslandTile> {
  /// 全局记录上一次右键菜单关闭的时间戳，用于在取消右键时拦截穿透到 Dock 的多余点击（与主窗口 ModalBarrier 行为保持一致）
  static DateTime _globalLastMenuClosedTime = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _isAnyMenuShowing = false;

  bool _isHovered = false;
  bool _isPressed = false;
  bool _isMenuOpen = false;

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accent = winManager.currentThemeStyle.accentColor;

    // 当右键菜单展开或按下时，持续保持明确强烈的焦点选中高亮状态
    final bool isActive = _isPressed || _isMenuOpen;

    final Color bgColor;
    final Border border;
    final List<BoxShadow>? shadows;

    if (isActive) {
      bgColor = accent.withValues(alpha: isLight ? 0.24 : 0.35);
      border = Border.all(
        color: accent.withValues(alpha: isLight ? 0.65 : 0.80),
        width: 1.2,
      );
      shadows = [
        BoxShadow(
          color: accent.withValues(alpha: isLight ? 0.22 : 0.35),
          blurRadius: 6.0,
          offset: const Offset(0, 1.5),
        ),
      ];
    } else if (_isHovered) {
      bgColor = isLight
          ? Colors.black.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.14);
      border = Border.all(
        color: isLight
            ? Colors.black.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.16),
        width: 1.0,
      );
      shadows = null;
    } else {
      bgColor = Colors.transparent;
      border = Border.all(color: Colors.transparent, width: 1.0);
      shadows = null;
    }

    final double w = widget.tileDim;
    final double h = widget.tileDim - 2;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          final msSinceClose = DateTime.now().difference(_globalLastMenuClosedTime).inMilliseconds;
          if (_isAnyMenuShowing || msSinceClose < 350) {
            return;
          }
          setState(() => _isPressed = true);
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onSecondaryTapDown: (_) => setState(() => _isPressed = true),
        onSecondaryTapCancel: () => setState(() => _isPressed = false),
        onTap: () {
          final msSinceClose = DateTime.now().difference(_globalLastMenuClosedTime).inMilliseconds;
          if (_isAnyMenuShowing || msSinceClose < 350) {
            // 用户点击是用于关闭/取消右键菜单的，完全拦截吞掉，绝不触发打开应用！
            return;
          }
          widget.onTap();
        },
        onSecondaryTapUp: (_) async {
          if (widget.onSecondaryTap != null) {
            _isAnyMenuShowing = true;
            if (mounted) {
              setState(() {
                _isPressed = false;
                _isMenuOpen = true;
              });
            }
            // 稍作微小延迟让 Flutter 完成高亮帧的渲染绘制并呈现在屏幕上，再触发原生右键菜单阻塞循环
            await Future.delayed(const Duration(milliseconds: 30));
            try {
              widget.onSecondaryTap?.call();
            } finally {
              _globalLastMenuClosedTime = DateTime.now();
              _isAnyMenuShowing = false;
              if (mounted) {
                setState(() {
                  _isMenuOpen = false;
                });
              }
            }
          } else {
            if (mounted) setState(() => _isPressed = false);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          width: w,
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
          margin: EdgeInsets.symmetric(
            horizontal: widget.isVertical ? 0 : 1.0,
            vertical: widget.isVertical ? 1.0 : 0,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8.0),
            border: border,
            boxShadow: shadows,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                height: widget.sizeConfig.iconSize + 2,
                child: Center(child: widget.iconWidget),
              ),
              const SizedBox(height: 1),
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.sizeConfig.fontSize,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  color: (_isHovered || _isMenuOpen)
                      ? (isActive ? accent : (isLight ? const Color(0xFF0F172A) : Colors.white))
                      : winManager.textColor.withValues(alpha: 0.88),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
