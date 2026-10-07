import 'dart:convert';
import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import '../../../core/logging/app_logger.dart';
import '../../desktop/models/desktop_item.dart';
import '../models/custom_category.dart';

/// 全局桌面分类与规则配置管理引擎 (ChangeNotifier 单例)
///
/// 核心职责：
/// 1. 【本地持久化】：将用户自定义分类规则以结构化 JSON 保存至 `%APPDATA%\tidy_desk\categories.json`；
/// 2. 【自愈与默认装载】：首次启动自动预设 6 大核心分类（全部、常用、文档、媒体、快捷、文件夹）；
/// 3. 【CRUD 与自定义管理】：支持用户在设置中自由新建分类、修改后缀规则、自定义 Fluent 图标、拖拽/上下调序、显示/隐藏；
/// 4. 【高吞吐匹配引擎】：提供 O(1) 扩展名哈希匹配，根据用户规则毫秒级自动将桌面文件分类归档；
/// 5. 【数据备份与导入】：支持完整规则配置的 JSON 导入与导出。
class CategoryManager extends ChangeNotifier {
  // 单例模式
  CategoryManager._internal();
  static final CategoryManager instance = CategoryManager._internal();

  /// 内存中维护的全部分类列表 (按 sortOrder 升序排列)
  final List<CustomCategory> _categories = [];
  List<CustomCategory> get allCategories => List.unmodifiable(_categories);
  List<CustomCategory> get categories => allCategories;

  /// 当前启用并展示在主界面导航栏中的分类列表
  List<CustomCategory> get enabledCategories =>
      List.unmodifiable(_categories.where((c) => c.isEnabled));

  /// 本地持久化文件存储路径
  String _configFilePath = '';
  String get configFilePath => _configFilePath;

  /// 是否已完成初始化装载
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// 初始化分类管理引擎 (在应用启动 main 时调用)
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      final configDir = Directory('$appData\\tidy_desk');
      if (!configDir.existsSync()) {
        configDir.createSync(recursive: true);
      }

      final configFile = File('${configDir.path}\\categories.json');
      _configFilePath = configFile.path;

      if (configFile.existsSync()) {
        final content = await configFile.readAsString();
        if (content.trim().isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          _categories.clear();
          for (final item in jsonList) {
            if (item is Map<String, dynamic>) {
              _categories.add(CustomCategory.fromJson(item));
            }
          }
          _sortCategories();
          AppLogger.i('成功从本地装载 ${_categories.length} 个自定义分类规则');
        }
      }

      // 如果本地没有配置文件或解析为空，装载系统默认分类配置
      if (_categories.isEmpty) {
        _loadDefaultCategories();
        await _saveToFile();
        AppLogger.i('已初始化并持久化系统默认 6 大分类规则');
      }

      _isInitialized = true;
    } catch (e, stack) {
      AppLogger.e('初始化 CategoryManager 失败，回退到默认分类: $e', e, stack);
      _loadDefaultCategories();
      _isInitialized = true;
    }
  }

  /// 装载默认的 6 大系统内置分类
  void _loadDefaultCategories() {
    _categories.clear();
    _categories.addAll([
      const CustomCategory(
        id: 'all',
        name: '全部',
        iconCodePoint: 0xE71D, // FluentIcons.all_apps
        matchExtensions: [],
        matchType: CategoryMatchType.all,
        isSystem: true,
        isEnabled: true,
        sortOrder: 0,
      ),
      const CustomCategory(
        id: 'frequent',
        name: '常用',
        iconCodePoint: 0xE734, // FluentIcons.favorite_star
        matchExtensions: [],
        matchType: CategoryMatchType.frequent,
        isSystem: true,
        isEnabled: true,
        sortOrder: 1,
      ),
      const CustomCategory(
        id: 'document',
        name: '文档',
        iconCodePoint: 0xE8A5, // FluentIcons.document
        matchExtensions: [
          '.txt', '.doc', '.docx', '.pdf', '.xls', '.xlsx',
          '.ppt', '.pptx', '.csv', '.md', '.rtf', '.wps',
          '.html', '.json', '.xml', '.yaml', '.yml', '.log',
          '.zip', '.rar', '.7z', '.tar', '.gz'
        ],
        matchType: CategoryMatchType.extension,
        isSystem: true,
        isEnabled: true,
        sortOrder: 2,
      ),
      const CustomCategory(
        id: 'media',
        name: '媒体',
        iconCodePoint: 0xEA69, // FluentIcons.photo_video_media
        matchExtensions: [
          '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico',
          '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.rmvb',
          '.mp3', '.flac', '.wav', '.aac', '.ogg', '.m4a'
        ],
        matchType: CategoryMatchType.extension,
        isSystem: true,
        isEnabled: true,
        sortOrder: 3,
      ),
      const CustomCategory(
        id: 'shortcut',
        name: '快捷',
        iconCodePoint: 0xE71B, // FluentIcons.link
        matchExtensions: [
          '.lnk', '.url', '.exe', '.bat', '.cmd', '.msi', '.ps1'
        ],
        matchType: CategoryMatchType.extension,
        isSystem: true,
        isEnabled: true,
        sortOrder: 4,
      ),
      const CustomCategory(
        id: 'folder',
        name: '文件夹',
        iconCodePoint: 0xE8B7, // FluentIcons.folder
        matchExtensions: [],
        matchType: CategoryMatchType.folder,
        isSystem: true,
        isEnabled: true,
        sortOrder: 5,
      ),
    ]);
    _sortCategories();
  }

  /// 内部辅助：按 sortOrder 升序排列
  void _sortCategories() {
    _categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// 将当前配置异步写入本地 JSON 文件
  Future<void> _saveToFile() async {
    try {
      if (_configFilePath.isEmpty) return;
      final file = File(_configFilePath);
      final jsonStr = const JsonEncoder.withIndent('  ').convert(
        _categories.map((c) => c.toJson()).toList(),
      );
      await file.writeAsString(jsonStr);
    } catch (e, stack) {
      AppLogger.e('保存分类规则文件失败: $e', e, stack);
    }
  }

  // ---------------------------------------------------------------------------
  // 分类与规则匹配核心算法
  // ---------------------------------------------------------------------------

  /// 判断一个桌面项目是否匹配指定分类
  /// [item]: 桌面文件或文件夹
  /// [categoryId]: 分类 ID
  /// [usageCounts]: 各项目应用内打开次数 (用于 'frequent' 分类判定)
  bool matchesItem(
    DesktopItem item,
    String categoryId, {
    Map<String, int>? usageCounts,
  }) {
    final cat = getCategoryById(categoryId);
    if (cat == null) return false;

    // 1. 全部项目：匹配所有项
    if (cat.matchType == CategoryMatchType.all || cat.id == 'all') {
      return true;
    }

    // 2. 常用项目：必须存在打开使用记录
    if (cat.matchType == CategoryMatchType.frequent || cat.id == 'frequent') {
      final count = usageCounts?[item.path] ?? 0;
      return count > 0;
    }

    // 3. 手动自选分类：判断文件唯一路径/标识是否在已选集合中
    if (cat.matchType == CategoryMatchType.manual) {
      return cat.manualItemKeys.contains(item.path);
    }

    // 4. 文件夹分类：专门匹配目录
    if (cat.matchType == CategoryMatchType.folder || cat.id == 'folder') {
      return item.isDirectory;
    }

    // 5. 普通文件规则：如果是文件夹则不属于普通文件分类
    if (item.isDirectory) {
      return false;
    }

    // 6. 扩展名匹配
    final ext = item.extension.toLowerCase();
    if (ext.isEmpty) return false;

    return cat.matchExtensions.contains(ext);
  }

  /// 根据分类 ID 查找分类对象
  CustomCategory? getCategoryById(String id) {
    try {
      return _categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// 获取所有启用的手动自选分类列表
  List<CustomCategory> get manualCategories =>
      _categories.where((c) => c.isEnabled && c.matchType == CategoryMatchType.manual).toList();

  /// 检查某文件是否包含在指定的手动分类中
  bool isItemInManualCategory(String categoryId, String itemPath) {
    final cat = getCategoryById(categoryId);
    if (cat == null || cat.matchType != CategoryMatchType.manual) return false;
    return cat.manualItemKeys.contains(itemPath);
  }

  /// 切换项目在指定手动分类中的归属状态 (存在则移除，不存在则加入)
  Future<bool> toggleItemInManualCategory(String categoryId, String itemPath) async {
    final cat = getCategoryById(categoryId);
    if (cat == null || cat.matchType != CategoryMatchType.manual) return false;

    final updatedKeys = List<String>.from(cat.manualItemKeys);
    if (updatedKeys.contains(itemPath)) {
      updatedKeys.remove(itemPath);
    } else {
      updatedKeys.add(itemPath);
    }

    return await updateCategory(cat.copyWith(manualItemKeys: updatedKeys));
  }

  /// 将项目加入到指定手动分类
  Future<bool> addItemToManualCategory(String categoryId, String itemPath) async {
    final cat = getCategoryById(categoryId);
    if (cat == null || cat.matchType != CategoryMatchType.manual) return false;

    if (cat.manualItemKeys.contains(itemPath)) return true; // 已存在

    final updatedKeys = List<String>.from(cat.manualItemKeys)..add(itemPath);
    return await updateCategory(cat.copyWith(manualItemKeys: updatedKeys));
  }

  /// 将项目从指定手动分类中移除
  Future<bool> removeItemFromManualCategory(String categoryId, String itemPath) async {
    final cat = getCategoryById(categoryId);
    if (cat == null || cat.matchType != CategoryMatchType.manual) return false;

    if (!cat.manualItemKeys.contains(itemPath)) return true;

    final updatedKeys = List<String>.from(cat.manualItemKeys)..remove(itemPath);
    return await updateCategory(cat.copyWith(manualItemKeys: updatedKeys));
  }

  /// 当文件发生重命名时，批量更新所有手动分类中绑定的路径引用
  Future<void> handleItemRenamed(String oldPath, String newPath) async {
    bool hasChanged = false;
    for (int i = 0; i < _categories.length; i++) {
      final cat = _categories[i];
      if (cat.matchType == CategoryMatchType.manual && cat.manualItemKeys.contains(oldPath)) {
        final updatedKeys = cat.manualItemKeys.map((k) => k == oldPath ? newPath : k).toList();
        _categories[i] = cat.copyWith(manualItemKeys: updatedKeys);
        hasChanged = true;
      }
    }
    if (hasChanged) {
      notifyListeners();
      await _saveToFile();
    }
  }

  /// 当文件被永久删除时，自动清洗所有手动分类中失效的路径引用
  Future<void> handleItemDeleted(String path) async {
    bool hasChanged = false;
    for (int i = 0; i < _categories.length; i++) {
      final cat = _categories[i];
      if (cat.matchType == CategoryMatchType.manual && cat.manualItemKeys.contains(path)) {
        final updatedKeys = List<String>.from(cat.manualItemKeys)..remove(path);
        _categories[i] = cat.copyWith(manualItemKeys: updatedKeys);
        hasChanged = true;
      }
    }
    if (hasChanged) {
      notifyListeners();
      await _saveToFile();
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD 业务操作接口
  // ---------------------------------------------------------------------------

  /// 添加新的自定义分类
  Future<bool> addCategory(CustomCategory category) async {
    // 检查 ID 重复
    if (_categories.any((c) => c.id == category.id)) {
      return false;
    }

    final newSortOrder = _categories.isNotEmpty
        ? _categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1
        : 0;

    final newCat = category.copyWith(sortOrder: newSortOrder);
    _categories.add(newCat);
    _sortCategories();
    notifyListeners();
    await _saveToFile();
    AppLogger.i('新增自定义分类成功: [${newCat.name}] (规则数: ${newCat.matchExtensions.length})');
    return true;
  }

  /// 更新现有分类 (支持修改名称、图标、规则后缀)
  Future<bool> updateCategory(CustomCategory category) async {
    final index = _categories.indexWhere((c) => c.id == category.id);
    if (index == -1) return false;

    _categories[index] = category;
    _sortCategories();
    notifyListeners();
    await _saveToFile();
    AppLogger.i('更新分类规则成功: [${category.name}]');
    return true;
  }

  /// 删除指定分类 (仅允许删除非系统内置分类)
  Future<bool> deleteCategory(String id) async {
    final cat = getCategoryById(id);
    if (cat == null || cat.isSystem) {
      return false; // 系统分类禁止物理删除
    }

    _categories.removeWhere((c) => c.id == id);
    _sortCategories();
    notifyListeners();
    await _saveToFile();
    AppLogger.i('删除分类成功: [${cat.name}]');
    return true;
  }

  /// 切换分类的启用/隐藏状态
  Future<void> toggleCategoryEnabled(String id, bool enabled) async {
    final index = _categories.indexWhere((c) => c.id == id);
    if (index == -1) return;

    _categories[index] = _categories[index].copyWith(isEnabled: enabled);
    notifyListeners();
    await _saveToFile();
  }

  /// 调整分类上下排序
  Future<void> moveCategory(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _categories.length) return;
    if (newIndex < 0 || newIndex >= _categories.length) return;

    final item = _categories.removeAt(oldIndex);
    _categories.insert(newIndex, item);

    // 重新校准所有分类的 sortOrder 索引
    for (int i = 0; i < _categories.length; i++) {
      _categories[i] = _categories[i].copyWith(sortOrder: i);
    }

    notifyListeners();
    await _saveToFile();
  }

  /// 恢复出厂默认分类配置
  Future<void> resetToDefaults() async {
    _loadDefaultCategories();
    notifyListeners();
    await _saveToFile();
    AppLogger.i('已恢复出厂默认分类配置');
  }

  /// 导出完整规则配置为 JSON 字符串 (供用户备份或分享)
  String exportConfigJson() {
    return const JsonEncoder.withIndent('  ').convert(
      _categories.map((c) => c.toJson()).toList(),
    );
  }

  /// 从外部导入 JSON 配置字符串
  Future<bool> importConfigJson(String jsonStr) async {
    try {
      final List<dynamic> jsonList = jsonDecode(jsonStr);
      final importedList = <CustomCategory>[];
      for (final item in jsonList) {
        if (item is Map<String, dynamic>) {
          importedList.add(CustomCategory.fromJson(item));
        }
      }

      if (importedList.isNotEmpty) {
        _categories
          ..clear()
          ..addAll(importedList);
        _sortCategories();
        notifyListeners();
        await _saveToFile();
        AppLogger.i('导入分类规则配置成功: 共 ${_categories.length} 个分类');
        return true;
      }
      return false;
    } catch (e, stack) {
      AppLogger.e('导入分类配置失败: $e', e, stack);
      return false;
    }
  }
}
