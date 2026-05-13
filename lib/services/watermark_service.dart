import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Archivos producidos por [WatermarkService.applyWatermark].
class WatermarkResult {
  final File full;
  final File thumb;
  const WatermarkResult({required this.full, required this.thumb});
}

// ── tipos para compute() ──────────────────────────────────────────────────────

class _EncodeInput {
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  const _EncodeInput(this.rgbaBytes, this.width, this.height);
}

class _EncodeOutput {
  final Uint8List full;
  final Uint8List thumb;
  const _EncodeOutput(this.full, this.thumb);
}

// Top-level para compute() — codifica RGBA→JPEG y genera thumbnail 200px
_EncodeOutput _encodeRgbaIsolate(_EncodeInput input) {
  final image = img.Image.fromBytes(
    width: input.width,
    height: input.height,
    bytes: input.rgbaBytes.buffer,
    numChannels: 4,
  );
  final fullJpeg = img.encodeJpg(image, quality: 85);

  final maxDim = image.width > image.height ? image.width : image.height;
  final scale  = 200 / maxDim;
  final thumb  = img.copyResize(
    image,
    width:         (image.width  * scale).round(),
    height:        (image.height * scale).round(),
    interpolation: img.Interpolation.average,
  );
  final thumbJpeg = img.encodeJpg(thumb, quality: 70);

  return _EncodeOutput(
    Uint8List.fromList(fullJpeg),
    Uint8List.fromList(thumbJpeg),
  );
}

// ── servicio ──────────────────────────────────────────────────────────────────

class WatermarkService {
  Uint8List? _logoBytes;

  Future<Uint8List> _logoData() async {
    if (_logoBytes != null) return _logoBytes!;
    const loader = SvgAssetLoader('assets/site_visit_icon.svg');
    final info    = await vg.loadPicture(loader, null);
    final image   = await info.picture.toImage(175, 105);
    info.picture.dispose();
    final byteData = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    image.dispose();
    _logoBytes = byteData.buffer.asUint8List();
    return _logoBytes!;
  }

  Future<WatermarkResult> applyWatermark(
    File photo,
    double? lat,
    double? lon,
  ) async {
    final logoRaw  = await _logoData();
    final photoRaw = await photo.readAsBytes();

    // Decodifica la foto reduciendo a máx 1600px — mucho más rápido que full-res
    const maxDim = 1600;
    final photoCodec = await ui.instantiateImageCodec(
      photoRaw,
      targetWidth: maxDim,
    );
    final photoImg = (await photoCodec.getNextFrame()).image;
    final w = photoImg.width.toDouble();
    final h = photoImg.height.toDouble();

    final logoCodec = await ui.instantiateImageCodec(
      logoRaw,
      targetWidth: (w * 0.12).toInt(),
    );
    final logoImg = (await logoCodec.getNextFrame()).image;

    final pad      = w * 0.030;
    final fontSize = w * 0.022;
    final gap      = w * 0.015;

    const shadows = [
      Shadow(offset: Offset(1, 1), blurRadius: 4, color: Color(0xDD000000)),
      Shadow(offset: Offset(-1, -1), blurRadius: 4, color: Color(0xDD000000)),
    ];

    final coordStyle = TextStyle(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      shadows: shadows,
    );
    final noGpsStyle = TextStyle(
      color: Colors.white70,
      fontSize: fontSize * 0.9,
      fontStyle: FontStyle.italic,
      shadows: shadows,
    );

    final latPainter = TextPainter(
      text: TextSpan(
        text:  lat != null ? 'lat: ${lat.toStringAsFixed(6)}' : 'Sin GPS',
        style: lat != null ? coordStyle : noGpsStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w * 0.5);

    final lonPainter = lat != null
        ? (TextPainter(
            text: TextSpan(
              text:  'lon: ${lon!.toStringAsFixed(6)}',
              style: coordStyle,
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: w * 0.5))
        : null;

    final lineGap = fontSize * 0.35;
    final coordW  = [latPainter.width, lonPainter?.width ?? 0]
        .reduce((a, b) => a > b ? a : b);
    final coordH  = latPainter.height +
        (lonPainter != null ? lineGap + lonPainter.height : 0);

    final lw = logoImg.width.toDouble();
    final lh = logoImg.height.toDouble();

    final blockH  = coordH > lh ? coordH : lh;
    final blockY  = h - pad - blockH;
    final textY   = blockY + (blockH - coordH) / 2;
    final logoY   = blockY + (blockH - lh) / 2;
    final logoX   = w - pad - lw;
    final coordX  = logoX - gap - coordW;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);

    canvas.drawImage(photoImg, Offset.zero, Paint());
    latPainter.paint(canvas, Offset(coordX, textY));
    lonPainter?.paint(canvas, Offset(coordX, textY + latPainter.height + lineGap));
    canvas.drawImage(logoImg, Offset(logoX, logoY), Paint());

    final wInt = photoImg.width;
    final hInt = photoImg.height;

    final picture = recorder.endRecording();
    final result  = await picture.toImage(wInt, hInt);

    // rawRgba es instantáneo (copia directa del buffer GPU, sin compresión)
    final rawBytes = (await result.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    result.dispose();
    photoImg.dispose();
    logoImg.dispose();

    // Codifica JPEG + thumbnail en background isolate
    final encoded = await compute(
      _encodeRgbaIsolate,
      _EncodeInput(rawBytes, wInt, hInt),
    );

    final docsDir   = await getApplicationDocumentsDirectory();
    final photosDir = Directory('${docsDir.path}/photos');
    if (!await photosDir.exists()) await photosDir.create(recursive: true);

    final ts        = DateTime.now().millisecondsSinceEpoch;
    final fullFile  = File('${photosDir.path}/wm_$ts.jpg');
    final thumbFile = File('${photosDir.path}/wm_${ts}_thumb.jpg');

    await Future.wait([
      fullFile.writeAsBytes(encoded.full),
      thumbFile.writeAsBytes(encoded.thumb),
    ]);

    // Borrar la foto raw original para no acumular archivos
    if (await photo.exists()) await photo.delete();

    return WatermarkResult(full: fullFile, thumb: thumbFile);
  }
}
