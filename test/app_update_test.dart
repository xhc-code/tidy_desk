import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:tidy_desk/src/core/update/models/app_update_info.dart';
import 'package:tidy_desk/src/core/update/utils/update_crypto_helper.dart';

void main() {
  group('AppUpdateInfo 语义化版本比对测试', () {
    test('正确识别更高的小版本与补丁版本', () {
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '1.0.0', remoteVersion: '1.0.1'), isTrue);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '1.0.0', remoteVersion: '1.1.0'), isTrue);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '1.0.0', remoteVersion: '2.0.0'), isTrue);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '1.0.9', remoteVersion: '1.1.0'), isTrue);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: 'v1.0.0+1', remoteVersion: '1.0.1'), isTrue);
    });

    test('版本号相同时，能够识别构建号 (+3 -> +4) 递增触发更新', () {
      expect(
        AppUpdateInfo.hasNewVersion(
          currentVersion: '1.0.0',
          remoteVersion: '1.0.0',
          currentBuildCode: 3,
          remoteBuildCode: 4,
        ),
        isTrue,
      );
      expect(
        AppUpdateInfo.hasNewVersion(
          currentVersion: '1.0.0',
          remoteVersion: '1.0.0',
          currentBuildCode: 3,
          remoteBuildCode: 3,
        ),
        isFalse,
      );
    });

    test('正确识别相同版本或更低版本不触发更新', () {
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '1.0.0', remoteVersion: '1.0.0'), isFalse);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '1.0.1', remoteVersion: '1.0.0'), isFalse);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: '2.0.0', remoteVersion: '1.9.9'), isFalse);
      expect(AppUpdateInfo.hasNewVersion(currentVersion: 'v1.0.0', remoteVersion: '1.0.0'), isFalse);
    });

    test('从 JSON 正确反序列化', () {
      final json = {
        'version': '1.0.1',
        'versionCode': 2,
        'minSupportVersion': '1.0.0',
        'releaseDate': '2026-10-01',
        'title': 'v1.0.1 优化发布',
        'changelog': ['1. 优化流畅度', '2. 修复已知问题'],
        'downloadUrl': 'https://example.com/download/update.exe',
        'sha256': 'abcdef123456',
        'forceUpdate': false,
      };

      final info = AppUpdateInfo.fromJson(json);
      expect(info.version, '1.0.1');
      expect(info.changelog.length, 2);
      expect(info.downloadUrl, 'https://example.com/download/update.exe');
      expect(info.sha256, 'abcdef123456');
    });
  });

  group('UpdateCryptoHelper 安全哈希校验测试', () {
    test('正确计算临时文件的 SHA-256 并验证指纹', () async {
      final tempFile = File('${Directory.systemTemp.path}/test_hash.txt');
      await tempFile.writeAsString('TidyDeskSecurityTest2026');

      final hash = await UpdateCryptoHelper.calculateFileSha256(tempFile);
      expect(hash, isNotEmpty);

      // 验证相同哈希通过
      final isMatch = await UpdateCryptoHelper.verifyFileIntegrity(tempFile, hash);
      expect(isMatch, isTrue);

      // 验证被篡改的哈希被拒绝
      final isTampered = await UpdateCryptoHelper.verifyFileIntegrity(tempFile, 'wrong_hash_code');
      expect(isTampered, isFalse);

      await tempFile.delete();
    });
  });
}
