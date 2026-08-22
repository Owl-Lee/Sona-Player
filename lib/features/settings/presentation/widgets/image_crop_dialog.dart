import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/sona_localizations.dart';
import '../../../../core/theme/app_theme.dart';

class ImageCropDialog extends StatefulWidget {
  const ImageCropDialog({
    super.key,
    required this.imageBytes,
    required this.aspectRatio,
    required this.title,
    required this.hint,
  });

  final Uint8List imageBytes;
  final double aspectRatio;
  final String title;
  final String hint;

  static Future<Uint8List?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required double aspectRatio,
    String? title,
    String? hint,
  }) {
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ImageCropDialog(
        imageBytes: imageBytes,
        aspectRatio: aspectRatio,
        title: title ?? context.tr('裁切图片'),
        hint: hint ?? context.tr('拖动图片调整位置，双指或滚轮缩放'),
      ),
    );
  }

  @override
  State<ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<ImageCropDialog> {
  final _controller = CropController();
  var _cropping = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 920,
          maxHeight: screen.height * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.hint,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _cropping
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ColoredBox(
                    color: const Color(0xFF171A22),
                    child: Crop(
                      image: widget.imageBytes,
                      controller: _controller,
                      aspectRatio: widget.aspectRatio,
                      initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                        size: 0.86,
                        aspectRatio: widget.aspectRatio,
                      ),
                      interactive: true,
                      fixCropRect: true,
                      baseColor: const Color(0xFF171A22),
                      maskColor: Colors.black.withValues(alpha: 0.54),
                      cornerDotBuilder: (size, edgeAlignment) =>
                          const DotControl(color: Colors.white),
                      onCropped: (result) {
                        if (!mounted) return;
                        switch (result) {
                          case CropSuccess(:final croppedImage):
                            Navigator.of(context).pop(croppedImage);
                          case CropFailure(:final cause):
                            setState(() {
                              _cropping = false;
                              _error = context
                                  .tr('裁切失败：{cause}')
                                  .replaceAll('{cause}', '$cause');
                            });
                        }
                      },
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.aspect_ratio_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      context
                          .tr('已锁定当前播放器比例 {ratio} : 1')
                          .replaceAll(
                            '{ratio}',
                            widget.aspectRatio.toStringAsFixed(2),
                          ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _cropping
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(context.tr('取消')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _cropping
                        ? null
                        : () {
                            setState(() {
                              _cropping = true;
                              _error = null;
                            });
                            _controller.crop();
                          },
                    icon: _cropping
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(context.tr(_cropping ? '处理中' : '使用这一区域')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
