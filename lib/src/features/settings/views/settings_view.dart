import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import '../../../core/hotkey/desktop_hotkey_service.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/startup/desktop_startup_service.dart';
import '../../../core/tray/desktop_tray_service.dart';
import '../../../core/update/services/app_update_service.dart';
import '../../../core/window/window_manager_win32.dart';
import '../../categories/models/custom_category.dart';
import '../../categories/services/category_manager.dart';
import '../../desktop/controllers/desktop_controller.dart';
import '../../dock_island/services/dock_island_service.dart';
import 'widgets/app_update_dialog.dart';

/// 设置视图组件 (个性化外观、常驻行为、快捷键与开机启动)
class SettingsView extends StatefulWidget {
  final DesktopController desktopController;
  final VoidCallback? onBack;

  const SettingsView({
    super.key,
    required this.desktopController,
    this.onBack,
  });

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final WindowManagerWin32 _winManager = WindowManagerWin32.instance;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isScrolledNotifier = ValueNotifier<bool>(false);
  bool _isRefreshing = false;
  bool _isCheckingUpdate = false;

  late WindowThemeStyle _themeStyle;
  late double _panelOpacity;
  late WindowBackdropType _backdropType;
  late bool _isStartupEnabled;
  late bool _isHotkeyEnabled;
  late WindowCloseBehavior _closeBehavior;

  /// 手动检查在线新版本
  Future<void> _handleCheckUpdate() async {
    if (_isCheckingUpdate) return;
    setState(() => _isCheckingUpdate = true);

    try {
      final updateInfo = await AppUpdateService.instance.checkForUpdate();
      if (!mounted) return;

      if (updateInfo != null) {
        await AppUpdateDialog.show(context, updateInfo);
      } else {
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
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdate = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _themeStyle = _winManager.currentThemeStyle;
    _panelOpacity = _winManager.panelOpacity;
    _backdropType = _winManager.currentBackdrop;
    _isStartupEnabled = DesktopStartupService.instance.isStartupEnabled();
    _isHotkeyEnabled = DesktopHotkeyService.instance.isEnabled;
    _closeBehavior = _winManager.closeBehavior;

    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final scrolled = offset > 4.0;
    if (scrolled != _isScrolledNotifier.value) {
      _isScrolledNotifier.value = scrolled;
    }
  }

  @override
  void dispose() {
    try {
      _scrollController.removeListener(_onScroll);
      _scrollController.dispose();
      _isScrolledNotifier.dispose();
    } finally {
      super.dispose();
    }
  }

  /// 点击预设快捷键方案时的处理 (带有自定义覆盖防误触保护)
  Future<void> _onPresetSelected(int index, AppHotKeyOption option) async {
    if (!_isHotkeyEnabled) return;
    if (DesktopHotkeyService.instance.isCustom) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => ContentDialog(
          title: const Text('切换快捷键确认'),
          content: Text(
            '当前正在使用自定义快捷键 [${DesktopHotkeyService.instance.currentKeyDisplay}]。\n\n是否确认切换为预设方案 [${option.label}]？',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认切换'),
            ),
            Button(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await DesktopHotkeyService.instance.setHotKeyIndex(index);
    setState(() {});
  }

  void _showRefreshSuccess() {
    displayInfoBar(
      context,
      builder: (context, close) {
        return InfoBar(
          title: const Text('刷新完成'),
          content: const Text('已同步最新桌面文件。'),
          severity: InfoBarSeverity.success,
          onClose: close,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = _winManager.isLight;
    final accentColor = _winManager.currentThemeStyle.accentColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 现代 Fluent 粘性 Header (稳定底色，0 闪烁，下边缘带独立平滑微阴影)
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.only(left: 18.0, right: 18.0, top: 10.0, bottom: 9.0),
              decoration: BoxDecoration(
                color: _winManager.cardColor.withValues(alpha: isLight ? 0.90 : 0.85),
                border: Border(
                  bottom: BorderSide(
                    color: isLight
                        ? Colors.black.withValues(alpha: 0.06)
                        : Colors.white.withValues(alpha: 0.08),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (widget.onBack != null) ...[
                    _FluentInteractiveBackButton(
                      onPressed: widget.onBack!,
                    ),
                    const SizedBox(width: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(FluentIcons.settings, size: 15, color: accentColor),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '个性化与行为设置',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _winManager.textColor,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),

            // 向下滑动时在 Header 底边缘平滑淡入的立体微阴影 (ValueListenableBuilder 局部更新，0 毫秒父级重绘开销)
            Positioned(
              left: 0,
              right: 0,
              bottom: -4,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _isScrolledNotifier,
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
        ),

        // 2. 独立滚动的设置项目内容区域 (与主页面完全统一的滚动条与硬件位移物理阻尼)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 6.0),
            child: ScrollConfiguration(
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
                  thickness: 5.0,
                  hoveringThickness: 7.0,
                  mainAxisMargin: 6.0,
                  crossAxisMargin: 3.0,
                  radius: Radius.circular(3.0),
                  hoveringRadius: Radius.circular(3.0),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  interactive: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: _winManager.scrollPhysics,
                    padding: const EdgeInsets.only(left: 18.0, right: 24.0, top: 12.0, bottom: 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // =================================================================
                        // 1. 系统常驻与交互行为分组
                        // =================================================================
                        _buildSectionHeader('系统常驻与交互'),
                        const SizedBox(height: 8),

                        // 1.1 窗口置顶
                        _buildSettingCard(
                          title: '窗口始终置顶',
                          subtitle: '保持在最前端，方便随手取用桌面文件',
                          action: ToggleSwitch(
                            checked: _winManager.isAlwaysOnTop,
                            onChanged: (value) async {
                              await _winManager.setAlwaysOnTop(value);
                              setState(() {});
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 1.2 纯净壁纸模式 (一键隐藏/恢复 Windows 原生桌面图标)
                        _buildSettingCard(
                          title: '纯净壁纸模式 (隐藏原生桌面图标)',
                          subtitle: '一键隐藏 Windows 原生桌面所有杂乱图标，只留纯净高清壁纸，文件在抽屉中随时取用',
                          badgeText: 'Win10/Win11 原生',
                          action: ToggleSwitch(
                            checked: _winManager.isDesktopIconsHidden,
                            onChanged: (value) {
                              _winManager.setDesktopIconsHidden(value);
                              setState(() {});
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 1.3 顶部硬件状态监视器 (CPU / 内存)
                        Card(
                          backgroundColor: _winManager.cardColor,
                          borderColor: _winManager.cardBorderColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          '顶部硬件状态监视器',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: _winManager.textColor,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '实时极低开销',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: accentColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '在顶部标题栏显示 CPU 与物理内存实时占用，可分别开启或彻底关闭',
                                      style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Checkbox(
                                    checked: _winManager.showCpuMonitor,
                                    content: Text(
                                      'CPU',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _winManager.textColor,
                                      ),
                                    ),
                                    onChanged: (val) async {
                                      if (val != null) {
                                        await _winManager.setShowCpuMonitor(val);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 14),
                                  Checkbox(
                                    checked: _winManager.showMemoryMonitor,
                                    content: Text(
                                      '内存',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: _winManager.textColor,
                                      ),
                                    ),
                                    onChanged: (val) async {
                                      if (val != null) {
                                        await _winManager.setShowMemoryMonitor(val);
                                        setState(() {});
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 1.4 全局召唤快捷键 (支持用户键盘自主录制绑定 + 常用预设防误触切换)
                        Card(
                          backgroundColor: _winManager.cardColor,
                          borderColor: _winManager.cardBorderColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '全局召唤快捷键',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: _winManager.textColor,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                              decoration: BoxDecoration(
                                                color: accentColor.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(
                                                  color: accentColor.withValues(alpha: 0.40),
                                                  width: 0.9,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    FluentIcons.keyboard_classic,
                                                    size: 11,
                                                    color: accentColor,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    DesktopHotkeyService.instance.currentKeyDisplay,
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.bold,
                                                      color: accentColor,
                                                    ),
                                                  ),
                                                  if (DesktopHotkeyService.instance.isCustom) ...[
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '(自定义)',
                                                      style: TextStyle(
                                                        fontSize: 9.5,
                                                        color: accentColor.withValues(alpha: 0.8),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '在任何软件或全屏游戏界面下按下，秒级召唤/收起桌面抽屉',
                                          style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ToggleSwitch(
                                    checked: _isHotkeyEnabled,
                                    onChanged: (value) async {
                                      setState(() => _isHotkeyEnabled = value);
                                      await DesktopHotkeyService.instance.setEnabled(value);
                                    },
                                  ),
                                ],
                              ),

                              const SizedBox(height: 12),

                              // 用户自主按键录制栏
                              _HotkeyRecorderControlBar(
                                isEnabled: _isHotkeyEnabled,
                                onUpdated: () => setState(() {}),
                              ),

                              const SizedBox(height: 12),

                              // 快速预设选项推荐
                              Row(
                                children: [
                                  Text(
                                    '快速预设方案：',
                                    style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '(点击可选用)',
                                    style: TextStyle(fontSize: 10.5, color: _winManager.subTextColor.withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Opacity(
                                opacity: _isHotkeyEnabled ? 1.0 : 0.40,
                                child: Wrap(
                                  spacing: 7,
                                  runSpacing: 7,
                                  children: DesktopHotkeyService.presetOptions.asMap().entries.map((entry) {
                                    final index = entry.key;
                                    final option = entry.value;
                                    final isSelected = !DesktopHotkeyService.instance.isCustom &&
                                        DesktopHotkeyService.instance.selectedOptionIndex == index;

                                    return _PresetKeyButton(
                                      label: option.label,
                                      isSelected: isSelected,
                                      isEnabled: _isHotkeyEnabled,
                                      onTap: () => _onPresetSelected(index, option),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 1.5 开机自动启动
                        _buildSettingCard(
                          title: '开机自动启动',
                          subtitle: '开机随系统启动并静默常驻在右下角托盘',
                          action: ToggleSwitch(
                            checked: _isStartupEnabled,
                            onChanged: (value) async {
                              setState(() => _isStartupEnabled = value);
                              await DesktopStartupService.instance.setStartupEnabled(value);
                              await DesktopTrayService.instance.updateContextMenu();
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 1.6 关闭按钮动作
                        _buildSettingCard(
                          title: '点击标题栏关闭按钮动作',
                          subtitle: '可选择收缩到托盘常驻或彻底杀死进程退出',
                          action: _PillSegmentedControl<WindowCloseBehavior>(
                            value: _closeBehavior,
                            items: const [
                              (value: WindowCloseBehavior.minimizeToTray, label: '最小化到托盘', icon: FluentIcons.mini_expand),
                              (value: WindowCloseBehavior.exitApp, label: '彻底退出', icon: FluentIcons.power_button),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _closeBehavior = val;
                                _winManager.setCloseBehavior(val);
                              });
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 1.7 弹性回弹滚动阻尼 (iOS / macOS 风格)
                        _buildSettingCard(
                          title: '弹性回弹滚动阻尼 (iOS / macOS 风格)',
                          subtitle: '开启后滚动到顶/底端产生柔和橡皮筋拉伸回弹；关闭后为 Windows 原生平滑贴边（返回主界面后生效）',
                          badgeText: '返回生效',
                          action: ToggleSwitch(
                            checked: _winManager.enableBouncingScroll,
                            onChanged: (value) async {
                              await _winManager.setEnableBouncingScroll(value);
                              setState(() {});
                            },
                          ),
                        ),

                        const SizedBox(height: 18),

                        // =================================================================
                        // 2. Dock 快捷启动坞与桌面挂件
                        // =================================================================
                        _buildSectionHeader('Dock 快捷启动坞与桌面挂件'),
                        const SizedBox(height: 8),

                        // 2.1 软件内置底部 Dock 栏 (纯净开关，无多余配置)
                        _buildSettingCard(
                          title: '软件内置底部 Dock 栏',
                          subtitle: '在主收纳盒底部悬停自动展开快捷启动坞；关闭后彻底隐藏并释放收纳盒底部空间',
                          badgeText: _winManager.enableInternalBottomDock ? '已启用' : '已关闭',
                          action: ToggleSwitch(
                            checked: _winManager.enableInternalBottomDock,
                            onChanged: (value) async {
                              await _winManager.setEnableInternalBottomDock(value);
                              setState(() {});
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        ListenableBuilder(
                          listenable: DockIslandService.instance,
                          builder: (context, _) {
                            final dockService = DockIslandService.instance;
                            final isEnabled = dockService.isEnabled;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 2.2 独立常驻 Dock 总开关
                                _buildSettingCard(
                                  title: '启用桌面常驻 Dock 挂件',
                                  subtitle: '不受主收纳盒最小化或隐藏影响，常驻在桌面提供快捷系统入口与固定软件',
                                  badgeText: '独立进程',
                                  action: ToggleSwitch(
                                    checked: isEnabled,
                                    onChanged: (value) async {
                                      await dockService.setEnabled(value);
                                    },
                                  ),
                                ),

                                if (isEnabled) ...[
                                  const SizedBox(height: 8),

                                  // 2.2 停靠方位 DIY
                                  _buildSettingCard(
                                    title: 'Dock 停靠方位 (居中停靠)',
                                    subtitle: '固定停靠在屏幕边缘居中位置（禁止拖出屏幕防丢失；左右方位自动切换为纵向立体排列）',
                                    action: _PillSegmentedControl<DockIslandPosition>(
                                      value: dockService.position,
                                      items: const [
                                        (value: DockIslandPosition.bottomCenter, label: '底部居中', icon: FluentIcons.down),
                                        (value: DockIslandPosition.topCenter, label: '顶部居中', icon: FluentIcons.up),
                                        (value: DockIslandPosition.leftCenter, label: '左侧居中', icon: FluentIcons.chevron_left),
                                        (value: DockIslandPosition.rightCenter, label: '右侧居中', icon: FluentIcons.chevron_right),
                                      ],
                                      onChanged: (pos) async {
                                        await dockService.setPosition(pos);
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // 2.3 尺寸规格 DIY
                                  _buildSettingCard(
                                    title: 'Dock 尺寸规格',
                                    subtitle: '自定义独立 Dock 挂件的立体卡片厚度、图标与字体大小',
                                    action: _PillSegmentedControl<DockIslandSize>(
                                      value: dockService.size,
                                      items: const [
                                        (value: DockIslandSize.compact, label: '紧凑 (44px)', icon: FluentIcons.mini_expand),
                                        (value: DockIslandSize.standard, label: '标准 (54px)', icon: FluentIcons.checkbox_composite),
                                        (value: DockIslandSize.large, label: '大号 (64px)', icon: FluentIcons.all_apps),
                                      ],
                                      onChanged: (sz) async {
                                        await dockService.setSize(sz);
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // 2.4 挂件置顶
                                  _buildSettingCard(
                                    title: '挂件窗口始终置顶',
                                    subtitle: '开启后悬浮在所有软件窗口最上层，关闭后贴在桌面底层',
                                    action: ToggleSwitch(
                                      checked: dockService.isAlwaysOnTop,
                                      onChanged: (val) async {
                                        await dockService.setAlwaysOnTop(val);
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // 2.5 自动隐藏 (触碰屏幕边缘弹出)
                                  _buildSettingCard(
                                    title: '自动隐藏 (触碰屏幕边缘弹出)',
                                    subtitle: '开启后平时自动隐藏入屏幕边缘，仅当鼠标移至对应的屏幕边缘时平滑滑出，移开后自动收起',
                                    badgeText: '防遮挡',
                                    action: ToggleSwitch(
                                      checked: dockService.autoHide,
                                      onChanged: (val) async {
                                        await dockService.setAutoHide(val);
                                      },
                                    ),
                                  ),

                                  if (dockService.autoHide) ...[
                                    const SizedBox(height: 8),
                                    _buildSettingCard(
                                      title: '显示边缘感应提示条 (指示唤醒区域)',
                                      subtitle: '开启后在 Dock 收起时保留精致细长的胶囊指示条，清晰提示感应唤醒区域；播放全屏视频或运行全屏软件时将自动彻底隐藏',
                                      badgeText: '防遮挡联动',
                                      action: ToggleSwitch(
                                        checked: dockService.showEdgeIndicator,
                                        onChanged: (val) async {
                                          await dockService.setShowEdgeIndicator(val);
                                        },
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 8),

                                  // 2.5 采样桌面壁纸毛玻璃底色
                                  _buildSettingCard(
                                    title: '采样桌面壁纸毛玻璃底色',
                                    subtitle: '开启后自动采集 Windows 桌面壁纸切片并施加高斯模糊，呈现纯正 macOS 磨砂质感；关闭后采用纯净通透亚克力微光色',
                                    badgeText: '推荐',
                                    action: ToggleSwitch(
                                      checked: dockService.useWallpaperBackdrop,
                                      onChanged: (val) async {
                                        await dockService.setUseWallpaperBackdrop(val);
                                      },
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  // 2.6 挂件独立 Acrylic 不透明度滑块
                                  Card(
                                    backgroundColor: _winManager.cardColor,
                                    borderColor: _winManager.cardBorderColor,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              '挂件独立 Acrylic 磨砂浓度',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                                color: _winManager.textColor,
                                              ),
                                            ),
                                            Text(
                                              '${(dockService.opacity * 100).toInt()}%',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: accentColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '独立调节常驻 Dock 挂件的 Acrylic 毛玻璃浓度与立体透光度（不影响主程序窗口）',
                                          style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                                        ),
                                        const SizedBox(height: 6),
                                        Slider(
                                          value: dockService.opacity.clamp(0.50, 1.0),
                                          min: 0.50,
                                          max: 1.0,
                                          divisions: 50,
                                          onChanged: (val) {
                                            dockService.setOpacity(val);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 18),

                        // =================================================================
                        // 3. 外观与视觉风格分组
                        // =================================================================
                        _buildSectionHeader('外观与视觉风格'),
                        const SizedBox(height: 8),

                        // 2.1 磨砂主题风格
                        _buildSettingCard(
                          title: '主题视觉风格',
                          subtitle: '深色暗黑、浅色纯白与 Aero 晶莹毛玻璃',
                          action: _PillSegmentedControl<WindowThemeStyle>(
                            value: _themeStyle,
                            items: const [
                              (value: WindowThemeStyle.light, label: '磨砂纯白', icon: FluentIcons.sunny),
                              (value: WindowThemeStyle.dark, label: '深邃暗黑', icon: FluentIcons.clear_night),
                              (value: WindowThemeStyle.acrylic, label: 'Aero 晶莹', icon: FluentIcons.brush),
                            ],
                            onChanged: (style) {
                              setState(() {
                                _themeStyle = style;
                                _winManager.setThemeStyle(style);
                              });
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 2.2 面板不透明度调节滑块
                        Card(
                          backgroundColor: _winManager.cardColor,
                          borderColor: _winManager.cardBorderColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '面板不透明度',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: _winManager.textColor,
                                    ),
                                  ),
                                  Text(
                                    '${(_panelOpacity * 100).toInt()}%',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: accentColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '调节磨砂浓度，左滑更通透显现壁纸，右滑更深邃纯粹',
                                style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                              ),
                              const SizedBox(height: 6),
                              Slider(
                                value: _panelOpacity.clamp(0.20, 1.0),
                                min: 0.20,
                                max: 1.0,
                                divisions: 80,
                                onChanged: (val) {
                                  setState(() {
                                    _panelOpacity = val;
                                  });
                                  _winManager.setPanelOpacityFast(val);
                                },
                                onChangeEnd: (val) {
                                  _winManager.savePanelOpacity(val);
                                },
                              ),
                            ],
                          ),
                        ),

                        // 2.3 Windows 系统底层材质与 GPU 性能模式配置 (Acrylic / Mica / Mica Alt / Solid 纯色)
                        const SizedBox(height: 8),
                        Card(
                          backgroundColor: _winManager.cardColor,
                          borderColor: _winManager.cardBorderColor,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '系统底层背景材质与 GPU 渲染模式',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: _winManager.textColor,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: accentColor.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'DWM 硬件加速驱动',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: accentColor,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '不同材质对 Windows DWM 合成器与 GPU 显卡开销不同，您可以根据视觉喜好或硬件配置自由选择：',
                                        style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),

                              // 4 种材质模式卡片
                              Column(
                                children: [
                                  for (final type in WindowBackdropType.values) ...[
                                    _BackdropOptionCard(
                                      type: type,
                                      isSelected: _backdropType == type,
                                      accentColor: accentColor,
                                      isLight: isLight,
                                      onTap: () {
                                        setState(() {
                                          _backdropType = type;
                                          _winManager.setBackdropType(type);
                                        });
                                      },
                                    ),
                                    if (type != WindowBackdropType.values.last)
                                      const SizedBox(height: 6),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        // =================================================================
                        // 3. 桌面分类与规则配置 (支持用户自定义规则与扩展名匹配)
                        // =================================================================
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildSectionHeader('桌面分类与规则引擎'),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _FluentActionButton(
                                  icon: FluentIcons.add,
                                  label: '新建分类',
                                  onPressed: () => _showAddOrEditCategoryDialog(context),
                                ),
                                const SizedBox(width: 8),
                                _FluentActionButton(
                                  icon: FluentIcons.reset,
                                  label: '恢复出厂分类',
                                  onPressed: () => _showResetCategoriesConfirmDialog(context),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '支持自主定义分类名称、专属图标与后缀匹配规则；可拖动/上下调序，实时生效于顶部分类栏。',
                          style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                        ),
                        const SizedBox(height: 8),

                        // 分类列表渲染 (监听 CategoryManager 实时变更)
                        AnimatedBuilder(
                          animation: CategoryManager.instance,
                          builder: (context, _) {
                            final categories = CategoryManager.instance.categories;
                            return Column(
                              children: [
                                for (int i = 0; i < categories.length; i++) ...[
                                  _CategoryItemCard(
                                    category: categories[i],
                                    isFirst: i == 0,
                                    isLast: i == categories.length - 1,
                                    onMoveUp: () => CategoryManager.instance.moveCategory(i, i - 1),
                                    onMoveDown: () => CategoryManager.instance.moveCategory(i, i + 1),
                                    onToggleEnable: (val) => CategoryManager.instance.toggleCategoryEnabled(categories[i].id, val),
                                    onEdit: () => _showAddOrEditCategoryDialog(context, categories[i]),
                                    onDelete: categories[i].isSystem
                                        ? null
                                        : () => _showDeleteCategoryConfirmDialog(context, categories[i]),
                                  ),
                                  if (i < categories.length - 1) const SizedBox(height: 6),
                                ],
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 18),

                        // =================================================================
                        // 4. 数据管理与系统诊断
                        // =================================================================
                        _buildSectionHeader('数据管理与系统诊断'),
                        const SizedBox(height: 8),
                        _buildSettingCard(
                          title: '重新扫描桌面',
                          subtitle: '同步用户桌面与公共桌面的新增或变动项',
                          action: _FluentActionButton(
                            icon: FluentIcons.refresh,
                            label: _isRefreshing ? '正在同步...' : '立即刷新',
                            isLoading: _isRefreshing,
                            onPressed: _isRefreshing
                                ? null
                                : () async {
                                    setState(() => _isRefreshing = true);
                                    await widget.desktopController.refreshItems();
                                    if (mounted) {
                                      setState(() => _isRefreshing = false);
                                      _showRefreshSuccess();
                                    }
                                  },
                          ),
                        ),

                        const SizedBox(height: 8),

                        _buildSettingCard(
                          title: '运行日志与故障排查',
                          subtitle: '记录启动与异常日志（保留最近7天），方便排查异常',
                          badgeText: '诊断排障',
                          action: _FluentActionButton(
                            icon: FluentIcons.open_folder_horizontal,
                            label: '打开日志目录',
                            onPressed: () => AppLogger.openLogDirectory(),
                          ),
                        ),

                        const SizedBox(height: 18),

                        // =================================================================
                        // 4. 软件版本与在线更新 (支持自动检查与手动一键检测)
                        // =================================================================
                        _buildSectionHeader('软件版本与在线更新'),
                        const SizedBox(height: 8),

                        // 4.1 自动检查新版本开关
                        _buildSettingCard(
                          title: '启动时自动检查更新',
                          subtitle: '开启后每次启动应用自动在后台静默检测新版本；关闭后完全免打扰',
                          badgeText: '智能推送',
                          action: ToggleSwitch(
                            checked: AppUpdateService.instance.autoCheckUpdate,
                            onChanged: (value) async {
                              await AppUpdateService.instance.setAutoCheckUpdate(value);
                              setState(() {});
                            },
                          ),
                        ),

                        const SizedBox(height: 8),

                        // 4.2 手动检查更新卡片
                        _buildSettingCard(
                          title: '当前版本: v${AppUpdateService.currentAppVersion}',
                          subtitle: '点击检测官方最新版本、安全补丁与功能更新',
                          badgeText: '官方源',
                          action: _FluentActionButton(
                            icon: _isCheckingUpdate ? FluentIcons.sync_folder : FluentIcons.sync,
                            label: _isCheckingUpdate ? '正在检测...' : '检查更新',
                            onPressed: _isCheckingUpdate ? null : _handleCheckUpdate,
                          ),
                        ),

                        const SizedBox(height: 24),

                        // 关于说明
                        Center(
                          child: Text(
                            '桌面收纳盒 (Tidy Desk) v${AppUpdateService.currentAppVersion} • 开源桌面收纳整理工具 (Apache-2.0 License)',
                            style: TextStyle(
                              fontSize: 11,
                              color: _winManager.subTextColor.withValues(alpha: 0.6),
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
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: _winManager.textColor.withValues(alpha: 0.9),
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    String? badgeText,
    required Widget action,
  }) {
    final accentColor = _winManager.currentThemeStyle.accentColor;

    return Card(
      backgroundColor: _winManager.cardColor,
      borderColor: _winManager.cardBorderColor,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: _winManager.textColor,
                      ),
                    ),
                    if (badgeText != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badgeText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 11.5, color: _winManager.subTextColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          action,
        ],
      ),
    );
  }

  /// 弹出新建或编辑分类对话框
  Future<void> _showAddOrEditCategoryDialog(BuildContext context, [CustomCategory? category]) async {
    await showDialog(
      context: context,
      builder: (ctx) => _CategoryEditDialog(category: category),
    );
  }

  /// 弹出恢复出厂分类配置确认对话框
  Future<void> _showResetCategoriesConfirmDialog(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('恢复出厂分类设置'),
        content: const Text(
          '恢复出厂分类将重置所有分类名称、图标、匹配规则与排序顺序，已新建的自定义分类将被清除。\n\n是否确认恢复出厂设置？',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(const Color(0xFFDC2626)),
            ),
            child: const Text('确认重置'),
          ),
          Button(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CategoryManager.instance.resetToDefaults();
      if (!context.mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('已恢复出厂配置'),
          content: const Text('所有分类已重置为系统默认配置。'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  /// 弹出删除分类确认对话框
  Future<void> _showDeleteCategoryConfirmDialog(BuildContext context, CustomCategory category) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ContentDialog(
        title: const Text('删除分类确认'),
        content: Text('是否确认删除自定义分类 [${category.name}]？\n该操作仅删除分类标签与收纳规则，不会删除您的任何本地实际文件。'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.all(const Color(0xFFDC2626)),
            ),
            child: const Text('确认删除'),
          ),
          Button(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await CategoryManager.instance.deleteCategory(category.id);
      if (!context.mounted) return;
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('删除成功'),
          content: Text('已成功删除分类 [${category.name}]。'),
          severity: InfoBarSeverity.info,
          onClose: close,
        ),
      );
    }
  }
}

/// 现代 Fluent 交互式返回按钮 (带微平移与按压缩放反馈)
class _FluentInteractiveBackButton extends StatefulWidget {
  final VoidCallback onPressed;

  const _FluentInteractiveBackButton({
    required this.onPressed,
  });

  @override
  State<_FluentInteractiveBackButton> createState() => _FluentInteractiveBackButtonState();
}

class _FluentInteractiveBackButtonState extends State<_FluentInteractiveBackButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;

    final Color bgColor;
    final Border border;

    if (_isPressed) {
      bgColor = isLight ? accentColor.withValues(alpha: 0.18) : accentColor.withValues(alpha: 0.28);
      border = Border.all(color: accentColor.withValues(alpha: 0.8), width: 1.0);
    } else if (_isHovered) {
      bgColor = isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.12);
      border = Border.all(
        color: isLight ? Colors.black.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.25),
        width: 1.0,
      );
    } else {
      bgColor = isLight ? Colors.black.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05);
      border = Border.all(
        color: isLight ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.12),
        width: 1.0,
      );
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
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSlide(
                  offset: Offset(_isHovered ? -0.15 : 0.0, 0.0),
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    FluentIcons.back,
                    size: 11,
                    color: _isHovered ? accentColor : winManager.textColor,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '返回',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _isHovered ? accentColor : winManager.textColor,
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

/// 现代 Fluent 交互式操作按钮 (如立即刷新)
class _FluentActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;

  const _FluentActionButton({
    required this.icon,
    required this.label,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  State<_FluentActionButton> createState() => _FluentActionButtonState();
}

class _FluentActionButtonState extends State<_FluentActionButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;
    final isEnabled = widget.onPressed != null;

    final Color bgColor;
    final Border border;

    if (!isEnabled) {
      bgColor = isLight ? Colors.black.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.03);
      border = Border.all(color: Colors.transparent, width: 1.0);
    } else if (_isPressed) {
      bgColor = isLight ? accentColor.withValues(alpha: 0.18) : accentColor.withValues(alpha: 0.28);
      border = Border.all(color: accentColor.withValues(alpha: 0.8), width: 1.0);
    } else if (_isHovered) {
      bgColor = isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.12);
      border = Border.all(
        color: isLight ? Colors.black.withValues(alpha: 0.16) : Colors.white.withValues(alpha: 0.25),
        width: 1.0,
      );
    } else {
      bgColor = isLight ? Colors.black.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.05);
      border = Border.all(
        color: isLight ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.12),
        width: 1.0,
      );
    }

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) {
        if (isEnabled) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (isEnabled) {
          setState(() {
            _isHovered = false;
            _isPressed = false;
          });
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          if (isEnabled) setState(() => _isPressed = true);
        },
        onTapUp: (_) {
          if (isEnabled) setState(() => _isPressed = false);
        },
        onTapCancel: () {
          if (isEnabled) setState(() => _isPressed = false);
        },
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _isPressed ? 0.95 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: border,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.isLoading)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: ProgressRing(strokeWidth: 2),
                  )
                else
                  Icon(
                    widget.icon,
                    size: 12,
                    color: _isHovered ? accentColor : winManager.textColor,
                  ),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: _isHovered ? accentColor : winManager.textColor,
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

/// 预设热键选项按钮
class _PresetKeyButton extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isEnabled;
  final VoidCallback onTap;

  const _PresetKeyButton({
    required this.label,
    required this.isSelected,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  State<_PresetKeyButton> createState() => _PresetKeyButtonState();
}

class _PresetKeyButtonState extends State<_PresetKeyButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;

    return MouseRegion(
      cursor: widget.isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.isEnabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? accentColor
                : (_isHovered
                    ? (isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.12))
                    : (isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.06))),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: widget.isSelected
                  ? accentColor
                  : (_isHovered
                      ? accentColor.withValues(alpha: 0.5)
                      : (isLight ? Colors.black.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.12))),
              width: 0.8,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isSelected) ...[
                const Icon(
                  FluentIcons.check_mark,
                  size: 10,
                  color: Colors.white,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: widget.isSelected ? Colors.white : winManager.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 现代流畅胶囊分段选择器 (0 延迟即时切换、0 遮挡)
class _PillSegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<({T value, String label, IconData? icon})> items;
  final ValueChanged<T> onChanged;

  const _PillSegmentedControl({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: items.map((item) {
          final isSelected = item.value == value;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _PillSegmentItem(
              label: item.label,
              icon: item.icon,
              isSelected: isSelected,
              accentColor: accentColor,
              textColor: winManager.textColor,
              onTap: () => onChanged(item.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PillSegmentItem extends StatefulWidget {
  final String label;
  final IconData? icon;
  final bool isSelected;
  final Color accentColor;
  final Color textColor;
  final VoidCallback onTap;

  const _PillSegmentItem({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.accentColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  State<_PillSegmentItem> createState() => _PillSegmentItemState();
}

class _PillSegmentItemState extends State<_PillSegmentItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.accentColor
                : (_isHovered ? Colors.white.withValues(alpha: 0.10) : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: 12,
                  color: widget.isSelected ? Colors.white : widget.textColor,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: widget.isSelected ? Colors.white : widget.textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快捷键录制控制栏 (高度对齐、防误触覆盖、支持实时键盘录制与一键恢复默认)
class _HotkeyRecorderControlBar extends StatefulWidget {
  final bool isEnabled;
  final VoidCallback onUpdated;

  const _HotkeyRecorderControlBar({
    required this.isEnabled,
    required this.onUpdated,
  });

  @override
  State<_HotkeyRecorderControlBar> createState() => _HotkeyRecorderControlBarState();
}

class _HotkeyRecorderControlBarState extends State<_HotkeyRecorderControlBar> {
  bool _isRecording = false;
  HotKey? _pendingHotKey;
  String _pendingDisplay = '';
  String? _validationError;
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    if (_isRecording) {
      DesktopHotkeyService.instance.setRecordingMode(false);
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    if (!widget.isEnabled) return;
    DesktopHotkeyService.instance.setRecordingMode(true);
    setState(() {
      _isRecording = true;
      _pendingHotKey = null;
      _pendingDisplay = '';
      _validationError = null;
    });
    _focusNode.requestFocus();
  }

  void _stopRecording() {
    DesktopHotkeyService.instance.setRecordingMode(false);
    setState(() {
      _isRecording = false;
      _pendingHotKey = null;
      _pendingDisplay = '';
      _validationError = null;
    });
    _focusNode.unfocus();
  }

  Future<void> _applyPendingHotKey() async {
    if (_pendingHotKey == null) return;
    final result = await DesktopHotkeyService.instance.setCustomHotKey(_pendingHotKey!);
    _stopRecording();
    widget.onUpdated();

    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) {
          return InfoBar(
            title: Text(result.success ? '快捷键绑定成功' : '快捷键绑定失败'),
            content: Text(result.message),
            severity: result.success ? InfoBarSeverity.success : InfoBarSeverity.warning,
            onClose: close,
          );
        },
      );
    }
  }

  Future<void> _onRestoreDefault() async {
    if (!widget.isEnabled) return;
    final hotkeyService = DesktopHotkeyService.instance;

    if (!hotkeyService.isCustom && hotkeyService.selectedOptionIndex == 0) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('已是默认快捷键'),
          content: const Text('当前已经是默认的 Alt + Space 快捷键。'),
          severity: InfoBarSeverity.info,
          onClose: close,
        ),
      );
      return;
    }

    if (hotkeyService.isCustom) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => ContentDialog(
          title: const Text('恢复默认快捷键'),
          content: Text(
            '当前正在使用自定义快捷键 [${hotkeyService.currentKeyDisplay}]。\n\n是否确认恢复为出厂默认的 [Alt + Space]？',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认恢复'),
            ),
            Button(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await hotkeyService.resetToDefault();
    widget.onUpdated();

    if (mounted) {
      displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('已恢复默认'),
          content: const Text('召唤快捷键已恢复为 Alt + Space。'),
          severity: InfoBarSeverity.success,
          onClose: close,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final accentColor = winManager.currentThemeStyle.accentColor;
    final isLight = winManager.isLight;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (!_isRecording) return KeyEventResult.ignored;

        if (event is KeyDownEvent) {
          final logicalKey = event.logicalKey;

          if (logicalKey == LogicalKeyboardKey.escape) {
            _stopRecording();
            return KeyEventResult.handled;
          }

          final isModifier = logicalKey == LogicalKeyboardKey.controlLeft ||
              logicalKey == LogicalKeyboardKey.controlRight ||
              logicalKey == LogicalKeyboardKey.altLeft ||
              logicalKey == LogicalKeyboardKey.altRight ||
              logicalKey == LogicalKeyboardKey.shiftLeft ||
              logicalKey == LogicalKeyboardKey.shiftRight ||
              logicalKey == LogicalKeyboardKey.metaLeft ||
              logicalKey == LogicalKeyboardKey.metaRight ||
              logicalKey == LogicalKeyboardKey.capsLock;

          if (isModifier) {
            return KeyEventResult.handled;
          }

          final modifiers = <HotKeyModifier>[];
          if (HardwareKeyboard.instance.isControlPressed) modifiers.add(HotKeyModifier.control);
          if (HardwareKeyboard.instance.isAltPressed) modifiers.add(HotKeyModifier.alt);
          if (HardwareKeyboard.instance.isShiftPressed) modifiers.add(HotKeyModifier.shift);
          if (HardwareKeyboard.instance.isMetaPressed) modifiers.add(HotKeyModifier.meta);

          final newHotKey = HotKey(
            key: logicalKey,
            modifiers: modifiers.isEmpty ? null : modifiers,
            scope: HotKeyScope.system,
          );

          final validation = DesktopHotkeyService.validateHotKey(newHotKey);
          if (!validation.isValid) {
            setState(() {
              _pendingHotKey = null;
              _pendingDisplay = '';
              _validationError = validation.errorMessage;
            });
            return KeyEventResult.handled;
          }

          setState(() {
            _pendingHotKey = newHotKey;
            _pendingDisplay = DesktopHotkeyService.formatHotKey(newHotKey);
            _validationError = null;
          });

          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: !_isRecording
            ? Row(
                key: const ValueKey('idle_bar'),
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 32,
                      child: Tooltip(
                        message: '点击开始录制任意自定义快捷键组合',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.isEnabled ? _startRecording : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isLight
                                  ? Colors.black.withValues(alpha: 0.03)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: isLight
                                    ? Colors.black.withValues(alpha: 0.12)
                                    : Colors.white.withValues(alpha: 0.14),
                                width: 0.9,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  FluentIcons.keyboard_classic,
                                  size: 13,
                                  color: widget.isEnabled ? accentColor : winManager.subTextColor,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  '点击录制自定义快捷键',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: widget.isEnabled ? winManager.textColor : winManager.subTextColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '(支持任意组合，如 Ctrl+Alt+K 等)',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: winManager.subTextColor,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '录制',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: accentColor,
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
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: _FluentActionButton(
                      icon: FluentIcons.refresh,
                      label: '恢复默认 (Alt+Space)',
                      onPressed: widget.isEnabled ? _onRestoreDefault : null,
                    ),
                  ),
                ],
              )
            : Container(
                key: const ValueKey('recording_bar'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: accentColor,
                    width: 1.2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(FluentIcons.radio_bullet, size: 12, color: Color(0xFFEF4444)),
                        const SizedBox(width: 6),
                        Text(
                          _pendingDisplay.isEmpty
                              ? '请在键盘上直接按下您的组合键...'
                              : '已捕获按键：',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: winManager.textColor,
                          ),
                        ),
                        if (_pendingDisplay.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: accentColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _pendingDisplay,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                        const Spacer(),
                        if (_pendingHotKey != null) ...[
                          SizedBox(
                            height: 26,
                            child: FilledButton(
                              onPressed: _applyPendingHotKey,
                              style: ButtonStyle(
                                padding: WidgetStateProperty.all(
                                  const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                ),
                              ),
                              child: const Text('保存并绑定', style: TextStyle(fontSize: 11.5)),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        SizedBox(
                          height: 26,
                          child: Button(
                            onPressed: _stopRecording,
                            style: ButtonStyle(
                              padding: WidgetStateProperty.all(
                                const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                              ),
                            ),
                            child: const Text('取消 (Esc)', style: TextStyle(fontSize: 11.5)),
                          ),
                        ),
                      ],
                    ),
                    if (_validationError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _validationError!,
                        style: TextStyle(fontSize: 11, color: Colors.warningPrimaryColor),
                      ),
                    ],
                  ],
                ),
              ),
      ),
    );
  }
}

// =============================================================================
// 系统底层 DWM 背景材质与 GPU 性能选项卡片
// =============================================================================

/// 材质模式选项卡片 (展示材质特征、视觉表现及 GPU 负载性能详尽解析)
class _BackdropOptionCard extends StatefulWidget {
  final WindowBackdropType type;
  final bool isSelected;
  final Color accentColor;
  final bool isLight;
  final VoidCallback onTap;

  const _BackdropOptionCard({
    required this.type,
    required this.isSelected,
    required this.accentColor,
    required this.isLight,
    required this.onTap,
  });

  @override
  State<_BackdropOptionCard> createState() => _BackdropOptionCardState();
}

class _BackdropOptionCardState extends State<_BackdropOptionCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    final isSelected = widget.isSelected;
    final accent = widget.accentColor;
    final isLight = widget.isLight;
    final winManager = WindowManagerWin32.instance;
    final isSupported = type.isSupported(winManager.isWindows11);

    final Color bgColor;
    final Color borderColor;

    if (!isSupported) {
      bgColor = isLight
          ? Colors.black.withValues(alpha: 0.015)
          : Colors.white.withValues(alpha: 0.02);
      borderColor = isLight
          ? Colors.black.withValues(alpha: 0.05)
          : Colors.white.withValues(alpha: 0.06);
    } else if (isSelected) {
      bgColor = isLight
          ? accent.withValues(alpha: 0.10)
          : accent.withValues(alpha: 0.18);
      borderColor = accent;
    } else if (_isHovered) {
      bgColor = isLight
          ? Colors.black.withValues(alpha: 0.04)
          : Colors.white.withValues(alpha: 0.07);
      borderColor = isLight
          ? Colors.black.withValues(alpha: 0.15)
          : Colors.white.withValues(alpha: 0.20);
    } else {
      bgColor = isLight
          ? Colors.black.withValues(alpha: 0.02)
          : Colors.white.withValues(alpha: 0.03);
      borderColor = isLight
          ? Colors.black.withValues(alpha: 0.07)
          : Colors.white.withValues(alpha: 0.08);
    }

    return RepaintBoundary(
      child: MouseRegion(
        cursor: isSupported
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onEnter: (_) {
          if (isSupported) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (isSupported) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          onTap: isSupported ? widget.onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              // 边框宽度固定为 1.0，彻底消除 1px 抖动
              border: Border.all(color: borderColor, width: 1.0),
            ),
            child: Opacity(
              opacity: isSupported ? 1.0 : 0.48,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 单选圆点指示器 (固定 16x16 尺寸，绝对 0 像素抖动)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? accent
                              : (isSupported
                                  ? winManager.subTextColor.withValues(alpha: 0.45)
                                  : winManager.subTextColor.withValues(alpha: 0.25)),
                          width: 1.2,
                        ),
                        color: isSelected ? accent.withValues(alpha: 0.15) : Colors.transparent,
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: accent,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // 2. 材质名称、视觉介绍与 GPU 性能影响
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              type.label,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected ? accent : winManager.textColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 性能评级徽章
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: isSupported
                                    ? type.badgeColor.withValues(alpha: 0.15)
                                    : (isLight ? Colors.black.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.08)),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: isSupported
                                      ? type.badgeColor.withValues(alpha: 0.4)
                                      : Colors.transparent,
                                  width: 0.6,
                                ),
                              ),
                              child: Text(
                                isSupported ? type.badgeText : '仅限 Win11',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSupported ? type.badgeColor : winManager.subTextColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // 视觉特色说明
                        Text(
                          isSupported
                              ? type.visualDesc
                              : '${type.visualDesc} (当前系统不支持云母材质，已自动兼容处理)',
                          style: TextStyle(
                            fontSize: 11,
                            color: winManager.subTextColor,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // GPU 性能影响详解
                        Row(
                          children: [
                            Icon(
                              FluentIcons.speed_high,
                              size: 10,
                              color: isSupported ? type.badgeColor : winManager.subTextColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                type.perfDesc,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w500,
                                  color: isLight
                                      ? const Color(0xFF334155)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// 分类与规则管理专属 Fluent UI 组件与对话框
// =============================================================================

/// 单个分类条目卡片 (展示图标、名称、匹配规则、排序调序、编辑与删除)
class _CategoryItemCard extends StatelessWidget {
  final CustomCategory category;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final ValueChanged<bool> onToggleEnable;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _CategoryItemCard({
    required this.category,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onToggleEnable,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;

    return Card(
      backgroundColor: winManager.cardColor,
      borderColor: winManager.cardBorderColor,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // 1. 上下排序按钮组 (极简紧凑)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MiniIconButton(
                icon: FluentIcons.chevron_up,
                tooltip: '上移分类',
                isEnabled: !isFirst,
                onTap: onMoveUp,
              ),
              const SizedBox(height: 2),
              _MiniIconButton(
                icon: FluentIcons.chevron_down,
                tooltip: '下移分类',
                isEnabled: !isLast,
                onTap: onMoveDown,
              ),
            ],
          ),
          const SizedBox(width: 10),

          // 2. 分类图标 (带圆角浅色背景容器)
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: category.isEnabled
                  ? accentColor.withValues(alpha: 0.12)
                  : (isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.04)),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: category.isEnabled
                    ? accentColor.withValues(alpha: 0.35)
                    : Colors.transparent,
                width: 0.8,
              ),
            ),
            child: Center(
              child: Icon(
                category.iconData,
                size: 15,
                color: category.isEnabled ? accentColor : winManager.subTextColor,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 3. 分类信息与匹配规则预览
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      category.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: category.isEnabled ? winManager.textColor : winManager.subTextColor,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 系统内置 / 自定义规则标签
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: category.isSystem
                            ? (isLight ? Colors.black.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.08))
                            : accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        category.isSystem ? '系统内置' : '自定义',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: category.isSystem ? winManager.subTextColor : accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // 规则说明与后缀 Chips 预览
                _buildRuleDescription(context, accentColor, isLight),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 4. 操作按钮组 (编辑 / 删除 / 启用切换)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 编辑按钮
              Tooltip(
                message: '编辑分类与规则',
                child: IconButton(
                  icon: Icon(FluentIcons.edit, size: 12, color: winManager.subTextColor),
                  onPressed: onEdit,
                ),
              ),
              const SizedBox(width: 2),

              // 删除按钮 (系统内置分类禁用并提示)
              Tooltip(
                message: category.isSystem ? '系统内置分类不可删除 (可关闭开关隐藏)' : '删除分类',
                child: IconButton(
                  icon: Icon(
                    FluentIcons.delete,
                    size: 12,
                    color: category.isSystem
                        ? winManager.subTextColor.withValues(alpha: 0.3)
                        : const Color(0xFFEF4444),
                  ),
                  onPressed: onDelete,
                ),
              ),
              const SizedBox(width: 6),

              // 启用/隐藏开关
              Tooltip(
                message: category.isEnabled ? '点击隐藏该分类标签' : '点击在主页面展示该分类',
                child: ToggleSwitch(
                  checked: category.isEnabled,
                  onChanged: onToggleEnable,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建分类匹配规则预览描述
  Widget _buildRuleDescription(BuildContext context, Color accentColor, bool isLight) {
    final winManager = WindowManagerWin32.instance;

    switch (category.matchType) {
      case CategoryMatchType.all:
        return Text(
          '匹配全量桌面图标与文件',
          style: TextStyle(fontSize: 11, color: winManager.subTextColor),
        );
      case CategoryMatchType.frequent:
        return Text(
          '智能识别或手动星标的高频使用项',
          style: TextStyle(fontSize: 11, color: winManager.subTextColor),
        );
      case CategoryMatchType.folder:
        return Text(
          '匹配桌面所有目录与文件夹',
          style: TextStyle(fontSize: 11, color: winManager.subTextColor),
        );
      case CategoryMatchType.manual:
        final count = category.manualItemKeys.length;
        return Text(
          '手动自选收纳 · 当前已收纳 $count 个桌面项目',
          style: TextStyle(fontSize: 11, color: winManager.subTextColor),
        );
      case CategoryMatchType.extension:
        if (category.matchExtensions.isEmpty) {
          return const Text(
            '未配置匹配扩展名（无文件会被收纳）',
            style: TextStyle(fontSize: 11, color: Color(0xFFF59E0B)),
          );
        }
        final displayExts = category.matchExtensions.take(6).toList();
        final remainingCount = category.matchExtensions.length - displayExts.length;

        return Wrap(
          spacing: 4,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final ext in displayExts)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                    color: isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.1),
                    width: 0.6,
                  ),
                ),
                child: Text(
                  ext,
                  style: TextStyle(fontSize: 10, color: winManager.subTextColor),
                ),
              ),
            if (remainingCount > 0)
              Text(
                '+$remainingCount',
                style: TextStyle(fontSize: 10, color: winManager.subTextColor.withValues(alpha: 0.8)),
              ),
          ],
        );
    }
  }
}

/// 极简微型上下移动按钮
class _MiniIconButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onTap;

  const _MiniIconButton({
    required this.icon,
    required this.tooltip,
    required this.isEnabled,
    required this.onTap,
  });

  @override
  State<_MiniIconButton> createState() => _MiniIconButtonState();
}

class _MiniIconButtonState extends State<_MiniIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: widget.isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) {
          if (widget.isEnabled) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (widget.isEnabled) setState(() => _isHovered = false);
        },
        child: GestureDetector(
          onTap: widget.isEnabled ? widget.onTap : null,
          child: Container(
            width: 20,
            height: 14,
            decoration: BoxDecoration(
              color: _isHovered
                  ? (isLight ? accentColor.withValues(alpha: 0.15) : accentColor.withValues(alpha: 0.25))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Center(
              child: Icon(
                widget.icon,
                size: 9,
                color: widget.isEnabled
                    ? (_isHovered ? accentColor : winManager.subTextColor)
                    : winManager.subTextColor.withValues(alpha: 0.25),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 分类新建与编辑对话框 (提供名称输入、24 款常用 Fluent 图标选择网格、匹配规则及常用预设 Chips)
class _CategoryEditDialog extends StatefulWidget {
  final CustomCategory? category;

  const _CategoryEditDialog({this.category});

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _extController;
  late int _selectedIconCodePoint;
  late CategoryMatchType _selectedMatchType;
  String? _errorMessage;

  /// 预设可供点选的 64 款 Fluent 现代高频图标库 (Unicode 码点)
  static const List<({String name, int codePoint})> _availableIcons = [
    // 1. 核心与状态
    (name: '全部应用', codePoint: 0xE71D),
    (name: '常用/星标', codePoint: 0xE734),
    (name: '收藏/心形', codePoint: 0xEB51),
    (name: '极速/闪电', codePoint: 0xE945),
    (name: '启动/火箭', codePoint: 0xF3B3),
    (name: '主页/首页', codePoint: 0xE80F),
    (name: '桌面/屏幕', codePoint: 0xF5D9),
    (name: '已完成/勾选', codePoint: 0xE73E),

    // 2. 办公与文档
    (name: '文本文档', codePoint: 0xE8A5),
    (name: '便签/记事', codePoint: 0xE70B),
    (name: '图书/阅读', codePoint: 0xE736),
    (name: '统计/报表', codePoint: 0xE9D2),
    (name: '数据分析', codePoint: 0xF1C3),
    (name: '财务/金钱', codePoint: 0xE8C7),
    (name: '打印输出', codePoint: 0xE749),
    (name: '知识库/字典', codePoint: 0xE8F1),

    // 3. 影音与多媒体
    (name: '图片素材', codePoint: 0xEB9F),
    (name: '影视视频', codePoint: 0xE714),
    (name: '音频音乐', codePoint: 0xEC4F),
    (name: '媒体播放', codePoint: 0xE768),
    (name: '耳机/收听', codePoint: 0xE7F6),
    (name: '相机/摄影', codePoint: 0xE722),
    (name: '录音/麦克风', codePoint: 0xE720),
    (name: '设计/画笔', codePoint: 0xE76D),

    // 4. 代码开发与科技
    (name: '代码/编程', codePoint: 0xE943),
    (name: '终端/命令行', codePoint: 0xE756),
    (name: '网页/浏览器', codePoint: 0xE774),
    (name: '数据库/存储', codePoint: 0xE74C),
    (name: '开发者工具', codePoint: 0xEC7A),
    (name: '云端/网盘', codePoint: 0xE753),
    (name: '分支/版本', codePoint: 0xEA68),
    (name: '工作区/容器', codePoint: 0xF158),

    // 5. 文件与整理
    (name: '普通文件夹', codePoint: 0xE8B7),
    (name: '压缩/归档', codePoint: 0xE7B8),
    (name: '快捷方式', codePoint: 0xE71B),
    (name: '标签/分类', codePoint: 0xE8EC),
    (name: '搜索/查找', codePoint: 0xE721),
    (name: '下载中心', codePoint: 0xE896),
    (name: '上传同步', codePoint: 0xE898),
    (name: '清理/删除', codePoint: 0xE74D),

    // 6. 系统与工具
    (name: '设置/系统', codePoint: 0xE713),
    (name: '维护/工具', codePoint: 0xE90F),
    (name: '安全/加锁', codePoint: 0xE72E),
    (name: '权限/钥匙', codePoint: 0xE8D7),
    (name: '防护/盾牌', codePoint: 0xEA18),
    (name: '电量/能源', codePoint: 0xE83F),
    (name: '时钟/定时', codePoint: 0xE823),
    (name: '日历/日程', codePoint: 0xE787),

    // 7. 商务、社交与生活
    (name: '游戏/娱乐', codePoint: 0xE7FC),
    (name: '奖杯/荣誉', codePoint: 0xE7F7),
    (name: '消息/沟通', codePoint: 0xE8BD),
    (name: '邮件/信件', codePoint: 0xE715),
    (name: '电话/通讯', codePoint: 0xE717),
    (name: '购物/电商', codePoint: 0xE7BF),
    (name: '餐饮/休闲', codePoint: 0xEC32),
    (name: '教育/学习', codePoint: 0xE7BE),

    // 8. 效率与协作
    (name: '公文包/工作', codePoint: 0xEDE2),
    (name: '办公协同', codePoint: 0xEDE1),
    (name: '图钉/固定', codePoint: 0xE840),
    (name: '发送/传输', codePoint: 0xE724),
    (name: '分享/协作', codePoint: 0xE72D),
    (name: '过滤/筛选', codePoint: 0xE71C),
    (name: '调色盘/艺术', codePoint: 0xE790),
    (name: '灵感/探索', codePoint: 0xEA16),
  ];

  /// 常见扩展名预设包 (点击可快速追加到扩展名输入框中)
  static const List<({String label, List<String> exts})> _presetExtensionPacks = [
    (label: '办公文档', exts: ['doc', 'docx', 'pdf', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md']),
    (label: '图片素材', exts: ['jpg', 'jpeg', 'png', 'gif', 'webp', 'svg', 'bmp', 'ico']),
    (label: '影视音乐', exts: ['mp4', 'mkv', 'avi', 'mov', 'flv', 'mp3', 'wav', 'flac', 'aac']),
    (label: '代码开发', exts: ['dart', 'js', 'ts', 'py', 'java', 'cpp', 'html', 'css', 'json', 'yaml']),
    (label: '压缩包', exts: ['zip', 'rar', '7z', 'tar', 'gz']),
    (label: '安装快捷', exts: ['lnk', 'url', 'exe', 'msi', 'bat', 'cmd', 'ps1']),
    (label: '设计工程', exts: ['psd', 'ai', 'sketch', 'fig', 'xd', 'cdr', 'dwg']),
  ];

  late final ScrollController _dialogScrollController;
  late final ScrollController _iconScrollController;

  @override
  void initState() {
    super.initState();
    _dialogScrollController = ScrollController();
    _iconScrollController = ScrollController();
    final cat = widget.category;
    _nameController = TextEditingController(text: cat?.name ?? '');
    _extController = TextEditingController(text: cat?.matchExtensions.join(', ') ?? '');
    _selectedIconCodePoint = cat?.iconCodePoint ?? 0xE71D;
    _selectedMatchType = cat?.matchType ?? CategoryMatchType.extension;
  }

  @override
  void dispose() {
    _dialogScrollController.dispose();
    _iconScrollController.dispose();
    _nameController.dispose();
    _extController.dispose();
    super.dispose();
  }

  /// 一键追加预设扩展名到输入框
  void _appendExtensions(List<String> newExts) {
    final current = CustomCategory.normalizeExtensions(_extController.text.split(RegExp(r'[,，\s]+')));
    final union = <String>{...current, ...CustomCategory.normalizeExtensions(newExts)}.toList();
    _extController.text = union.join(', ');
    setState(() {});
  }

  /// 验证并保存分类
  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = '分类名称不能为空');
      return;
    }

    List<String> extensions = [];
    if (_selectedMatchType == CategoryMatchType.extension) {
      extensions = CustomCategory.normalizeExtensions(
        _extController.text.split(RegExp(r'[,，\s]+')),
      );
      if (extensions.isEmpty) {
        setState(() => _errorMessage = '按扩展名匹配的分类必须至少填写一个扩展名');
        return;
      }
    }

    if (widget.category == null) {
      // 新建分类
      final newCategory = CustomCategory(
        id: 'user_cat_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        iconCodePoint: _selectedIconCodePoint,
        matchType: _selectedMatchType,
        matchExtensions: extensions,
        manualItemKeys: const [],
        isSystem: false,
        isEnabled: true,
        sortOrder: CategoryManager.instance.categories.length,
      );
      await CategoryManager.instance.addCategory(newCategory);
    } else {
      // 编辑已有分类 (保留已有 manualItemKeys)
      final updated = widget.category!.copyWith(
        name: name,
        iconCodePoint: _selectedIconCodePoint,
        matchType: _selectedMatchType,
        matchExtensions: extensions,
      );
      await CategoryManager.instance.updateCategory(updated);
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final winManager = WindowManagerWin32.instance;
    final isLight = winManager.isLight;
    final accentColor = winManager.currentThemeStyle.accentColor;
    final isEditing = widget.category != null;

    final inputDecoration = BoxDecoration(
      color: isLight ? Colors.white : Colors.black.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(6.0),
      border: Border.all(
        color: isLight ? const Color(0x33000000) : const Color(0x33FFFFFF),
        width: 0.8,
      ),
    );

    return ContentDialog(
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 660),
      title: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              isEditing ? FluentIcons.edit : FluentIcons.add,
              size: 13,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            isEditing ? '编辑桌面分类与规则' : '新建桌面自定义分类',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: winManager.textColor,
            ),
          ),
        ],
      ),
      content: ScrollbarTheme(
        data: const ScrollbarThemeData(
          thickness: 5.0,
          hoveringThickness: 7.0,
          mainAxisMargin: 6.0,
          crossAxisMargin: 2.0,
          radius: Radius.circular(3.0),
          hoveringRadius: Radius.circular(3.0),
        ),
        child: Scrollbar(
          controller: _dialogScrollController,
          interactive: true,
          child: SingleChildScrollView(
            controller: _dialogScrollController,
            padding: const EdgeInsets.only(top: 2.0, right: 14.0, bottom: 4.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 分类名称输入
                Text(
                  '分类名称',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: winManager.textColor),
                ),
                const SizedBox(height: 5),
                TextBox(
                  controller: _nameController,
                  placeholder: '例如：工作文档、设计素材、开发项目...',
                  maxLength: 12,
                  decoration: WidgetStatePropertyAll(inputDecoration),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  style: TextStyle(fontSize: 12.5, color: winManager.textColor),
                  highlightColor: accentColor.withValues(alpha: 0.15),
                  onChanged: (_) {
                    if (_errorMessage != null) setState(() => _errorMessage = null);
                  },
                ),

                const SizedBox(height: 11),

                // 2. 选择分类图标 (现代 Fluent 图标网格)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '分类专属图标',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: winManager.textColor),
                    ),
                    Row(
                      children: [
                        Icon(
                          CustomCategory.getIconFromCodePoint(_selectedIconCodePoint),
                          size: 13,
                          color: accentColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '已选择',
                          style: TextStyle(fontSize: 11, color: accentColor, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  height: 118,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isLight ? Colors.black.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isLight ? Colors.black.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.1),
                      width: 0.8,
                    ),
                  ),
                  child: ScrollbarTheme(
                    data: const ScrollbarThemeData(
                      thickness: 4.0,
                      hoveringThickness: 6.0,
                      radius: Radius.circular(2.0),
                    ),
                    child: Scrollbar(
                      controller: _iconScrollController,
                      interactive: true,
                      child: GridView.builder(
                        controller: _iconScrollController,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                        ),
                        itemCount: _availableIcons.length,
                        itemBuilder: (context, index) {
                          final iconItem = _availableIcons[index];
                          final iconName = iconItem.name;
                          final codePoint = iconItem.codePoint;
                          final isSelected = codePoint == _selectedIconCodePoint;

                          return Tooltip(
                            message: iconName,
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedIconCodePoint = codePoint),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? accentColor.withValues(alpha: 0.18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: isSelected ? accentColor : Colors.transparent,
                                    width: 1.2,
                                  ),
                                ),
                                child: Center(
                                  child: Icon(
                                    CustomCategory.getIconFromCodePoint(codePoint),
                                    size: 15,
                                    color: isSelected ? accentColor : winManager.textColor,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 11),

                // 3. 匹配规则类型选择
                Text(
                  '匹配规则类型',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: winManager.textColor),
                ),
                const SizedBox(height: 5),
                ComboBox<CategoryMatchType>(
                  value: _selectedMatchType,
                  isExpanded: true,
                  items: const [
                    ComboBoxItem(
                      value: CategoryMatchType.extension,
                      child: Text('按文件扩展名自动匹配 (如 doc, jpg, zip)'),
                    ),
                    ComboBoxItem(
                      value: CategoryMatchType.manual,
                      child: Text('手动自选分类 (由您自由挑选项目收纳)'),
                    ),
                    ComboBoxItem(
                      value: CategoryMatchType.folder,
                      child: Text('所有文件夹与目录'),
                    ),
                    ComboBoxItem(
                      value: CategoryMatchType.all,
                      child: Text('全部桌面项 (不作任何过滤)'),
                    ),
                    ComboBoxItem(
                      value: CategoryMatchType.frequent,
                      child: Text('常用 / 星标高频项'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedMatchType = val);
                  },
                ),

                // 4. 当选择手动分类时，展示贴心指引卡片
                if (_selectedMatchType == CategoryMatchType.manual) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(FluentIcons.info, size: 14, color: accentColor),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '手动自选分类无需配置后缀规则。创建后，您可在任意桌面项目上右键选择「归类到...」，或直接将外部文件拖入此分类收纳。',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: winManager.textColor,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 4. 当选择按扩展名匹配时，展示后缀输入框及快捷 Chip
                if (_selectedMatchType == CategoryMatchType.extension) ...[
                  const SizedBox(height: 11),
                  Text(
                    '匹配扩展名 (以逗号或空格分隔，无需带点)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: winManager.textColor),
                  ),
                  const SizedBox(height: 5),
                  TextBox(
                    controller: _extController,
                    placeholder: '例如：pdf, doc, docx, txt, md',
                    decoration: WidgetStatePropertyAll(inputDecoration),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    style: TextStyle(fontSize: 12.5, color: winManager.textColor),
                    highlightColor: accentColor.withValues(alpha: 0.15),
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                  ),
                  const SizedBox(height: 7),

                  // 快速预设扩展名包 Chips
                  Text(
                    '点击快速追加常用类型：',
                    style: TextStyle(fontSize: 11, color: winManager.subTextColor),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final pack in _presetExtensionPacks)
                        GestureDetector(
                          onTap: () => _appendExtensions(pack.exts),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isLight ? Colors.black.withValues(alpha: 0.04) : Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isLight ? Colors.black.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.15),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(FluentIcons.add, size: 9, color: accentColor),
                                const SizedBox(width: 3),
                                Text(
                                  pack.label,
                                  style: TextStyle(fontSize: 11, color: winManager.textColor),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3), width: 0.8),
                    ),
                    child: Row(
                      children: [
                        const Icon(FluentIcons.error_badge, size: 12, color: Color(0xFFEF4444)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFEF4444)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: _handleSave,
          child: const Text('保存分类'),
        ),
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ],
    );
  }
}
