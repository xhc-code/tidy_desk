import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32_registry/win32_registry.dart';

/// shlwapi.dll SHLoadIndirectString 解析间接资源引用 (如 @notepad.exe,-470)
typedef _SHLoadIndirectStringC = Int32 Function(
  Pointer<Utf16> pszSource,
  Pointer<Utf16> pszOutBuf,
  Uint32 cchOutBuf,
  Pointer<Pointer<Void>> ppvReserved,
);
typedef _SHLoadIndirectStringDart = int Function(
  Pointer<Utf16> pszSource,
  Pointer<Utf16> pszOutBuf,
  int cchOutBuf,
  Pointer<Pointer<Void>> ppvReserved,
);

/// kernel32.dll ExpandEnvironmentStringsW 展开环境变量 (如 %SystemRoot%)
typedef _ExpandEnvironmentStringsC = Uint32 Function(
  Pointer<Utf16> lpSrc,
  Pointer<Utf16> lpDst,
  Uint32 nSize,
);
typedef _ExpandEnvironmentStringsDart = int Function(
  Pointer<Utf16> lpSrc,
  Pointer<Utf16> lpDst,
  int nSize,
);

/// kernel32.dll / user32.dll 加载 DLL 字符串资源
typedef _LoadLibraryExC = IntPtr Function(Pointer<Utf16>, IntPtr, Uint32);
typedef _LoadLibraryExDart = int Function(Pointer<Utf16>, int, int);

typedef _FreeLibraryC = Int32 Function(IntPtr);
typedef _FreeLibraryDart = int Function(int);

typedef _LoadStringC = Int32 Function(IntPtr, Uint32, Pointer<Utf16>, Int32);
typedef _LoadStringDart = int Function(int, int, Pointer<Utf16>, int);

/// 单个动态「新建」模板项实体
class ShellNewItem {
  /// 文件扩展名 (如 .txt, .docx, .xlsx, .zip)
  final String extension;

  /// 显示给用户的友好中文/系统名称 (如 "文本文档", "Microsoft Word 文档")
  final String displayName;

  /// 模板文件路径 (若存在 FileName)
  final String? templateFileName;

  /// 是否为空文件创建 (NullFile)
  final bool isNullFile;

  /// 模板二进制数据 (若存在 Data)
  final List<int>? templateData;

  const ShellNewItem({
    required this.extension,
    required this.displayName,
    this.templateFileName,
    this.isNullFile = false,
    this.templateData,
  });

  @override
  String toString() => 'ShellNewItem($extension: $displayName)';
}

/// Windows 桌面背景扩展命令项实体 (读取自 DesktopBackground\shell 或 Directory\Background\shell)
class DesktopShellCommandItem {
  /// 命令标识键名 (如 'WebStorm', 'GitClone')
  final String key;

  /// 显示名称 (如 'Open Folder as WebStorm Project', 'Git Clone...')
  final String title;

  /// 图标路径或可执行文件路径 (可选)
  final String? iconPath;

  /// 待执行的命令行模板 (如 '"C:\Program Files\...\webstorm64.exe" "%V"')
  final String commandLine;

  const DesktopShellCommandItem({
    required this.key,
    required this.title,
    this.iconPath,
    required this.commandLine,
  });
}

/// Windows 注册表 Shell 动态项扫描与生成助手 (基于 Dart 官方标准库 package:win32_registry)
class WindowsShellNewHelper {
  static final DynamicLibrary _shlwapi = DynamicLibrary.open('shlwapi.dll');
  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final DynamicLibrary _user32 = DynamicLibrary.open('user32.dll');

  static final _SHLoadIndirectStringDart _shLoadIndirectString = _shlwapi
      .lookup<NativeFunction<_SHLoadIndirectStringC>>('SHLoadIndirectString')
      .asFunction<_SHLoadIndirectStringDart>();

  static final _ExpandEnvironmentStringsDart _expandEnvironmentStrings = _kernel32
      .lookup<NativeFunction<_ExpandEnvironmentStringsC>>('ExpandEnvironmentStringsW')
      .asFunction<_ExpandEnvironmentStringsDart>();

  static final _LoadLibraryExDart _loadLibraryEx = _kernel32
      .lookup<NativeFunction<_LoadLibraryExC>>('LoadLibraryExW')
      .asFunction<_LoadLibraryExDart>();

  static final _FreeLibraryDart _freeLibrary = _kernel32
      .lookup<NativeFunction<_FreeLibraryC>>('FreeLibrary')
      .asFunction<_FreeLibraryDart>();

  static final _LoadStringDart _loadString = _user32
      .lookup<NativeFunction<_LoadStringC>>('LoadStringW')
      .asFunction<_LoadStringDart>();

  /// 内存缓存的已扫描新建项列表
  static List<ShellNewItem>? _cachedShellNewItems;

  /// 内存缓存的桌面第三方快捷命令列表
  static List<DesktopShellCommandItem>? _cachedDesktopCommands;

  /// 已知 Windows 官方组件间接字符串快速映射字典 (保证 100% 准确中文，0 延迟)
  static final Map<String, String> _knownIndirectStrings = {
    r'@%systemroot%\system32\notepad.exe,-470': '文本文档',
    r'@notepad.exe,-470': '文本文档',
    r'@%systemroot%\system32\mspaint.exe,-59414': '位图图像',
    r'@mspaint.exe,-59414': '位图图像',
    r'@shell32.dll,-30397': '快捷方式',
    r'@shell32.dll,-10152': '文件夹',
    r'@shell32.dll,-30598': 'ZIP 压缩文件',
    r'@shell32.dll,-8506': '撤消',
    r'@shell32.dll,-8508': '恢复',
    r'@wsl.exe,-2': '在 Linux (WSL) 中打开',
    r'@rtfobj.dll,-2': '富文本文档',
    r'@wordpad.exe,-213': '富文本文档',
    r'@zipfldr.dll,-10194': 'ZIP 压缩文件',
    r'@zipfldr.dll,-10195': 'ZIP 压缩文件',
  };

  /// 系统内部黑名单扩展名 (不应当出现在新建菜单中的非实体文件)
  static const Set<String> _blacklistedExtensions = {
    '.library-ms',
    '.search-ms',
    '.searchconnector-ms',
    '.contact',
    '.desklink',
    '.mapimail',
    '.mydocs',
    '.zfsendtotarget',
    '.accountpicture-ms',
    '.settingcontent-ms',
  };

  /// 获取系统当前实际安装的所有新建模板项 (若未扫描则自动触发扫描)
  static Future<List<ShellNewItem>> getShellNewItems() async {
    if (_cachedShellNewItems != null && _cachedShellNewItems!.isNotEmpty) {
      return _cachedShellNewItems!;
    }

    try {
      _cachedShellNewItems = await compute(_scanShellNewWithRegistryPackage, null);
    } catch (e) {
      debugPrint('win32_registry 扫描 ShellNew 失败: $e');
      _cachedShellNewItems = _getFallbackItems();
    }

    return _cachedShellNewItems!;
  }

  /// 强制刷新重新扫描注册表
  static Future<List<ShellNewItem>> refreshShellNewItems() async {
    _cachedShellNewItems = null;
    return getShellNewItems();
  }

  /// 获取系统桌面空白处注册的第三方命令列表 (如 WebStorm, VS Code, Git 等)
  static Future<List<DesktopShellCommandItem>> getDesktopBackgroundCommands() async {
    if (_cachedDesktopCommands != null) {
      return _cachedDesktopCommands!;
    }

    try {
      _cachedDesktopCommands = await compute(_scanDesktopCommandsWithRegistryPackage, null);
    } catch (e) {
      debugPrint('win32_registry 扫描 DesktopCommands 失败: $e');
      _cachedDesktopCommands = [];
    }

    return _cachedDesktopCommands!;
  }

  /// 展开环境变量 (如 %SystemRoot% -> C:\Windows)
  static String expandEnvironmentVars(String input) {
    if (!input.contains('%')) return input;
    final srcPtr = input.toNativeUtf16();
    final dstBuf = malloc<Uint16>(1024).cast<Utf16>();
    try {
      final len = _expandEnvironmentStrings(srcPtr, dstBuf, 1024);
      if (len > 0) {
        return dstBuf.toDartString();
      }
    } catch (e) {
      // 忽略
    } finally {
      malloc.free(srcPtr);
      malloc.free(dstBuf);
    }
    return input;
  }

  /// 从 DLL 字符串表中精确读取资源字符串 (LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x22)
  static String? _loadStringFromDll(String dllPath, int resId) {
    final expandedPath = expandEnvironmentVars(dllPath);
    final pathPtr = expandedPath.toNativeUtf16();
    final hModule = _loadLibraryEx(pathPtr, 0, 0x00000022);
    malloc.free(pathPtr);

    if (hModule == 0) return null;

    final buffer = malloc<Uint16>(512).cast<Utf16>();
    try {
      final len = _loadString(hModule, resId, buffer, 512);
      if (len > 0) {
        return buffer.toDartString();
      }
    } catch (_) {
      return null;
    } finally {
      malloc.free(buffer);
      _freeLibrary(hModule);
    }
    return null;
  }

  /// 解析形如 @notepad.exe,-470 或 @C:\...\VSLauncherUI.dll,-1002 的 Win32 间接字符串资源为真实本地化文本
  static String resolveIndirectString(String raw, {String? extension}) {
    if (raw.isEmpty) return raw;
    final trimmed = raw.trim();

    // 1. 快速匹配已知系统字典 (不区分大小写)
    final lower = trimmed.toLowerCase();
    for (final entry in _knownIndirectStrings.entries) {
      if (lower == entry.key.toLowerCase() || lower.endsWith(entry.key.toLowerCase())) {
        return entry.value;
      }
    }

    if (!trimmed.startsWith('@')) {
      return trimmed;
    }

    final expanded = expandEnvironmentVars(trimmed);

    // 2. 尝试 Win32 SHLoadIndirectString 原生 API
    final srcPtr = expanded.toNativeUtf16();
    final outBuf = malloc<Uint16>(512).cast<Utf16>();
    try {
      final hr = _shLoadIndirectString(srcPtr, outBuf, 512, nullptr);
      if (hr == 0) {
        final str = outBuf.toDartString().trim();
        if (str.isNotEmpty && !str.startsWith('@')) {
          return str;
        }
      }
    } catch (_) {
      // 忽略
    } finally {
      malloc.free(srcPtr);
      malloc.free(outBuf);
    }

    // 3. 深度解析：直接调用 LoadLibraryExW + LoadStringW 提取 DLL 字符串表资源
    try {
      final atRemoved = expanded.substring(1);
      final lastComma = atRemoved.lastIndexOf(',');
      if (lastComma != -1) {
        final dllPart = atRemoved.substring(0, lastComma).trim();
        final idPart = atRemoved.substring(lastComma + 1).trim();
        final resId = int.tryParse(idPart.replaceAll('-', ''));
        if (resId != null && dllPart.isNotEmpty) {
          final loaded = _loadStringFromDll(dllPart, resId);
          if (loaded != null && loaded.isNotEmpty && !loaded.startsWith('@')) {
            return loaded;
          }
        }
      }
    } catch (_) {}

    // 4. 若解析失败且指定了扩展名，返回智能友好中文名称
    if (extension != null && extension.isNotEmpty) {
      return _getDefaultDisplayNameForExt(extension);
    }

    // 5. 绝对不向用户展示 @... 乱码路径
    final clean = trimmed.replaceFirst('@', '').split(',').first.split(Platform.pathSeparator).last;
    if (clean.toLowerCase().contains('vslauncherui')) return '使用 Visual Studio 打开';
    if (clean.toLowerCase().contains('wsl')) return '在 Linux (WSL) 中打开';
    return clean;
  }

  /// 使用 Dart 官方标准库 package:win32_registry 同步扫描 ShellNew 注册表
  static List<ShellNewItem> _scanShellNewWithRegistryPackage(dynamic _) {
    final results = <ShellNewItem>[];

    try {
      final hkcr = CLASSES_ROOT;
      final subkeys = hkcr.keys;

      for (final extKey in subkeys) {
        if (!extKey.startsWith('.')) continue;

        final extLower = extKey.toLowerCase();
        if (_blacklistedExtensions.contains(extLower)) continue;

        try {
          final items = _inspectExtWithRegistry(hkcr, extKey);
          if (items.isNotEmpty) {
            results.addAll(items);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('win32_registry 扫描根键异常: $e');
      return _getFallbackItems();
    }

    // 去重与合并
    final map = <String, ShellNewItem>{};
    for (final it in results) {
      final ext = it.extension.toLowerCase();
      if (_blacklistedExtensions.contains(ext)) continue;

      if (!map.containsKey(ext)) {
        map[ext] = it;
      } else {
        final existing = map[ext]!;
        if (existing.templateFileName == null && it.templateFileName != null) {
          map[ext] = it;
        } else if (existing.displayName.startsWith('.') && !it.displayName.startsWith('.')) {
          map[ext] = it;
        }
      }
    }

    final sortedList = map.values.toList();
    sortedList.sort((a, b) {
      final prioA = _getExtensionPriority(a.extension);
      final prioB = _getExtensionPriority(b.extension);
      if (prioA != prioB) return prioA.compareTo(prioB);
      return a.displayName.compareTo(b.displayName);
    });

    return sortedList.isEmpty ? _getFallbackItems() : sortedList;
  }

  /// 深度检查扩展名下的所有 ShellNew 注册
  static List<ShellNewItem> _inspectExtWithRegistry(BaseRegistryKey hkcr, String extKey) {
    final items = <ShellNewItem>[];

    // 1. 检查直接注册: .ext\ShellNew
    final directItem = _readShellNewItemFromKey(hkcr, extKey, '$extKey\\ShellNew');
    if (directItem != null) {
      items.add(directItem);
    }

    // 2. 打开 .ext 键并枚举其所有子键
    try {
      final extRegKey = hkcr.open(extKey);
      try {
        final childNames = extRegKey.keys;
        for (final child in childNames) {
          final childLower = child.toLowerCase();
          if (childLower == 'shellnew' ||
              childLower == 'openwithprogids' ||
              childLower == 'persistenthandler' ||
              childLower == 'shellex') {
            continue;
          }

          final childShellNewPath = '$extKey\\$child\\ShellNew';
          final childItem = _readShellNewItemFromKey(hkcr, extKey, childShellNewPath, progId: child);
          if (childItem != null) {
            items.add(childItem);
          }
        }
      } finally {
        extRegKey.close();
      }
    } catch (_) {}

    // 3. 检查 .ext 默认值关联的 ProgID
    final progId = _getRegistryStringValue(hkcr, extKey, '');
    if (progId != null && progId.isNotEmpty) {
      final progItem = _readShellNewItemFromKey(hkcr, extKey, '$progId\\ShellNew', progId: progId);
      if (progItem != null) {
        items.add(progItem);
      }
    }

    return items;
  }

  /// 从特定路径的 ShellNew 键中提取模板数据并构造 ShellNewItem
  static ShellNewItem? _readShellNewItemFromKey(
    BaseRegistryKey hkcr,
    String ext,
    String shellNewPath, {
    String? progId,
  }) {
    try {
      final snKey = hkcr.open(shellNewPath);
      try {
        final valNames = snKey.values.map((e) => e.name.toLowerCase()).toSet();
        final isNullFile = valNames.contains('nullfile');
        final fileName = _getRegistryStringValueDirect(snKey, 'FileName');
        final command = _getRegistryStringValueDirect(snKey, 'Command');
        final directory = _getRegistryStringValueDirect(snKey, 'Directory');
        final dataBytes = snKey.getBinary('Data')?.toList();

        final isValid = isNullFile ||
            (fileName != null && fileName.isNotEmpty) ||
            (command != null && command.isNotEmpty) ||
            (directory != null && directory.isNotEmpty) ||
            (dataBytes != null && dataBytes.isNotEmpty);

        if (!isValid) return null;

        // 获取友好名称
        String? friendlyName = _getRegistryStringValueDirect(snKey, 'ItemName');
        if (friendlyName != null && friendlyName.isNotEmpty) {
          friendlyName = resolveIndirectString(friendlyName, extension: ext);
        }

        if (friendlyName == null || friendlyName.isEmpty || friendlyName.startsWith('@')) {
          if (progId != null && progId.isNotEmpty) {
            final progFriendly = _getRegistryStringValue(hkcr, progId, 'FriendlyTypeName');
            if (progFriendly != null && progFriendly.isNotEmpty) {
              friendlyName = resolveIndirectString(progFriendly, extension: ext);
            }
            if (friendlyName == null || friendlyName.isEmpty || friendlyName.startsWith('@')) {
              friendlyName = _getRegistryStringValue(hkcr, progId, '');
            }
          }
        }

        if (friendlyName == null || friendlyName.isEmpty || friendlyName.startsWith('@')) {
          final extFriendly = _getRegistryStringValue(hkcr, ext, 'FriendlyTypeName');
          if (extFriendly != null && extFriendly.isNotEmpty) {
            friendlyName = resolveIndirectString(extFriendly, extension: ext);
          }
        }

        if (friendlyName == null || friendlyName.isEmpty || friendlyName.startsWith('@')) {
          friendlyName = _getDefaultDisplayNameForExt(ext);
        }

        return ShellNewItem(
          extension: ext,
          displayName: friendlyName,
          templateFileName: fileName,
          isNullFile: isNullFile,
          templateData: dataBytes,
        );
      } finally {
        snKey.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// 使用 package:win32_registry 扫描桌面背景第三方菜单项
  static List<DesktopShellCommandItem> _scanDesktopCommandsWithRegistryPackage(dynamic _) {
    final results = <DesktopShellCommandItem>[];
    final scannedKeys = <String>{};

    const targetPaths = [
      r'DesktopBackground\shell',
      r'Directory\Background\shell',
    ];

    // 过滤系统内部默认动作（避免与我们自定义的刷新、新建、终端等基础动作重复）
    const ignoredKeys = {'undo', 'redo', 'cmd', 'powershell', 'terminal', 'refresh', 'display', 'personalize'};

    for (final basePath in targetPaths) {
      try {
        final baseKey = CLASSES_ROOT.open(basePath);
        try {
          for (final subName in baseKey.keys) {
            final lowerSub = subName.toLowerCase();
            if (scannedKeys.contains(lowerSub)) continue;
            if (ignoredKeys.contains(lowerSub)) continue;

            try {
              final cmdKey = baseKey.open(subName);
              try {
                // 读取标题 (优先 MUIVerb，其次默认值，其次键名)
                String? title = _getRegistryStringValueDirect(cmdKey, 'MUIVerb');
                if (title != null && title.isNotEmpty) {
                  title = resolveIndirectString(title);
                }
                if (title == null || title.isEmpty || title.startsWith('@')) {
                  title = _getRegistryStringValueDirect(cmdKey, '');
                }
                if (title != null && title.isNotEmpty) {
                  title = resolveIndirectString(title);
                }
                if (title == null || title.isEmpty || title.startsWith('@')) {
                  title = subName;
                }

                // 移除 Windows 原生热键加速符 (如 (&V), &V, (&T))
                title = title
                    .replaceAll(RegExp(r'\(&[a-zA-Z0-9]\)'), '')
                    .replaceAll(RegExp(r'\([a-zA-Z0-9]\)'), '')
                    .replaceAll('&', '')
                    .trim();

                // 读取图标路径
                String? icon = _getRegistryStringValueDirect(cmdKey, 'Icon');

                // 读取实际执行命令行 (command 子键)
                String? commandLine;
                try {
                  final commandSubKey = cmdKey.open('command');
                  try {
                    commandLine = _getRegistryStringValueDirect(commandSubKey, '');
                  } finally {
                    commandSubKey.close();
                  }
                } catch (_) {}

                if (commandLine != null && commandLine.isNotEmpty) {
                  scannedKeys.add(lowerSub);
                  results.add(DesktopShellCommandItem(
                    key: subName,
                    title: title,
                    iconPath: icon,
                    commandLine: commandLine,
                  ));
                }
              } finally {
                cmdKey.close();
              }
            } catch (_) {}
          }
        } finally {
          baseKey.close();
        }
      } catch (_) {}
    }

    return results;
  }

  static String? _getRegistryStringValue(BaseRegistryKey parentKey, String subPath, String valueName) {
    try {
      final key = parentKey.open(subPath);
      try {
        return _getRegistryStringValueDirect(key, valueName);
      } finally {
        key.close();
      }
    } catch (_) {
      return null;
    }
  }

  static String? _getRegistryStringValueDirect(BaseRegistryKey key, String valueName) {
    try {
      final str = key.getString(valueName);
      if (str != null && str.isNotEmpty) return str.trim();
      return key.getUnexpandedString(valueName)?.trim();
    } catch (_) {
      return null;
    }
  }

  /// 扩展名排序优先级
  static int _getExtensionPriority(String ext) {
    switch (ext.toLowerCase()) {
      case '.txt':
        return 0;
      case '.docx':
      case '.doc':
        return 1;
      case '.xlsx':
      case '.xls':
        return 2;
      case '.pptx':
      case '.ppt':
        return 3;
      case '.accdb':
      case '.mdb':
        return 4;
      case '.odt':
      case '.sxd':
      case '.sxp':
      case '.odp':
      case '.ods':
        return 5;
      case '.pub':
        return 6;
      case '.py':
        return 7;
      case '.md':
        return 8;
      case '.rar':
      case '.zip':
      case '.7z':
        return 9;
      case '.rtf':
        return 10;
      case '.bmp':
      case '.png':
      case '.jpg':
        return 11;
      default:
        return 20;
    }
  }

  /// 默认标准纯正中文友好名称映射
  static String _getDefaultDisplayNameForExt(String ext) {
    switch (ext.toLowerCase()) {
      case '.txt':
        return '文本文档';
      case '.docx':
      case '.doc':
        return 'Microsoft Word 文档';
      case '.xlsx':
      case '.xls':
        return 'Microsoft Excel 工作表';
      case '.pptx':
      case '.ppt':
        return 'Microsoft PowerPoint 演示文稿';
      case '.accdb':
      case '.mdb':
        return 'Microsoft Access Database';
      case '.pub':
        return 'Microsoft Publisher Document';
      case '.odt':
        return 'OpenDocument 文本';
      case '.sxd':
        return 'Open Office 绘图';
      case '.sxp':
        return 'Open Office 演示文稿';
      case '.md':
        return 'Markdown 文档';
      case '.py':
        return 'Python 脚本';
      case '.zip':
        return 'ZIP 压缩文件';
      case '.rar':
        return 'WinRAR 压缩文件';
      case '.7z':
        return '7-Zip 压缩文件';
      case '.rtf':
        return '富文本文档';
      case '.bmp':
        return '位图图像';
      case '.lnk':
        return '快捷方式';
      default:
        return '$ext 文件';
    }
  }

  /// 兜底安全列表
  static List<ShellNewItem> _getFallbackItems() {
    return const [
      ShellNewItem(extension: '.txt', displayName: '文本文档', isNullFile: true),
      ShellNewItem(extension: '.docx', displayName: 'Microsoft Word 文档', isNullFile: true),
      ShellNewItem(extension: '.xlsx', displayName: 'Microsoft Excel 工作表', isNullFile: true),
      ShellNewItem(extension: '.pptx', displayName: 'Microsoft PowerPoint 演示文稿', isNullFile: true),
      ShellNewItem(extension: '.md', displayName: 'Markdown 文档', isNullFile: true),
      ShellNewItem(extension: '.zip', displayName: 'ZIP 压缩文件', isNullFile: true),
    ];
  }

  /// 根据 ShellNew 模板在目标目录动态创建文件 (成功返回创建的绝对路径，失败返回 null)
  static Future<String?> createNewFileFromTemplate({
    required String targetDirectory,
    required ShellNewItem item,
    String? customBaseName,
  }) async {
    try {
      final ext = item.extension.startsWith('.') ? item.extension : '.${item.extension}';
      String baseName = customBaseName?.trim() ?? '';
      if (baseName.isEmpty) {
        baseName = item.displayName.split('(').first.trim();
        if (!baseName.startsWith('新建')) {
          baseName = '新建 $baseName';
        }
      } else {
        if (baseName.toLowerCase().endsWith(ext.toLowerCase())) {
          baseName = baseName.substring(0, baseName.length - ext.length).trim();
        }
      }

      String targetPath = '$targetDirectory${Platform.pathSeparator}$baseName$ext';
      int count = 2;
      while (File(targetPath).existsSync() || Directory(targetPath).existsSync()) {
        targetPath = '$targetDirectory${Platform.pathSeparator}$baseName ($count)$ext';
        count++;
      }

      // 1. 如果有注册的模板文件名，依次在 Windows 标准模板目录中寻找并克隆
      if (item.templateFileName != null && item.templateFileName!.isNotEmpty) {
        final winDir = Platform.environment['WINDIR'] ?? r'C:\Windows';
        final appData = Platform.environment['APPDATA'] ?? '';
        final userProfile = Platform.environment['USERPROFILE'] ?? '';
        final programData = Platform.environment['ProgramData'] ?? r'C:\ProgramData';

        final candidatePaths = [
          '$winDir\\ShellNew\\${item.templateFileName}',
          if (appData.isNotEmpty) '$appData\\Microsoft\\Windows\\Templates\\${item.templateFileName}',
          if (programData.isNotEmpty) '$programData\\Microsoft\\Windows\\Templates\\${item.templateFileName}',
          if (userProfile.isNotEmpty) '$userProfile\\Templates\\${item.templateFileName}',
          item.templateFileName!,
        ];

        for (final candidate in candidatePaths) {
          final tf = File(candidate);
          if (tf.existsSync()) {
            await tf.copy(targetPath);
            return targetPath;
          }
        }
      }

      // 2. 如果包含二进制初始数据，直接写入文件
      if (item.templateData != null && item.templateData!.isNotEmpty) {
        final file = File(targetPath);
        await file.writeAsBytes(item.templateData!);
        return targetPath;
      }

      // 3. 否则创建空文件
      final file = File(targetPath);
      await file.create(recursive: true);
      return targetPath;
    } catch (e) {
      debugPrint('动态创建模板文件失败: $e');
      return null;
    }
  }
}
