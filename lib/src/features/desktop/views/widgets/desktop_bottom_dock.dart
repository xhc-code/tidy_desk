import 'dart:async';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import '../../../../core/window/window_manager_win32.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../../utils/file_type_helper.dart';
import '../../../../utils/windows_shell_helper.dart';
import '../../../../utils/windows_icon_extractor.dart';
import '../../models/desktop_item.dart';
import '../../controllers/desktop_controller.dart';

/// 桌面底部自动隐藏快速启动坞 (Auto-Hide Bottom Dock · 悬停自动唤出 / 平时完全不遮挡)
///
/// 核心特性：
/// 1. 【方案 B 智能自动隐藏】：平时仅在最底部保留极简微光指示把手，100% 释放桌面图标纵向空间；
/// 2. 【0 延迟丝滑唤出】：鼠标移入底部区域立即平滑浮现完整 Dock，移出后延时优雅收回；
/// 3. 【上下图文微卡片】：上部 19px 高清图标，下部 10px 精致小字，第一眼 100% 秒认。
class DesktopBottomDock extends StatefulWidget {
  final DesktopController desktopController;

  const DesktopBottomDock({
    super.key,
    required this.desktopController,
  });

  @override
  State<DesktopBottomDock> createState() => _DesktopBottomDockState();
}

class _DesktopBottomDockState extends State<DesktopBottomDock> {
  final WindowManagerWin32 _winManager = WindowManagerWin32.instance;

  /// 是否处于展开状态
  bool _isExpanded = false;

  /// 鼠标移出防误触延时收回定时器
  Timer? _hideTimer;

  /// 横向滚动控制器
  late final ScrollController _scrollController;
  final ValueNotifier<bool> _canScrollLeftNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _canScrollRightNotifier = ValueNotifier<bool>(false);
  double _targetScrollOffset = 0.0;
  bool _isAnimatingScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _canScrollLeftNotifier.dispose();
    _canScrollRightNotifier.dispose();
    _hideTimer?.cancel();
    super.dispose();
  }

  /// 鼠标是否在 Dock 区域内
  bool _isMouseInside = false;

  /// 当前打开的菜单/弹窗计数（防止右键菜单或弹窗开启时 Dock 自动收回）
  int _activeMenuCount = 0;

  void _onMouseEnter() {
    _isMouseInside = true;
    _hideTimer?.cancel();
    _isAnimatingScroll = false;
    if (!_isExpanded) {
      setState(() {
        _isExpanded = true;
      });
      // 展开时更新边缘淡出提示
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;
        _canScrollLeftNotifier.value = pos.pixels > 2.0;
        _canScrollRightNotifier.value = pos.pixels < pos.maxScrollExtent - 2.0;
      });
    }
  }

  void _onMouseExit() {
    _isMouseInside = false;
    if (_activeMenuCount > 0) {
      // 只要有右键菜单或弹窗正在展示，绝对不隐藏 Dock
      _hideTimer?.cancel();
      return;
    }
    _startHideTimer();
  }

  void _onMenuStateChanged(bool isOpen) {
    if (isOpen) {
      _activeMenuCount++;
      _hideTimer?.cancel();
    } else {
      if (_activeMenuCount > 0) _activeMenuCount--;
      if (_activeMenuCount == 0 && !_isMouseInside) {
        _startHideTimer();
      }
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && _isExpanded && _activeMenuCount == 0 && !_isMouseInside) {
        setState(() {
          _isExpanded = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.desktopController,
      builder: (context, _) {
        final isLight = _winManager.isLight;
        final accent = _winManager.currentThemeStyle.accentColor;
        final pinnedItems = widget.desktopController.dockPinnedItems;

        return RepaintBoundary(
          child: MouseRegion(
            onEnter: (_) => _onMouseEnter(),
            onExit: (_) => _onMouseExit(),
            child: SizedBox(
              height: 62.0,
              child: Stack(
                alignment: Alignment.bottomCenter,
                clipBehavior: Clip.none,
                children: [
                  // 1. 平时收起状态：极简微光指示把手 (当未展开时展示，展开时平滑淡出)
                  Positioned(
                    bottom: 3.0,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      opacity: _isExpanded ? 0.0 : 1.0,
                      child: Container(
                        width: 44.0,
                        height: 4.0,
                        decoration: BoxDecoration(
                          color: isLight
                              ? Colors.black.withValues(alpha: 0.28)
                              : Colors.white.withValues(alpha: 0.40),
                          borderRadius: BorderRadius.circular(2.0),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withValues(alpha: isLight ? 0.25 : 0.45),
                              blurRadius: 4.0,
                              spreadRadius: 0.5,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 2. 悬停展开状态：完整的上下图文 Dock 坞 (平滑从底部升起，立体微浮岛设计)
                  Positioned(
                    bottom: 3.0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      ignoring: !_isExpanded,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        offset: _isExpanded ? Offset.zero : const Offset(0, 1.25),
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          opacity: _isExpanded ? 1.0 : 0.0,
                          child: Center(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final double maxDockWidth = constraints.maxWidth * 0.80;
                                final Color dockBgTop = isLight ? const Color(0xFFFFFFFF) : const Color(0xFF2C2C30);
                                final Color dockBgBottom = isLight ? const Color(0xFFF6F7F9) : const Color(0xFF212124);
                                final Color dockBorderColor = isLight ? const Color(0x1C000000) : const Color(0x2EFFFFFF);

                                return Container(
                                  height: 56,
                                  constraints: BoxConstraints(maxWidth: maxDockWidth),
                                  margin: const EdgeInsets.symmetric(horizontal: 14.0),
                                  decoration: BoxDecoration(
                                    // 极简微拟物渐变 + 双层柔和悬浮阴影，赋予呼吸感与立体层次
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [dockBgTop, dockBgBottom],
                                    ),
                                    borderRadius: BorderRadius.circular(12.0),
                                    border: Border.all(
                                      color: dockBorderColor,
                                      width: 1.0,
                                    ),
                                    boxShadow: [
                                      // 1. 大范围柔和环境光阴影 (拉开与底层桌面景深)
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isLight ? 0.10 : 0.40),
                                        blurRadius: 22.0,
                                        offset: const Offset(0, 7),
                                        spreadRadius: 0.5,
                                      ),
                                      // 2. 近景微阴影 (勾勒边缘立体锐度)
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isLight ? 0.05 : 0.20),
                                        blurRadius: 5.0,
                                        offset: const Offset(0, 1.5),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(11.0),
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        // 1. 横向滚动列表 + 鼠标滚轮 Y 轴智能平滑转 X 轴 (无任何侵入式按钮遮挡)
                                        NotificationListener<ScrollNotification>(
                                          onNotification: (notification) {
                                            if (notification is ScrollStartNotification && notification.dragDetails != null) {
                                              _isAnimatingScroll = false;
                                            }
                                            final pos = notification.metrics;
                                            final canLeft = pos.pixels > 2.0;
                                            final canRight = pos.pixels < pos.maxScrollExtent - 2.0;
                                            if (_canScrollLeftNotifier.value != canLeft) {
                                              _canScrollLeftNotifier.value = canLeft;
                                            }
                                            if (_canScrollRightNotifier.value != canRight) {
                                              _canScrollRightNotifier.value = canRight;
                                            }
                                            return false;
                                          },
                                          child: Listener(
                                            onPointerSignal: (pointerSignal) {
                                              if (pointerSignal is PointerScrollEvent) {
                                                final dy = pointerSignal.scrollDelta.dy;
                                                final dx = pointerSignal.scrollDelta.dx;
                                                // 仅在纯垂直滚轮滚动时将 Y 轴转为 X 轴，平滑累加过渡，杜绝瞬间跳变
                                                if (dy != 0 && dx == 0 && _scrollController.hasClients) {
                                                  final pos = _scrollController.position;
                                                  final base = _isAnimatingScroll ? _targetScrollOffset : pos.pixels;
                                                  _targetScrollOffset = (base + dy).clamp(0.0, pos.maxScrollExtent);
                                                  if (_targetScrollOffset != pos.pixels) {
                                                    _isAnimatingScroll = true;
                                                    _scrollController.animateTo(
                                                      _targetScrollOffset,
                                                      duration: const Duration(milliseconds: 160),
                                                      curve: Curves.easeOutCubic,
                                                    ).then((_) {
                                                      _isAnimatingScroll = false;
                                                    });
                                                  }
                                                }
                                              }
                                            },
                                            child: SingleChildScrollView(
                                              controller: _scrollController,
                                              scrollDirection: Axis.horizontal,
                                              physics: _winManager.horizontalScrollPhysics,
                                              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.5),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                children: _buildAllDockItems(pinnedItems, isLight),
                                              ),
                                            ),
                                          ),
                                        ),

                                        // 2. 左边缘渐变淡出遮罩 (提示左侧有隐藏项，点击完全穿透，不遮挡任何图标)
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          bottom: 0,
                                          width: 28,
                                          child: ValueListenableBuilder<bool>(
                                            valueListenable: _canScrollLeftNotifier,
                                            builder: (context, canLeft, _) {
                                              return IgnorePointer(
                                                child: AnimatedOpacity(
                                                  duration: const Duration(milliseconds: 150),
                                                  opacity: canLeft ? 1.0 : 0.0,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment.centerLeft,
                                                        end: Alignment.centerRight,
                                                        colors: [
                                                          dockBgTop,
                                                          dockBgTop.withValues(alpha: 0.0),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),

                                        // 3. 右边缘渐变淡出遮罩 (提示右侧有隐藏项，点击完全穿透，不遮挡任何图标)
                                        Positioned(
                                          right: 0,
                                          top: 0,
                                          bottom: 0,
                                          width: 28,
                                          child: ValueListenableBuilder<bool>(
                                            valueListenable: _canScrollRightNotifier,
                                            builder: (context, canRight, _) {
                                              return IgnorePointer(
                                                child: AnimatedOpacity(
                                                  duration: const Duration(milliseconds: 150),
                                                  opacity: canRight ? 1.0 : 0.0,
                                                  child: DecoratedBox(
                                                    decoration: BoxDecoration(
                                                      gradient: LinearGradient(
                                                        begin: Alignment.centerRight,
                                                        end: Alignment.centerLeft,
                                                        colors: [
                                                          dockBgTop,
                                                          dockBgTop.withValues(alpha: 0.0),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
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
        );
      },
    );
  }

  /// 构建所有图文上下结构的 Dock 卡片
  List<Widget> _buildAllDockItems(List<DesktopItem> pinnedItems, bool isLight) {
    final list = <Widget>[];

    // 1. 系统项: 此电脑
    list.add(
      _DockTileButton(
        title: '此电脑',
        iconWidget: const Icon(
          FluentIcons.devices3,
          size: 21,
          color: Color(0xFF0078D4),
        ),
        onTap: () {
          AppLogger.i('Dock: 打开此电脑');
          WindowsShellHelper.openThisPC();
        },
        onMenuOpenChanged: _onMenuStateChanged,
        contextMenuItems: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.open_folder_horizontal, size: 14),
            text: const Text('打开此电脑'),
            onPressed: () => WindowsShellHelper.openThisPC(),
          ),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.settings, size: 14),
            text: const Text('打开控制面板'),
            onPressed: () => WindowsShellHelper.openControlPanel(),
          ),
        ],
      ),
    );

    // 2. 系统项: 回收站
    list.add(
      _DockTileButton(
        title: '回收站',
        iconWidget: const Icon(
          FluentIcons.delete,
          size: 21,
          color: Color(0xFFD83B01),
        ),
        onTap: () {
          AppLogger.i('Dock: 打开回收站');
          WindowsShellHelper.openRecycleBin();
        },
        onMenuOpenChanged: _onMenuStateChanged,
        contextMenuItems: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.open_folder_horizontal, size: 14),
            text: const Text('打开回收站'),
            onPressed: () => WindowsShellHelper.openRecycleBin(),
          ),
          const MenuFlyoutSeparator(),
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.delete, size: 14, color: Color(0xFFE81123)),
            text: const Text('清空回收站', style: TextStyle(color: Color(0xFFE81123))),
            onPressed: _confirmAndEmptyRecycleBin,
          ),
        ],
      ),
    );

    // 3. 系统项: 桌面
    list.add(
      _DockTileButton(
        title: '桌面',
        iconWidget: const Icon(
          FluentIcons.folder_horizontal,
          size: 21,
          color: Color(0xFFFFB900),
        ),
        onTap: () {
          AppLogger.i('Dock: 打开桌面文件夹');
          WindowsShellHelper.openDesktopFolder(
            widget.desktopController.userDesktopPath,
          );
        },
        onMenuOpenChanged: _onMenuStateChanged,
        contextMenuItems: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.open_folder_horizontal, size: 14),
            text: const Text('打开桌面文件夹'),
            onPressed: () => WindowsShellHelper.openDesktopFolder(
              widget.desktopController.userDesktopPath,
            ),
          ),
        ],
      ),
    );

    // 4. 系统项: 终端
    list.add(
      _DockTileButton(
        title: '终端',
        iconWidget: const Icon(
          FluentIcons.command_prompt,
          size: 21,
          color: Color(0xFF107C41),
        ),
        onTap: () {
          AppLogger.i('Dock: 启动终端');
          WindowsShellHelper.openTerminal();
        },
        onMenuOpenChanged: _onMenuStateChanged,
        contextMenuItems: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.command_prompt, size: 14),
            text: const Text('启动终端'),
            onPressed: () => WindowsShellHelper.openTerminal(),
          ),
        ],
      ),
    );

    // 5. 分割线 (更细腻的居中半透微线)
    list.add(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5.0),
        child: Container(
          width: 1.0,
          height: 26.0,
          color: isLight
              ? Colors.black.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.14),
        ),
      ),
    );

    // 6. 用户自定义固定项 (图标在上，文件/目录名在下，第一眼清晰秒认)
    for (final item in pinnedItems) {
      list.add(
        _DockTileButton(
          title: item.displayName,
          minWidth: 46,
          maxWidth: 68,
          iconWidget: _buildItemIcon(item),
          onTap: () async {
            AppLogger.i('Dock: 打开固定项 [${item.displayName}]');
            await widget.desktopController.openItem(item);
          },
          onMenuOpenChanged: _onMenuStateChanged,
          contextMenuItems: [
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.open_folder_horizontal, size: 14),
              text: const Text('打开'),
              onPressed: () => widget.desktopController.openItem(item),
            ),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.folder_search, size: 14),
              text: const Text('在资源管理器中定位'),
              onPressed: () => WindowsShellHelper.showInExplorer(item.path),
            ),
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.unpin, size: 14, color: Colors.warningPrimaryColor),
              text: const Text('从底部 Dock 移除'),
              onPressed: () => widget.desktopController.toggleDockPin(item),
            ),
          ],
        ),
      );
    }

    // 7. 刷新按钮
    list.add(
      _DockTileButton(
        title: '刷新',
        iconWidget: Icon(
          FluentIcons.refresh,
          size: 18,
          color: isLight ? Colors.grey[140] : Colors.grey[80],
        ),
        onTap: () {
          AppLogger.i('Dock: 手动刷新');
          widget.desktopController.refresh();
        },
        onMenuOpenChanged: _onMenuStateChanged,
        contextMenuItems: [
          MenuFlyoutItem(
            leading: const Icon(FluentIcons.refresh, size: 14),
            text: const Text('刷新 Dock 栏'),
            onPressed: () => widget.desktopController.refresh(),
          ),
        ],
      ),
    );

    return list;
  }

  /// 弹出清空回收站确认对话框并执行 Win32 原生清空
  Future<void> _confirmAndEmptyRecycleBin() async {
    _onMenuStateChanged(true);
    final bool? result;
    try {
      result = await showDialog<bool>(
        context: context,
        builder: (dlgContext) => ContentDialog(
          title: const Row(
            children: [
              Icon(FluentIcons.delete, color: Color(0xFFE81123), size: 20),
              SizedBox(width: 8),
              Text('清空回收站'),
            ],
          ),
          content: const Text('您确定要永久删除回收站中的所有项目吗？此操作无法撤销。'),
          actions: [
            Button(
              child: const Text('取消'),
              onPressed: () => Navigator.of(dlgContext).pop(false),
            ),
            FilledButton(
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.all(const Color(0xFFE81123)),
              ),
              child: const Text('清空'),
              onPressed: () => Navigator.of(dlgContext).pop(true),
            ),
          ],
        ),
      );
    } finally {
      _onMenuStateChanged(false);
    }

    if (result == true) {
      AppLogger.i('执行清空回收站');
      final success = WindowsShellHelper.emptyRecycleBin(
        showConfirmation: false,
        playSound: true,
      );
      if (mounted) {
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: Text(success ? '回收站已清空' : '回收站清空失败或已是空'),
            severity: success ? InfoBarSeverity.success : InfoBarSeverity.warning,
            onClose: close,
          ),
        );
      }
    }
  }

  /// 渲染自定义固定项图标 (支持动画加载占位与无缝淡入)
  Widget _buildItemIcon(DesktopItem item) {
    return _BottomDockItemAnimatedIcon(item: item);
  }
}

/// 底部 Dock 自定义项动态图标组件 (支持呼吸微光占位与流畅淡入)
class _BottomDockItemAnimatedIcon extends StatefulWidget {
  final DesktopItem item;

  const _BottomDockItemAnimatedIcon({required this.item});

  @override
  State<_BottomDockItemAnimatedIcon> createState() => _BottomDockItemAnimatedIconState();
}

class _BottomDockItemAnimatedIconState extends State<_BottomDockItemAnimatedIcon> {
  ImageProvider? _imageProvider;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoadIcon();
  }

  @override
  void didUpdateWidget(covariant _BottomDockItemAnimatedIcon oldWidget) {
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
      return const Icon(
        FluentIcons.folder,
        size: 21,
        color: Color(0xFFFFB900),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      child: _imageProvider != null
          ? Image(
              key: ValueKey('dock_icon_${widget.item.path}'),
              image: _imageProvider!,
              width: 21,
              height: 21,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => _buildFallback(isLight),
            )
          : (_isLoading
              ? _BottomDockIconShimmerPlaceholder(
                  key: ValueKey('dock_shimmer_${widget.item.path}'),
                  item: widget.item,
                )
              : _buildFallback(isLight)),
    );
  }

  Widget _buildFallback(bool isLight) {
    final iconData = FileTypeHelper.getIconForExtension(widget.item.extension, false);
    final color = FileTypeHelper.getAccentColor(widget.item.extension, false, isLight);
    return Icon(
      iconData,
      size: 21,
      color: color,
    );
  }
}

/// 底部 Dock 呼吸微光占位组件
class _BottomDockIconShimmerPlaceholder extends StatefulWidget {
  final DesktopItem item;

  const _BottomDockIconShimmerPlaceholder({super.key, required this.item});

  @override
  State<_BottomDockIconShimmerPlaceholder> createState() => _BottomDockIconShimmerPlaceholderState();
}

class _BottomDockIconShimmerPlaceholderState extends State<_BottomDockIconShimmerPlaceholder>
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
                width: 21,
                height: 21,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: baseColor.withValues(alpha: 0.12 * _pulseAnimation.value),
                ),
              ),
              Icon(
                iconData,
                size: 21,
                color: baseColor.withValues(alpha: 0.85),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 上下结构的单个 Dock 微卡片按钮组件 (图标在上，小字在下，平稳 Fluent 高亮)
class _DockTileButton extends StatefulWidget {
  final String title;
  final Widget iconWidget;
  final VoidCallback onTap;
  final List<MenuFlyoutItemBase>? contextMenuItems;
  final ValueChanged<bool>? onMenuOpenChanged;
  final double minWidth;
  final double maxWidth;

  const _DockTileButton({
    required this.title,
    required this.iconWidget,
    required this.onTap,
    this.contextMenuItems,
    this.onMenuOpenChanged,
    this.minWidth = 46,
    this.maxWidth = 64,
  });

  @override
  State<_DockTileButton> createState() => _DockTileButtonState();
}

class _DockTileButtonState extends State<_DockTileButton> {
  final FlyoutController _flyoutController = FlyoutController();
  bool _isHovered = false;
  bool _isPressed = false;
  bool _isMenuOpen = false;

  @override
  void dispose() {
    try {
      _flyoutController.dispose();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accent = winManager.currentThemeStyle.accentColor;

    final Color bgColor;
    final Border border;
    final List<BoxShadow>? shadows;

    // 当右键菜单展开或按下时，持续保持明确强烈的焦点选中高亮状态
    final bool isActive = _isPressed || _isMenuOpen;

    if (isActive) {
      bgColor = accent.withValues(alpha: isLight ? 0.22 : 0.32);
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
          ? const Color(0x12000000)
          : const Color(0x1CFFFFFF);
      border = Border.all(
        color: isLight
            ? const Color(0x10000000)
            : const Color(0x22FFFFFF),
        width: 1.0,
      );
      shadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.18),
          blurRadius: 4.0,
          offset: const Offset(0, 1.5),
        ),
      ];
    } else {
      // 默认静止态：边框完全透明无痕，背景透明，消灭双层框
      bgColor = Colors.transparent;
      border = Border.all(color: Colors.transparent, width: 1.0);
      shadows = null;
    }

    return FlyoutTarget(
      controller: _flyoutController,
      child: MouseRegion(
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
          onSecondaryTapDown: (_) => setState(() => _isPressed = true),
          onSecondaryTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          onSecondaryTapUp: (details) async {
            if (widget.contextMenuItems != null && widget.contextMenuItems!.isNotEmpty) {
              if (mounted) {
                setState(() {
                  _isPressed = false;
                  _isMenuOpen = true;
                });
              }
              widget.onMenuOpenChanged?.call(true);
              try {
                await _flyoutController.showFlyout(
                  builder: (ctx) => MenuFlyout(items: widget.contextMenuItems!),
                );
              } finally {
                if (mounted) {
                  setState(() {
                    _isMenuOpen = false;
                  });
                }
                widget.onMenuOpenChanged?.call(false);
              }
            } else {
              if (mounted) setState(() => _isPressed = false);
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            constraints: BoxConstraints(
              minWidth: widget.minWidth,
              maxWidth: widget.maxWidth,
              minHeight: 46,
              maxHeight: 48,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 3.0),
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
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
                // 1. 图标区 (居中规整，适度放大提升辨识度与立体感)
                SizedBox(
                  height: 22,
                  child: Center(child: widget.iconWidget),
                ),
                const SizedBox(height: 2.5),
                // 2. 小字名称区 (单行居中，超长省略，第一眼辨识)
                Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: (_isHovered || _isMenuOpen)
                        ? (isActive ? accent : (isLight ? const Color(0xFF0F172A) : Colors.white))
                        : winManager.textColor.withValues(alpha: 0.88),
                    height: 1.15,
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

