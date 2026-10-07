import 'package:flutter/gestures.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:window_manager/window_manager.dart';

/// Windows 原生 0 毫秒硬件级窗口拖拽区域
///
/// 核心原理与突破：
/// 1. 传统的 DragToMoveArea 基于 GestureDetector.onPanStart，Flutter 手势竞技场会强制等待
///    18 像素 (kTouchSlop / kPanSlop) 的位移仲裁阈值，导致鼠标拖动前 150ms 窗口完全静止，随后产生漂移突变。
/// 2. NativeDragArea 采用底层的 Listener.onPointerDown，在鼠标左键按下的瞬间 (0ms、0px 位移)，
///    立即向 Windows 发送 WM_NCLBUTTONDOWN (HTCAPTION) 消息。
/// 3. 在鼠标开始移动前，Windows 系统已完全接管原生 DWM 硬件级拖动循环，彻底消除一切跨线程与手势仲裁延迟。
class NativeDragArea extends StatelessWidget {
  final Widget child;

  const NativeDragArea({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind == PointerDeviceKind.mouse &&
            event.buttons == kPrimaryMouseButton) {
          windowManager.startDragging();
        }
      },
      child: child,
    );
  }
}

/// Windows 原生 0 毫秒 8 方向边缘/四角缩放拉伸区域
///
/// 避免 GestureDetector 的 18px 判定延迟，鼠标按下瞬间立即调用 Windows 原生 startResizing。
class NativeResizeArea extends StatelessWidget {
  final Widget child;
  final double edgeThickness;
  final double cornerSize;
  final bool enableTopResize;

  const NativeResizeArea({
    super.key,
    required this.child,
    this.edgeThickness = 4.0,
    this.cornerSize = 10.0,
    this.enableTopResize = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. 主体内容铺满
        Positioned.fill(child: child),

        // 2. 边缘与角落原生拉伸响应层 (严格使用 opaque 拦截，绝不与底层拖拽冲突)
        // 顶部边缘 (桌面抽屉标题栏默认全区域专供 0 延迟拖拽，避免顶部拉伸引发的坐标抖动)
        if (enableTopResize)
          Positioned(
            top: 0,
            left: cornerSize,
            right: cornerSize,
            height: edgeThickness,
            child: _buildEdge(ResizeEdge.top, SystemMouseCursors.resizeRow),
          ),
        // 底部边缘 (向下自由拉伸高度)
        Positioned(
          bottom: 0,
          left: cornerSize,
          right: cornerSize,
          height: edgeThickness,
          child: _buildEdge(ResizeEdge.bottom, SystemMouseCursors.resizeRow),
        ),
        // 左侧边缘 (向左自由拉伸宽度)
        Positioned(
          top: enableTopResize ? cornerSize : 0,
          bottom: cornerSize,
          left: 0,
          width: edgeThickness,
          child: _buildEdge(ResizeEdge.left, SystemMouseCursors.resizeColumn),
        ),
        // 右侧边缘 (向右自由拉伸宽度)
        Positioned(
          top: enableTopResize ? cornerSize : 0,
          bottom: cornerSize,
          right: 0,
          width: edgeThickness,
          child: _buildEdge(ResizeEdge.right, SystemMouseCursors.resizeColumn),
        ),

        // 3. 角落拉伸区
        if (enableTopResize) ...[
          // 左上角
          Positioned(
            top: 0,
            left: 0,
            width: cornerSize,
            height: cornerSize,
            child: _buildEdge(ResizeEdge.topLeft, SystemMouseCursors.resizeUpLeftDownRight),
          ),
          // 右上角
          Positioned(
            top: 0,
            right: 0,
            width: cornerSize,
            height: cornerSize,
            child: _buildEdge(ResizeEdge.topRight, SystemMouseCursors.resizeUpRightDownLeft),
          ),
        ],
        // 左下角
        Positioned(
          bottom: 0,
          left: 0,
          width: cornerSize,
          height: cornerSize,
          child: _buildEdge(ResizeEdge.bottomLeft, SystemMouseCursors.resizeUpRightDownLeft),
        ),
        // 右下角
        Positioned(
          bottom: 0,
          right: 0,
          width: cornerSize,
          height: cornerSize,
          child: _buildEdge(ResizeEdge.bottomRight, SystemMouseCursors.resizeUpLeftDownRight),
        ),
      ],
    );
  }

  Widget _buildEdge(ResizeEdge edge, MouseCursor cursor) {
    return MouseRegion(
      cursor: cursor,
      hitTestBehavior: HitTestBehavior.opaque,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse &&
              event.buttons == kPrimaryMouseButton) {
            windowManager.startResizing(edge);
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}

