// lib/widgets/attachment_panel.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../design/tokens.dart';
import '../util/mime.dart';

class AttachmentPanel extends ConsumerStatefulWidget {
  final VoidCallback? onClose;
  final void Function(File file)? onPickImage;
  final void Function(File file, String filename, String mime)? onPickFile;

  const AttachmentPanel({super.key, this.onClose, this.onPickImage, this.onPickFile});

  @override
  ConsumerState<AttachmentPanel> createState() => _AttachmentPanelState();
}

class _AttachmentPanelState extends ConsumerState<AttachmentPanel> {
  final _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = AppColors.of(context);
    final bg = c.surface;
    final labelColor = c.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Option(
                    icon: Icons.camera_alt_rounded,
                    label: '拍照',
                    tint: const Color(0xFF6D5DF0),
                    labelColor: labelColor,
                    isDark: isDark,
                    onTap: () => _capture(ImageSource.camera),
                  ),
                  _Option(
                    icon: Icons.photo_library_rounded,
                    label: '相册',
                    tint: const Color(0xFF16A37F),
                    labelColor: labelColor,
                    isDark: isDark,
                    onTap: () => _capture(ImageSource.gallery),
                  ),
                  _Option(
                    icon: Icons.insert_drive_file_rounded,
                    label: '文件',
                    tint: const Color(0xFFE58A12),
                    labelColor: labelColor,
                    isDark: isDark,
                    onTap: () => _pickFile(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _capture(ImageSource source) async {
    try {
      if (source == ImageSource.camera) {
        final status = await Permission.camera.request();
        if (!status.isGranted) {
          if (mounted) _showError('相机权限未授予');
          return;
        }
      }
      final XFile? xfile = await _picker.pickImage(source: source, imageQuality: 85);
      if (xfile == null) return;
      widget.onClose?.call();
      widget.onPickImage?.call(File(xfile.path));
    } catch (e) {
      if (mounted) _showError('拍照失败: $e');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result == null || result.files.isEmpty) return;
      final file = File(result.files.single.path!);
      final filename = result.files.single.name;
      // 按原始文件名推断：picker 的缓存临时路径可能不带扩展名
      final mime = mimeForExtension(filename);
      widget.onClose?.call();
      widget.onPickFile?.call(file, filename, mime);
    } catch (e) {
      if (mounted) _showError('选择文件失败: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)));
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color tint;
  final Color labelColor;
  final bool isDark;
  final VoidCallback onTap;

  const _Option({
    required this.icon,
    required this.label,
    required this.tint,
    required this.labelColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 三个入口各用一个柔和的语义色（同明度、低饱和底），一眼可分又不花哨。
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 76,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58, height: 58,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: isDark ? 0.20 : 0.11),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: tint, size: 26),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: labelColor, fontSize: 12, fontWeight: FontWeight.w500), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
