import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Shared image-upload widget used by every admin form that accepts a photo
/// (menu items, vendors, advertisements).
///
/// The widget handles the full lifecycle:
///   1. Tap → `image_picker` opens the gallery.
///   2. Bytes are processed (resize + optional center-crop).
///   3. `uploadFn` is called; a progress overlay shows while it runs.
///   4. On success the preview updates and `onChanged` is called with the URL.
///   5. On failure a red error strip appears with a Retry button.
///   6. A "Remove" button clears the image and calls `onChanged(null)`.
///
/// **[cropToSquare]** — `true` for food/vendor photos (auto center-crops
/// to 1:1 before upload).  `false` for ad banners (preserves aspect ratio).
///
/// **[hint]** — shown beneath the picker area; use it for size/crop guidance.
class ImageUploadField extends StatefulWidget {
  const ImageUploadField({
    super.key,
    this.initialUrl,
    required this.uploadFn,
    this.onChanged,
    this.cropToSquare = false,
    this.hint,
  });

  /// URL of the image already stored (e.g. when editing an existing record).
  final String? initialUrl;

  /// Called with the processed bytes and a generated file name.
  /// Must return the public URL of the uploaded file.
  final Future<String> Function(Uint8List bytes, String fileName) uploadFn;

  /// Called with the new URL after a successful upload, or `null` after removal.
  final ValueChanged<String?>? onChanged;

  /// When `true` the image is center-cropped to a 1:1 square before upload.
  final bool cropToSquare;

  /// Optional hint text shown beneath the picker area.
  final String? hint;

  @override
  State<ImageUploadField> createState() => _ImageUploadFieldState();
}

class _ImageUploadFieldState extends State<ImageUploadField> {
  /// URL currently being displayed (network or just uploaded).
  String? _url;

  /// Bytes of the pending image (before or during upload — kept so the
  /// preview shows the chosen photo immediately, without waiting for upload).
  Uint8List? _previewBytes;

  bool _isUploading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _url = widget.initialUrl;
  }

  Future<void> _pick() async {
    setState(() {
      _errorMessage = null;
    });

    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      // Pick at the original resolution; we do our own resize below so we
      // get predictable results rather than relying on the picker's downscale.
    );
    if (file == null) return;

    final raw = await file.readAsBytes();

    // Process on a separate isolate-free path — synchronous but fast enough
    // for the sizes we're working with (phone photos are at most a few MB).
    final processed = await _processImage(raw, file.name);
    if (processed == null) {
      if (mounted) {
        setState(() => _errorMessage = 'Could not read the image. Try another.');
      }
      return;
    }

    // Show the preview immediately (before upload finishes).
    setState(() {
      _previewBytes = processed.bytes;
      _isUploading = true;
    });

    await _upload(processed.bytes, processed.fileName);
  }

  Future<_ProcessedImage?> _processImage(
      Uint8List raw, String originalName) async {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return null;

      img.Image processed;

      if (widget.cropToSquare) {
        // Center-crop to the shorter dimension, then resize to 1200×1200.
        final size = min(decoded.width, decoded.height);
        final x = (decoded.width - size) ~/ 2;
        final y = (decoded.height - size) ~/ 2;
        final cropped = img.copyCrop(decoded, x: x, y: y, width: size, height: size);
        processed = img.copyResize(cropped,
            width: 1200, height: 1200, interpolation: img.Interpolation.linear);
      } else {
        // Preserve aspect ratio; cap the longer side at 1200 px.
        final longerSide = max(decoded.width, decoded.height);
        if (longerSide > 1200) {
          if (decoded.width >= decoded.height) {
            processed = img.copyResize(decoded,
                width: 1200, interpolation: img.Interpolation.linear);
          } else {
            processed = img.copyResize(decoded,
                height: 1200, interpolation: img.Interpolation.linear);
          }
        } else {
          processed = decoded;
        }
      }

      final jpegBytes =
          Uint8List.fromList(img.encodeJpg(processed, quality: 80));
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${_stem(originalName)}.jpg';

      return _ProcessedImage(bytes: jpegBytes, fileName: fileName);
    } catch (_) {
      return null;
    }
  }

  Future<void> _upload(Uint8List bytes, String fileName) async {
    try {
      final url = await widget.uploadFn(bytes, fileName);
      if (!mounted) return;
      setState(() {
        _url = url;
        _previewBytes = null; // switch to network image
        _isUploading = false;
        _errorMessage = null;
      });
      widget.onChanged?.call(url);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _errorMessage = 'Upload failed. Check your connection and try again.';
      });
    }
  }

  Future<void> _retryUpload() async {
    if (_previewBytes == null) return;
    setState(() {
      _isUploading = true;
      _errorMessage = null;
    });
    await _upload(_previewBytes!, '${DateTime.now().millisecondsSinceEpoch}_retry.jpg');
  }

  void _remove() {
    setState(() {
      _url = null;
      _previewBytes = null;
      _errorMessage = null;
    });
    widget.onChanged?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasImage = _previewBytes != null || (_url != null && _url!.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Preview / picker area ────────────────────────────────────
        GestureDetector(
          onTap: _isUploading ? null : _pick,
          child: Container(
            height: 148,
            width: double.infinity,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(
                color: _errorMessage != null
                    ? AppColors.error
                    : theme.dividerColor,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Image content
                if (_previewBytes != null)
                  Image.memory(_previewBytes!, fit: BoxFit.cover)
                else if (_url != null && _url!.isNotEmpty)
                  Image.network(
                    _url!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _Placeholder(theme: theme),
                  )
                else
                  _Placeholder(theme: theme),

                // Upload progress overlay
                if (_isUploading)
                  ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Error strip ───────────────────────────────────────────────
        if (_errorMessage != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.error),
                ),
              ),
              TextButton(
                onPressed: _retryUpload,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                  minimumSize: Size.zero,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ],

        // ── Action row ────────────────────────────────────────────────
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: _isUploading ? null : _pick,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(hasImage ? 'Change photo' : 'Choose photo'),
            ),
            if (hasImage) ...[
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: _isUploading ? null : _remove,
                child: Text(
                  'Remove',
                  style: TextStyle(color: AppColors.error),
                ),
              ),
            ],
          ],
        ),

        // ── Hint ─────────────────────────────────────────────────────
        if (widget.hint != null) ...[
          const SizedBox(height: 4),
          Text(
            widget.hint!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_photo_alternate_outlined,
          size: 32,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap to add photo',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.35),
          ),
        ),
      ],
    );
  }
}

/// Stem of a file name without extension, clamped to 32 chars.
String _stem(String fileName) {
  final dot = fileName.lastIndexOf('.');
  final name = dot > 0 ? fileName.substring(0, dot) : fileName;
  return name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_').substring(
        0,
        name.length.clamp(0, 32),
      );
}

class _ProcessedImage {
  const _ProcessedImage({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;
}
