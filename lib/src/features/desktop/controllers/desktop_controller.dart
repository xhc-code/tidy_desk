import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/desktop_item.dart';
import '../../categories/models/custom_category.dart';
import '../../categories/services/category_manager.dart';
import '../../../core/logging/app_logger.dart';
import '../../../utils/file_type_helper.dart';
import '../../../utils/windows_icon_extractor.dart';
import '../../../utils/windows_shell_helper.dart';
import '../../../utils/windows_shell_new_helper.dart';
import '../../dock_island/services/dock_island_service.dart';

/// 桌面文件状态管理与系统交互控制器 (ChangeNotifier)
///
/// 遵循 Flutter 官方推荐的 ChangeNotifier + ListenableBuilder 范式。
/// 核心职责：
/// 1. 扫描当前用户桌面与 Windows 公共桌面 (Public Desktop)，合并去重。
/// 2. 【Windows 原生实时目录同步】：基于 Directory.watch (ReadDirectoryChangesW) 实时监听文件增删改，300ms 智能防抖秒级静默自动更新。
/// 3. 提供分类过滤 (全部、常用、文件、媒体、快捷方式、文件夹) 与拼音全拼/首字母秒级搜索。
/// 4. 【应用内点击加权】：在「常用」分类下依据应用内点击频次和最后打开时间智能排序。
/// 5. 【系统交接红线】：文件夹或文件必须直接调用 Windows 原生 explorer.exe 或系统关联程序打开。
/// 6. 【100% 动态注册表 ShellNew】：动态扫描 Windows 注册表当前已安装的所有新建项。
class DesktopController extends ChangeNotifier {
  static const String _prefUsageCountsKey = 'pref_desktop_usage_counts';
  static const String _prefLastOpenedKey = 'pref_desktop_last_opened';
  static const String _prefPinnedItemsKey = 'pref_category_pinned_items';
  static const String _prefDockPinnedItemsKey = 'pref_dock_pinned_items';

  bool _disposed = false;
  bool get isDisposed => _disposed;

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// 所有已扫描到的桌面项
  final List<DesktopItem> _allItems = [];
  List<DesktopItem> get allItems => List.unmodifiable(_allItems);

  /// 动态从 Windows 注册表扫描得到的所有已安装新建项列表
  List<ShellNewItem> _shellNewItems = [];
  List<ShellNewItem> get shellNewItems => List.unmodifiable(_shellNewItems);

  /// 动态从 Windows 注册表扫描得到的第三方桌面右键菜单项 (如 WebStorm, VS Code, Git 等)
  List<DesktopShellCommandItem> _desktopBackgroundCommands = [];
  List<DesktopShellCommandItem> get desktopBackgroundCommands => List.unmodifiable(_desktopBackgroundCommands);

  /// 每个项目的点击打开使用次数 (路径 -> 次数)
  final Map<String, int> _usageCounts = {};

  /// 每个项目最后一次打开的时间戳 (路径 -> epoch ms)
  final Map<String, int> _lastOpenedTimes = {};

  /// 每个分类下置顶的项目路径列表 (分类 ID -> [项目路径列表])
  final Map<String, List<String>> _pinnedPathsByCategory = {};

  /// 底部常驻 Dock 栏中用户固定的应用/文件路径列表
  final List<String> _dockPinnedPaths = [];
  List<String> get dockPinnedPaths => List.unmodifiable(_dockPinnedPaths);

  /// 最新创建或保存的文件/文件夹绝对路径 (用于视口滚动定位与呼吸高亮)
  String? _recentlyCreatedPath;
  String? get recentlyCreatedPath => _recentlyCreatedPath;

  /// 最新创建的桌面项目实体 (用于底部浮动操作胶囊)
  DesktopItem? _recentlyCreatedItem;
  DesktopItem? get recentlyCreatedItem => _recentlyCreatedItem;

  /// 呼吸高亮自动淡出定时器
  Timer? _highlightTimer;

  /// 目录变更监听流列表
  final List<StreamSubscription<FileSystemEvent>> _watcherSubscriptions = [];

  /// 目录变更防抖定时器
  Timer? _watcherDebounceTimer;

  /// 是否已经初始化了目录监听器
  bool _isWatcherInitialized = false;

  /// 当前是否正在加载数据
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// 当前选中的分类 ID (默认 'all')
  String _selectedCategoryId = 'all';
  String get selectedCategoryId => _selectedCategoryId;

  /// 搜索关键词
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  /// 错误信息 (若存在)
  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// 用户个人桌面路径
  String _userDesktopPath = '';
  String get userDesktopPath => _userDesktopPath;

  DesktopController() {
    CategoryManager.instance.addListener(_onCategoriesChanged);
    _bootstrap();
  }

  /// 统一协调启动流程：并行预加载全部本地持久化数据，单次通知 UI，杜绝启动期 5+ 次重复 Rebuild
  Future<void> _bootstrap() async {
    _isLoading = true;
    try {
      await Future.wait([
        _initUsageData(notify: false),
        _initPinnedData(notify: false),
        _initDockPinnedData(notify: false),
      ]);
      await loadDesktopItems(silent: true);
    } catch (e) {
      debugPrint('启动初始化异常: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }

    // 非阻塞异步预热注册表模版 (0 毫秒阻碍首屏展示)
    Future.microtask(() => _initShellNewData());
  }

  /// 异步预热加载注册表 ShellNew 动态新建模板与桌面第三方扩展命令
  Future<void> _initShellNewData() async {
    try {
      final items = await WindowsShellNewHelper.getShellNewItems();
      _shellNewItems = items;
      final cmds = await WindowsShellNewHelper.getDesktopBackgroundCommands();
      _desktopBackgroundCommands = cmds;
      notifyListeners();
    } catch (e) {
      debugPrint('加载注册表 Shell 数据失败: $e');
    }
  }

  /// 重新扫描注册表 ShellNew
  Future<void> refreshShellNewTemplates() async {
    final items = await WindowsShellNewHelper.refreshShellNewItems();
    _shellNewItems = items;
    final cmds = await WindowsShellNewHelper.getDesktopBackgroundCommands();
    _desktopBackgroundCommands = cmds;
    notifyListeners();
  }

  /// 执行第三方桌面扩展命令 (如 WebStorm, Git 等)
  void runDesktopCommand(DesktopShellCommandItem command) {
    try {
      String cmd = command.commandLine;
      final dPath = _userDesktopPath;
      cmd = cmd.replaceAll('%V', dPath).replaceAll('%v', dPath).replaceAll('%1', dPath).replaceAll('%L', dPath).replaceAll('%l', dPath);
      WindowsShellHelper.launchCommandLine(cmd, workingDirectory: dPath);
    } catch (e) {
      debugPrint('执行桌面命令失败: $e');
    }
  }

  /// 响应分类管理器规则或顺序变化
  void _onCategoriesChanged() {
    final cat = CategoryManager.instance.getCategoryById(_selectedCategoryId);
    if (cat == null || !cat.isEnabled) {
      _selectedCategoryId = 'all';
    }
    notifyListeners();
  }

  /// 初始化本地持久化分类置顶数据
  Future<void> _initPinnedData({bool notify = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_prefPinnedItemsKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        _pinnedPathsByCategory.clear();
        decoded.forEach((k, v) {
          if (v is List) {
            _pinnedPathsByCategory[k] = v.map((e) => e.toString()).toList();
          }
        });
      }
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('加载分类置顶数据失败: $e');
    }
  }

  /// 持久化保存分类置顶数据
  Future<void> _savePinnedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefPinnedItemsKey, jsonEncode(_pinnedPathsByCategory));
    } catch (e) {
      debugPrint('保存分类置顶数据失败: $e');
    }
  }

  /// 初始化底部 Dock 常驻应用数据
  Future<void> _initDockPinnedData({bool notify = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefDockPinnedItemsKey);
      if (list != null) {
        _dockPinnedPaths.clear();
        _dockPinnedPaths.addAll(list);
      }
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('加载 Dock 固定数据失败: $e');
    }
  }

  /// 持久化保存底部 Dock 常驻应用数据
  Future<void> _saveDockPinnedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefDockPinnedItemsKey, _dockPinnedPaths);
    } catch (e) {
      debugPrint('保存 Dock 固定数据失败: $e');
    }
  }

  /// 判断某个项目是否已固定到底部 Dock
  bool isItemPinnedToDock(String itemPath) {
    return _dockPinnedPaths.contains(itemPath);
  }

  /// 外部/子进程通过 IPC 远程同步固定项列表
  void updatePinnedPathsFromRemote(List<String> paths) {
    _dockPinnedPaths.clear();
    _dockPinnedPaths.addAll(paths);
    notifyListeners();
  }

  /// 切换某个项目固定到底部 Dock 的状态 (固定 / 取消固定)
  Future<void> toggleDockPin(DesktopItem item) async {
    if (_dockPinnedPaths.contains(item.path)) {
      _dockPinnedPaths.remove(item.path);
      AppLogger.i('从底部 Dock 移除 [${item.displayName}]');
    } else {
      _dockPinnedPaths.add(item.path);
      AppLogger.i('固定到底部 Dock [${item.displayName}]');
    }
    await _saveDockPinnedData();
    notifyListeners();

    // 跨进程毫秒级通知独立常驻 Dock 挂件同步更新项目与尺寸
    try {
      if (DockIslandService.instance.isEnabled) {
        await DockIslandService.instance.sendIpcConfig(pinnedItems: _dockPinnedPaths);
      }
    } catch (_) {}
  }

  /// 刷新桌面文件列表
  Future<void> refresh() async {
    await loadDesktopItems();
  }

  /// 获取当前固定到底部 Dock 的所有桌面项目实体 (支持在首屏扫描完成前即时同步构造，保证图标秒开显示全)
  List<DesktopItem> get dockPinnedItems {
    final result = <DesktopItem>[];
    for (final path in _dockPinnedPaths) {
      DesktopItem? found;
      for (final it in _allItems) {
        if (it.path == path) {
          found = it;
          break;
        }
      }
      if (found != null) {
        result.add(found);
      } else {
        // 如果文件全盘扫描尚未完成，立即从路径同步生成 DesktopItem 实体，杜绝启动首屏图标缺失与尺寸跳跃
        try {
          final isDir = FileSystemEntity.isDirectorySync(path);
          final entity = isDir ? Directory(path) : File(path);
          final item = DesktopItem.fromEntity(
            entity,
            category: isDir ? DesktopCategory.folder : DesktopCategory.all,
          );
          if (item != null) {
            result.add(item);
          }
        } catch (_) {}
      }
    }
    return result;
  }

  /// 判断某个项目是否在当前分类（或指定分类）中置顶
  bool isItemPinned(String itemPath, {String? categoryId}) {
    final catId = categoryId ?? _selectedCategoryId;
    return _pinnedPathsByCategory[catId]?.contains(itemPath) ?? false;
  }

  /// 切换某个项目在当前分类（或指定分类）中的置顶状态 (置顶 / 取消置顶)
  Future<void> togglePinItem(DesktopItem item, {String? categoryId}) async {
    final catId = categoryId ?? _selectedCategoryId;
    final list = _pinnedPathsByCategory[catId] != null
        ? List<String>.from(_pinnedPathsByCategory[catId]!)
        : <String>[];

    if (list.contains(item.path)) {
      list.remove(item.path);
      AppLogger.i('取消置顶 [${item.displayName}] (分类: $catId)');
    } else {
      list.add(item.path);
      AppLogger.i('本分类置顶 [${item.displayName}] (分类: $catId)');
    }
    _pinnedPathsByCategory[catId] = list;
    await _savePinnedData();
    notifyListeners();
  }

  /// 初始化本地持久化点击加权数据
  Future<void> _initUsageData({bool notify = true}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final countsJson = prefs.getString(_prefUsageCountsKey);
      if (countsJson != null && countsJson.isNotEmpty) {
        final decoded = jsonDecode(countsJson) as Map<String, dynamic>;
        _usageCounts.clear();
        decoded.forEach((k, v) {
          if (v is int) _usageCounts[k] = v;
        });
      }

      final timesJson = prefs.getString(_prefLastOpenedKey);
      if (timesJson != null && timesJson.isNotEmpty) {
        final decoded = jsonDecode(timesJson) as Map<String, dynamic>;
        _lastOpenedTimes.clear();
        decoded.forEach((k, v) {
          if (v is int) _lastOpenedTimes[k] = v;
        });
      }
      if (notify) notifyListeners();
    } catch (e) {
      debugPrint('加载常用使用频次数据失败: $e');
    }
  }

  /// 持久化保存点击加权数据
  Future<void> _saveUsageData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUsageCountsKey, jsonEncode(_usageCounts));
      await prefs.setString(_prefLastOpenedKey, jsonEncode(_lastOpenedTimes));
    } catch (e) {
      debugPrint('保存常用使用频次数据失败: $e');
    }
  }

  /// 切换选中的分类 ID
  void setCategoryId(String categoryId) {
    if (_selectedCategoryId != categoryId) {
      _selectedCategoryId = categoryId;
      notifyListeners();
    }
  }

  /// 更新搜索关键词并实时更新视图
  void setSearchQuery(String query) {
    final trimmed = query.trim();
    if (_searchQuery != trimmed) {
      _searchQuery = trimmed;
      notifyListeners();
    }
  }

  /// 清空搜索关键词
  void clearSearch() {
    if (_searchQuery.isNotEmpty) {
      _searchQuery = '';
      notifyListeners();
    }
  }

  /// 智能多维度匹配搜索关键词 (支持原始名、文件名、拼音首字母缩写与无音调全拼)
  bool _matchesSearchQuery(DesktopItem item, String queryLower) {
    if (queryLower.isEmpty) return true;
    return item.displayName.toLowerCase().contains(queryLower) ||
        item.fileName.toLowerCase().contains(queryLower) ||
        item.pinyinAbbr.contains(queryLower) ||
        item.pinyinFull.contains(queryLower);
  }

  /// 获取经过分类和搜索过滤后的展示列表 (当前分类下置顶项目优先置顶展示)
  List<DesktopItem> get filteredItems {
    final queryLower = _searchQuery.toLowerCase();
    final cat = CategoryManager.instance.getCategoryById(_selectedCategoryId);
    final currentPinnedList = _pinnedPathsByCategory[_selectedCategoryId] ?? const <String>[];

    List<DesktopItem> rawList;

    // 1. 常用分类：专属加权排序 (按使用次数降序，相同次数按最近打开时间降序)
    if (cat?.matchType == CategoryMatchType.frequent || _selectedCategoryId == 'frequent') {
      rawList = _allItems.where((item) {
        final count = _usageCounts[item.path] ?? 0;
        if (count <= 0) return false;
        return _matchesSearchQuery(item, queryLower);
      }).toList()
        ..sort((a, b) {
          final countA = _usageCounts[a.path] ?? 0;
          final countB = _usageCounts[b.path] ?? 0;
          if (countB != countA) {
            return countB.compareTo(countA); // 点击次数高者排在前面
          }
          final timeA = _lastOpenedTimes[a.path] ?? 0;
          final timeB = _lastOpenedTimes[b.path] ?? 0;
          return timeB.compareTo(timeA); // 最近打开者排在前面
        });
    } else {
      // 2. 全部与自定义/其他规则分类
      rawList = _allItems.where((item) {
        if (!CategoryManager.instance.matchesItem(item, _selectedCategoryId, usageCounts: _usageCounts)) {
          return false;
        }
        return _matchesSearchQuery(item, queryLower);
      }).toList();
    }

    if (currentPinnedList.isEmpty) {
      return rawList;
    }

    // 3. 将本分类下置顶的项目排在最前 (保持稳定的置顶先后次序)
    final pinnedItems = <DesktopItem>[];
    final unpinnedItems = <DesktopItem>[];

    for (final item in rawList) {
      if (currentPinnedList.contains(item.path)) {
        pinnedItems.add(item);
      } else {
        unpinnedItems.add(item);
      }
    }

    pinnedItems.sort((a, b) {
      final idxA = currentPinnedList.indexOf(a.path);
      final idxB = currentPinnedList.indexOf(b.path);
      return idxA.compareTo(idxB);
    });

    return [...pinnedItems, ...unpinnedItems];
  }

  /// 启动当前过滤列表中的第一个项目 (用于搜索框直接按回车即刻启动)
  Future<bool> openFirstFilteredItem() async {
    final list = filteredItems;
    if (list.isNotEmpty) {
      await openItem(list.first);
      return true;
    }
    return false;
  }

  /// 按分类 ID 统计数量
  int countByCategoryId(String categoryId) {
    final cat = CategoryManager.instance.getCategoryById(categoryId);
    if (cat == null) return 0;

    if (cat.matchType == CategoryMatchType.all || categoryId == 'all') {
      return _allItems.length;
    }
    if (cat.matchType == CategoryMatchType.frequent || categoryId == 'frequent') {
      return _allItems.where((item) => (_usageCounts[item.path] ?? 0) > 0).length;
    }
    if (cat.matchType == CategoryMatchType.folder || categoryId == 'folder') {
      return _allItems.where((item) => item.isDirectory).length;
    }

    return _allItems.where((item) {
      return CategoryManager.instance.matchesItem(
        item,
        categoryId,
        usageCounts: _usageCounts,
      );
    }).length;
  }

  /// 处理从外部（资源管理器/浏览器/微信）拖入到收纳盒的文件/文件夹
  Future<void> handleDroppedFiles(List<String> filePaths) async {
    if (filePaths.isEmpty) return;

    final userProfile = Platform.environment['USERPROFILE'];
    final targetDir = _userDesktopPath.isNotEmpty
        ? _userDesktopPath
        : (userProfile != null ? '$userProfile\\Desktop' : '');
    if (targetDir.isEmpty) return;

    for (final srcPath in filePaths) {
      try {
        final isDir = await FileSystemEntity.isDirectory(srcPath);
        final fileName = srcPath.split(Platform.pathSeparator).last;
        String destPath = '$targetDir\\$fileName';

        // 避免自身与同目录操作
        if (srcPath.toLowerCase() == destPath.toLowerCase()) continue;

        // 如果目标文件已存在，自动生成带 (1), (2) 序号的文件名
        int counter = 1;
        while (await FileSystemEntity.type(destPath) != FileSystemEntityType.notFound) {
          final dotIdx = fileName.lastIndexOf('.');
          if (dotIdx > 0 && !isDir) {
            final base = fileName.substring(0, dotIdx);
            final ext = fileName.substring(dotIdx);
            destPath = '$targetDir\\$base ($counter)$ext';
          } else {
            destPath = '$targetDir\\$fileName ($counter)';
          }
          counter++;
        }

        if (isDir) {
          await _copyDirectory(Directory(srcPath), Directory(destPath));
        } else {
          await File(srcPath).copy(destPath);
        }
        AppLogger.i('外部拖入文件成功存入桌面: $srcPath -> $destPath');
        _recentlyCreatedPath = destPath;

        // 如果当前处于手动自选分类，自动将新拖入的文件加入当前分类
        final currentCat = CategoryManager.instance.getCategoryById(_selectedCategoryId);
        if (currentCat != null && currentCat.matchType == CategoryMatchType.manual) {
          await CategoryManager.instance.addItemToManualCategory(currentCat.id, destPath);
        }
      } catch (e, stack) {
        AppLogger.e('处理拖入文件发生异常: $srcPath', e, stack);
      }
    }

    // 重新扫描并更新 UI
    await refreshItems();
  }

  /// 递归复制文件夹
  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final newPath = destination.path + Platform.pathSeparator + entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }

  /// 核心方法：扫描桌面目录并读取所有文件与快捷方式
  /// [silent]: 是否静默刷新 (目录变动监听自动同步时为 true，不打扰当前 UI 操作)
  Future<void> loadDesktopItems({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      // 1. 智能解析真实物理桌面路径 (兼容 Win10/Win11 原生桌面、OneDrive 桌面同步与磁盘重定向)
      _userDesktopPath = WindowsShellHelper.getActualDesktopPath();

      // 2. 彻底卸载到后台 Isolate 执行目录遍历与拼音全拼/缩写索引计算，主 UI 线程 0ms 阻塞
      final sortedList = await compute(
        _scanDesktopAsync,
        _ScanDesktopParams(
          userDesktopPath: _userDesktopPath,
        ),
      );

      _allItems
        ..clear()
        ..addAll(sortedList);

      AppLogger.i('个人桌面扫描完成: 共发现 ${_allItems.length} 个桌面项目 (后台 Isolate 解析完成)');

      // 3. 首次扫描完成后，开启用户个人桌面原生目录变更实时监听 (IOCP 0% CPU 占用)
      if (!_isWatcherInitialized && _userDesktopPath.isNotEmpty) {
        _initDirectoryWatchers([Directory(_userDesktopPath)]);
        _isWatcherInitialized = true;
      }

      // 后台全量预热所有应用与快捷方式图标至内存缓存 (过滤文件夹，杜绝滑动时的 I/O 丢帧卡顿)
      WindowsIconExtractor.preloadIcons(
        sortedList.where((e) => !e.isDirectory).map((e) => e.path).toList(),
      );
    } catch (e, stack) {
      _errorMessage = '扫描桌面发生异常: $e';
      AppLogger.e(_errorMessage!, e, stack);
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  /// 初始化 Windows 原生目录变更实时监听引擎 (基于 ReadDirectoryChangesW)
  void _initDirectoryWatchers(List<Directory> dirs) {
    for (final sub in _watcherSubscriptions) {
      sub.cancel();
    }
    _watcherSubscriptions.clear();

    for (final dir in dirs) {
      try {
        final watcher = dir.watch(recursive: false);
        final subscription = watcher.listen(
          _onFileSystemEvent,
          onError: (e) {
            debugPrint('桌面目录实时监听发生异常: $dir, error: $e');
          },
        );
        _watcherSubscriptions.add(subscription);
      } catch (e) {
        debugPrint('无法启动桌面实时监听: $dir, error: $e');
      }
    }
  }

  /// 目录变更事件处理与 300ms 智能防抖合并
  void _onFileSystemEvent(FileSystemEvent event) {
    final fileName = event.path.split(Platform.pathSeparator).last.toLowerCase();

    // 智能过滤 Windows 临时锁文件、desktop.ini 与隐藏临时文件
    if (fileName == 'desktop.ini' ||
        fileName.endsWith('.tmp') ||
        fileName.endsWith('.crdownload') ||
        fileName.startsWith(r'~$') ||
        fileName.startsWith('.')) {
      return;
    }

    final isCreate = event.type == FileSystemEvent.create;
    final createdPath = event.path;

    _watcherDebounceTimer?.cancel();
    _watcherDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      AppLogger.i('检测到桌面文件变动 (${event.type}): ${event.path}，正在自动静默同步...');
      await loadDesktopItems(silent: true);
      if (isCreate) {
        notifyRecentlyCreated(createdPath);
      }
    });
  }

  /// 触发新创建/保存文件的全局视觉定位与操作胶囊 (智能联动分类与视口)
  void notifyRecentlyCreated(String path) {
    _recentlyCreatedPath = path;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(milliseconds: 3500), () {
      _recentlyCreatedPath = null;
      _recentlyCreatedItem = null;
      notifyListeners();
    });

    // 查找对应 item
    DesktopItem? foundItem;
    for (final it in _allItems) {
      if (it.path.toLowerCase() == path.toLowerCase()) {
        foundItem = it;
        break;
      }
    }

    if (foundItem != null) {
      _recentlyCreatedItem = foundItem;

      // 智能分类保护：若当前分类不包含新创建的文件，自动无感切换至「全部」
      if (_selectedCategoryId != 'all') {
        final matchesCurrentCat = CategoryManager.instance.matchesItem(
          foundItem,
          _selectedCategoryId,
          usageCounts: _usageCounts,
        );
        if (!matchesCurrentCat) {
          _selectedCategoryId = 'all';
        }
      }
    }

    notifyListeners();
  }

  /// 手动关闭或清除最新创建高亮
  void clearRecentlyCreated() {
    _highlightTimer?.cancel();
    _recentlyCreatedPath = null;
    _recentlyCreatedItem = null;
    notifyListeners();
  }

  /// 当前选中的项目路径 (焦点显示)
  String? _selectedItemPath;
  String? get selectedItemPath => _selectedItemPath;

  /// 设置当前聚焦选中的项目
  void selectItem(String? path) {
    if (_selectedItemPath != path) {
      _selectedItemPath = path;
      notifyListeners();
    }
  }

  /// 刷新桌面列表
  Future<void> refreshItems() async {
    await loadDesktopItems();
  }

  // ===========================================================================
  // 系统交接红线 (Native Windows Interaction - 0ms 原生 ShellAPI)
  // ===========================================================================

  /// 记录项目打开使用频次与时间戳
  void _recordUsage(String path) {
    _usageCounts[path] = (_usageCounts[path] ?? 0) + 1;
    _lastOpenedTimes[path] = DateTime.now().millisecondsSinceEpoch;
    _saveUsageData();
    notifyListeners();
  }

  /// 打开选中的桌面项
  ///
  /// 【系统交接红线】：
  /// 1. 直接调用 Windows 原生 ShellExecuteW API，0 毫秒极速响应，无需启动任何中转进程。
  /// 2. 文件夹、.lnk 快捷方式、应用软件与各类文档完全交由 Windows 系统原生关联程序打开。
  Future<void> openItem(DesktopItem item) async {
    // 记录点击加权使用频次 (仅在「常用」分类下依据加权排序)
    _recordUsage(item.path);

    try {
      final success = WindowsShellHelper.openPath(item.path);
      if (!success) {
        // 兜底降级策略
        if (item.isDirectory) {
          await Process.start('explorer.exe', [item.path], mode: ProcessStartMode.detached);
        } else {
          final uri = Uri.file(item.path);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        }
      }
    } catch (e) {
      debugPrint('打开项目失败: $e');
    }
  }

  /// 在桌面新建文件夹 (自动处理重名数字编号并触发定位)
  Future<String?> createNewFolder([String? customName]) async {
    final desktopPath = _userDesktopPath;
    if (desktopPath.isEmpty) return null;

    try {
      String folderName = customName?.trim() ?? '新建文件夹';
      if (folderName.isEmpty) folderName = '新建文件夹';

      String targetPath = '$desktopPath${Platform.pathSeparator}$folderName';
      int count = 2;
      while (Directory(targetPath).existsSync() || File(targetPath).existsSync()) {
        targetPath = '$desktopPath${Platform.pathSeparator}$folderName ($count)';
        count++;
      }

      await Directory(targetPath).create(recursive: true);
      AppLogger.i('成功新建文件夹: $targetPath');
      await loadDesktopItems();
      notifyRecentlyCreated(targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('新建文件夹失败: $e');
      return null;
    }
  }

  /// 依据注册表 ShellNewItem 动态模板在桌面创建真实新文件 (自动触发定位与打开胶囊)
  Future<String?> createNewFileFromShellNew(ShellNewItem templateItem, [String? customBaseName]) async {
    final desktopPath = _userDesktopPath;
    if (desktopPath.isEmpty) return null;

    final createdPath = await WindowsShellNewHelper.createNewFileFromTemplate(
      targetDirectory: desktopPath,
      item: templateItem,
      customBaseName: customBaseName,
    );

    if (createdPath != null) {
      AppLogger.i('成功从注册表模板新建 [${templateItem.displayName}]: $createdPath');
      await loadDesktopItems();
      notifyRecentlyCreated(createdPath);
    }
    return createdPath;
  }

  /// 在桌面新建指定类型的空文件 (支持 .txt, .docx, .xlsx, .pptx, .md 等模板)
  Future<String?> createNewFile(String extension, [String? baseName]) async {
    final desktopPath = _userDesktopPath;
    if (desktopPath.isEmpty) return null;

    try {
      final ext = extension.startsWith('.') ? extension : '.$extension';
      String defaultBase = baseName?.trim() ?? '';
      if (defaultBase.isEmpty) {
        switch (ext.toLowerCase()) {
          case '.txt':
            defaultBase = '新建文本文档';
            break;
          case '.docx':
          case '.doc':
            defaultBase = '新建 Microsoft Word 文档';
            break;
          case '.xlsx':
          case '.xls':
            defaultBase = '新建 Microsoft Excel 工作表';
            break;
          case '.pptx':
          case '.ppt':
            defaultBase = '新建 Microsoft PowerPoint 演示文稿';
            break;
          case '.md':
            defaultBase = '新建 Markdown 文档';
            break;
          default:
            defaultBase = '新建文件';
            break;
        }
      }

      String targetPath = '$desktopPath${Platform.pathSeparator}$defaultBase$ext';
      int count = 2;
      while (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
        targetPath = '$desktopPath${Platform.pathSeparator}$defaultBase ($count)$ext';
        count++;
      }

      final file = File(targetPath);
      await file.create(recursive: true);
      AppLogger.i('成功新建文件: $targetPath');
      await loadDesktopItems();
      notifyRecentlyCreated(targetPath);
      return targetPath;
    } catch (e) {
      debugPrint('新建文件失败: $e');
      return null;
    }
  }

  /// 重命名桌面项目 (安全重命名并自动更新列表)
  Future<bool> renameItem(DesktopItem item, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || trimmed == item.displayName || trimmed == item.fileName) {
      return false;
    }

    try {
      final parentDir = File(item.path).parent.path;
      final String newPath;
      if (item.isDirectory || trimmed.contains('.')) {
        newPath = '$parentDir${Platform.pathSeparator}$trimmed';
      } else {
        // 如果用户未显式修改扩展名，保留原有扩展名
        newPath = '$parentDir${Platform.pathSeparator}$trimmed${item.extension}';
      }

      if (File(newPath).existsSync() || Directory(newPath).existsSync()) {
        debugPrint('重命名失败: 目标名称已存在');
        return false;
      }

      if (item.isDirectory) {
        await Directory(item.path).rename(newPath);
      } else {
        await File(item.path).rename(newPath);
      }

      AppLogger.i('重命名成功: [${item.path}] -> [$newPath]');
      await CategoryManager.instance.handleItemRenamed(item.path, newPath);
      await loadDesktopItems();
      return true;
    } catch (e) {
      debugPrint('重命名异常: $e');
      return false;
    }
  }

  /// 将项目安全移入 Windows 回收站 (Win32 原生，支持 Ctrl+Z 撤回)
  Future<bool> deleteItemToRecycleBin(DesktopItem item) async {
    try {
      final success = WindowsShellHelper.moveToRecycleBin(item.path);
      if (success) {
        AppLogger.i('项目已安全移入回收站: [${item.displayName}]');
        await CategoryManager.instance.handleItemDeleted(item.path);
        await loadDesktopItems();
      }
      return success;
    } catch (e) {
      debugPrint('移入回收站失败: $e');
      return false;
    }
  }

  /// 弹出 Windows 原生属性对话框
  void showItemProperties(DesktopItem item) {
    WindowsShellHelper.showProperties(item.path);
  }

  /// 在 Windows 资源管理器中高亮定位该文件 (explorer.exe /select,"path")
  Future<void> showInExplorer(DesktopItem item) async {
    try {
      final success = WindowsShellHelper.showInExplorer(item.path);
      if (!success) {
        await Process.start('explorer.exe', ['/select,${item.path}'], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      debugPrint('定位文件失败: $e');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    try {
      _highlightTimer?.cancel();
      _highlightTimer = null;
      CategoryManager.instance.removeListener(_onCategoriesChanged);
      _watcherDebounceTimer?.cancel();
      _watcherDebounceTimer = null;
      for (final sub in _watcherSubscriptions) {
        sub.cancel();
      }
      _watcherSubscriptions.clear();
    } finally {
      super.dispose();
    }
  }
}

/// 用于在后台 Isolate (compute) 中执行桌面目录异步扫描的传参对象
class _ScanDesktopParams {
  final String userDesktopPath;

  const _ScanDesktopParams({
    required this.userDesktopPath,
  });
}

/// 后台 Isolate 独立运行的桌面扫描与拼音索引纯函数
///
/// 避免在主 UI 线程进行大量同步 I/O、路径字符串解析与汉字转拼音运算，
/// 将 100% 的解析负载移至后台线程，保证界面启动与加载期间 0 掉帧。
List<DesktopItem> _scanDesktopAsync(_ScanDesktopParams params) {
  final itemsMap = <String, DesktopItem>{};

  // 仅扫描当前登录用户的个人桌面目录
  if (params.userDesktopPath.isNotEmpty) {
    try {
      final userDir = Directory(params.userDesktopPath);
      if (userDir.existsSync()) {
        final entities = userDir.listSync(recursive: false, followLinks: true);
        for (final entity in entities) {
          final fileName = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.reversed.firstWhere((s) => s.isNotEmpty, orElse: () => '')
              : '';
          if (_shouldIgnoreFile(fileName)) continue;

          final isDir = entity is Directory;
          final ext = isDir
              ? ''
              : (fileName.contains('.') ? fileName.substring(fileName.lastIndexOf('.')).toLowerCase() : '');
          final category = FileTypeHelper.determineCategory(
            isDirectory: isDir,
            extension: ext,
          );

          final item = DesktopItem.fromEntity(
            entity,
            category: category,
            isPublic: false,
          );
          if (item != null) {
            itemsMap[item.fileName.toLowerCase()] = item;
          }
        }
      }
    } catch (_) {}
  }

  // 排序：文件夹优先置顶，然后按显示名称（拼音/字母）升序排序
  final sortedList = itemsMap.values.toList()
    ..sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

  return sortedList;
}

/// 智能过滤 Windows 临时锁文件、desktop.ini 与隐藏临时文件
bool _shouldIgnoreFile(String fileName) {
  if (fileName.isEmpty) return true;
  final lower = fileName.toLowerCase();
  return lower == 'desktop.ini' ||
      lower.endsWith('.tmp') ||
      lower.endsWith('.crdownload') ||
      lower.startsWith(r'~$') ||
      lower.startsWith('.');
}

