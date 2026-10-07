import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../window/window_manager_win32.dart';

/// 热键预设选项模型
class AppHotKeyOption {
  final String label;
  final String keyDisplay;
  final HotKey hotKey;

  const AppHotKeyOption({
    required this.label,
    required this.keyDisplay,
    required this.hotKey,
  });
}

/// 全局热键召唤服务 (支持多预设切换与任意前台应用下一键呼出/收起抽屉)
class DesktopHotkeyService {
  DesktopHotkeyService._internal();
  static final DesktopHotkeyService instance = DesktopHotkeyService._internal();

  static const String _prefEnabledKey = 'pref_hotkey_enabled';
  static const String _prefIndexKey = 'pref_hotkey_index';
  static const String _prefIsCustomKey = 'pref_is_custom_hotkey';
  static const String _prefCustomKeyIdKey = 'pref_custom_key_id';
  static const String _prefCustomModifiersKey = 'pref_custom_modifiers';
  static const String _prefCustomDisplayKey = 'pref_custom_display';

  /// 丰富且常用、防冲突的全局召唤快捷键预设列表
  static final List<AppHotKeyOption> presetOptions = [
    AppHotKeyOption(
      label: 'Alt + Space (推荐)',
      keyDisplay: 'Alt + Space',
      hotKey: HotKey(
        key: LogicalKeyboardKey.space,
        modifiers: [HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'Ctrl + Space',
      keyDisplay: 'Ctrl + Space',
      hotKey: HotKey(
        key: LogicalKeyboardKey.space,
        modifiers: [HotKeyModifier.control],
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'Alt + D',
      keyDisplay: 'Alt + D',
      hotKey: HotKey(
        key: LogicalKeyboardKey.keyD,
        modifiers: [HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'Alt + Q',
      keyDisplay: 'Alt + Q',
      hotKey: HotKey(
        key: LogicalKeyboardKey.keyQ,
        modifiers: [HotKeyModifier.alt],
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'Ctrl + Shift + D',
      keyDisplay: 'Ctrl + Shift + D',
      hotKey: HotKey(
        key: LogicalKeyboardKey.keyD,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'F12',
      keyDisplay: 'F12',
      hotKey: HotKey(
        key: LogicalKeyboardKey.f12,
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'F9',
      keyDisplay: 'F9',
      hotKey: HotKey(
        key: LogicalKeyboardKey.f9,
        scope: HotKeyScope.system,
      ),
    ),
    AppHotKeyOption(
      label: 'F4',
      keyDisplay: 'F4',
      hotKey: HotKey(
        key: LogicalKeyboardKey.f4,
        scope: HotKeyScope.system,
      ),
    ),
  ];

  bool _isEnabled = true;
  bool get isEnabled => _isEnabled;

  int _selectedOptionIndex = 0;
  int get selectedOptionIndex => _selectedOptionIndex;

  bool _isCustom = false;
  bool get isCustom => _isCustom;

  HotKey? _customHotKey;
  HotKey? get customHotKey => _customHotKey;

  String _customKeyDisplay = '';
  String get customKeyDisplay => _customKeyDisplay;

  bool _isCooldown = false;
  bool _isRecordingMode = false;

  /// 设置当前是否正在录制按键中 (录制期间彻底暂停全局热键响应，杜绝误触发窗口收起)
  void setRecordingMode(bool recording) {
    _isRecordingMode = recording;
  }

  AppHotKeyOption get currentOption =>
      presetOptions[_selectedOptionIndex.clamp(0, presetOptions.length - 1)];

  HotKey get currentHotKey =>
      (_isCustom && _customHotKey != null) ? _customHotKey! : currentOption.hotKey;

  String get currentKeyDisplay =>
      (_isCustom && _customHotKey != null) ? _customKeyDisplay : currentOption.keyDisplay;

  /// 初始化热键服务并读取配置
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isEnabled = prefs.getBool(_prefEnabledKey) ?? true;
      _selectedOptionIndex = (prefs.getInt(_prefIndexKey) ?? 0).clamp(0, presetOptions.length - 1);
      _isCustom = prefs.getBool(_prefIsCustomKey) ?? false;

      if (_isCustom) {
        final keyId = prefs.getInt(_prefCustomKeyIdKey);
        final modifiers = prefs.getStringList(_prefCustomModifiersKey) ?? [];
        final display = prefs.getString(_prefCustomDisplayKey) ?? '';
        if (keyId != null) {
          final loadedKey = deserializeHotKey(keyId, modifiers);
          final validation = validateHotKey(loadedKey);
          if (validation.isValid) {
            _customHotKey = loadedKey;
            _customKeyDisplay = display.isNotEmpty ? display : formatHotKey(_customHotKey!);
          } else {
            // 自定义键已不合法，安全回退到默认
            _isCustom = false;
          }
        } else {
          _isCustom = false;
        }
      }

      // 确保清空历史注册
      await hotKeyManager.unregisterAll();

      if (_isEnabled) {
        await _register();
      }
    } catch (e) {
      debugPrint('DesktopHotkeyService initialize error: $e');
    }
  }

  /// 注册当前全局热键 (带有录制隔离与冷却防抖保护)
  Future<bool> _register() async {
    try {
      await hotKeyManager.register(
        currentHotKey,
        keyDownHandler: (hotKey) {
          if (_isCooldown || _isRecordingMode) return;
          WindowManagerWin32.instance.toggleVisibility();
        },
      );
      return true;
    } catch (e) {
      debugPrint('DesktopHotkeyService register error: $e');
      return false;
    }
  }

  /// 验证热键合法性 (禁止单独单字母/空格等导致系统打字瘫痪的危险按键)
  static ({bool isValid, String? errorMessage}) validateHotKey(HotKey hotKey) {
    final logicalKey = hotKey.key is LogicalKeyboardKey
        ? (hotKey.key as LogicalKeyboardKey)
        : LogicalKeyboardKey.space;

    // F1 ~ F12 允许单功能键或带修饰键
    final isFKey = (logicalKey.keyId >= LogicalKeyboardKey.f1.keyId &&
        logicalKey.keyId <= LogicalKeyboardKey.f12.keyId);

    final hasModifiers = hotKey.modifiers != null && hotKey.modifiers!.isNotEmpty;

    if (!isFKey && !hasModifiers) {
      return (
        isValid: false,
        errorMessage: '普通字符键必须配合 Ctrl / Alt / Shift 组合使用，以防与系统打字输入冲突。',
      );
    }

    if (logicalKey == LogicalKeyboardKey.escape ||
        logicalKey == LogicalKeyboardKey.backspace ||
        logicalKey == LogicalKeyboardKey.delete) {
      return (
        isValid: false,
        errorMessage: '不允许将 Esc / 退格 / 删除键单独绑定为全局热键。',
      );
    }

    return (isValid: true, errorMessage: null);
  }

  /// 切换为预设热键方案
  Future<void> setHotKeyIndex(int index) async {
    if (index < 0 || index >= presetOptions.length) return;
    try {
      _isCooldown = true;
      // 1. 注销当前热键
      await hotKeyManager.unregister(currentHotKey);

      // 2. 更新配置
      _isCustom = false;
      _selectedOptionIndex = index;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefIndexKey, index);
      await prefs.setBool(_prefIsCustomKey, false);

      // 3. 重新注册
      if (_isEnabled) {
        await _register();
      }

      // 600ms 后解除冷却，防止按键余波触发
      Future.delayed(const Duration(milliseconds: 600), () {
        _isCooldown = false;
      });
    } catch (e) {
      debugPrint('DesktopHotkeyService setHotKeyIndex error: $e');
    }
  }

  /// 恢复为出厂默认快捷键 (Alt + Space)
  Future<void> resetToDefault() async {
    await setHotKeyIndex(0);
  }

  /// 设置并绑定用户自定义录制的热键 (具备冲突捕获与自动回滚)
  Future<({bool success, String message})> setCustomHotKey(HotKey hotKey) async {
    final validation = validateHotKey(hotKey);
    if (!validation.isValid) {
      return (success: false, message: validation.errorMessage ?? '无效快捷键');
    }

    // 开启防抖冷却，防止刚按下就立即触发关闭
    _isCooldown = true;
    final previousHotKey = currentHotKey;

    try {
      // 1. 注销旧热键
      await hotKeyManager.unregister(previousHotKey);

      // 2. 尝试注册新热键
      await hotKeyManager.register(
        hotKey,
        keyDownHandler: (key) {
          if (_isCooldown || _isRecordingMode) return;
          WindowManagerWin32.instance.toggleVisibility();
        },
      );

      // 3. 保存新配置
      _isCustom = true;
      _customHotKey = hotKey;
      _customKeyDisplay = formatHotKey(hotKey);

      final logicalKey = hotKey.key is LogicalKeyboardKey
          ? (hotKey.key as LogicalKeyboardKey)
          : LogicalKeyboardKey.space;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefIsCustomKey, true);
      await prefs.setInt(_prefCustomKeyIdKey, logicalKey.keyId);
      await prefs.setStringList(
        _prefCustomModifiersKey,
        hotKey.modifiers?.map((m) => m.name).toList() ?? [],
      );
      await prefs.setString(_prefCustomDisplayKey, _customKeyDisplay);

      Future.delayed(const Duration(milliseconds: 600), () {
        _isCooldown = false;
      });

      return (success: true, message: '快捷键已成功绑定为 $_customKeyDisplay');
    } catch (e) {
      debugPrint('setCustomHotKey failed: $e');
      // 注册失败（如被系统或其他软件占用），自动回滚
      await hotKeyManager.unregisterAll();
      if (_isEnabled) {
        await hotKeyManager.register(
          previousHotKey,
          keyDownHandler: (key) {
            if (_isCooldown || _isRecordingMode) return;
            WindowManagerWin32.instance.toggleVisibility();
          },
        );
      }
      Future.delayed(const Duration(milliseconds: 600), () {
        _isCooldown = false;
      });
      return (
        success: false,
        message: '快捷键 [${formatHotKey(hotKey)}] 已被系统或其他软件占用，请尝试其它组合。',
      );
    }
  }

  /// 启用或禁用全局热键
  Future<void> setEnabled(bool enable) async {
    _isEnabled = enable;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefEnabledKey, enable);

      if (enable) {
        await _register();
      } else {
        await hotKeyManager.unregister(currentHotKey);
      }
    } catch (e) {
      debugPrint('DesktopHotkeyService setEnabled error: $e');
    }
  }


  /// 反序列化热键模型
  static HotKey deserializeHotKey(int keyId, List<String> modifierNames) {
    final logicalKey = LogicalKeyboardKey.findKeyByKeyId(keyId) ?? LogicalKeyboardKey.space;
    final modifiers = <HotKeyModifier>[];
    for (final name in modifierNames) {
      for (final mod in HotKeyModifier.values) {
        if (mod.name == name) {
          modifiers.add(mod);
          break;
        }
      }
    }
    return HotKey(
      key: logicalKey,
      modifiers: modifiers.isEmpty ? null : modifiers,
      scope: HotKeyScope.system,
    );
  }

  /// 格式化热键为人类可读的按键字符串 (如 "Ctrl + Alt + K")
  static String formatHotKey(HotKey hotKey) {
    final parts = <String>[];
    if (hotKey.modifiers != null) {
      if (hotKey.modifiers!.contains(HotKeyModifier.control)) parts.add('Ctrl');
      if (hotKey.modifiers!.contains(HotKeyModifier.alt)) parts.add('Alt');
      if (hotKey.modifiers!.contains(HotKeyModifier.shift)) parts.add('Shift');
      if (hotKey.modifiers!.contains(HotKeyModifier.meta)) parts.add('Win');
    }
    final key = hotKey.key;
    if (key == LogicalKeyboardKey.space) {
      parts.add('Space');
    } else if (key == LogicalKeyboardKey.enter) {
      parts.add('Enter');
    } else if (key == LogicalKeyboardKey.tab) {
      parts.add('Tab');
    } else if (key == LogicalKeyboardKey.escape) {
      parts.add('Esc');
    } else if (key == LogicalKeyboardKey.backspace) {
      parts.add('Backspace');
    } else if (key is LogicalKeyboardKey) {
      final label = key.keyLabel.isNotEmpty ? key.keyLabel.toUpperCase() : (key.debugName ?? 'Key');
      parts.add(label);
    } else {
      parts.add('Key');
    }
    return parts.join(' + ');
  }
}

