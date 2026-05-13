import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../config/app_theme.dart';

class SelfieScreen extends StatefulWidget {
  const SelfieScreen({super.key});

  @override
  State<SelfieScreen> createState() => _SelfieScreenState();
}

class _SelfieScreenState extends State<SelfieScreen> {
  CameraController? _ctrl;
  bool _ready     = false;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isDenied || status.isPermanentlyDenied) {
      setState(() => _error = status.isPermanentlyDenied
          ? 'Permiso de cámara denegado.\nHabilítalo en Ajustes del dispositivo.'
          : 'Se necesita permiso de cámara para continuar.');
      return;
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _error = 'No se encontró cámara disponible.');
        return;
      }
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final ctrl = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await ctrl.initialize();
      if (!mounted) { await ctrl.dispose(); return; }
      _ctrl = ctrl;
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo iniciar la cámara.\nIntenta de nuevo.');
    }
  }

  Future<void> _capture() async {
    if (!_ready || _capturing || _ctrl == null) return;
    setState(() => _capturing = true);
    try {
      final xFile = await _ctrl!.takePicture();
      if (mounted) Navigator.of(context).pop(File(xFile.path));
    } catch (_) {
      if (mounted) setState(() => _capturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size   = MediaQuery.of(context).size;
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [

          // ── Live preview ──────────────────────────────────────────────────
          if (_ready && _ctrl != null)
            Positioned.fill(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width:  _ctrl!.value.previewSize?.height ?? size.width,
                  height: _ctrl!.value.previewSize?.width  ?? size.height,
                  child: CameraPreview(_ctrl!),
                ),
              ),
            )
          else
            const ColoredBox(color: Colors.black),

          // ── Máscara con óvalo transparente ─────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _OvalMaskPainter(ready: _ready),
            ),
          ),

          // ── Estado: cargando / error ────────────────────────────────────────
          if (!_ready && _error == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.camera_alt,
                        color: Color(0x88FFFFFF), size: 44),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, height: 1.6),
                    ),
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () {
                        setState(() => _error = null);
                        _initCamera();
                      },
                      child: Text('Reintentar',
                          style: TextStyle(color: AppTheme.primary)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Botón cerrar ───────────────────────────────────────────────────
          Positioned(
            top: top + 6,
            left: 4,
            child: IconButton(
              padding: const EdgeInsets.all(10),
              onPressed: () => Navigator.of(context).pop(null),
              icon: const Icon(Icons.cancel,
                  color: Color(0xBBFFFFFF), size: 32),
            ),
          ),

          // ── Instrucción ────────────────────────────────────────────────────
          if (_ready)
            Positioned(
              top: top + 52,
              left: 0,
              right: 0,
              child: const Text(
                'Centra tu cara en el óvalo',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  shadows: [Shadow(blurRadius: 8)],
                ),
              ),
            ),

          // ── Botón capturar ─────────────────────────────────────────────────
          if (_ready)
            Positioned(
              bottom: bottom + 44,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _capturing ? null : _capture,
                  child: AnimatedOpacity(
                    opacity: _capturing ? 0.4 : 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(6),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Máscara oval ───────────────────────────────────────────────────────────────

class _OvalMaskPainter extends CustomPainter {
  final bool ready;
  const _OvalMaskPainter({required this.ready});

  @override
  void paint(Canvas canvas, Size size) {
    final ovalW = size.width * 0.68;
    final ovalH = ovalW * 1.30;
    final oval  = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.50),
      width: ovalW,
      height: ovalH,
    );

    canvas.drawPath(
      Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addOval(oval)
        ..fillType = PathFillType.evenOdd,
      Paint()..color = const Color(0xBB000000),
    );

    if (!ready) return;

    canvas.drawOval(
      oval,
      Paint()
        ..color = const Color(0xCCFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final accent = Paint()
      ..color = AppTheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    const span = 0.30;
    for (final a in [
      -span / 2,
      1.5707963 - span / 2,
      3.1415926 - span / 2,
      4.7123889 - span / 2,
    ]) {
      canvas.drawArc(oval, a, span, false, accent);
    }
  }

  @override
  bool shouldRepaint(_OvalMaskPainter old) => old.ready != ready;
}
