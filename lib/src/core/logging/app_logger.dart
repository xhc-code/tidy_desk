import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import '../../utils/windows_shell_helper.dart';

/// 工业级本地文件持久化 LogOutput (结合 package:logger)
class _FileLogOutput extends LogOutput {
  final File file;
  late final IOSink _sink;

  _FileLogOutput(this.file) {
    _sink = file.openWrite(mode: FileMode.append);
  }

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      _sink.writeln(line);
      if (kDebugMode) {
        // ignore: avoid_print
        print(line);
      }
    }
  }

  @override
  Future<void> destroy() async {
    await _sink.flush();
    await _sink.close();
    await super.destroy();
  }
}

/// 简洁清晰的单行生产日志格式化器
class _CustomLogPrinter extends LogPrinter {
  @override
  List<String> log(LogEvent event) {
    final now = DateTime.now();
    final timeStr = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final levelStr = event.level.name.toUpperCase().padRight(7);
    final message = event.message.toString();
    final lines = <String>['[$timeStr] [$levelStr] $message'];

    if (event.error != null) {
      lines.add('  [Error Details]: ${event.error}');
    }
    if (event.stackTrace != null) {
      lines.add('  [Stack Trace]:\n${event.stackTrace}');
    }

    return lines;
  }
}

/// 全局应用日志管理诊断引擎 (基于 package:logger + 本地滚动持久化)
///
/// 核心职责：
/// 1. 【本地持久化】：将应用启动、环境指纹、各模块运行时状态与未捕获异常完整写入 `%APPDATA%\tidy_desk\logs\`。
/// 2. 【自动轮转清理】：按天分片归档，自动清理保留最近 7 天日志，杜绝膨胀占用磁盘。
/// 3. 【一键导出排障】：提供 `AppLogger.openLogDirectory()` 供用户随时打开日志目录提交排查。
class AppLogger {
  AppLogger._();

  static Logger? _logger;
  static String _logDirectoryPath = '';
  static String? _currentLogFilePath;

  /// 日志存储目录路径
  static String get logDirectoryPath => _logDirectoryPath;

  /// 当前生效的日志文件路径
  static String? get currentLogFilePath => _currentLogFilePath;

  /// 初始化日志框架 (在 main 最前置阶段同步/异步执行)
  static Future<void> initialize() async {
    try {
      // 1. 获取 Windows %APPDATA% 标准数据目录
      final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      final logDir = Directory('$appData\\tidy_desk\\logs');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      _logDirectoryPath = logDir.path;

      // 2. 自动清理超过 7 天的历史过期日志
      _cleanExpiredLogs(logDir);

      // 3. 构造当天的日志文件 (app_YYYY-MM-DD.log)
      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';
      final logFile = File('${logDir.path}\\app_$dateStr.log');
      _currentLogFilePath = logFile.path;

      // 4. 初始化 logger
      final fileOutput = _FileLogOutput(logFile);
      _logger = Logger(
        filter: ProductionFilter(),
        printer: _CustomLogPrinter(),
        output: fileOutput,
      );

      // 5. 打印系统启动环境指纹
      _logEnvironmentFingerprint();
    } catch (e) {
      debugPrint('初始化 AppLogger 异常: $e');
    }
  }

  /// 记录当前系统环境指纹信息
  static void _logEnvironmentFingerprint() {
    final osVersion = Platform.operatingSystemVersion;
    final dartVersion = Platform.version.split(' ').first;
    final localeName = Platform.localeName;
    final numProcessors = Platform.numberOfProcessors;

    i('==================== 应用程序启动 ====================');
    i('操作系统: $osVersion | CPU 核心: $numProcessors | 区域语言: $localeName');
    i('Dart 引擎版本: $dartVersion | 日志存储路径: $_currentLogFilePath');
    i('====================================================');
  }

  /// 自动清理超过 7 天的历史日志文件
  static void _cleanExpiredLogs(Directory dir) {
    try {
      final now = DateTime.now();
      final files = dir.listSync();
      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.log')) {
          final stat = entity.statSync();
          final diff = now.difference(stat.modified);
          if (diff.inDays > 7) {
            entity.deleteSync();
            debugPrint('已自动清理超过7天的历史日志: ${entity.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('清理过期日志失败: $e');
    }
  }

  /// 快速打开 Windows 资源管理器中的日志目录 (给用户提取排查)
  static void openLogDirectory() {
    if (_logDirectoryPath.isNotEmpty) {
      final dir = Directory(_logDirectoryPath);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final success = WindowsShellHelper.openPath(_logDirectoryPath);
      if (!success) {
        Process.start('explorer.exe', [_logDirectoryPath], mode: ProcessStartMode.detached);
      }
    }
  }

  // -------------------------------------------------------------
  // 核心日志输出接口
  // -------------------------------------------------------------

  /// 调试日志 (Verbose / Debug)
  static void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.d(message, error: error, stackTrace: stackTrace);
  }

  /// 信息日志 (Info)
  static void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.i(message, error: error, stackTrace: stackTrace);
  }

  /// 警告日志 (Warning)
  static void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.w(message, error: error, stackTrace: stackTrace);
  }

  /// 错误日志 (Error / Crash)
  static void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.e(message, error: error, stackTrace: stackTrace);
  }

  /// 致命严重崩溃 (Fatal)
  static void fatal(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger?.f(message, error: error, stackTrace: stackTrace);
  }
}
