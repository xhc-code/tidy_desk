import 'dart:async';
import 'dart:ui';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/window/native_drag_area.dart';
import '../../../core/window/window_manager_win32.dart';
import '../../../utils/file_type_helper.dart';
import '../../../utils/system_hardware_helper.dart';
import '../../categories/models/custom_category.dart';
import '../../categories/services/category_manager.dart';
import '../controllers/desktop_controller.dart';
import 'desktop_grid_view.dart';
import 'widgets/desktop_bottom_dock.dart';
import '../../settings/views/settings_view.dart';

/// 桌面主视图页面 (全景横向收纳抽屉 · 完美对标 easyDesktop 高颜值与原生 WM_NCHITTEST 拖拽)
class DesktopMainView extends StatefulWidget {
  final DesktopController desktopController;

  const DesktopMainView({
    super.key,
    required this.desktopController,
  });

  @override
  State<DesktopMainView> createState() => _DesktopMainViewState();
}

class _DesktopMainViewState extends State<DesktopMainView> {
  final WindowManagerWin32 _winManager = WindowManagerWin32.instance;

  bool _isSettingsSelected = false;
  bool _isDraggingOver = false;
  final ValueNotifier<bool> _isGridScrolledNotifier = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isGridScrolledNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _winManager,
      builder: (context, _) {
        final currentStyle = _winManager.currentThemeStyle;
        final opacity = _winManager.panelOpacity;
        final isLight = _winManager.isLight;

        // 真实动态不透明度：滑块 20%~100% 线性对应真实通透度，将选择权完全交给用户
        final double effectiveAlpha = opacity.clamp(0.20, 1.0);

        final overlayColor = currentStyle.baseColor.withValues(
          alpha: effectiveAlpha,
        );

        return NativeResizeArea(
          edgeThickness: 4.0,
          cornerSize: 10.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16.0),
              color: overlayColor,
              border: Border.all(
                color: isLight
                    ? const Color(0x38000000) // 浅色模式下：高对比度深色精致边框，清晰勾勒边界
                    : _winManager.windowBorderColor,
                width: 1.2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.0),
              child: DropTarget(
                onDragEntered: (detail) => setState(() => _isDraggingOver = true),
                onDragExited: (detail) => setState(() => _isDraggingOver = false),
                onDragDone: (detail) async {
                  setState(() => _isDraggingOver = false);
                  final filePaths = detail.files.map((e) => e.path).toList();
                  if (filePaths.isNotEmpty) {
                    await widget.desktopController.handleDroppedFiles(filePaths);
                  }
                },
                child: Stack(
                  children: [
                    // 【全景底层】：整个窗口底层铺满 NativeDragArea (0ms onPointerDown 原生拖拽，空白处随手一抓即可移动)
                    const Positioned.fill(
                      child: NativeDragArea(
                        child: SizedBox.expand(),
                      ),
                    ),

                    // 【顶层】：主界面交互层
                    Positioned.fill(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 1. 顶部全景控制栏 (底层全宽 WM_NCHITTEST 原生拖拽 + 顶层交互组件)
                          RepaintBoundary(
                            child: _buildTopHeader(),
                          ),

                          // 2. 水平分类子导航栏 (全部、文档、媒体、快捷、文件夹)
                          if (!_isSettingsSelected)
                            RepaintBoundary(
                              child: _buildHorizontalCategoryBar(),
                            ),

                          // 3. 主体内容展示区 (文件网格或设置面板)
                          Expanded(
                            child: _isSettingsSelected
                                ? SettingsView(
                                    desktopController: widget.desktopController,
                                    onBack: () => setState(() => _isSettingsSelected = false),
                                  )
                                : _buildContentArea(),
                          ),
                        ],
                      ),
                    ),

                    // 【顶层悬浮微提示】：新建/保存文件即时定位与快捷打开操作胶囊 (非阻塞式，居底悬浮)
                    Positioned(
                      bottom: _isSettingsSelected
                          ? 16.0
                          : (_winManager.enableInternalBottomDock ? 20.0 : 12.0),
                      left: 0,
                      right: 0,
                      child: _RecentlyCreatedToastCapsule(
                        desktopController: widget.desktopController,
                        winManager: _winManager,
                      ),
                    ),

                    // 【底部自动隐藏快速启动坞 (方案 B 悬停呼出，平时 100% 释放桌面空间)】
                    if (!_isSettingsSelected && _winManager.enableInternalBottomDock)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: RepaintBoundary(
                          child: DesktopBottomDock(
                            desktopController: widget.desktopController,
                          ),
                        ),
                      ),

                    // 【外部文件拖入微光悬浮提示层 (Drag & Drop Visual Feedback)】
                    if (_isDraggingOver)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: currentStyle.accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(15.0),
                            border: Border.all(
                              color: currentStyle.accentColor,
                              width: 2.0,
                            ),
                          ),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                                decoration: BoxDecoration(
                                  color: isLight
                                      ? Colors.white.withValues(alpha: 0.95)
                                      : const Color(0xFF1E293B).withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: currentStyle.accentColor.withValues(alpha: 0.4),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(FluentIcons.folder_open, size: 26, color: currentStyle.accentColor),
                                    const SizedBox(width: 10),
                                    Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '松开鼠标存入桌面',
                                          style: TextStyle(
                                            fontSize: 14.0,
                                            fontWeight: FontWeight.bold,
                                            color: _winManager.textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '文件将自动同步至桌面文件夹并即时智能分类',
                                          style: TextStyle(
                                            fontSize: 11.0,
                                            color: _winManager.subTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 顶部全景控制条 (底层全宽原生 DragToMoveArea 拦截 WM_NCHITTEST，顶层独立响应时钟、搜索与按钮)
  Widget _buildTopHeader() {
    final isLight = _winManager.isLight;

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: isLight
            ? Colors.black.withValues(alpha: 0.03)
            : Colors.black.withValues(alpha: 0.10),
        border: Border(
          bottom: BorderSide(
            color: isLight
                ? Colors.black.withValues(alpha: 0.04)
                : Colors.white.withValues(alpha: 0.06),
            width: 0.8,
          ),
        ),
      ),
      child: Stack(
        children: [
          // 【底层】：整个标题栏全区域覆盖 NativeDragArea (0ms onPointerDown 立即启动原生拖拽，0 延迟跟随鼠标)
          const Positioned.fill(
            child: NativeDragArea(
              child: SizedBox.expand(),
            ),
          ),

          // 【顶层】：交互组件层 (时钟固定宽度杜绝抖动 + 晶莹胶囊搜索 + 快捷控制按钮)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10.0),
              child: Row(
                children: [
                  // 左侧实时时钟 (自适应宽度，清晰展示完整年月日时间)
                  const _RealtimeClockWidget(),

                  const SizedBox(width: 8),

                  // 原生硬件监控胶囊 (实时 CPU % + 内存 %，1.5 秒低开销无感刷新)
                  const _HardwareMonitorWidget(),

                  // 中间弹性空间 (底层自然透传原生拖拽)
                  const Spacer(),

                  // 晶莹磨砂胶囊搜索框
                  _SearchBox(
                    onQueryChanged: (query) {
                      if (_isSettingsSelected) {
                        setState(() => _isSettingsSelected = false);
                      }
                      widget.desktopController.setSearchQuery(query);
                    },
                    onSubmitted: () async {
                      await widget.desktopController.openFirstFilteredItem();
                    },
                  ),

                  const SizedBox(width: 8),

                  // 右侧快捷控制按钮区 (0ms 极速响应)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 纯净壁纸模式切换 (一键隐藏/恢复 Windows 原生桌面图标)
                      _TopActionButton(
                        tooltip: _winManager.isDesktopIconsHidden
                            ? '纯净壁纸模式已开启 (点击恢复原生桌面图标)'
                            : '纯净壁纸模式 (点击隐藏原生桌面图标)',
                        icon: _winManager.isDesktopIconsHidden
                            ? FluentIcons.photo2
                            : FluentIcons.desktop_screenshot,
                        iconColor: _winManager.isDesktopIconsHidden
                            ? _winManager.currentThemeStyle.accentColor
                            : null,
                        onTap: () {
                          _winManager.toggleDesktopIconsVisibility();
                        },
                      ),

                      const SizedBox(width: 2),

                      // 置顶切换按钮
                      _TopActionButton(
                        tooltip: _winManager.isAlwaysOnTop ? '已置顶 (点击取消)' : '未置顶 (点击置顶)',
                        icon: _winManager.isAlwaysOnTop ? FluentIcons.pinned : FluentIcons.unpin,
                        iconColor: _winManager.isAlwaysOnTop
                            ? _winManager.currentThemeStyle.accentColor
                            : null,
                        onTap: () async {
                          await _winManager.toggleAlwaysOnTop();
                        },
                      ),

                      const SizedBox(width: 2),

                      // 设置面板切换按钮
                      _TopActionButton(
                        tooltip: '设置',
                        icon: FluentIcons.settings,
                        iconColor: _isSettingsSelected
                            ? _winManager.currentThemeStyle.accentColor
                            : null,
                        onTap: () {
                          setState(() {
                            _isSettingsSelected = !_isSettingsSelected;
                          });
                        },
                      ),

                      const SizedBox(width: 2),

                      // 最小化
                      _TopActionButton(
                        tooltip: '最小化',
                        icon: FluentIcons.chrome_minimize,
                        iconSize: 10,
                        onTap: () => _winManager.minimize(),
                      ),

                      const SizedBox(width: 2),

                      // 关闭 (根据偏好最小化到托盘或彻底退出)
                      _TopActionButton(
                        tooltip: _winManager.closeBehavior == WindowCloseBehavior.minimizeToTray
                            ? '关闭 (最小化到系统托盘)'
                            : '关闭 (退出程序)',
                        icon: FluentIcons.chrome_close,
                        iconSize: 10,
                        isCloseButton: true,
                        onTap: () => _winManager.handleCloseButton(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 水平分类选项栏 (带上下充足呼吸间距，底层全宽原生拖拽，顶层悬浮胶囊切换 + 滑动立体微阴影浮层)
  Widget _buildHorizontalCategoryBar() {
    final isLight = _winManager.isLight;

    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.desktopController,
        CategoryManager.instance,
      ]),
      builder: (context, _) {
        final currentCatId = widget.desktopController.selectedCategoryId;
        final categories = CategoryManager.instance.enabledCategories;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 6.0),
              child: SizedBox(
                height: 30,
                child: Stack(
                  children: [
                    // 底层全宽原生拖拽 (0ms 瞬时响应)
                    const Positioned.fill(
                      child: NativeDragArea(
                        child: SizedBox.expand(),
                      ),
                    ),

                    // 顶层分类标签项 (自适应水平滚动、大热区、宽间距、零误触)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          physics: _winManager.horizontalScrollPhysics,
                          child: Row(
                            children: [
                              for (int i = 0; i < categories.length; i++) ...[
                                _buildHorizontalCategoryItem(
                                  category: categories[i],
                                  isSelected: currentCatId == categories[i].id,
                                ),
                                if (i < categories.length - 1) const SizedBox(width: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 向下滑动时在分类栏底部平滑淡入的立体微阴影浮层 (ValueListenableBuilder 局部更新，0 毫秒父级重绘开销)
            Positioned(
              left: 0,
              right: 0,
              bottom: -4,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isGridScrolledNotifier,
                  builder: (context, isScrolled, _) {
                    return AnimatedOpacity(
                      opacity: isScrolled ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: isLight ? 0.08 : 0.25),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 构造单条水平分类项 (带发光胶囊与数量标记)
  Widget _buildHorizontalCategoryItem({
    required CustomCategory category,
    required bool isSelected,
  }) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accent = winManager.currentThemeStyle.accentColor;
    final count = widget.desktopController.countByCategoryId(category.id);

    return _CategoryTabButton(
      title: category.name,
      icon: category.iconData,
      count: count,
      isSelected: isSelected,
      accentColor: accent,
      isLight: isLight,
      textColor: winManager.textColor,
      subTextColor: winManager.subTextColor,
      onTap: () {
        widget.desktopController.setCategoryId(category.id);
      },
    );
  }

  /// 主体内容展示区域 (Windows 11 Fluent 骨架屏 + AnimatedSwitcher 丝滑渐变入场)
  Widget _buildContentArea() {
    return ListenableBuilder(
      listenable: widget.desktopController,
      builder: (context, _) {
        final Widget child;

        if (widget.desktopController.isLoading) {
          child = const _DesktopSkeletonView(key: ValueKey('skeleton_view'));
        } else if (widget.desktopController.errorMessage != null) {
          child = Center(
            key: const ValueKey('error_view'),
            child: InfoBar(
              title: const Text('加载失败'),
              content: Text(widget.desktopController.errorMessage!),
              severity: InfoBarSeverity.error,
            ),
          );
        } else {
          final items = widget.desktopController.filteredItems;
          child = DesktopGridView(
            key: const ValueKey('grid_view'),
            desktopController: widget.desktopController,
            items: items,
            onItemTap: (item) => widget.desktopController.openItem(item),
            onShowInExplorer: (item) => widget.desktopController.showInExplorer(item),
            isItemPinned: (item) => widget.desktopController.isItemPinned(item.path),
            onTogglePin: (item) => widget.desktopController.togglePinItem(item),
            isItemPinnedToDock: (item) => widget.desktopController.isItemPinnedToDock(item.path),
            onToggleDockPin: (item) => widget.desktopController.toggleDockPin(item),
            onScrollChanged: (scrolled) {
              if (_isGridScrolledNotifier.value != scrolled) {
                _isGridScrolledNotifier.value = scrolled;
              }
            },
          );
        }

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 240),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: child,
        );
      },
    );
  }
}

/// Windows 11 Fluent 风格骨架屏占位网格组件 (与真实网格 100% 像素级对齐，亚克力脉冲呼吸效果)
class _DesktopSkeletonView extends StatefulWidget {
  const _DesktopSkeletonView({super.key});

  @override
  State<_DesktopSkeletonView> createState() => _DesktopSkeletonViewState();
}

class _DesktopSkeletonViewState extends State<_DesktopSkeletonView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOutSine,
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLight = WindowManagerWin32.instance.isLight;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          final pulseVal = _pulseAnimation.value;
          final baseAlpha = isLight ? (0.04 + pulseVal * 0.05) : (0.05 + pulseVal * 0.07);
          final highlightAlpha = isLight ? (0.08 + pulseVal * 0.08) : (0.10 + pulseVal * 0.10);
          final cardColor = isLight
              ? Colors.black.withValues(alpha: baseAlpha)
              : Colors.white.withValues(alpha: baseAlpha);
          final itemPlaceholderColor = isLight
              ? Colors.black.withValues(alpha: highlightAlpha)
              : Colors.white.withValues(alpha: highlightAlpha);

          return GridView.builder(
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 10.0,
              top: 6.0,
              bottom: 8.0,
            ),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 88,
              mainAxisExtent: 76,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: 24,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  color: cardColor,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 图标骨架
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: itemPlaceholderColor,
                        borderRadius: BorderRadius.circular(6.0),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // 文字骨架 (交错微调宽度，模拟自然文件名长度)
                    Container(
                      width: 46.0 + (index % 3) * 10.0,
                      height: 9,
                      decoration: BoxDecoration(
                        color: itemPlaceholderColor,
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 独立实时时钟微组件 (等宽数字 + 独立定时器，绝不引发任何布局抖动与主界面重绘)
class _RealtimeClockWidget extends StatefulWidget {
  const _RealtimeClockWidget();

  @override
  State<_RealtimeClockWidget> createState() => _RealtimeClockWidgetState();
}

class _RealtimeClockWidgetState extends State<_RealtimeClockWidget> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WindowManagerWin32.instance.addListener(_onWindowVisibilityChanged);
    _syncTimer();
  }

  void _onWindowVisibilityChanged() {
    if (!mounted) return;
    _syncTimer();
  }

  void _syncTimer() {
    final winManager = WindowManagerWin32.instance;
    if (winManager.isWindowVisible) {
      if (_timer == null || !_timer!.isActive) {
        _currentTime = DateTime.now();
        _timer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() {
              _currentTime = DateTime.now();
            });
          }
        });
      }
    } else {
      _stopTimer();
    }
  }

  void _stopTimer() {
    try {
      _timer?.cancel();
    } finally {
      _timer = null;
    }
  }

  @override
  void dispose() {
    try {
      WindowManagerWin32.instance.removeListener(_onWindowVisibilityChanged);
      _stopTimer();
    } finally {
      super.dispose();
    }
  }

  String _formatDateTime(DateTime dt) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[dt.weekday - 1];
    final year = dt.year;
    final month = dt.month.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    return '$year年$month月$day日星期$weekday $hour:$minute:$second';
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;

    return RepaintBoundary(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFF0078D4),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                FluentIcons.clock,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 7),
          // 等宽数字显示 + 严格固定 250px 宽度容器，清晰大字号展示完整时间值
          SizedBox(
            width: 250,
            child: Text(
              _formatDateTime(_currentTime),
              maxLines: 1,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: isLight ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 原生系统硬件监控胶囊组件 (实时 CPU % + 内存 %，支持用户按需自由配置显隐，1.5 秒低开销无感刷新)
class _HardwareMonitorWidget extends StatefulWidget {
  const _HardwareMonitorWidget();

  @override
  State<_HardwareMonitorWidget> createState() => _HardwareMonitorWidgetState();
}

class _HardwareMonitorWidgetState extends State<_HardwareMonitorWidget> {
  Timer? _timer;
  SystemHardwareInfo _info = SystemHardwareInfo.empty;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    WindowManagerWin32.instance.addListener(_onPreferenceChanged);
    _syncTimerWithPreference();
  }

  void _onPreferenceChanged() {
    if (!mounted) return;
    _syncTimerWithPreference();
    setState(() {});
  }

  void _syncTimerWithPreference() {
    final winManager = WindowManagerWin32.instance;
    if (winManager.showHardwareMonitor && winManager.isWindowVisible) {
      if (_timer == null || !_timer!.isActive) {
        _info = SystemHardwareHelper.getHardwareInfo();
        _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
          if (mounted) {
            final newInfo = SystemHardwareHelper.getHardwareInfo();
            setState(() {
              _info = newInfo;
            });
          }
        });
      }
    } else {
      _stopTimer();
    }
  }

  void _stopTimer() {
    try {
      _timer?.cancel();
    } finally {
      _timer = null;
    }
  }

  @override
  void dispose() {
    try {
      WindowManagerWin32.instance.removeListener(_onPreferenceChanged);
      _stopTimer();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final showCpu = winManager.showCpuMonitor;
    final showMem = winManager.showMemoryMonitor;

    // 如果用户关闭了全部硬件监视器，直接返回空，0 开销
    if (!showCpu && !showMem) {
      return const SizedBox.shrink();
    }

    final isLight = winManager.isLight;
    final cpuPercent = _info.cpuUsage.round();
    final memPercent = _info.memoryUsage.round();

    // 根据负载动态呈现安全色 / 预警色
    final Color cpuColor;
    if (cpuPercent >= 85) {
      cpuColor = const Color(0xFFEF4444); // 高负载红
    } else if (cpuPercent >= 70) {
      cpuColor = const Color(0xFFF59E0B); // 中负载橙
    } else {
      cpuColor = isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8); // 正常蓝
    }

    final Color memColor;
    if (memPercent >= 85) {
      memColor = const Color(0xFFEF4444);
    } else if (memPercent >= 70) {
      memColor = const Color(0xFFF59E0B);
    } else {
      memColor = isLight ? const Color(0xFF059669) : const Color(0xFF34D399); // 正常绿
    }

    final tooltipLines = <String>['系统硬件实时状态:'];
    if (showCpu) {
      tooltipLines.add('• CPU 使用率: $cpuPercent%');
    }
    if (showMem) {
      tooltipLines.add('• 内存使用率: $memPercent%');
      tooltipLines.add('• 已用内存: ${_info.usedMemoryGB.toStringAsFixed(1)} GB / ${_info.totalMemoryGB.toStringAsFixed(1)} GB');
    }

    return RepaintBoundary(
      child: Tooltip(
        message: tooltipLines.join('\n'),
        style: const TooltipThemeData(
          waitDuration: Duration(milliseconds: 400),
        ),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.5),
            decoration: BoxDecoration(
              color: isLight
                  ? (_isHovered ? Colors.white.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.80))
                  : (_isHovered ? Colors.black.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.28)),
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(
                color: isLight
                    ? (_isHovered ? const Color(0x38000000) : const Color(0x1F000000))
                    : (_isHovered ? const Color(0x45FFFFFF) : const Color(0x22FFFFFF)),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (showCpu) ...[
                  // 1. CPU 监控 (等宽数字 + 严格固定 48px 宽度，无论数值位数如何变化绝对 0 抖动)
                  Icon(FluentIcons.speed_high, size: 11, color: cpuColor),
                  const SizedBox(width: 3.5),
                  SizedBox(
                    width: 48,
                    child: Text(
                      'CPU $cpuPercent%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isLight ? const Color(0xFF0F172A) : Colors.white,
                      ),
                    ),
                  ),
                ],

                if (showCpu && showMem)
                  // 分割竖线
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5.0),
                    child: Container(
                      width: 0.8,
                      height: 10,
                      color: isLight ? const Color(0x25000000) : const Color(0x30FFFFFF),
                    ),
                  ),

                if (showMem) ...[
                  // 2. 内存监控 (等宽数字 + 严格固定 48px 宽度)
                  Icon(FluentIcons.hard_drive, size: 11, color: memColor),
                  const SizedBox(width: 3.5),
                  SizedBox(
                    width: 48,
                    child: Text(
                      '内存 $memPercent%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isLight ? const Color(0xFF0F172A) : Colors.white,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// 晶莹磨砂胶囊搜索框 (对标 easyDesktop 极简美学，带聚焦扩散动效与即时响应)
class _SearchBox extends StatefulWidget {
  final ValueChanged<String> onQueryChanged;
  final VoidCallback? onSubmitted;

  const _SearchBox({
    required this.onQueryChanged,
    this.onSubmitted,
  });

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    try {
      _controller.dispose();
      _focusNode.dispose();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final isFocused = _focusNode.hasFocus;
    final accent = winManager.currentThemeStyle.accentColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: isFocused ? 180 : 145,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: isFocused
              ? (isLight ? Colors.white.withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.22))
              : (_isHovered
                  ? (isLight ? Colors.white.withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.18))
                  : (isLight ? Colors.white.withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.12))),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isFocused
                ? accent
                : (_isHovered
                    ? (isLight ? accent.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.45))
                    : (isLight ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.20))),
            width: isFocused ? 1.2 : 0.8,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Icon(
              FluentIcons.search,
              size: 12,
              color: isFocused ? accent : (isLight ? const Color(0xFF334155) : Colors.white),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: EditableText(
                controller: _controller,
                focusNode: _focusNode,
                style: TextStyle(
                  fontSize: 12,
                  color: isLight ? const Color(0xFF0F172A) : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                cursorColor: accent,
                backgroundCursorColor: Colors.transparent,
                keyboardType: TextInputType.text,
                onSubmitted: (_) {
                  widget.onSubmitted?.call();
                },
                onChanged: (text) {
                  widget.onQueryChanged(text);
                  setState(() {});
                },
              ),
            ),
            if (_controller.text.isEmpty && !isFocused)
              IgnorePointer(
                child: Text(
                  '搜索...',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isLight ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            if (_controller.text.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _controller.clear();
                  widget.onQueryChanged('');
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    FluentIcons.clear,
                    size: 11,
                    color: isLight ? const Color(0xFF334155) : Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶部快捷操作按钮 (0 延迟即时触控，大热区、防误触)
class _TopActionButton extends StatefulWidget {
  final String tooltip;
  final IconData icon;
  final double iconSize;
  final Color? iconColor;
  final bool isCloseButton;
  final VoidCallback onTap;

  const _TopActionButton({
    required this.tooltip,
    required this.icon,
    this.iconSize = 13.0,
    this.iconColor,
    this.isCloseButton = false,
    required this.onTap,
  });

  @override
  State<_TopActionButton> createState() => _TopActionButtonState();
}

class _TopActionButtonState extends State<_TopActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;

    final Color bgColor;
    final Color fgColor;

    if (widget.isCloseButton && _isHovered) {
      bgColor = const Color(0xFFE81123);
      fgColor = Colors.white;
    } else if (_isPressed) {
      bgColor = isLight
          ? Colors.black.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.28);
      fgColor = widget.iconColor ?? (isLight ? const Color(0xFF0F172A) : Colors.white);
    } else if (_isHovered) {
      bgColor = isLight
          ? Colors.black.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.20);
      fgColor = widget.iconColor ?? (isLight ? const Color(0xFF0F172A) : Colors.white);
    } else {
      bgColor = (isLight ? Colors.black : Colors.white).withValues(alpha: 0.0);
      // 常态下：纯白高亮图标 (暗色) 或深黑 (浅色)，绝对高对比度
      fgColor = widget.iconColor ?? (isLight ? const Color(0xFF1E293B) : const Color(0xFFFFFFFF));
    }

    return Tooltip(
      message: widget.tooltip,
      style: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 600),
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) {
          setState(() {
            _isHovered = false;
            _isPressed = false;
          });
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 90),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6.0),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: widget.iconSize,
                color: fgColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分类标签胶囊按钮 (宽间距、大热区、高对比度醒目标签，支持专属 Fluent 图标)
class _CategoryTabButton extends StatefulWidget {
  final String title;
  final IconData? icon;
  final int count;
  final bool isSelected;
  final Color accentColor;
  final bool isLight;
  final Color textColor;
  final Color subTextColor;
  final VoidCallback onTap;

  const _CategoryTabButton({
    required this.title,
    this.icon,
    required this.count,
    required this.isSelected,
    required this.accentColor,
    required this.isLight,
    required this.textColor,
    required this.subTextColor,
    required this.onTap,
  });

  @override
  State<_CategoryTabButton> createState() => _CategoryTabButtonState();
}

class _CategoryTabButtonState extends State<_CategoryTabButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isSelected = widget.isSelected;
    final isLight = widget.isLight;
    final accent = widget.accentColor;

    final Color bgColor;
    final Border border;
    final Color titleColor;
    final Color countColor;
    final Color badgeBg;
    final List<BoxShadow>? shadows;

    if (isSelected) {
      if (isLight) {
        bgColor = accent.withValues(alpha: 0.14);
        border = Border.all(color: accent.withValues(alpha: 0.65), width: 1.0);
        titleColor = accent;
        countColor = accent;
        badgeBg = accent.withValues(alpha: 0.20);
        shadows = [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ];
      } else {
        bgColor = accent;
        border = Border.all(color: Colors.transparent, width: 1.0);
        titleColor = Colors.white;
        countColor = Colors.white;
        badgeBg = Colors.black.withValues(alpha: 0.35);
        shadows = [
          BoxShadow(
            color: accent.withValues(alpha: 0.40),
            blurRadius: 6,
            offset: const Offset(0, 1.5),
          ),
        ];
      }
    } else if (_isHovered) {
      if (isLight) {
        bgColor = Colors.black.withValues(alpha: 0.06);
        border = Border.all(color: Colors.black.withValues(alpha: 0.15), width: 0.9);
        titleColor = const Color(0xFF0F172A);
        countColor = const Color(0xFF0F172A);
        badgeBg = Colors.black.withValues(alpha: 0.08);
        shadows = null;
      } else {
        bgColor = Colors.white.withValues(alpha: 0.12);
        border = Border.all(color: Colors.white.withValues(alpha: 0.25), width: 0.9);
        titleColor = Colors.white;
        countColor = Colors.white;
        badgeBg = Colors.white.withValues(alpha: 0.15);
        shadows = null;
      }
    } else {
      // 常态未选中：高对比度胶囊与鲜明数字
      if (isLight) {
        bgColor = Colors.black.withValues(alpha: 0.035);
        border = Border.all(color: Colors.black.withValues(alpha: 0.08), width: 0.8);
        titleColor = const Color(0xFF334155);
        countColor = const Color(0xFF475569);
        badgeBg = Colors.black.withValues(alpha: 0.06);
        shadows = null;
      } else {
        bgColor = Colors.white.withValues(alpha: 0.05);
        border = Border.all(color: Colors.white.withValues(alpha: 0.10), width: 0.8);
        titleColor = const Color(0xFFE2E8F0);
        countColor = const Color(0xFF94A3B8);
        badgeBg = Colors.white.withValues(alpha: 0.10);
        shadows = null;
      }
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8.0),
              border: border,
              boxShadow: shadows,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 12,
                    color: titleColor,
                  ),
                  const SizedBox(width: 5),
                ],
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: titleColor,
                  ),
                ),
                const SizedBox(width: 5),
                Container(
                  constraints: const BoxConstraints(minWidth: 16),
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.0),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${widget.count}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: countColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Windows 11 Fluent 悬浮即时操作胶囊 (在新建或保存文件时弹出，提供直观图标、文件名及「立即打开」极速入口)
class _RecentlyCreatedToastCapsule extends StatelessWidget {
  final DesktopController desktopController;
  final WindowManagerWin32 winManager;

  const _RecentlyCreatedToastCapsule({
    required this.desktopController,
    required this.winManager,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: desktopController,
      builder: (context, _) {
        final recentItem = desktopController.recentlyCreatedItem;
        final hasItem = recentItem != null;

        return IgnorePointer(
          ignoring: !hasItem,
          child: RepaintBoundary(
            child: AnimatedSlide(
              offset: hasItem ? Offset.zero : const Offset(0, 0.4),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: hasItem ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: hasItem
                    ? Center(
                        child: Container(
                        constraints: const BoxConstraints(maxWidth: 420, minWidth: 260),
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: winManager.isLight
                              ? Colors.white.withValues(alpha: 0.95)
                              : const Color(0xFF23272E).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: winManager.currentThemeStyle.accentColor.withValues(
                              alpha: winManager.isLight ? 0.65 : 0.85,
                            ),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: winManager.currentThemeStyle.accentColor.withValues(
                                alpha: winManager.isLight ? 0.25 : 0.45,
                              ),
                              blurRadius: 16,
                              spreadRadius: 1,
                              offset: const Offset(0, 3),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 1. 文件类型图标
                            Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: winManager.currentThemeStyle.accentColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  FileTypeHelper.getIconForExtension(
                                    recentItem.extension,
                                    recentItem.isDirectory,
                                  ),
                                  size: 14,
                                  color: winManager.currentThemeStyle.accentColor,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // 2. 状态提示与文件名
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                                        decoration: BoxDecoration(
                                          color: winManager.currentThemeStyle.accentColor,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: const Text(
                                          '已定位',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.bold,
                                            height: 1.1,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '新建项目',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          color: winManager.subTextColor,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    recentItem.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: winManager.textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // 3. 立即打开按钮
                            FilledButton(
                              style: ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                ),
                                shape: WidgetStateProperty.all(
                                  RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(FluentIcons.open_file, size: 10),
                                  SizedBox(width: 3),
                                  Text('打开', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                ],
                              ),
                              onPressed: () {
                                desktopController.openItem(recentItem);
                                desktopController.clearRecentlyCreated();
                              },
                            ),
                            const SizedBox(width: 2),

                            // 4. 关闭/忽略按钮
                            IconButton(
                              icon: Icon(
                                FluentIcons.chrome_close,
                                size: 9,
                                color: winManager.subTextColor,
                              ),
                              onPressed: () {
                                desktopController.clearRecentlyCreated();
                              },
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
      },
    );
  }
}
