import 'dart:io';
import 'package:pinyin/pinyin.dart';

/// 桌面文件分类类型
enum DesktopCategory {
  /// 全部项目
  all,

  /// 常用 / 高频项目 (根据应用内点击加权智能排序)
  frequent,

  /// 文档/工作文件
  document,

  /// 多媒体 (图像/音频/视频)
  media,

  /// 快捷方式与应用程序 (.lnk, .url, .exe 等)
  shortcut,

  /// 文件夹
  folder,
}

/// 桌面项数据模型
class DesktopItem {
  /// 文件或文件夹完整绝对路径
  final String path;

  /// 显示名称 (若为快捷方式则可去掉 .lnk 后缀显示更友好)
  final String displayName;

  /// 真实原始文件名
  final String fileName;

  /// 文件扩展名 (小写，例如 .pdf，如果是文件夹则为空字符串)
  final String extension;

  /// 拼音首字母缩写 (小写，如 "微信" -> "wx", "VS Code" -> "vscode")
  final String pinyinAbbr;

  /// 无音调全拼 (小写，如 "微信" -> "weixin")
  final String pinyinFull;

  /// 是否是目录
  final bool isDirectory;

  /// 所属分类
  final DesktopCategory category;

  /// 文件大小 (字节，文件夹通常为 0)
  final int size;

  /// 最后修改时间
  final DateTime modifiedTime;

  /// 是否来自公共桌面 (C:\Users\Public\Desktop)
  final bool isPublicDesktop;

  const DesktopItem({
    required this.path,
    required this.displayName,
    required this.fileName,
    required this.extension,
    required this.pinyinAbbr,
    required this.pinyinFull,
    required this.isDirectory,
    required this.category,
    required this.size,
    required this.modifiedTime,
    this.isPublicDesktop = false,
  });

  /// 从 FileSystemEntity 创建 DesktopItem 实例
  static DesktopItem? fromEntity(
    FileSystemEntity entity, {
    required DesktopCategory category,
    bool isPublic = false,
  }) {
    try {
      int size = 0;
      DateTime modifiedTime = DateTime.now();
      try {
        final stat = entity.statSync();
        size = stat.size;
        modifiedTime = stat.modified;
      } catch (_) {}

      final isDir = entity is Directory;
      final fileName = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.reversed.firstWhere((s) => s.isNotEmpty, orElse: () => '')
          : '';

      if (fileName.isEmpty) return null;

      // 针对快捷方式与普通文件处理友好显示名
      String display = fileName;
      String ext = '';

      if (!isDir) {
        final dotIndex = fileName.lastIndexOf('.');
        if (dotIndex != -1) {
          ext = fileName.substring(dotIndex).toLowerCase();
          if (ext == '.lnk' || ext == '.url') {
            display = fileName.substring(0, dotIndex);
          }
        }
      }

      // 预计算拼音索引 (首字母 + 全拼，全部转小写)
      String pinyinAbbr = '';
      String pinyinFull = '';
      try {
        pinyinAbbr = PinyinHelper.getShortPinyin(display).toLowerCase();
        pinyinFull = PinyinHelper.getPinyin(
          display,
          separator: '',
          format: PinyinFormat.WITHOUT_TONE,
        ).toLowerCase();
      } catch (_) {
        pinyinAbbr = display.toLowerCase();
        pinyinFull = display.toLowerCase();
      }

      return DesktopItem(
        path: entity.path,
        displayName: display,
        fileName: fileName,
        extension: ext,
        pinyinAbbr: pinyinAbbr,
        pinyinFull: pinyinFull,
        isDirectory: isDir,
        category: category,
        size: size,
        modifiedTime: modifiedTime,
        isPublicDesktop: isPublic,
      );
    } catch (_) {
      // 忽略因系统特殊权限无法读取的文件
      return null;
    }
  }

  /// 获取友好文件类型中文描述 (如 文件夹、应用软件、Word 文档等，对标 easyDesktop)
  String get typeDescription {
    if (isDirectory) return '文件夹';
    final ext = extension.toLowerCase();
    if (ext == '.lnk' || ext == '.url') return '快捷方式';
    if (ext == '.exe' || ext == '.msi' || ext == '.bat' || ext == '.cmd') return '应用软件';
    if (ext == '.doc' || ext == '.docx' || ext == '.wps') return 'Word 文档';
    if (ext == '.xls' || ext == '.xlsx' || ext == '.csv') return 'Excel 表格';
    if (ext == '.ppt' || ext == '.pptx') return 'PPT 演示';
    if (ext == '.pdf') return 'PDF 文档';
    if (ext == '.zip' || ext == '.rar' || ext == '.7z' || ext == '.tar' || ext == '.gz') return '压缩包';
    if (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.gif' || ext == '.webp' || ext == '.svg') return '图片';
    if (ext == '.mp4' || ext == '.mkv' || ext == '.avi' || ext == '.mov' || ext == '.wmv') return '视频';
    if (ext == '.mp3' || ext == '.flac' || ext == '.wav' || ext == '.aac') return '音频';
    if (ext == '.dart' || ext == '.py' || ext == '.js' || ext == '.ts' || ext == '.json' || ext == '.cpp' || ext == '.c') return '代码文件';
    if (ext == '.txt' || ext == '.md' || ext == '.log') return '文本文件';
    return ext.isNotEmpty ? '${ext.substring(1).toUpperCase()} 文件' : '文件';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopItem &&
          runtimeType == other.runtimeType &&
          path.toLowerCase() == other.path.toLowerCase();

  @override
  int get hashCode => path.toLowerCase().hashCode;
}
