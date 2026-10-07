import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../../logging/app_logger.dart';
import '../models/app_update_info.dart';
import '../utils/update_crypto_helper.dart';

/// 下载进度回调 (当前已下载字节数, 总字节数, 进度比例 0.0~1.0)
typedef OnDownloadProgress = void Function(int receivedBytes, int totalBytes, double progress);

/// 应用在线升级核心服务调度器 (单例)
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// 当前应用本地版本号 (编译期由 --dart-define-from-file=config/app_config.json 注入)
  static const String currentAppVersion = String.fromEnvironment('APP_VERSION');

  /// 当前应用本地构建号 (编译期由 --dart-define-from-file=config/app_config.json 注入)
  static const String _appBuildNumberStr = String.fromEnvironment('APP_BUILD_NUMBER');
  static int get currentAppBuildNumber => int.tryParse(_appBuildNumberStr) ?? 1;

  /// 官方升级检测静态地址 (编译期由 --dart-define-from-file=config/app_config.json 注入)
  static const String defaultUpdateCheckUrl = String.fromEnvironment('UPDATE_CHECK_URL');

  static const String _prefKeyAutoCheck = 'app_update_auto_check_enabled';

  HttpClient? _downloadClient;
  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _autoCheckUpdate = true;

  /// 用户是否开启了“启动时自动检查更新”
  bool get autoCheckUpdate => _autoCheckUpdate;

  /// 初始化服务并校验关键配置项
  Future<void> initialize() async {
    if (currentAppVersion.isEmpty) {
      AppLogger.e('⚠️ 关键编译期配置 APP_VERSION 为空！请确保构建/运行时传入了 --dart-define-from-file=config/app_config.json');
    }
    if (defaultUpdateCheckUrl.isEmpty) {
      AppLogger.e('⚠️ 关键编译期配置 UPDATE_CHECK_URL 为空！请确保构建/运行时传入了 --dart-define-from-file=config/app_config.json');
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      _autoCheckUpdate = prefs.getBool(_prefKeyAutoCheck) ?? true;
      AppLogger.i('AppUpdateService 初始化完成，当前版本: $currentAppVersion, 自动更新: $_autoCheckUpdate');
    } catch (e) {
      AppLogger.w('读取自动更新配置失败: $e');
    }
  }

  /// 设置并持久化用户偏好：是否自动检查更新
  Future<void> setAutoCheckUpdate(bool enabled) async {
    _autoCheckUpdate = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyAutoCheck, enabled);
      AppLogger.i('用户已更新自动检查更新设置为: $enabled');
    } catch (e) {
      AppLogger.e('持久化自动更新配置失败: $e');
    }
  }

  /// 启动时静默检查更新 (受用户开关控制)
  ///
  /// 若用户关闭了自动更新开关，则直接返回 null，不发起任何网络请求，彻底免打扰。
  Future<AppUpdateInfo?> silentlyCheckOnStartup() async {
    if (!_autoCheckUpdate) {
      AppLogger.i('用户已关闭自动更新检测，跳过启动静默检查');
      return null;
    }
    return checkForUpdate();
  }

  /// 检查是否有新版本可用
  ///
  /// [checkUrl] 升级元数据 JSON 请求地址
  /// [timeout] 网络请求超时时间，默认 8 秒
  /// 若无新版本或请求失败则返回 null
  Future<AppUpdateInfo?> checkForUpdate({
    String? checkUrl,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final targetUrl = checkUrl ?? defaultUpdateCheckUrl;
    if (targetUrl.isEmpty) {
      AppLogger.e('❌ 检查更新失败：UPDATE_CHECK_URL 为空，未正确定位更新源。请检查 config/app_config.json 是否已通过 --dart-define-from-file 传入。');
      return null;
    }
    if (currentAppVersion.isEmpty) {
      AppLogger.e('❌ 检查更新失败：APP_VERSION 为空，无法进行版本比对。请检查 config/app_config.json 是否已通过 --dart-define-from-file 传入。');
      return null;
    }

    HttpClient? client;
    try {
      AppLogger.i('正在检查在线新版本: $targetUrl (本地版本: $currentAppVersion)');
      final uri = Uri.parse(targetUrl);
      client = HttpClient()..connectionTimeout = timeout;
      final request = await client.getUrl(uri);
      final response = await request.close();

      if (response.statusCode == 200) {
        final bodyString = await response.transform(utf8.decoder).join();
        final decoded = json.decode(bodyString) as Map<String, dynamic>;
        final updateInfo = AppUpdateInfo.fromJson(decoded);

        final hasNew = AppUpdateInfo.hasNewVersion(
          currentVersion: currentAppVersion,
          remoteVersion: updateInfo.version,
          currentBuildCode: currentAppBuildNumber,
          remoteBuildCode: updateInfo.versionCode,
        );
        if (hasNew) {
          AppLogger.i('发现可用新版本: v${updateInfo.version}+${updateInfo.versionCode} (本地: v$currentAppVersion+$currentAppBuildNumber)');
          return updateInfo;
        } else {
          AppLogger.i('当前已是最新版本 (v$currentAppVersion+$currentAppBuildNumber)');
          return null;
        }
      } else {
        AppLogger.w('检查更新接口返回异常 HTTP 状态码: ${response.statusCode}');
        return null;
      }
    } catch (e, stack) {
      AppLogger.e('检查更新发生异常: $e', e, stack);
      return null;
    } finally {
      client?.close();
    }
  }

  /// 流式下载安装包并执行安全 SHA-256 校验
  ///
  /// [updateInfo] 目标版本信息
  /// [onProgress] 下载进度回调
  /// [savePath] 本地临时保存路径，默认保存在系统临时目录
  /// 返回下载完成且校验通过的本地 File 实例
  Future<File> downloadAndVerifyPackage(
    AppUpdateInfo updateInfo, {
    OnDownloadProgress? onProgress,
    String? savePath,
  }) async {
    if (_isDownloading) {
      throw StateError('当前已有下载任务正在执行');
    }

    _isDownloading = true;
    _downloadClient = HttpClient();

    try {
      final downloadUri = Uri.parse(updateInfo.downloadUrl);
      AppLogger.i('开始下载安装包: ${updateInfo.downloadUrl}');

      // 确定本地存储位置
      final targetPath = savePath ??
          '${Directory.systemTemp.path}\\桌面收纳盒_Setup_v${updateInfo.version}.exe';
      final targetFile = File(targetPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      final request = await _downloadClient!.getUrl(downloadUri);
      final response = await request.close();

      if (response.statusCode != 200) {
        throw HttpException('下载失败，HTTP 响应码: ${response.statusCode}', uri: downloadUri);
      }

      final totalBytes = response.contentLength;
      int receivedBytes = 0;

      final fileSink = targetFile.openWrite();

      await for (final chunk in response) {
        fileSink.add(chunk);
        receivedBytes += chunk.length;

        if (totalBytes > 0 && onProgress != null) {
          final progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
          onProgress(receivedBytes, totalBytes, progress);
        }
      }

      await fileSink.flush();
      await fileSink.close();

      AppLogger.i('安装包下载完成 (${targetFile.lengthSync()} 字节)，开始执行 SHA-256 安全校验...');

      // 2. 强安全指纹校验
      final isValid = await UpdateCryptoHelper.verifyFileIntegrity(targetFile, updateInfo.sha256);
      if (!isValid) {
        // 校验失败立即销毁可能被篡改的文件
        await targetFile.delete();
        AppLogger.e('安装包 SHA-256 校验失败！期望: ${updateInfo.sha256}');
        throw SecurityException('安装包完整性校验失败，文件可能已被篡改或下载损坏！');
      }

      AppLogger.i('✅ 安装包 SHA-256 安全校验通过！');
      return targetFile;
    } finally {
      _isDownloading = false;
      _downloadClient?.close();
      _downloadClient = null;
    }
  }

  /// 取消当前正在执行的下载任务
  void cancelDownload() {
    if (_isDownloading && _downloadClient != null) {
      _downloadClient?.close(force: true);
      _isDownloading = false;
      AppLogger.i('用户已主动取消安装包下载');
    }
  }

  /// 执行安装程序并优雅退出当前应用
  ///
  /// [installerFile] 已下载完成的安装包路径
  /// [silent] 是否采用静默/半静默覆盖安装 (Inno Setup /SILENT 参数)
  Future<void> launchInstallerAndExit(File installerFile, {bool silent = false}) async {
    if (!await installerFile.exists()) {
      throw FileNotFoundException('安装包文件未就绪: ${installerFile.path}');
    }

    AppLogger.i('正在启动安装程序并准备退出主应用: ${installerFile.path}');

    final arguments = <String>[];
    if (silent) {
      // Inno Setup 静默覆盖安装参数
      arguments.addAll(['/SILENT', '/NORESTART']);
    }

    // 采用非阻塞子进程方式拉起安装包
    await Process.start(installerFile.path, arguments, mode: ProcessStartMode.detached);

    // 优雅释放资源并退出当前进程，交由安装程序执行覆盖替换
    exit(0);
  }
}

/// 自定义安全校验异常
class SecurityException implements Exception {
  final String message;
  SecurityException(this.message);

  @override
  String toString() => 'SecurityException: $message';
}
