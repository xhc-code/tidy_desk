import 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import '../../../../core/update/models/app_update_info.dart';
import '../../../../core/update/services/app_update_service.dart';

/// Fluent UI 现代风格在线更新交互对话框
class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
  });

  /// 便捷展示更新弹窗
  static Future<void> show(BuildContext context, AppUpdateInfo updateInfo) async {
    await showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      builder: (context) => AppUpdateDialog(updateInfo: updateInfo),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  bool _isReadyToInstall = false;
  File? _downloadedInstallerFile;
  double _progress = 0.0;
  String _progressText = '';
  String? _errorMessage;

  @override
  void dispose() {
    if (_isDownloading) {
      AppUpdateService.instance.cancelDownload();
    }
    super.dispose();
  }

  /// 开始流式下载并校验
  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _isReadyToInstall = false;
      _errorMessage = null;
      _progress = 0.0;
      _progressText = '准备连接服务器...';
    });

    try {
      final installerFile = await AppUpdateService.instance.downloadAndVerifyPackage(
        widget.updateInfo,
        onProgress: (received, total, progress) {
          if (mounted) {
            final receivedMB = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMB = total > 0 ? (total / (1024 * 1024)).toStringAsFixed(1) : '?';
            setState(() {
              _progress = progress;
              _progressText = '$receivedMB MB / $totalMB MB (${(progress * 100).toInt()}%)';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isDownloading = false;
        _isReadyToInstall = true;
        _downloadedInstallerFile = installerFile;
        _progressText = '安全校验通过，安装包已准备就绪！';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isReadyToInstall = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  /// 确认立即重启并执行安装
  Future<void> _restartAndInstall() async {
    if (_downloadedInstallerFile == null) return;
    await AppUpdateService.instance.launchInstallerAndExit(
      _downloadedInstallerFile!,
      silent: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return ContentDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isReadyToInstall
                  ? Colors.green.withValues(alpha: 0.15)
                  : theme.accentColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isReadyToInstall ? FluentIcons.check_mark : FluentIcons.cloud_download,
              color: _isReadyToInstall ? Colors.green : theme.accentColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isReadyToInstall ? '新版本就绪，是否立即重启升级？' : widget.updateInfo.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '最新版本: v${widget.updateInfo.version} · 发布日期: ${widget.updateInfo.releaseDate}',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.resources.textFillColorSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            if (!_isReadyToInstall) ...[
              const Text(
                '更新内容与优化日志：',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.resources.cardBackgroundFillColorDefault,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.resources.cardStrokeColorDefault,
                    ),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.updateInfo.changelog.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      return Text(
                        widget.updateInfo.changelog[index],
                        style: const TextStyle(fontSize: 12.5, height: 1.4),
                      );
                    },
                  ),
                ),
              ),
            ] else ...[
              // 下载完成就绪提示卡片
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.resources.cardBackgroundFillColorDefault,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.resources.cardStrokeColorDefault),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(FluentIcons.info, color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '更新说明与保障',
                          style: TextStyle(fontWeight: FontWeight.bold, color: theme.accentColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 点击【立即重启并安装】：程序将优雅保存状态并关闭，后台自动覆盖升级并重新打开；\n'
                      '• 点击【稍后再说】：本次已下载安装包保留在本地，不打扰您当前的工作。',
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              ProgressBar(value: _progress * 100),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progressText,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.resources.textFillColorSecondary,
                    ),
                  ),
                  Button(
                    onPressed: () {
                      AppUpdateService.instance.cancelDownload();
                      setState(() {
                        _isDownloading = false;
                        _progressText = '已取消下载';
                      });
                    },
                    child: const Text('取消下载'),
                  ),
                ],
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              InfoBar(
                title: const Text('更新失败'),
                content: Text(_errorMessage!),
                severity: InfoBarSeverity.error,
              ),
            ],
          ],
        ),
      ),
      actions: _buildActions(context),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (_isDownloading) {
      return [];
    }

    if (_isReadyToInstall) {
      return [
        if (!widget.updateInfo.forceUpdate)
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('稍后再说'),
          ),
        FilledButton(
          onPressed: _restartAndInstall,
          child: const Text('立即重启并安装'),
        ),
      ];
    }

    return [
      if (!widget.updateInfo.forceUpdate)
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后再说'),
        ),
      FilledButton(
        onPressed: _startDownload,
        child: const Text('开始下载新版本'),
      ),
    ];
  }
}
