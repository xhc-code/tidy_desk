import 'package:fluent_ui/fluent_ui.dart';

/// 分类规则匹配类型
enum CategoryMatchType {
  /// 全部项目特殊分类 (匹配所有非空项目)
  all('全部项目', '展示桌面所有收纳项目'),

  /// 常用/高频特殊分类 (根据用户点击频次与最后打开时间智能加权)
  frequent('常用高频', '依据应用内打开频次与最近访问时间智能排序'),

  /// 扩展名后缀规则匹配 (如 .dart, .pdf, .zip 等)
  extension('扩展名匹配', '根据文件后缀名自动归类'),

  /// 文件夹专属分类
  folder('文件夹', '匹配所有文件目录与文件夹'),

  /// 用户手动自选分类 (由用户自由添加或移出项目)
  manual('手动自选', '由用户自由挑选项目收纳');

  /// 类型的中文显示名称
  final String label;

  /// 类型的详细说明
  final String description;

  const CategoryMatchType(this.label, this.description);

  /// 从字符串解析枚举值 (防崩溃容错)
  static CategoryMatchType fromString(String? val) {
    if (val == null) return CategoryMatchType.extension;
    return CategoryMatchType.values.firstWhere(
      (e) => e.name == val,
      orElse: () => CategoryMatchType.extension,
    );
  }
}

/// 用户自定义桌面分类数据模型
///
/// 结构化描述一个分类的唯一标识、显示名称、图标、匹配后缀集与排序属性。
/// 支持完整 JSON 序列化与反序列化，便于本地文件持久化和云端备份。
class CustomCategory {
  /// 分类唯一标识 (如 'all', 'frequent', 'document', 'media', 'code_dev' 等)
  final String id;

  /// 分类在界面上展示的名称 (如 '全部', '常用', '文档', '代码工程')
  final String name;

  /// Fluent 图标的 Unicode 码点 (如 FluentIcons.document.codePoint)
  final int iconCodePoint;

  /// 图标所在的字体家族 (默认为 FluentIcons)
  final String? iconFontFamily;

  /// 该分类包含的文件扩展名列表 (全部自动规范化为带点小写，如 ['.dart', '.py', '.js'])
  final List<String> matchExtensions;

  /// 手动自选分类包含的项目标识/路径列表 (当 matchType == manual 时生效)
  final List<String> manualItemKeys;

  /// 匹配规则模式
  final CategoryMatchType matchType;

  /// 是否为系统内置分类 (系统分类不可被删除，但可自由编辑规则、调整顺序或临时隐藏)
  final bool isSystem;

  /// 是否启用 (为 false 时不会显示在主界面的分类导航栏中)
  final bool isEnabled;

  /// 排序权重 (数字越小排在越前面)
  final int sortOrder;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.iconCodePoint,
    this.iconFontFamily = 'FluentIcons',
    this.matchExtensions = const [],
    this.manualItemKeys = const [],
    required this.matchType,
    this.isSystem = false,
    this.isEnabled = true,
    required this.sortOrder,
  });

  /// 获取 Fluent UI 图标对象 (优先匹配预设常量图标以获得最佳渲染与静态分析表现)
  IconData get iconData => getIconFromCodePoint(iconCodePoint);

  /// 根据 Unicode 码点安全获取对应的 Fluent 图标 (支持 1000+ 完整 Fluent 图标集)
  static IconData getIconFromCodePoint(int codePoint) {
    // ignore: non_const_argument_for_const_parameter
    return IconData(codePoint, fontFamily: 'FluentIcons', fontPackage: 'fluent_ui');
  }

  /// 规范化扩展名列表辅助函数 (去除多余空格，自动补齐点前缀，全部转小写)
  static List<String> normalizeExtensions(Iterable<String> rawExtensions) {
    final result = <String>{};
    for (final raw in rawExtensions) {
      var trimmed = raw.trim().toLowerCase();
      if (trimmed.isEmpty) continue;
      if (!trimmed.startsWith('.')) {
        trimmed = '.$trimmed';
      }
      result.add(trimmed);
    }
    return result.toList()..sort();
  }

  /// 复制并生成新实例 (用于不可变状态更新)
  CustomCategory copyWith({
    String? id,
    String? name,
    int? iconCodePoint,
    String? iconFontFamily,
    List<String>? matchExtensions,
    List<String>? manualItemKeys,
    CategoryMatchType? matchType,
    bool? isSystem,
    bool? isEnabled,
    int? sortOrder,
  }) {
    return CustomCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconFontFamily: iconFontFamily ?? this.iconFontFamily,
      matchExtensions: matchExtensions != null
          ? normalizeExtensions(matchExtensions)
          : this.matchExtensions,
      manualItemKeys: manualItemKeys ?? this.manualItemKeys,
      matchType: matchType ?? this.matchType,
      isSystem: isSystem ?? this.isSystem,
      isEnabled: isEnabled ?? this.isEnabled,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  /// 将数据模型序列化为 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'iconCodePoint': iconCodePoint,
      'iconFontFamily': iconFontFamily,
      'matchExtensions': matchExtensions,
      'manualItemKeys': manualItemKeys,
      'matchType': matchType.name,
      'isSystem': isSystem,
      'isEnabled': isEnabled,
      'sortOrder': sortOrder,
    };
  }

  /// 从 JSON Map 反序列化为数据模型 (带全面的空值与异常防护)
  factory CustomCategory.fromJson(Map<String, dynamic> json) {
    final rawExts = json['matchExtensions'];
    final extList = <String>[];
    if (rawExts is List) {
      for (final item in rawExts) {
        if (item != null) {
          extList.add(item.toString());
        }
      }
    }

    final rawKeys = json['manualItemKeys'];
    final keyList = <String>[];
    if (rawKeys is List) {
      for (final item in rawKeys) {
        if (item != null && item.toString().trim().isNotEmpty) {
          keyList.add(item.toString().trim());
        }
      }
    }

    return CustomCategory(
      id: json['id'] as String? ?? 'category_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? '未命名分类',
      iconCodePoint: json['iconCodePoint'] as int? ?? FluentIcons.folder.codePoint,
      iconFontFamily: json['iconFontFamily'] as String? ?? 'FluentIcons',
      matchExtensions: normalizeExtensions(extList),
      manualItemKeys: keyList,
      matchType: CategoryMatchType.fromString(json['matchType'] as String?),
      isSystem: json['isSystem'] as bool? ?? false,
      isEnabled: json['isEnabled'] as bool? ?? true,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomCategory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
