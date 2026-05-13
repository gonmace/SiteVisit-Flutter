import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../config/app_theme.dart';
import '../services/camera_service.dart';
import '../services/watermark_service.dart';

class PhotoTile extends StatefulWidget {
  final String label;
  final String description;
  final File? fullFile;
  final File? thumbFile;
  final bool required;
  final bool uploading;
  final void Function(File full, File thumb, double? lat, double? lon) onFileCaptured;
  final Color? descriptionColor;

  const PhotoTile({
    super.key,
    required this.label,
    required this.description,
    required this.fullFile,
    required this.thumbFile,
    required this.required,
    required this.uploading,
    required this.onFileCaptured,
    this.descriptionColor,
  });

  @override
  State<PhotoTile> createState() => _PhotoTileState();
}

class _PhotoTileState extends State<PhotoTile> {
  bool _processing = false;

  Future<Position?> _getPos() async {
    try {
      final fresh = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 5));
      return fresh;
    } catch (_) {}
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {}
    return null;
  }

  Future<void> _capture() async {
    if (_processing || widget.uploading) return;
    final cameraSvc = context.read<CameraService>();
    final wmSvc     = context.read<WatermarkService>();
    final raw = await cameraSvc.capturePhoto();
    if (raw == null || !mounted) return;
    setState(() => _processing = true);
    try {
      final pos = await _getPos();
      final wm  = await wmSvc.applyWatermark(
        raw,
        pos?.latitude,
        pos?.longitude,
      );
      if (mounted) {
        widget.onFileCaptured(wm.full, wm.thumb, pos?.latitude, pos?.longitude);
      }
    } catch (_) {
      // Watermark falló — usar raw como full y thumb (mejor que perder la foto)
      if (mounted) widget.onFileCaptured(raw, raw, null, null);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  bool get _busy => _processing || widget.uploading;

  @override
  Widget build(BuildContext context) {
    final taken = widget.fullFile != null;
    return Material(
      color: AppTheme.surf(context),
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.03),
      child: InkWell(
        onTap: _busy ? null : _capture,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: taken
                  ? AppTheme.success.withValues(alpha: 0.4)
                  : AppTheme.sep(context),
            ),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: _busy
                    ? Container(
                        width: 52,
                        height: 52,
                        color: AppTheme.surfSec(context),
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    : taken
                        ? Image.file(
                            widget.thumbFile ?? widget.fullFile!,
                            width: 52,
                            height: 52,
                            fit: BoxFit.cover,
                            cacheWidth: 104,
                            cacheHeight: 104,
                            gaplessPlayback: true,
                          )
                        : Container(
                            width: 52,
                            height: 52,
                            color: AppTheme.surfSec(context),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.grey,
                              size: 24,
                            ),
                          ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          widget.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        if (widget.required)
                          Text(
                            ' *',
                            style: TextStyle(
                                color: AppTheme.error,
                                fontWeight: FontWeight.w700),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _processing
                          ? 'Procesando imagen…'
                          : widget.uploading
                              ? 'Subiendo foto…'
                              : taken
                                  ? 'Imagen capturada — toca para retomar'
                                  : widget.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: _busy
                            ? Colors.grey
                            : taken
                                ? AppTheme.success
                                : widget.descriptionColor ?? AppTheme.info,
                      ),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(width: 22)
              else
                Icon(
                  taken ? Icons.check_circle : Icons.camera_alt_outlined,
                  color: taken ? AppTheme.success : Colors.grey,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
