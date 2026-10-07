/// 应用在线版本更新信息模型
///
/// 对应服务器静态 `version.json` 的标准数据结构：
/// ```json
/// {
///   "version": "1.0.1",
///   "versionCode": 2,
///   "minSupportVersion": "1.0.0",
///   "releaseDate": "2026-10-01",
///   "title": "v1.0.1 性能与体验优化发布",
///   "changelog": ["1. 优化流畅度", "2. 修复已知问题"],
///   "downloadUrl": "https://github.com/xhc-code/tidy_desk/releases/download/v1.0.1/TidyDesk_Setup_v1.0.1.exe",
///   "sha256": "8f481c4e908f4c022dd7ef03197609a0a1ee085352c6f14068565b9fc078e38d",
///   "forceUpdate": false
/// }
/// ```
class AppUpdateInfo {
  /// 目标发布版本号 (必填，语义化三段式，例如 "1.0.1")
  final String version;

  /// 数字构建序号 (可选，递增整数，例如 2)
  final int versionCode;

  /// 最低支持版本 (可选，低于此版本的客户端强制要求升级，例如 "1.0.0")
  final String minSupportVersion;

  /// 发版日期 (可选，展示于弹窗右上角，例如 "2026-10-01")
  final String releaseDate;

  /// 更新弹窗主标题 (必填，例如 "v1.0.1 性能与体验优化发布")
  final String title;

  /// 更新日志条目列表 (必填，在弹窗中按行呈现)
  final List<String> changelog;

  /// 新版安装包下载直链 (必填，以 https 开头)
  final String downloadUrl;

  /// 安装包 SHA-256 安全哈希校验码 (必填，64位小写十六进制字符串)
  ///
  /// 客户端下载后自动计算本地文件哈希并比对，若不匹配则立即物理销毁文件，彻底防止网络劫持或包损坏。
  final String sha256;

  /// 是否为强制更新 (必填，若为 true 则弹窗隐藏“稍后再说”和关闭按钮)
  final bool forceUpdate;

  const AppUpdateInfo({
    required this.version,
    required this.versionCode,
    required this.minSupportVersion,
    required this.releaseDate,
    required this.title,
    required this.changelog,
    required this.downloadUrl,
    required this.sha256,
    required this.forceUpdate,
  });

  /// 从 JSON Map 解析并填充默认安全回退值
  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      version: json['version'] as String? ?? '1.0.0',
      versionCode: (json['versionCode'] as num?)?.toInt() ?? 1,
      minSupportVersion: json['minSupportVersion'] as String? ?? '1.0.0',
      releaseDate: json['releaseDate'] as String? ?? '',
      title: json['title'] as String? ?? '发现新版本',
      changelog: (json['changelog'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      forceUpdate: json['forceUpdate'] as bool? ?? false,
    );
  }

  /// 转换为结构化 JSON Map
  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'versionCode': versionCode,
      'minSupportVersion': minSupportVersion,
      'releaseDate': releaseDate,
      'title': title,
      'changelog': changelog,
      'downloadUrl': downloadUrl,
      'sha256': sha256,
      'forceUpdate': forceUpdate,
    };
  }

  /// 语义化版本比对核心算法 (SemVer + 构建号双重比较)
  ///
  /// 比对规则：
  /// 1. 过滤版本字符串中的 'v'、'V' 前缀与 '+构建号' 附加段；
  /// 2. 按照点号 '.' 切分为整数数组 (如 "1.0.1" -> [1, 0, 1])；
  /// 3. 从左往右逐位比对数值大小：
  ///    - 若 remote[i] > current[i]，立即判定为【有新版本】返回 true；
  ///    - 若 remote[i] < current[i]，立即判定为【无新版本】返回 false；
  ///    - 若相等则继续往右比对下一位；
  /// 4. 若主版本号完全一致，且提供了构建号，则比对构建号：
  ///    - 若 remoteBuildCode > currentBuildCode，判定为【发现构建号更新】返回 true；
  /// 5. 全部比对完毕依然相等则返回 false。
  static bool hasNewVersion({
    required String currentVersion,
    required String remoteVersion,
    int currentBuildCode = 0,
    int remoteBuildCode = 0,
  }) {
    final curParts = _parseVersion(currentVersion);
    final remParts = _parseVersion(remoteVersion);

    final maxLength =
        curParts.length > remParts.length ? curParts.length : remParts.length;
    for (var i = 0; i < maxLength; i++) {
      final curVal = i < curParts.length ? curParts[i] : 0;
      final remVal = i < remParts.length ? remParts[i] : 0;
      if (remVal > curVal) return true;
      if (remVal < curVal) return false;
    }

    // 主版本完全相等时，比对递增构建号 (例如 1.0.0+3 vs 1.0.0+4)
    if (remoteBuildCode > currentBuildCode && currentBuildCode > 0) {
      return true;
    }

    return false;
  }

  /// 清洗并解析版本字符串为数值序列
  static List<int> _parseVersion(String versionStr) {
    var cleanStr = versionStr.toLowerCase().replaceAll('v', '').trim();
    if (cleanStr.contains('+')) {
      cleanStr = cleanStr.split('+').first;
    }
    return cleanStr
        .split('.')
        .map((part) => int.tryParse(part) ?? 0)
        .toList();
  }
}
