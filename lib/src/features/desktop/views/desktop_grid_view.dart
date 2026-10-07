import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../../../core/window/window_manager_win32.dart';
import '../../../utils/file_type_helper.dart';
import '../../../utils/windows_icon_extractor.dart';
import '../../../utils/windows_shell_helper.dart';
import '../../../utils/windows_shell_new_helper.dart';
import '../../categories/models/custom_category.dart';
import '../../categories/services/category_manager.dart';
import '../models/desktop_item.dart';
import '../controllers/desktop_controller.dart';

/// 桌面项目紧凑网格视图 (支持卡片完整操作与网格空白处桌面级右键菜单)
///
/// 遵循 Windows 11 Fluent Design 与 easyDesktop 极简美学规范：
/// - 统一卡片内部高度基准线，确保所有图标与文字严格对齐
/// - 充足的四周呼吸间距，保证所有卡片的上、下、左、右四周边框与圆角 100% 完整显示，绝无裁剪
/// - 纯粹的局部微交互 (悬停图标微放大 + 平滑微光卡片背景)，绝无整页重绘与位置偏移
/// - 完备的桌面级文件交互闭环：新建文件夹、新建文档、重命名、Win32 原生安全移入回收站、文件属性面板
class DesktopGridView extends StatefulWidget {
  /// 桌面状态控制器
  final DesktopController desktopController;

  /// 文件列表
  final List<DesktopItem> items;

  /// 点击项的回调 (原生打开)
  final void Function(DesktopItem item) onItemTap;

  /// 在资源管理器中定位的回调
  final void Function(DesktopItem item) onShowInExplorer;

  /// 检查某项目是否置顶的回调
  final bool Function(DesktopItem item) isItemPinned;

  /// 切换项目在本分类置顶状态的回调
  final void Function(DesktopItem item) onTogglePin;

  /// 检查某项目是否固定到底部 Dock 的回调
  final bool Function(DesktopItem item)? isItemPinnedToDock;

  /// 切换项目固定到底部 Dock 状态的回调
  final void Function(DesktopItem item)? onToggleDockPin;

  /// 滚动状态变化回调 (用于分类Header动态展示立体微阴影浮层)
  final ValueChanged<bool>? onScrollChanged;

  const DesktopGridView({
    super.key,
    required this.desktopController,
    required this.items,
    required this.onItemTap,
    required this.onShowInExplorer,
    required this.isItemPinned,
    required this.onTogglePin,
    this.isItemPinnedToDock,
    this.onToggleDockPin,
    this.onScrollChanged,
  });

  @override
  State<DesktopGridView> createState() => _DesktopGridViewState();
}

class _DesktopGridViewState extends State<DesktopGridView> {
  final ScrollController _scrollController = ScrollController();
  final FlyoutController _backgroundFlyoutController = FlyoutController();
  bool _isScrolled = false;
  String? _lastScrolledPath;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    widget.desktopController.addListener(_checkRecentlyCreatedScroll);
  }

  @override
  void didUpdateWidget(covariant DesktopGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.desktopController != widget.desktopController) {
      oldWidget.desktopController.removeListener(_checkRecentlyCreatedScroll);
      widget.desktopController.addListener(_checkRecentlyCreatedScroll);
    }
  }

  void _checkRecentlyCreatedScroll() {
    final recentPath = widget.desktopController.recentlyCreatedPath;
    if (recentPath != null && recentPath != _lastScrolledPath) {
      _lastScrolledPath = recentPath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToItem(recentPath);
      });
    } else if (recentPath == null) {
      _lastScrolledPath = null;
    }
  }

  /// 智能计算并平滑滚动到最新创建项的视口中央
  void _scrollToItem(String path) {
    if (!_scrollController.hasClients || widget.items.isEmpty) return;
    final index = widget.items.indexWhere(
      (item) => item.path.toLowerCase() == path.toLowerCase(),
    );
    if (index == -1) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final width = renderBox.size.width - 26.0; // 左右 padding 合计 (16 + 10)
    final viewportHeight = renderBox.size.height;
    if (width <= 0) return;

    // 根据 SliverGridDelegateWithMaxCrossAxisExtent 规则计算列数
    int crossAxisCount = (width / 88.0).ceil();
    if (crossAxisCount < 1) crossAxisCount = 1;

    final rowIndex = index ~/ crossAxisCount;
    // 每行高度 76 + 间距 6 = 82
    const rowHeight = 82.0;
    final targetOffset = (6.0 + rowIndex * rowHeight) - (viewportHeight / 2) + 38.0;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final clampedOffset = targetOffset.clamp(0.0, maxScroll);

    _scrollController.animateTo(
      clampedOffset,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final scrolled = _scrollController.offset > 4.0;
    if (scrolled != _isScrolled) {
      _isScrolled = scrolled;
      widget.onScrollChanged?.call(scrolled);
    }
  }

  @override
  void dispose() {
    try {
      widget.desktopController.removeListener(_checkRecentlyCreatedScroll);
      _scrollController.removeListener(_handleScroll);
      _scrollController.dispose();
      _backgroundFlyoutController.dispose();
    } finally {
      super.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;

    return RepaintBoundary(
      child: Padding(
        // 【方案 A 核心物理隔离】：视口层整体向内缩进 6px，留出 0~4px 专属拉伸轨道，彻底杜绝误触
        padding: const EdgeInsets.only(right: 6.0),
        child: FlyoutTarget(
          controller: _backgroundFlyoutController,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onSecondaryTapUp: (details) {
              _showBackgroundContextMenu(context, details.globalPosition);
            },
            child: widget.items.isEmpty
                ? Center(
                    child: Builder(
                      builder: (context) {
                        final currentCat = CategoryManager.instance.getCategoryById(widget.desktopController.selectedCategoryId);
                        final isManual = currentCat != null && currentCat.matchType == CategoryMatchType.manual;

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isManual ? currentCat.iconData : FluentIcons.folder_search,
                              size: 40,
                              color: winManager.subTextColor.withValues(alpha: 0.6),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              isManual
                                  ? '「${currentCat.name}」暂无项目 (右键文件选择「归类到...」或直接拖入文件)'
                                  : '没有找到相关桌面项目 (右键可新建文件夹/文档)',
                              style: TextStyle(
                                fontSize: 13,
                                color: winManager.subTextColor,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  )
                : ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(
                      scrollbars: false,
                      dragDevices: {
                        PointerDeviceKind.touch,
                        PointerDeviceKind.mouse,
                        PointerDeviceKind.trackpad,
                        PointerDeviceKind.stylus,
                      },
                    ),
                    child: ScrollbarTheme(
                      data: const ScrollbarThemeData(
                        thickness: 6.0,
                        hoveringThickness: 8.0,
                        mainAxisMargin: 6.0,
                        crossAxisMargin: 4.0,
                        radius: Radius.circular(4.0),
                        hoveringRadius: Radius.circular(4.0),
                      ),
                      child: Scrollbar(
                        controller: _scrollController,
                        interactive: true,
                        child: SmoothMouseWheelScroll(
                          controller: _scrollController,
                          child: GridView.builder(
                            controller: _scrollController,
                            addAutomaticKeepAlives: true,
                            addRepaintBoundaries: true,
                            // ignore: deprecated_member_use
                            cacheExtent: 500.0,
                            padding: const EdgeInsets.only(
                              left: 16.0,
                              right: 16.0,
                              top: 6.0,
                              bottom: 8.0,
                            ),
                            physics: winManager.scrollPhysics,
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 88,
                              mainAxisSpacing: 6,
                              crossAxisSpacing: 6,
                              mainAxisExtent: 76,
                            ),
                            itemCount: widget.items.length,
                            itemBuilder: (context, index) {
                              final item = widget.items[index];
                              final isPinned = widget.isItemPinned(item);
                              final isDockPinned = widget.isItemPinnedToDock?.call(item) ?? false;
                              final isRecentlyCreated = widget.desktopController.recentlyCreatedPath?.toLowerCase() == item.path.toLowerCase();
                              return _DesktopItemCard(
                                key: ValueKey(item.path),
                                item: item,
                                isPinned: isPinned,
                                isDockPinned: isDockPinned,
                                isRecentlyCreated: isRecentlyCreated,
                                desktopController: widget.desktopController,
                                onTap: () => widget.onItemTap(item),
                                onShowInExplorer: () => widget.onShowInExplorer(item),
                                onTogglePin: () => widget.onTogglePin(item),
                                onToggleDockPin: widget.onToggleDockPin != null
                                    ? () => widget.onToggleDockPin!(item)
                                    : null,
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// 弹出桌面网格空白处右键菜单 (跟随鼠标坐标精确呼出，全量同步 Windows 桌面系统级功能)
  void _showBackgroundContextMenu(BuildContext context, Offset globalPos) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;

    // 1. 一次性预构建二级菜单所有新建项 (0ms 悬停瞬时直出，彻底根除鼠标移入时的重复循环计算与掉帧)
    final shellNewItems = widget.desktopController.shellNewItems;
    final List<MenuFlyoutItemBase> subMenuItems;
    if (shellNewItems.isEmpty) {
      subMenuItems = [
        MenuFlyoutItem(
          leading: const Icon(FluentIcons.text_document, size: 14),
          text: const Text('文本文档 (.txt)'),
          onPressed: () {
            _promptCreateNewFile(
              context,
              const ShellNewItem(extension: '.txt', displayName: '文本文档', isNullFile: true),
            );
          },
        ),
      ];
    } else {
      subMenuItems = shellNewItems.map((template) {
        final iconData = FileTypeHelper.getIconForExtension(template.extension, false);
        final color = FileTypeHelper.getAccentColor(template.extension, false, isLight);

        return MenuFlyoutItem(
          leading: Icon(iconData, size: 14, color: color),
          text: Text(template.displayName),
          onPressed: () {
            _promptCreateNewFile(context, template);
          },
        );
      }).toList(growable: false);
    }

    // 2. 一次性预构建第三方桌面扩展命令 (WebStorm, Visual Studio, Git 等)
    final bgCommands = widget.desktopController.desktopBackgroundCommands;
    final List<MenuFlyoutItemBase> commandMenuItems = bgCommands.map((cmd) {
      final iconData = _getCommandIcon(cmd.key, cmd.title, cmd.commandLine);
      final iconColor = _getCommandColor(cmd.key, cmd.title, cmd.commandLine);

      return MenuFlyoutItem(
        leading: Icon(iconData, size: 14, color: iconColor),
        text: Text(cmd.title),
        onPressed: () {
          widget.desktopController.runDesktopCommand(cmd);
        },
      );
    }).toList(growable: false);

    _backgroundFlyoutController.showFlyout(
      position: globalPos,
      barrierColor: Colors.transparent,
      builder: (flyoutCtx) {
        return RepaintBoundary(
          child: MenuFlyout(
            items: [
              // 1. 新建文件夹
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.new_folder, size: 14, color: Color(0xFFFFB900)),
                text: const Text('新建文件夹'),
                onPressed: () {
                  Navigator.of(flyoutCtx).pop();
                  _promptCreateNewFolder(context);
                },
              ),

              // 2. 动态扫描 Windows 注册表 ShellNew 生成的所有新建项 (预计算 0ms 秒开)
              MenuFlyoutSubItem(
                leading: const Icon(FluentIcons.add, size: 14),
                text: const Text('新建文档 / 文件'),
                items: (_) => subMenuItems,
              ),

              // 3. 在终端中打开
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.command_prompt, size: 14, color: Color(0xFF107C41)),
                text: const Text('在终端中打开'),
                onPressed: () {
                  Navigator.of(flyoutCtx).pop();
                  WindowsShellHelper.openTerminalInPath(widget.desktopController.userDesktopPath);
                },
              ),

              // 4. 在资源管理器中打开桌面文件夹
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.open_folder_horizontal, size: 14),
                text: const Text('打开桌面文件夹'),
                onPressed: () {
                  Navigator.of(flyoutCtx).pop();
                  WindowsShellHelper.openDesktopFolder(widget.desktopController.userDesktopPath);
                },
              ),

              // 动态同步用户电脑上注册的第三方桌面工具 (如 WebStorm, Visual Studio, Git, WSL 等)
              if (commandMenuItems.isNotEmpty) ...[
                const MenuFlyoutSeparator(),
                ...commandMenuItems,
              ],

              const MenuFlyoutSeparator(),

              // 5. 显示设置
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.devices3, size: 14),
                text: const Text('显示设置'),
                onPressed: () {
                  Navigator.of(flyoutCtx).pop();
                  WindowsShellHelper.openDisplaySettings();
                },
              ),

              // 6. 个性化
              MenuFlyoutItem(
                leading: const Icon(FluentIcons.color, size: 14),
                text: const Text('个性化'),
                onPressed: () {
                  Navigator.of(flyoutCtx).pop();
                  WindowsShellHelper.openPersonalizationSettings();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  /// 弹出新建文件夹对话框
  Future<void> _promptCreateNewFolder(BuildContext context) async {
    final textController = TextEditingController(text: '新建文件夹');
    textController.selection = TextSelection(baseOffset: 0, extentOffset: textController.text.length);

    final result = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => ContentDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.new_folder, size: 18, color: Color(0xFFFFB900)),
            SizedBox(width: 8),
            Text('新建文件夹'),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: TextBox(
            controller: textController,
            autofocus: true,
            placeholder: '请输入文件夹名称',
            onSubmitted: (val) => Navigator.of(dlgCtx).pop(val),
          ),
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dlgCtx).pop(),
          ),
          FilledButton(
            child: const Text('创建'),
            onPressed: () => Navigator.of(dlgCtx).pop(textController.text),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      await widget.desktopController.createNewFolder(result.trim());
    }
  }

  /// 弹出新建文件命名对话框 (默认名称全选，直接输入即覆盖，按 Enter 即可快速创建)
  Future<void> _promptCreateNewFile(BuildContext context, ShellNewItem template) async {
    String defaultName = template.displayName.split('(').first.trim();
    if (!defaultName.startsWith('新建')) {
      defaultName = '新建 $defaultName';
    }

    final textController = TextEditingController(text: defaultName);
    textController.selection = TextSelection(baseOffset: 0, extentOffset: textController.text.length);

    final iconData = FileTypeHelper.getIconForExtension(template.extension, false);
    final winManager = WindowManagerWin32.instance;
    final color = FileTypeHelper.getAccentColor(template.extension, false, winManager.isLight);

    final result = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => ContentDialog(
        title: Row(
          children: [
            Icon(iconData, size: 18, color: color),
            const SizedBox(width: 8),
            Text('新建 ${template.displayName}'),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextBox(
                controller: textController,
                autofocus: true,
                placeholder: '请输入文件名称',
                suffix: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Center(
                    widthFactor: 1.0,
                    child: Text(
                      template.extension,
                      style: TextStyle(
                        fontSize: 12,
                        color: winManager.subTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                onSubmitted: (val) => Navigator.of(dlgCtx).pop(val),
              ),
            ],
          ),
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dlgCtx).pop(),
          ),
          FilledButton(
            child: const Text('创建'),
            onPressed: () => Navigator.of(dlgCtx).pop(textController.text),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      await widget.desktopController.createNewFileFromShellNew(template, result.trim());
    }
  }

  /// 依据命令关键字与命令行获取专属品牌 Fluent 图标
  IconData _getCommandIcon(String key, String title, String cmdLine) {
    final lower = '$key $title $cmdLine'.toLowerCase();
    if (lower.contains('visual studio') || lower.contains('devenv') || lower.contains('vslauncher')) {
      return FluentIcons.visual_studio_for_windows;
    }
    if (lower.contains('webstorm') || lower.contains('idea') || lower.contains('pycharm') || lower.contains('clion') || lower.contains('code')) {
      return FluentIcons.code;
    }
    if (lower.contains('wsl') || lower.contains('linux') || lower.contains('ubuntu') || lower.contains('debian')) {
      return FluentIcons.command_prompt;
    }
    if (lower.contains('git')) {
      return FluentIcons.git_graph;
    }
    if (lower.contains('nvidia') || lower.contains('nvcpl')) {
      return FluentIcons.devices3;
    }
    if (lower.contains('显示') || lower.contains('效果') || lower.contains('display')) {
      return FluentIcons.color;
    }
    return FluentIcons.app_icon_default;
  }

  /// 依据命令关键字获取专属品牌高对比度色彩
  Color _getCommandColor(String key, String title, String cmdLine) {
    final lower = '$key $title $cmdLine'.toLowerCase();
    if (lower.contains('visual studio') || lower.contains('devenv') || lower.contains('vslauncher')) {
      return const Color(0xFF5C2D91); // VS 紫
    }
    if (lower.contains('webstorm') || lower.contains('idea')) {
      return const Color(0xFF008AD7); // JetBrains 蓝
    }
    if (lower.contains('wsl') || lower.contains('linux')) {
      return const Color(0xFFEAA23C); // Linux 橙黄
    }
    if (lower.contains('git')) {
      return const Color(0xFFF05032); // Git 橙红
    }
    if (lower.contains('nvidia')) {
      return const Color(0xFF76B900); // NVIDIA 绿
    }
    if (lower.contains('显示') || lower.contains('效果')) {
      return const Color(0xFF0078D4);
    }
    return const Color(0xFF0078D4);
  }
}

/// 单个桌面项卡片组件 (支持右键重命名、安全移入回收站、属性面板、置顶与Dock、新建高亮微光)
class _DesktopItemCard extends StatefulWidget {
  final DesktopItem item;
  final bool isPinned;
  final bool isDockPinned;
  final bool isRecentlyCreated;
  final DesktopController desktopController;
  final VoidCallback onTap;
  final VoidCallback onShowInExplorer;
  final VoidCallback onTogglePin;
  final VoidCallback? onToggleDockPin;

  const _DesktopItemCard({
    super.key,
    required this.item,
    required this.isPinned,
    this.isDockPinned = false,
    this.isRecentlyCreated = false,
    required this.desktopController,
    required this.onTap,
    required this.onShowInExplorer,
    required this.onTogglePin,
    this.onToggleDockPin,
  });

  @override
  State<_DesktopItemCard> createState() => _DesktopItemCardState();
}

class _DesktopItemCardState extends State<_DesktopItemCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _isHovered = false;
  bool _isPressed = false;
  bool _isContextMenuOpen = false;
  final FlyoutController _flyoutController = FlyoutController();
  ImageProvider? _nativeImageProvider;

  @override
  void initState() {
    super.initState();
    _loadNativePngIcon();
  }

  @override
  void didUpdateWidget(covariant _DesktopItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _nativeImageProvider = null;
      _loadNativePngIcon();
    }
  }

  void _loadNativePngIcon() {
    if (widget.item.isDirectory) return;

    final cached = WindowsIconExtractor.getImageProvider(widget.item.path);
    if (cached != null) {
      _nativeImageProvider = cached;
      return;
    }

    WindowsIconExtractor.extractIconToPng(widget.item.path).then((pngPath) {
      if (mounted && pngPath != null) {
        final provider = WindowsIconExtractor.getImageProvider(widget.item.path);
        if (provider != null && _nativeImageProvider != provider) {
          setState(() {
            _nativeImageProvider = provider;
          });
        }
      }
    });
  }

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
    super.build(context);
    final item = widget.item;
    final isRecent = widget.isRecentlyCreated;
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accent = winManager.currentThemeStyle.accentColor;

    final iconData = FileTypeHelper.getIconForExtension(
      item.extension,
      item.isDirectory,
    );
    final accentColor = FileTypeHelper.getAccentColor(
      item.extension,
      item.isDirectory,
      isLight,
    );

    // 背景色与边框计算：最新创建高亮 > 右键菜单激活 / 按下 > 悬停 > 默认透明
    final Color bgColor;
    final Border? border;
    final List<BoxShadow>? shadows;

    if (isRecent) {
      bgColor = isLight
          ? accent.withValues(alpha: 0.22)
          : accent.withValues(alpha: 0.38);
      border = Border.all(color: accent, width: 1.5);
      shadows = [
        BoxShadow(
          color: accent.withValues(alpha: isLight ? 0.45 : 0.65),
          blurRadius: 10,
          spreadRadius: 1.0,
        ),
      ];
    } else if (_isContextMenuOpen || _isPressed) {
      bgColor = isLight
          ? accent.withValues(alpha: 0.18)
          : accent.withValues(alpha: 0.30);
      border = Border.all(color: accent.withValues(alpha: 0.85), width: 1.2);
      shadows = null;
    } else if (_isHovered) {
      // 悬停：精致通透的 Fluent 亚克力微光 (浅色模式用微柔主题色，暗色模式用纯白微光)
      bgColor = isLight
          ? accent.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.12);
      border = Border.all(
        color: isLight
            ? accent.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.20),
        width: 1.0,
      );
      shadows = null;
    } else {
      // 常态：保持与悬停相同的基底色彩且仅 Alpha 为 0，彻底根除 Color.lerp 灰底闪烁与生硬过渡
      bgColor = (isLight ? accent : Colors.white).withValues(alpha: 0.0);
      border = Border.all(
        color: (isLight ? accent : Colors.white).withValues(alpha: 0.0),
        width: 1.0,
      );
      shadows = null;
    }

    final cachedImageProvider = _nativeImageProvider ?? WindowsIconExtractor.getImageProvider(item.path);

    return RepaintBoundary(
      child: FlyoutTarget(
        controller: _flyoutController,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_isHovered) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (_isHovered) setState(() => _isHovered = false);
          if (_isPressed) setState(() => _isPressed = false);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          onTap: widget.onTap,
          onSecondaryTapUp: (details) async {
            setState(() => _isContextMenuOpen = true);
            try {
              await _flyoutController.showFlyout(
                barrierColor: Colors.transparent,
                builder: (menuContext) {
                  return RepaintBoundary(
                    child: MenuFlyout(
                      items: [
                        // 1. 运行 / 打开
                        MenuFlyoutItem(
                          leading: Icon(
                            item.isDirectory ? FluentIcons.open_folder_horizontal : FluentIcons.open_file,
                            size: 14,
                          ),
                          text: Text(item.isDirectory ? '系统打开文件夹' : '运行 / 打开'),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            widget.onTap();
                          },
                        ),

                        // 2. 重命名
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.rename, size: 14),
                          text: const Text('重命名'),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            _promptRenameItem(context, item);
                          },
                        ),

                        // 3. 安全移入回收站 (支持撤回)
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.delete, size: 14, color: Color(0xFFE81123)),
                          text: const Text('移入回收站', style: TextStyle(color: Color(0xFFE81123))),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            _confirmAndDeleteItem(context, item);
                          },
                        ),

                        const MenuFlyoutSeparator(),

                        // 4. 置顶
                        MenuFlyoutItem(
                          leading: Icon(
                            widget.isPinned ? FluentIcons.unpin : FluentIcons.pinned,
                            size: 14,
                            color: widget.isPinned ? accent : null,
                          ),
                          text: Text(widget.isPinned ? '取消本分类置顶' : '在本分类置顶'),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            widget.onTogglePin();
                          },
                        ),

                        // 5. 固定到 Dock
                        if (widget.onToggleDockPin != null)
                          MenuFlyoutItem(
                            leading: Icon(
                              widget.isDockPinned ? FluentIcons.unpin : FluentIcons.pin,
                              size: 14,
                              color: widget.isDockPinned ? const Color(0xFF0078D4) : null,
                            ),
                            text: Text(widget.isDockPinned ? '从底部 Dock 移除' : '固定到底部 Dock'),
                            onPressed: () {
                              Navigator.of(menuContext).pop();
                              widget.onToggleDockPin!();
                            },
                          ),

                        // 6. 手动自选分类操作
                        ...(() {
                          final currentCat = CategoryManager.instance.getCategoryById(widget.desktopController.selectedCategoryId);
                          final isCurrentManual = currentCat != null && currentCat.matchType == CategoryMatchType.manual;
                          final manualCats = CategoryManager.instance.manualCategories;
                          final menuList = <MenuFlyoutItemBase>[];

                          if (isCurrentManual) {
                            menuList.add(
                              MenuFlyoutItem(
                                leading: const Icon(FluentIcons.remove, size: 14),
                                text: Text('从「${currentCat.name}」移出'),
                                onPressed: () async {
                                  Navigator.of(menuContext).pop();
                                  await CategoryManager.instance.removeItemFromManualCategory(currentCat.id, item.path);
                                },
                              ),
                            );
                          }

                          if (manualCats.isNotEmpty) {
                            menuList.add(
                              MenuFlyoutSubItem(
                                leading: const Icon(FluentIcons.tag, size: 14),
                                text: const Text('归类到自选分类'),
                                items: (subContext) => [
                                  for (final mCat in manualCats)
                                    MenuFlyoutItem(
                                      leading: Icon(
                                        mCat.manualItemKeys.contains(item.path)
                                            ? FluentIcons.check_mark
                                            : mCat.iconData,
                                        size: 14,
                                        color: mCat.manualItemKeys.contains(item.path) ? accent : null,
                                      ),
                                      text: Text(mCat.name),
                                      trailing: mCat.manualItemKeys.contains(item.path)
                                          ? Text('已收纳', style: TextStyle(fontSize: 10, color: accent))
                                          : null,
                                      onPressed: () async {
                                        Navigator.of(subContext).pop();
                                        await CategoryManager.instance.toggleItemInManualCategory(mCat.id, item.path);
                                      },
                                    ),
                                ],
                              ),
                            );
                          }

                          return menuList;
                        })(),

                        const MenuFlyoutSeparator(),

                        // 6. 复制路径
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.copy, size: 14),
                          text: const Text('复制文件路径'),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            Clipboard.setData(ClipboardData(text: item.path));
                            displayInfoBar(
                              context,
                              builder: (ctx, close) => InfoBar(
                                title: const Text('路径已复制到剪贴板'),
                                severity: InfoBarSeverity.success,
                                onClose: close,
                              ),
                            );
                          },
                        ),

                        // 7. 资源管理器定位
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.file_system, size: 14),
                          text: const Text('在文件资源管理器中定位'),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            widget.onShowInExplorer();
                          },
                        ),

                        // 8. 查看属性 (Win32 原生属性窗口)
                        MenuFlyoutItem(
                          leading: const Icon(FluentIcons.info, size: 14),
                          text: const Text('属性'),
                          onPressed: () {
                            Navigator.of(menuContext).pop();
                            widget.desktopController.showItemProperties(item);
                          },
                        ),
                      ],
                    ),
                  );
                },
              );
            } finally {
              if (mounted) {
                setState(() => _isContextMenuOpen = false);
              }
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8.0),
              border: border,
              boxShadow: shadows,
            ),
            child: Stack(
              children: [
                // 1. 卡片主体内容 (图标与两行文字)
                Positioned.fill(
                  child: Column(
                    mainAxisSize: MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 36,
                        child: Center(
                          child: AnimatedScale(
                            scale: (_isContextMenuOpen || _isPressed)
                                ? 0.94
                                : (_isHovered ? 1.08 : 1.0),
                            duration: const Duration(milliseconds: 120),
                            curve: Curves.easeOutCubic,
                            child: (!item.isDirectory && cachedImageProvider != null)
                                ? Image(
                                    image: cachedImageProvider,
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.contain,
                                    filterQuality: FilterQuality.low,
                                    gaplessPlayback: true,
                                    errorBuilder: (context, error, stackTrace) => Icon(
                                      iconData,
                                      size: 28,
                                      color: accentColor,
                                    ),
                                  )
                                : Icon(
                                    item.isDirectory ? FluentIcons.folder_fill : iconData,
                                    size: item.isDirectory ? 30 : 28,
                                    color: item.isDirectory
                                        ? (isLight ? const Color(0xFFD97706) : const Color(0xFFFFB900))
                                        : accentColor,
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 2),

                      Text(
                        item.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: winManager.textColor,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        item.typeDescription,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.normal,
                          color: winManager.subTextColor.withValues(alpha: 0.85),
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. 右上角置顶标记
                if (widget.isPinned)
                  Positioned(
                    top: 1,
                    right: 1,
                    child: Container(
                      padding: const EdgeInsets.all(2.0),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(4.0),
                      ),
                      child: Icon(
                        FluentIcons.pinned,
                        size: 9.5,
                        color: accent,
                      ),
                    ),
                  ),

                // 3. 最新创建高亮标记 (NEW 醒目胶囊)
                if (isRecent)
                  Positioned(
                    top: 2,
                    left: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4.0),
                        boxShadow: [
                          BoxShadow(
                            color: accent.withValues(alpha: 0.5),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: const Text(
                        'NEW',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  /// 重命名弹窗
  Future<void> _promptRenameItem(BuildContext context, DesktopItem item) async {
    final textController = TextEditingController(text: item.displayName);
    textController.selection = TextSelection(baseOffset: 0, extentOffset: textController.text.length);

    final result = await showDialog<String>(
      context: context,
      builder: (dlgCtx) => ContentDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.rename, size: 18),
            SizedBox(width: 8),
            Text('重命名'),
          ],
        ),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: TextBox(
            controller: textController,
            autofocus: true,
            placeholder: '请输入新名称',
            onSubmitted: (val) => Navigator.of(dlgCtx).pop(val),
          ),
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dlgCtx).pop(),
          ),
          FilledButton(
            child: const Text('重命名'),
            onPressed: () => Navigator.of(dlgCtx).pop(textController.text),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty && result.trim() != item.displayName) {
      final ok = await widget.desktopController.renameItem(item, result.trim());
      if (!ok && context.mounted) {
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: const Text('重命名失败，名称可能已存在或包含非法字符'),
            severity: InfoBarSeverity.error,
            onClose: close,
          ),
        );
      }
    }
  }

  /// 移入回收站确认弹窗
  Future<void> _confirmAndDeleteItem(BuildContext context, DesktopItem item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dlgCtx) => ContentDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.delete, size: 18, color: Color(0xFFE81123)),
            SizedBox(width: 8),
            Text('移入回收站'),
          ],
        ),
        content: Text('确定要将 "${item.displayName}" 移入回收站吗？\n(可在回收站中恢复或按 Ctrl+Z 撤销)'),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.of(dlgCtx).pop(false),
          ),
          FilledButton(
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(const Color(0xFFE81123)),
            ),
            child: const Text('移入回收站'),
            onPressed: () => Navigator.of(dlgCtx).pop(true),
          ),
        ],
      ),
    );

    if (result == true) {
      final ok = await widget.desktopController.deleteItemToRecycleBin(item);
      if (ok && context.mounted) {
        displayInfoBar(
          context,
          builder: (ctx, close) => InfoBar(
            title: Text('"${item.displayName}" 已移入回收站'),
            severity: InfoBarSeverity.success,
            onClose: close,
          ),
        );
      }
    }
  }
}

/// Windows 专属丝滑鼠标滚轮平滑滚动容器 (接管鼠标滚轮的步进离散跳跃，注入 Curves.easeOutCubic 丝滑动力学阻尼)
class SmoothMouseWheelScroll extends StatefulWidget {
  final ScrollController controller;
  final Widget child;
  final double scrollFactor;

  const SmoothMouseWheelScroll({
    super.key,
    required this.controller,
    required this.child,
    this.scrollFactor = 1.0,
  });

  @override
  State<SmoothMouseWheelScroll> createState() => _SmoothMouseWheelScrollState();
}

class _SmoothMouseWheelScrollState extends State<SmoothMouseWheelScroll>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  Animation<double>? _animation;
  double _targetOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _animController.addListener(_onAnimationTick);
  }

  void _onAnimationTick() {
    if (_animation != null && widget.controller.hasClients) {
      final maxScroll = widget.controller.position.maxScrollExtent;
      final minScroll = widget.controller.position.minScrollExtent;
      final newOffset = _animation!.value.clamp(minScroll, maxScroll);
      widget.controller.jumpTo(newOffset);
    }
  }

  @override
  void dispose() {
    _animController.removeListener(_onAnimationTick);
    _animController.dispose();
    super.dispose();
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent && widget.controller.hasClients) {
      GestureBinding.instance.pointerSignalResolver.register(event, (resolvedEvent) {
        if (resolvedEvent is! PointerScrollEvent) return;
        final delta = resolvedEvent.scrollDelta.dy * widget.scrollFactor;
        if (delta == 0) return;

        final current = widget.controller.offset;
        final maxScroll = widget.controller.position.maxScrollExtent;
        final minScroll = widget.controller.position.minScrollExtent;

        // 如果用户连续滚动滚轮，以当前目标 offset 累加，保证手感连贯无阻滞
        final base = _animController.isAnimating ? _targetOffset : current;
        _targetOffset = (base + delta).clamp(minScroll, maxScroll);

        if (_targetOffset == current) return;

        _animation = Tween<double>(
          begin: current,
          end: _targetOffset,
        ).animate(CurvedAnimation(
          parent: _animController,
          curve: Curves.easeOutCubic,
        ));

        _animController.forward(from: 0.0);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: _handlePointerSignal,
      child: widget.child,
    );
  }
}

