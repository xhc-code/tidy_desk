import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// ==========================================
// Win32 User32 动态链接库底层 API 声明
// ==========================================
final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

typedef _FindWindowNative = IntPtr Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
typedef _FindWindowDart = int Function(Pointer<Utf16> lpClassName, Pointer<Utf16> lpWindowName);
final _findWindow = _user32.lookupFunction<_FindWindowNative, _FindWindowDart>('FindWindowW');

typedef _FindWindowExNative = IntPtr Function(IntPtr hWndParent, IntPtr hWndChildAfter, Pointer<Utf16> lpszClass, Pointer<Utf16> lpszWindow);
typedef _FindWindowExDart = int Function(int hWndParent, int hWndChildAfter, Pointer<Utf16> lpszClass, Pointer<Utf16> lpszWindow);
final _findWindowEx = _user32.lookupFunction<_FindWindowExNative, _FindWindowExDart>('FindWindowExW');

typedef _ShowWindowNative = Int32 Function(IntPtr hWnd, Int32 nCmdShow);
typedef _ShowWindowDart = int Function(int hWnd, int nCmdShow);
final _showWindow = _user32.lookupFunction<_ShowWindowNative, _ShowWindowDart>('ShowWindow');

typedef _IsWindowVisibleNative = Int32 Function(IntPtr hWnd);
typedef _IsWindowVisibleDart = int Function(int hWnd);
final _isWindowVisible = _user32.lookupFunction<_IsWindowVisibleNative, _IsWindowVisibleDart>('IsWindowVisible');

typedef _EnumWindowsProc = Int32 Function(IntPtr hWnd, IntPtr lParam);
typedef _EnumWindowsNative = Int32 Function(Pointer<NativeFunction<_EnumWindowsProc>> lpEnumFunc, IntPtr lParam);
typedef _EnumWindowsDart = int Function(Pointer<NativeFunction<_EnumWindowsProc>> lpEnumFunc, int lParam);
final _enumWindows = _user32.lookupFunction<_EnumWindowsNative, _EnumWindowsDart>('EnumWindows');

const int _swHide = 0;
const int _swShow = 5;

// 用于 EnumWindows 寻找 WorkerW 下的 SHELLDLL_DefView
int _foundDefViewHwnd = 0;
int _enumWindowsCallback(int hWnd, int lParam) {
  return using((Arena arena) {
    final defViewName = 'SHELLDLL_DefView'.toNativeUtf16(allocator: arena);
    final defView = _findWindowEx(hWnd, 0, defViewName, nullptr);
    if (defView != 0) {
      _foundDefViewHwnd = defView;
      return 0; // 停止枚举
    }
    return 1; // 继续枚举
  });
}

/// 窗口视觉主题风格枚举 (聚焦 3 种高颜值、高清晰度、高对比度经典磨砂主题)
enum WindowThemeStyle {
  /// 磨砂纯白 (晶莹纯白透亮，壁纸透显，如 easyDesktop 经典磨砂白)
  light(
    '磨砂纯白 (晶莹透亮 · 磨砂透显)',
    WindowEffect.acrylic,
    Color(0x20FFFFFF),
    Color(0xFFFFFFFF),
    Color(0xFF0078D4),
    true,
  ),

  /// 深邃暗黑 (经典 Fluent 晶莹黑曜石磨砂，纯白高对比度文字)
  dark(
    '深邃暗黑 (晶莹磨砂 · 经典纯黑)',
    WindowEffect.acrylic,
    Color(0x20000000),
    Color(0xFF14161F),
    Color(0xFF38BDF8),
    false,
  ),

  /// Aero 晶莹高透 (全透晶莹 · 极致高透)
  acrylic(
    'Aero 晶莹高透 (全透晶莹 · 极致高透)',
    WindowEffect.acrylic,
    Color(0x10000000),
    Color(0xFF1E2430),
    Color(0xFF60A5FA),
    false,
  );

  final String label;
  final WindowEffect effect;
  final Color tintColor;
  final Color baseColor;
  final Color accentColor;
  final bool isLight;

  const WindowThemeStyle(
    this.label,
    this.effect,
    this.tintColor,
    this.baseColor,
    this.accentColor,
    this.isLight,
  );
}

/// 窗口系统材质类型 (Windows 11 / 10 原生 DWM 驱动)
enum WindowBackdropType {
  /// Aero (经典毛玻璃，Win10 极速推荐，0 拖拽延迟)
  aero(
    'Aero 极速毛玻璃 (Win10 推荐)',
    'Windows 原生硬件级 DWM 毛玻璃模糊，晶莹透亮且拖动窗口 0 延迟、1:1 绝对贴手',
    'GPU 开销：极低 (Windows 原生 DWM 硬件级合成，无拖动延迟)',
    '极速流畅',
    Color(0xFF0EA5E9),
    WindowEffect.aero,
  ),

  /// 亚克力 (Acrylic)
  acrylic(
    'Acrylic 晶莹亚克力',
    '高斯模糊穿透壁纸与背景窗口，产生晶莹剔透毛玻璃质感 (拖动窗口时 DWM 实时重采样背景会有微小滞后)',
    'GPU 开销：轻度~中等 (Windows DWM 每帧实时模糊卷积合成；追求极致拖动跟手推荐 Aero 或 Mica)',
    '视觉惊艳',
    Color(0xFF8B5CF6),
    WindowEffect.acrylic,
  ),

  /// Mica (云母材质，Win11 专属)
  mica(
    'Mica 原生云母 (Win11 推荐)',
    'Win11 官方标准材质，智能采样桌面壁纸并柔和着色，兼顾美感与极高帧率',
    'GPU 开销：极低 (仅采样壁纸静态纹理，0 实时模糊开销)',
    '均衡流畅',
    Color(0xFF10B981),
    WindowEffect.mica,
  ),

  /// Mica Alt (深沉云母，Win11 专属)
  tabbed(
    'Mica Alt 深邃云母',
    'Win11 现代标签页专属材质，色彩深沉纯粹，层次清晰分明',
    'GPU 开销：极低 (高效静态色彩混合，无模糊合成开销)',
    '极低负载',
    Color(0xFF3B82F6),
    WindowEffect.tabbed,
  ),

  /// 无系统材质 (纯色 / 节能模式)
  none(
    'Solid 纯色节能',
    '关闭所有 Windows DWM 模糊与壁纸采样，呈现干净纯色背景',
    'GPU 开销：0% (彻底关闭 DWM 材质渲染，极端节能与老旧设备首选)',
    '极致省电',
    Color(0xFF64748B),
    WindowEffect.transparent,
  );

  /// 材质中文名称
  final String label;

  /// 视觉特征描述
  final String visualDesc;

  /// 对 GPU 与系统性能的影响详解
  final String perfDesc;

  /// 状态角标文本
  final String badgeText;

  /// 状态角标颜色
  final Color badgeColor;

  /// 对应的底层 flutter_acrylic 窗口效果
  final WindowEffect effect;

  const WindowBackdropType(
    this.label,
    this.visualDesc,
    this.perfDesc,
    this.badgeText,
    this.badgeColor,
    this.effect,
  );

  /// 判断当前操作系统环境是否支持该材质 (Mica 与 Mica Alt 需要 Windows 11 Build 22000+)
  bool isSupported(bool isWin11) {
    if (this == WindowBackdropType.mica || this == WindowBackdropType.tabbed) {
      return isWin11;
    }
    return true;
  }
}

/// 窗口关闭按钮交互行为偏好
enum WindowCloseBehavior {
  /// 最小化到系统托盘 (保持后台常驻)
  minimizeToTray('最小化到系统托盘 (常驻后台)'),

  /// 彻底退出程序
  exitApp('彻底退出程序');

  final String label;
  const WindowCloseBehavior(this.label);
}

/// Windows Fluent 专属丝滑惯性滚动阻尼模型
///
/// 核心特性：
/// 1. 【平滑惯性滑行动力学】：采用 0.010 细腻摩擦阻尼与 Ballistic 抛掷动力学模拟，滑行减速平滑自然，彻底告别死板硬停。
/// 2. 【无缝与回弹结合】：当开启弹性回弹时，超限位移平滑弹簧阻尼收敛；未开启时，平滑贴边静止。
class FluentInertialScrollPhysics extends ScrollPhysics {
  final bool enableBouncing;

  const FluentInertialScrollPhysics({
    this.enableBouncing = false,
    super.parent,
  });

  @override
  FluentInertialScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return FluentInertialScrollPhysics(
      enableBouncing: enableBouncing,
      parent: buildParent(ancestor),
    );
  }

  @override
  double get minFlingVelocity => 25.0; // 降低惯性触发门槛，轻微滑动即有丝滑惯性

  @override
  double get maxFlingVelocity => 8000.0;

  @override
  double get dragStartDistanceMotionThreshold => 3.5;

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.5,
        stiffness: 100.0,
        ratio: 1.1,
      );

  /// 阻尼衰减系数 (经典 iOS / macOS 橡皮筋公式，拉伸越远阻力指数级增强)
  double frictionFactor(double overscrollFraction) =>
      0.52 * math.pow(1 - math.min(overscrollFraction, 1.0), 2);

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    assert(offset != 0.0);
    assert(position.minScrollExtent <= position.maxScrollExtent);

    if (!enableBouncing || !position.outOfRange) {
      return offset;
    }

    // 弹性拉伸动力学 (越界时产生阻尼)
    final double overscrollPastStart = math.max(1.0, position.minScrollExtent - position.pixels);
    final double overscrollPastEnd = math.max(1.0, position.pixels - position.maxScrollExtent);
    final double overscrollPast = math.max(overscrollPastStart, overscrollPastEnd);
    final bool easing = (overscrollPastStart > 0.0 && offset > 0.0) || (overscrollPastEnd > 0.0 && offset < 0.0);

    final double friction = easing
        ? frictionFactor((overscrollPast - 1.0) / (position.viewportDimension > 0 ? position.viewportDimension : 400.0))
        : frictionFactor(overscrollPast / (position.viewportDimension > 0 ? position.viewportDimension : 400.0));
    final double direction = offset.sign;

    return direction * _applyFriction(overscrollPast, offset.abs(), friction);
  }

  static double _applyFriction(double extentOutside, double absDelta, double gamma) {
    assert(absDelta > 0);
    double total = 0.0;
    if (extentOutside > 0) {
      final double deltaToLimit = extentOutside / gamma;
      if (absDelta < deltaToLimit) {
        return absDelta * gamma;
      }
      total += extentOutside;
      absDelta -= deltaToLimit;
    }
    return total + absDelta;
  }

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (!enableBouncing) {
      // 未开启弹性时：严格贴边（不允许任何越界），低 GPU 开销
      if (value < position.pixels && position.pixels <= position.minScrollExtent) {
        return value - position.pixels;
      }
      if (position.maxScrollExtent <= position.pixels && position.pixels < value) {
        return value - position.pixels;
      }
      if (value < position.minScrollExtent && position.minScrollExtent < position.pixels) {
        return value - position.minScrollExtent;
      }
      if (position.pixels < position.maxScrollExtent && position.maxScrollExtent < value) {
        return value - position.maxScrollExtent;
      }
      return 0.0;
    }

    // 开启弹性时：放行越界进入弹簧模拟层进行柔和回弹
    return 0.0;
  }

  @override
  Simulation? createBallisticSimulation(ScrollMetrics position, double velocity) {
    final Tolerance tolerance = toleranceFor(position);

    if (position.outOfRange) {
      if (!enableBouncing) {
        return null;
      }
      double? end;
      if (position.pixels > position.maxScrollExtent) {
        end = position.maxScrollExtent;
      }
      if (position.pixels < position.minScrollExtent) {
        end = position.minScrollExtent;
      }
      if (end == null) return null;
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        end,
        velocity,
        tolerance: tolerance,
      );
    }

    if (velocity.abs() < tolerance.velocity) {
      return null;
    }

    if (velocity > 0.0 && position.pixels >= position.maxScrollExtent) {
      return null;
    }
    if (velocity < 0.0 && position.pixels <= position.minScrollExtent) {
      return null;
    }

    if (enableBouncing) {
      // 开启弹性时：动量冲向边界时产生弹性冲出与平滑收敛回弹
      return BouncingScrollSimulation(
        spring: spring,
        position: position.pixels,
        velocity: velocity,
        leadingExtent: position.minScrollExtent,
        trailingExtent: position.maxScrollExtent,
        tolerance: tolerance,
      );
    }

    // 未开启弹性时：采用 0.010 超细腻黄金摩擦阻尼，带来极具高级感的平滑贴边惯性滑行
    return ClampingScrollSimulation(
      position: position.pixels,
      velocity: velocity,
      friction: 0.010,
      tolerance: tolerance,
    );
  }
}

/// Windows 原生窗口管理器 (无缝驱动：window_manager + flutter_acrylic)
class WindowManagerWin32 extends ChangeNotifier with WindowListener {
  // 单例模式
  WindowManagerWin32._internal();
  static final WindowManagerWin32 instance = WindowManagerWin32._internal();

  /// 窗口最小尺寸定义 (保证时钟、路径标签、搜索框、分类标签与操作按钮完全展示不拥挤)
  static const double minWindowWidth = 640.0;
  static const double minWindowHeight = 260.0;

  /// 当前窗口宽高 (记忆用户偏好，默认 980 x 420 舒适大视野)
  double _windowWidth = 980.0;
  double get windowWidth => _windowWidth;

  double _windowHeight = 420.0;
  double get windowHeight => _windowHeight;

  /// 操作系统是否为 Windows 11 或更高版本
  bool _isWindows11 = false;
  bool get isWindows11 => _isWindows11;

  /// 记录当前是否已置顶
  bool _isAlwaysOnTop = false;
  bool get isAlwaysOnTop => _isAlwaysOnTop;

  /// 【亮点功能 1】：纯净壁纸模式 (系统原生桌面图标是否已隐藏)
  bool _isDesktopIconsHidden = false;
  bool get isDesktopIconsHidden => _isDesktopIconsHidden;

  /// 当前视觉主题风格 (默认磨砂纯白 · 晶莹透亮对标 easyDesktop)
  WindowThemeStyle _currentThemeStyle = WindowThemeStyle.light;
  WindowThemeStyle get currentThemeStyle => _currentThemeStyle;

  /// 是否为浅色模式
  bool get isLight => _currentThemeStyle.isLight;

  /// 主题亮度
  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  /// 主文字颜色 (100% 确保深/浅色与磨砂下极致对比度，杜绝看不清)
  Color get textColor => isLight ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);

  /// 描述/副标题文字颜色 (高对比度次要文字)
  Color get subTextColor => isLight ? const Color(0xFF475569) : const Color(0xFFCBD5E1);

  /// 卡片与容器背景色 (动态跟随面板不透明度，全界面统一通透)
  Color get cardColor {
    if (isLight) return const Color(0xFFFFFFFF).withValues(alpha: (_panelOpacity * 0.40 + 0.20).clamp(0.15, 0.70));
    if (_currentThemeStyle == WindowThemeStyle.acrylic) return const Color(0xFF000000).withValues(alpha: 0.30);
    return const Color(0xFF000000).withValues(alpha: (_panelOpacity * 0.30 + 0.15).clamp(0.15, 0.50));
  }

  /// 卡片边框颜色
  Color get cardBorderColor {
    if (isLight) return const Color(0xFF000000).withValues(alpha: (_panelOpacity * 0.10 + 0.08).clamp(0.06, 0.18));
    if (_currentThemeStyle == WindowThemeStyle.acrylic) return const Color(0xFFFFFFFF).withValues(alpha: 0.20);
    return const Color(0xFFFFFFFF).withValues(alpha: 0.16);
  }

  /// 分割线颜色
  Color get dividerColor {
    if (isLight) return const Color(0x22000000);
    if (_currentThemeStyle == WindowThemeStyle.acrylic) return const Color(0x20FFFFFF);
    return const Color(0x18FFFFFF);
  }

  /// 悬停微光颜色
  Color get hoverColor {
    if (isLight) return const Color(0x18000000);
    if (_currentThemeStyle == WindowThemeStyle.acrylic) return const Color(0x25FFFFFF);
    return const Color(0x20FFFFFF);
  }

  /// 窗口外边框颜色
  Color get windowBorderColor {
    if (isLight) return const Color(0x40000000);
    if (_currentThemeStyle == WindowThemeStyle.acrylic) return const Color(0x40FFFFFF);
    return const Color(0x35FFFFFF);
  }

  /// 面板不透明度 (0.20 ~ 1.0，默认 1.0 / 100% 完全不透明)
  double _panelOpacity = 1.0;
  double get panelOpacity => _panelOpacity;

  /// 是否在顶部状态栏显示 CPU 监控 (默认开启)
  bool _showCpuMonitor = true;
  bool get showCpuMonitor => _showCpuMonitor;

  /// 是否在顶部状态栏显示 内存 监控 (默认开启)
  bool _showMemoryMonitor = true;
  bool get showMemoryMonitor => _showMemoryMonitor;

  /// 硬件监视器总开关 (只要 CPU 或 内存 有一个开启即为 true)
  bool get showHardwareMonitor => _showCpuMonitor || _showMemoryMonitor;

  /// Windows 11 原生系统材质类型
  WindowBackdropType _currentBackdrop = WindowBackdropType.acrylic;
  WindowBackdropType get currentBackdrop => _currentBackdrop;

  /// 窗口关闭按钮交互偏好 (默认最小化到托盘)
  WindowCloseBehavior _closeBehavior = WindowCloseBehavior.minimizeToTray;
  WindowCloseBehavior get closeBehavior => _closeBehavior;

  /// 是否启用弹性回弹滚动阻尼 (iOS/macOS 弹性拉伸风格，默认关闭以保持极低 GPU 开销)
  bool _enableBouncingScroll = false;
  bool get enableBouncingScroll => _enableBouncingScroll;

  /// 是否启用软件内置底部 Dock 栏 (默认开启 true)
  bool _enableInternalBottomDock = true;
  bool get enableInternalBottomDock => _enableInternalBottomDock;

  /// 纵向滚动视图物理阻尼特性 (支持超平滑自然惯性滑行动力学，并支持弹性回弹配置)
  ScrollPhysics get scrollPhysics => FluentInertialScrollPhysics(
        enableBouncing: _enableBouncingScroll,
        parent: const AlwaysScrollableScrollPhysics(),
      );

  /// 横向滚动视图物理阻尼特性
  ScrollPhysics get horizontalScrollPhysics => FluentInertialScrollPhysics(
        enableBouncing: _enableBouncingScroll,
      );

  /// 专为独立常驻 Dock 子进程初始化的轻量方法 (0 最小窗口约束，不监听主界面尺寸缩放)
  Future<bool> initializeForStandaloneDock() async {
    try {
      _isWindows11 = _checkIsWindows11();
      await _loadPreferences();
      return true;
    } catch (e) {
      debugPrint('WindowManagerWin32 initializeForStandaloneDock error: $e');
      return false;
    }
  }

  /// 初始化窗口管理器状态与偏好 (主程序专用)
  Future<bool> initialize() async {
    try {
      // 1. 注册窗口监听器 (监听用户缩放事件并实时持久化窗口大小)
      windowManager.addListener(this);

      // 2. 检测是否是 Windows 11
      _isWindows11 = _checkIsWindows11();

      // 3. 读取用户持久化偏好 (包括窗口宽高、材质风格等)
      await _loadPreferences();

      // 4. 配置最小窗口大小与可缩放能力
      await windowManager.setMinimumSize(const Size(minWindowWidth, minWindowHeight));
      await windowManager.setResizable(true);

      // 5. 应用原生背景材质特效
      await updateNativeEffect();

      // 6. 恢复置顶状态
      if (_isAlwaysOnTop) {
        await windowManager.setAlwaysOnTop(true);
      }

      // 7. 恢复纯净壁纸模式 (桌面图标隐藏状态)
      if (_isDesktopIconsHidden) {
        setDesktopIconsHidden(true);
      }

      return true;
    } catch (e) {
      debugPrint('WindowManagerWin32 initialize error: $e');
      return false;
    }
  }

  /// 记录当前窗口是否可见 (为 false 时完全挂起所有前端高频定时器，实现托盘后台常驻 0% CPU 占用)
  bool _isDrawerVisible = true;
  bool get isDrawerVisible => _isDrawerVisible;
  bool get isWindowVisible => _isDrawerVisible;

  @override
  void onWindowMinimize() {
    if (_isDrawerVisible) {
      _isDrawerVisible = false;
      notifyListeners();
    }
  }

  @override
  void onWindowRestore() {
    if (!_isDrawerVisible) {
      _isDrawerVisible = true;
      notifyListeners();
    }
  }

  @override
  void onWindowEvent(String eventName) {
    if (eventName == 'hide') {
      if (_isDrawerVisible) {
        _isDrawerVisible = false;
        notifyListeners();
      }
    } else if (eventName == 'show' || eventName == 'restore') {
      if (!_isDrawerVisible) {
        _isDrawerVisible = true;
        notifyListeners();
      }
    }
  }

  @override
  void onWindowResized() async {
    try {
      final size = await windowManager.getSize();
      if (size.width >= minWindowWidth && size.height >= minWindowHeight) {
        _windowWidth = size.width;
        _windowHeight = size.height;
        await _savePreference('pref_window_width', size.width);
        await _savePreference('pref_window_height', size.height);
      }
    } catch (e) {
      debugPrint('onWindowResized error: $e');
    }
  }

  /// 检测是否是 Windows 11 (Build >= 22000)
  bool _checkIsWindows11() {
    try {
      final versionStr = Platform.operatingSystemVersion;
      final match = RegExp(r'Build (\d+)').firstMatch(versionStr);
      if (match != null) {
        final build = int.tryParse(match.group(1) ?? '0') ?? 0;
        return build >= 22000;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 加载本地持久化配置
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isAlwaysOnTop = prefs.getBool('pref_always_on_top') ?? false;
      _isDesktopIconsHidden = prefs.getBool('pref_desktop_icons_hidden') ?? false;

      final styleIdx = prefs.getInt('pref_theme_style') ?? 0;
      if (styleIdx >= 0 && styleIdx < WindowThemeStyle.values.length) {
        _currentThemeStyle = WindowThemeStyle.values[styleIdx];
      }

      _panelOpacity = prefs.getDouble('pref_panel_opacity') ?? 1.0;

      final backdropIdx = prefs.getInt('pref_backdrop_type');
      if (backdropIdx != null && backdropIdx >= 0 && backdropIdx < WindowBackdropType.values.length) {
        _currentBackdrop = WindowBackdropType.values[backdropIdx];
      } else {
        _currentBackdrop = _isWindows11 ? WindowBackdropType.mica : WindowBackdropType.aero;
      }

      final closeBehaviorIdx = prefs.getInt('pref_close_behavior') ?? 0;
      if (closeBehaviorIdx >= 0 && closeBehaviorIdx < WindowCloseBehavior.values.length) {
        _closeBehavior = WindowCloseBehavior.values[closeBehaviorIdx];
      }

      _showCpuMonitor = prefs.getBool('pref_show_cpu_monitor') ?? true;
      _showMemoryMonitor = prefs.getBool('pref_show_memory_monitor') ?? true;
      _enableBouncingScroll = prefs.getBool('pref_enable_bouncing_scroll') ?? false;
      _enableInternalBottomDock = prefs.getBool('pref_enable_internal_bottom_dock') ?? true;

      // 读取记忆的窗口尺寸 (限定在 minWindowWidth / minWindowHeight 以上)
      final savedW = prefs.getDouble('pref_window_width') ?? 980.0;
      final savedH = prefs.getDouble('pref_window_height') ?? 420.0;
      _windowWidth = savedW.clamp(minWindowWidth, 3840.0);
      _windowHeight = savedH.clamp(minWindowHeight, 2160.0);
    } catch (_) {}
  }

  // ==========================================
  // 【亮点功能 1】：纯净壁纸模式 (Win32 原生控制)
  // ==========================================

  /// 获取 Windows 桌面图标 ListView 句柄 (兼容 Win10 / Win11 与动态壁纸 WorkerW 场景)
  int _getDesktopListViewHandle() {
    return using((Arena arena) {
      try {
        int defView = 0;

        // 1. 优先尝试从 Progman 寻找 SHELLDLL_DefView
        final progmanName = 'Progman'.toNativeUtf16(allocator: arena);
        final defViewName = 'SHELLDLL_DefView'.toNativeUtf16(allocator: arena);
        final listViewName = 'SysListView32'.toNativeUtf16(allocator: arena);

        final progman = _findWindow(progmanName, nullptr);
        if (progman != 0) {
          defView = _findWindowEx(progman, 0, defViewName, nullptr);
        }

        // 2. 若在 Progman 下未找到 (如用户开启了 Wallpaper Engine 等动态壁纸)，枚举顶级 WorkerW 窗口
        if (defView == 0) {
          _foundDefViewHwnd = 0;
          final enumCallbackPtr = Pointer.fromFunction<_EnumWindowsProc>(_enumWindowsCallback, 0);
          _enumWindows(enumCallbackPtr, 0);
          defView = _foundDefViewHwnd;
        }

        int listView = 0;
        if (defView != 0) {
          listView = _findWindowEx(defView, 0, listViewName, nullptr);
        }

        return listView;
      } catch (e) {
        debugPrint('获取桌面 ListView 句柄失败: $e');
        return 0;
      }
    });
  }

  /// 切换纯净壁纸模式 (一键隐藏 / 显示 Windows 原生桌面图标)
  bool toggleDesktopIconsVisibility() {
    final hListView = _getDesktopListViewHandle();
    if (hListView != 0) {
      final isCurrentlyVisible = _isWindowVisible(hListView) != 0;
      final willHide = isCurrentlyVisible; // 若当前可见，则切换为隐藏
      _showWindow(hListView, willHide ? _swHide : _swShow);
      _isDesktopIconsHidden = willHide;
      _savePreference('pref_desktop_icons_hidden', willHide);
      notifyListeners();
      return willHide;
    }
    return _isDesktopIconsHidden;
  }

  /// 设置纯净壁纸模式 (显式指定是否隐藏桌面图标)
  void setDesktopIconsHidden(bool hide) {
    final hListView = _getDesktopListViewHandle();
    if (hListView != 0) {
      _showWindow(hListView, hide ? _swHide : _swShow);
      _isDesktopIconsHidden = hide;
      _savePreference('pref_desktop_icons_hidden', hide);
      notifyListeners();
    }
  }

  /// 保存本地配置
  Future<void> _savePreference(String key, dynamic value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      }
    } catch (_) {}
  }

  /// 实时向原生系统注入毛玻璃与亚克力模糊 (Windows 10 / 11)
  Future<void> updateNativeEffect() async {
    try {
      await Window.setEffect(
        effect: _currentBackdrop.effect,
        color: _currentThemeStyle.tintColor,
        dark: !_currentThemeStyle.isLight,
      );
    } catch (e) {
      debugPrint('Window.setEffect error: $e');
    }
  }

  /// 设置当前视觉主题风格 (立即生效并触发界面重绘)
  void setThemeStyle(WindowThemeStyle style) {
    _currentThemeStyle = style;
    notifyListeners();
    _savePreference('pref_theme_style', style.index);
    updateNativeEffect();
  }

  /// 快速设置面板不透明度 (仅更新 Flutter 界面渲染，0 延迟无频闪，拖拽滑动时使用)
  void setPanelOpacityFast(double opacity) {
    _panelOpacity = opacity.clamp(0.20, 1.0);
    notifyListeners();
  }

  /// 持久化保存面板不透明度 (仅存配置并通知 Flutter 重绘，不破坏 DWM 帧合成，彻底消除鼠标松开时的黑白闪烁)
  void savePanelOpacity(double opacity) {
    _panelOpacity = opacity.clamp(0.20, 1.0);
    notifyListeners();
    _savePreference('pref_panel_opacity', _panelOpacity);
  }

  /// 设置面板不透明度 (兼容旧调用)
  void setPanelOpacity(double opacity) {
    savePanelOpacity(opacity);
  }

  /// 设置关闭按钮行为偏好
  void setCloseBehavior(WindowCloseBehavior behavior) {
    _closeBehavior = behavior;
    notifyListeners();
    _savePreference('pref_close_behavior', behavior.index);
  }

  /// 设置 Windows 系统背景材质
  void setBackdropType(WindowBackdropType type) {
    _currentBackdrop = type;
    notifyListeners();
    _savePreference('pref_backdrop_type', type.index);

    updateNativeEffect();
  }

  /// 设置窗口置顶状态
  Future<void> setAlwaysOnTop(bool isTop) async {
    _isAlwaysOnTop = isTop;
    notifyListeners();
    _savePreference('pref_always_on_top', isTop);
    try {
      await windowManager.setAlwaysOnTop(isTop);
    } catch (e) {
      debugPrint('setAlwaysOnTop error: $e');
    }
  }

  /// 切换窗口置顶状态
  Future<void> toggleAlwaysOnTop() async {
    await setAlwaysOnTop(!_isAlwaysOnTop);
  }

  /// 设置顶部状态栏 CPU 监控显隐
  Future<void> setShowCpuMonitor(bool show) async {
    _showCpuMonitor = show;
    notifyListeners();
    await _savePreference('pref_show_cpu_monitor', show);
  }

  /// 设置顶部状态栏 内存 监控显隐
  Future<void> setShowMemoryMonitor(bool show) async {
    _showMemoryMonitor = show;
    notifyListeners();
    await _savePreference('pref_show_memory_monitor', show);
  }

  /// 设置是否启用弹性回弹滚动阻尼 (iOS/macOS 风格)
  Future<void> setEnableBouncingScroll(bool enable) async {
    _enableBouncingScroll = enable;
    notifyListeners();
    await _savePreference('pref_enable_bouncing_scroll', enable);
  }

  /// 设置是否启用软件内置底部 Dock 栏
  Future<void> setEnableInternalBottomDock(bool enable) async {
    _enableInternalBottomDock = enable;
    notifyListeners();
    await _savePreference('pref_enable_internal_bottom_dock', enable);
  }

  /// 启动原生窗口拖动 (保持亚克力/磨砂质感常驻，零延迟、无频闪、无黑白切换)
  Future<void> startDrag() async {
    try {
      await windowManager.startDragging();
    } catch (e) {
      debugPrint('startDrag error: $e');
    }
  }

  /// 最小化窗口
  Future<void> minimize() async {
    try {
      if (_isDrawerVisible) {
        _isDrawerVisible = false;
        notifyListeners();
      }
      await windowManager.minimize();
    } catch (e) {
      debugPrint('minimize error: $e');
    }
  }

  /// 响应顶栏关闭按钮 (根据偏好最小化到托盘或彻底退出)
  void handleCloseButton() {
    if (_closeBehavior == WindowCloseBehavior.minimizeToTray) {
      hide();
    } else {
      closeApp();
    }
  }

  /// 隐藏窗口至后台 (挂起所有前端高频定时器)
  Future<void> hide() async {
    try {
      if (_isDrawerVisible) {
        _isDrawerVisible = false;
        notifyListeners();
      }
      await windowManager.hide();
    } catch (e) {
      debugPrint('hide error: $e');
    }
  }

  /// 切换窗口显隐状态 (供快捷键与托盘快速唤起)
  Future<void> toggleVisibility() async {
    try {
      final isVisible = await windowManager.isVisible();
      final isFocused = await windowManager.isFocused();
      if (isVisible && isFocused) {
        await hide();
      } else {
        await show();
      }
    } catch (e) {
      debugPrint('toggleVisibility error: $e');
    }
  }

  /// 退出前回调钩子 (用于主窗口关闭时同步退出子挂件进程)
  VoidCallback? onBeforeExit;

  /// 彻底安全退出程序 (销毁窗口并退出进程，保证无后台残留)
  void closeApp() {
    try {
      onBeforeExit?.call();
    } catch (_) {}
    try {
      windowManager.destroy();
    } catch (_) {}
    exit(0);
  }

  /// 显示窗口并激活聚焦
  Future<void> show() async {
    try {
      if (!_isDrawerVisible) {
        _isDrawerVisible = true;
        notifyListeners();
      }
      await windowManager.show();
      await windowManager.focus();
    } catch (e) {
      debugPrint('show error: $e');
    }
  }

  /// 设置窗口大小与位置
  void setWindowBounds({
    required int width,
    required int height,
    bool center = false,
  }) {
    windowManager.setSize(Size(width.toDouble(), height.toDouble())).then((_) {
      if (center) {
        windowManager.center();
      }
    }).catchError((_) {});
  }
}
