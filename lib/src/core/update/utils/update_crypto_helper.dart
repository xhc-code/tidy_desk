import 'dart:io';
import 'package:crypto/crypto.dart';

/// 工业级安装包安全指纹与校验工具类 (可通用复用)
class UpdateCryptoHelper {
  UpdateCryptoHelper._();

  /// 针对本地文件进行流式 SHA-256 哈希计算
  ///
  /// 采用流式读取 (Chunked Streaming)，即使几十兆/上百兆的大型安装包也不会撑爆应用内存。
  static Future<String> calculateFileSha256(File file) async {
    if (!await file.exists()) {
      throw FileNotFoundException('目标文件不存在: ${file.path}');
    }

    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// 校验本地文件指纹是否与服务端预期 SHA-256 完全匹配
  ///
  /// [file] 下载完成的本地文件
  /// [expectedSha256] 期望的哈希值 (不区分大小写，自动修剪空格)
  /// 返回 true 表示校验通过，false 表示文件已被损坏或篡改
  static Future<bool> verifyFileIntegrity(File file, String expectedSha256) async {
    if (expectedSha256.trim().isEmpty) {
      // 若服务端未配置 hash 则跳过强校验
      return true;
    }

    try {
      final actualSha256 = await calculateFileSha256(file);
      return actualSha256.toLowerCase().trim() == expectedSha256.toLowerCase().trim();
    } catch (_) {
      return false;
    }
  }
}

/// 自定义文件未找到异常
class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);

  @override
  String toString() => 'FileNotFoundException: $message';
}
