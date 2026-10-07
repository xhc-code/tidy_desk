import 'package:fluent_ui/fluent_ui.dart';
import '../features/desktop/models/desktop_item.dart';

/// 文件类型与 Fluent UI 图标/颜色映射工具类 (精准适配 Microsoft 365 / OpenOffice / 压缩包 / 媒体 / 快捷方式)
class FileTypeHelper {
  FileTypeHelper._();

  // 文档类扩展名
  static const Set<String> documentExtensions = {
    '.txt', '.doc', '.docx', '.pdf', '.xls', '.xlsx',
    '.ppt', '.pptx', '.csv', '.md', '.rtf', '.wps',
    '.accdb', '.mdb', '.pub', '.odt', '.ods', '.odp',
    '.sxd', '.sxp', '.html', '.json', '.xml', '.yaml',
    '.yml', '.log', '.zip', '.rar', '.7z', '.tar', '.gz'
  };

  // 媒体类扩展名
  static const Set<String> mediaExtensions = {
    '.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp', '.svg', '.ico',
    '.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.rmvb',
    '.mp3', '.flac', '.wav', '.aac', '.ogg', '.m4a'
  };

  // 快捷方式与可执行文件
  static const Set<String> shortcutExtensions = {
    '.lnk', '.url', '.exe', '.bat', '.cmd', '.msi', '.ps1'
  };

  /// 根据文件路径与扩展名判断所属的分类
  static DesktopCategory determineCategory({
    required bool isDirectory,
    required String extension,
  }) {
    if (isDirectory) {
      return DesktopCategory.folder;
    }

    final ext = extension.toLowerCase();
    if (shortcutExtensions.contains(ext)) {
      return DesktopCategory.shortcut;
    }
    if (mediaExtensions.contains(ext)) {
      return DesktopCategory.media;
    }
    if (documentExtensions.contains(ext)) {
      return DesktopCategory.document;
    }

    return DesktopCategory.document;
  }

  /// 获取文件对应的 Fluent 图标
  static IconData getIconForExtension(String extension, bool isDirectory) {
    if (isDirectory) {
      return FluentIcons.folder_fill;
    }

    final ext = extension.toLowerCase();

    // 1. Microsoft Word & OpenDocument Text
    if (ext == '.doc' || ext == '.docx' || ext == '.wps' || ext == '.odt') {
      return FluentIcons.document_set;
    }
    // 2. Microsoft Excel & OpenDocument Spreadsheet
    if (ext == '.xls' || ext == '.xlsx' || ext == '.csv' || ext == '.ods') {
      return FluentIcons.excel_document;
    }
    // 3. Microsoft PowerPoint & OpenDocument Presentation
    if (ext == '.ppt' || ext == '.pptx' || ext == '.odp' || ext == '.sxp') {
      return FluentIcons.power_point_document;
    }
    // 4. Microsoft Access 数据库
    if (ext == '.accdb' || ext == '.mdb') {
      return FluentIcons.database;
    }
    // 5. Microsoft Publisher
    if (ext == '.pub') {
      return FluentIcons.project_document;
    }
    // 6. OpenOffice 绘图
    if (ext == '.sxd') {
      return FluentIcons.brush;
    }
    // 7. 纯文本 / 记事本
    if (ext == '.txt' || ext == '.log') {
      return FluentIcons.text_document;
    }
    // 8. 富文本文档 (RTF)
    if (ext == '.rtf') {
      return FluentIcons.text_document_edit;
    }
    // 9. Markdown
    if (ext == '.md') {
      return FluentIcons.mark_down_language;
    }
    // 10. PDF
    if (ext == '.pdf') {
      return FluentIcons.pdf;
    }
    // 11. 压缩包 (ZIP / RAR / 7Z)
    if (ext == '.zip' || ext == '.rar' || ext == '.7z' || ext == '.tar' || ext == '.gz') {
      return FluentIcons.archive;
    }
    // 12. 图片
    if (ext == '.png' || ext == '.jpg' || ext == '.jpeg' || ext == '.gif' || ext == '.bmp' || ext == '.webp' || ext == '.svg' || ext == '.ico') {
      return FluentIcons.photo_collection;
    }
    // 13. 视频
    if (ext == '.mp4' || ext == '.mkv' || ext == '.avi' || ext == '.mov' || ext == '.wmv') {
      return FluentIcons.video;
    }
    // 14. 音频
    if (ext == '.mp3' || ext == '.flac' || ext == '.wav' || ext == '.aac' || ext == '.ogg') {
      return FluentIcons.music_in_collection;
    }
    // 15. 快捷方式
    if (ext == '.lnk' || ext == '.url') {
      return FluentIcons.link;
    }
    // 16. 可执行程序
    if (ext == '.exe' || ext == '.msi' || ext == '.bat' || ext == '.cmd' || ext == '.ps1') {
      return FluentIcons.app_icon_default;
    }
    // 17. 编程语言代码
    if (ext == '.json' || ext == '.xml' || ext == '.yaml' || ext == '.yml' || ext == '.dart' || ext == '.py' || ext == '.js' || ext == '.ts' || ext == '.cpp' || ext == '.c' || ext == '.h') {
      return FluentIcons.code;
    }

    return FluentIcons.document;
  }

  /// 获取文件图标主色调（精准还原微软官方品牌色）
  static Color getAccentColor(String extension, bool isDirectory, [bool isLight = false]) {
    if (isDirectory) {
      return isLight ? const Color(0xFFD97706) : const Color(0xFFFFC107);
    }

    final ext = extension.toLowerCase();

    // Word 蓝
    if (ext == '.doc' || ext == '.docx' || ext == '.wps' || ext == '.odt') {
      return isLight ? const Color(0xFF0067B8) : const Color(0xFF4A90E2);
    }
    // Excel 绿
    if (ext == '.xls' || ext == '.xlsx' || ext == '.csv' || ext == '.ods') {
      return isLight ? const Color(0xFF107C41) : const Color(0xFF23B574);
    }
    // PowerPoint 橙红
    if (ext == '.ppt' || ext == '.pptx' || ext == '.odp' || ext == '.sxp') {
      return isLight ? const Color(0xFFD83B01) : const Color(0xFFFF8555);
    }
    // Access 砖红
    if (ext == '.accdb' || ext == '.mdb') {
      return isLight ? const Color(0xFFA4373A) : const Color(0xFFE57373);
    }
    // Publisher 墨绿
    if (ext == '.pub') {
      return isLight ? const Color(0xFF008272) : const Color(0xFF4DB6AC);
    }
    // OpenOffice 绘图
    if (ext == '.sxd') {
      return isLight ? const Color(0xFF881798) : const Color(0xFFBA68C8);
    }
    // 纯文本 深灰青
    if (ext == '.txt' || ext == '.log') {
      return isLight ? const Color(0xFF4A5568) : const Color(0xFFA0AEC0);
    }
    // RTF / MD 蓝青
    if (ext == '.rtf' || ext == '.md') {
      return isLight ? const Color(0xFF0078D4) : const Color(0xFF60CDFF);
    }
    // PDF 红
    if (ext == '.pdf') {
      return isLight ? const Color(0xFFD13438) : const Color(0xFFFF6060);
    }
    // 压缩包 琥珀橙
    if (ext == '.zip' || ext == '.rar' || ext == '.7z' || ext == '.tar' || ext == '.gz') {
      return isLight ? const Color(0xFFCA5010) : const Color(0xFFFFA255);
    }
    // 图片 紫/玫红
    if (mediaExtensions.contains(ext)) {
      return isLight ? const Color(0xFF881798) : const Color(0xFFD870FF);
    }
    // 快捷方式 微软经典蓝
    if (ext == '.lnk' || ext == '.url') {
      return isLight ? const Color(0xFF0078D4) : const Color(0xFF60CDFF);
    }
    // 可执行程序 天蓝
    if (ext == '.exe' || ext == '.msi' || ext == '.bat' || ext == '.cmd' || ext == '.ps1') {
      return isLight ? const Color(0xFF0284C7) : const Color(0xFF38BDF8);
    }
    // 代码 翡翠绿
    if (ext == '.json' || ext == '.xml' || ext == '.yaml' || ext == '.yml' || ext == '.dart' || ext == '.py' || ext == '.js') {
      return isLight ? const Color(0xFF059669) : const Color(0xFF34D399);
    }

    return isLight ? const Color(0xFF4B5563) : const Color(0xFFCBD5E1);
  }

  /// 获取图标卡片背景底色
  static Color getBadgeBackgroundColor(String extension, bool isDirectory, [bool isLight = false]) {
    final accent = getAccentColor(extension, isDirectory, isLight);
    if (isLight) {
      if (isDirectory) return const Color(0xFFFFF4D6);
      return accent.withValues(alpha: 0.12);
    } else {
      return accent.withValues(alpha: 0.22);
    }
  }
}
