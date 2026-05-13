import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../config/app_theme.dart';
import '../../widgets/loading_overlay.dart';
import '../../widgets/photo_tile.dart';
import '../../models/site.dart';
import '../../models/visit.dart';
import '../../repositories/site_repository.dart';
import '../../repositories/visit_repository.dart';

class VisitExecutionScreen extends StatefulWidget {
  const VisitExecutionScreen({super.key});

  @override
  State<VisitExecutionScreen> createState() => _VisitExecutionScreenState();
}

class _VisitExecutionScreenState extends State<VisitExecutionScreen> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _timerStarted = false;

  final Map<String, File?> _photos = {
    'llegada':    null,
    'vehiculo':   null,
    'trabajo_1':  null,
    'trabajo_2':  null,
    'trabajo_3':  null,
    'trabajo_4':  null,
    'trabajo_5':  null,
    'trabajo_6':  null,
    'trabajo_7':  null,
    'trabajo_8':  null,
    'trabajo_9':  null,
    'trabajo_10': null,
    'cierre':     null,
  };

  final Map<String, File?> _thumbPhotos = {};

  final Set<String> _uploadingPhotos = {};
  final Map<String, double?> _photoLats = {};
  final Map<String, double?> _photoLons = {};
  bool _transitioning = false;
  bool _sessionPhotosLoaded = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_sessionPhotosLoaded) {
      _sessionPhotosLoaded = true;
      _loadSessionPhotos();
    }
  }

  Future<void> _loadSessionPhotos() async {
    final repo = context.read<VisitRepository>();
    final saved = await repo.loadSessionPhotos();
    if (saved.isEmpty || !mounted) return;
    setState(() {
      for (final entry in saved.entries) {
        final data = entry.value as Map<String, dynamic>;
        final path = data['path'] as String?;
        if (path != null && File(path).existsSync()) {
          _photos[entry.key] = File(path);
          _photoLats[entry.key] = (data['lat'] as num?)?.toDouble();
          _photoLons[entry.key] = (data['lon'] as num?)?.toDouble();
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(DateTime? since) {
    _timer?.cancel();
    _elapsedSeconds = since != null
        ? DateTime.now().difference(since).inSeconds.clamp(0, 86400)
        : 0;
    _timerStarted = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  String get _formattedTime {
    final h = (_elapsedSeconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((_elapsedSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<Position?> _getPosition() async {
    // Intento 1: alta precisión, 12 segundos
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {}
    // Intento 2: precisión reducida, 8 segundos
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      ).timeout(const Duration(seconds: 8));
    } catch (_) {}
    // Intento 3: última posición conocida
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {}
    return null;
  }

  void _onFileCaptured(
    String type,
    File fullFile,
    File thumbFile,
    double? lat,
    double? lon,
  ) {
    setState(() {
      _photos[type]      = fullFile;
      _thumbPhotos[type] = thumbFile;
      _photoLats[type]   = lat;
      _photoLons[type]   = lon;
    });
    context.read<VisitRepository>().persistSessionPhoto(
      type, fullFile.path, lat: lat, lon: lon,
    );
  }

  // Sube las fotos indicadas mostrando spinner individual en cada tile.
  // Devuelve false si alguna falla.
  Future<bool> _uploadPendingPhotos(
    List<String> types,
    int visitId, {
    Map<String, String>? descriptions,
    bool showTileSpinners = true,
  }) async {
    for (final type in types) {
      final file = _photos[type];
      if (file == null) continue;
      if (showTileSpinners) setState(() => _uploadingPhotos.add(type));
      try {
        await context.read<VisitRepository>().uploadPhoto(
          visitId: visitId,
          photoType: type,
          imagePath: file.path,
          latitude: _photoLats[type],
          longitude: _photoLons[type],
          description: descriptions?[type],
        );
      } catch (e) {
        if (mounted) setState(() {
          _error = 'Error al subir foto: $e';
          if (showTileSpinners) _uploadingPhotos.remove(type);
        });
        return false;
      }
      if (mounted && showTileSpinners) setState(() => _uploadingPhotos.remove(type));
    }
    return true;
  }

  Future<void> _iniciarViaje(VisitModel visit, String eta) async {
    const storage = FlutterSecureStorage(aOptions: AndroidOptions(resetOnError: true));
    await storage.write(key: 'trip_initiated_${visit.id}', value: '1');
    await _transitionTo(visit, VisitStatus.enCamino, eta: eta);
  }

  Future<void> _transitionTo(
    VisitModel visit,
    VisitStatus target, {
    String? eta,
    bool alreadyTransitioning = false,
  }) async {
    if (!alreadyTransitioning) {
      if (_transitioning) return;
      setState(() { _transitioning = true; _error = null; });
    }

    final pos = await _getPosition();

    if (pos == null) {
      if (mounted) {
        setState(() {
          _transitioning = false;
          _error = 'No se pudo obtener tu ubicación GPS. '
              'Asegúrate de que el GPS esté activo e inténtalo de nuevo.';
        });
      }
      return;
    }

    final repo = context.read<VisitRepository>();
    try {
      await repo.updateVisitStatus(
        visitId: visit.id,
        newStatus: target.apiName,
        latitude: pos.latitude,
        longitude: pos.longitude,
        timestamp: DateTime.now(),
        eta: (target == VisitStatus.enCamino) ? eta : null,
      );

      if (target == VisitStatus.trabajando && !_timerStarted) _startTimer(null);
      if (target == VisitStatus.completada) _timer?.cancel();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  Future<void> _saveNotas(VisitModel visit, String notas) async {
    if (_transitioning) return;
    setState(() { _transitioning = true; _error = null; });
    try {
      final repo = context.read<VisitRepository>();

      // Transicionar a completada (genera evento GPS 'cierre' via STATUS_TO_GPS_EVENT).
      // Si ya está completada (reintento tras fallo de updateNotas), saltar este paso.
      if (visit.status != VisitStatus.completada) {
        await _transitionTo(visit, VisitStatus.completada, alreadyTransitioning: true);
      }

      await repo.updateNotas(visitId: visit.id, notas: notas);

      if (mounted) {
        repo.clearSessionPhotos();
        repo.fetchVisits();
        context.go('/visits');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _transitioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visit = context.watch<VisitRepository>().activeVisit;

    if (visit == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Visita')),
        body: const Center(child: Text('Sin visita activa')),
      );
    }

    if (visit.status == VisitStatus.trabajando && !_timerStarted) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _startTimer(visit.horaInicioTrabajos),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(visit.siteCode),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StageBar(status: visit.status),
              const SizedBox(height: 16),
              Expanded(
                child: LoadingOverlay(
                  isLoading: _transitioning,
                  child: _buildBody(visit),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppTheme.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(VisitModel visit) {
    return switch (visit.status) {
      VisitStatus.programada => _ProgramadaBody(
          visit: visit,
          loading: _transitioning,
          onStart: (eta) => _iniciarViaje(visit, eta),
        ),
      VisitStatus.enCamino => _EnCaminoBody(
          visit: visit,
          photos: _photos,
          thumbPhotos: _thumbPhotos,
          uploadingPhotos: _uploadingPhotos,
          loading: _transitioning,
          onFileCaptured: _onFileCaptured,
          onArrive: () async {
            if (_transitioning) return;
            setState(() { _transitioning = true; _error = null; });
            final ok = await _uploadPendingPhotos(
              ['llegada', 'vehiculo'], visit.id,
              showTileSpinners: false,
            );
            if (!ok || !mounted) {
              setState(() => _transitioning = false);
              return;
            }
            await _transitionTo(
              visit, VisitStatus.llegada,
              alreadyTransitioning: true,
            );
          },
        ),
      VisitStatus.llegada => _LlegadaBody(
          visit: visit,
          loading: _transitioning,
          onBegin: () => _transitionTo(visit, VisitStatus.trabajando),
        ),
      VisitStatus.trabajando => _TrabajandoBody(
          visit: visit,
          photos: _photos,
          thumbPhotos: _thumbPhotos,
          uploadingPhotos: _uploadingPhotos,
          formattedTime: _formattedTime,
          loading: _transitioning,
          onFileCaptured: _onFileCaptured,
          onFinish: (descriptions) async {
            if (_transitioning) return;
            setState(() { _transitioning = true; _error = null; });
            final tipos = _photos.entries
                .where((e) => e.key.startsWith('trabajo_') && e.value != null)
                .map((e) => e.key)
                .toList();
            final ok = await _uploadPendingPhotos(tipos, visit.id, descriptions: descriptions, showTileSpinners: false);
            if (!ok || !mounted) {
              setState(() => _transitioning = false);
              return;
            }
            // Transicionar a finalizando — genera evento GPS 'finalizado' via STATUS_TO_GPS_EVENT
            await _transitionTo(visit, VisitStatus.finalizando, alreadyTransitioning: true);
          },
        ),
      VisitStatus.finalizando => _ComentariosBody(
          visit: visit,
          loading: _transitioning,
          onDone: (notas) => _saveNotas(visit, notas),
        ),
      _ => Center(child: Text('Estado: ${visit.status.label}')),
    };
  }
}

// ── Stage progress bar ────────────────────────────────────────────────────────

class _StageBar extends StatelessWidget {
  final VisitStatus status;
  const _StageBar({required this.status});

  static const _stages = [
    VisitStatus.programada,
    VisitStatus.enCamino,
    VisitStatus.llegada,
    VisitStatus.trabajando,
    VisitStatus.finalizando,
  ];

  static const _labels = [
    'Traslado',
    'Llegada',
    'Inicio',
    'Servicio',
    'Cierre',
  ];

  @override
  Widget build(BuildContext context) {
    final current = status == VisitStatus.completada
        ? _stages.length
        : _stages.indexOf(status).clamp(0, _stages.length - 1);
    const color = AppTheme.primary;
    return Column(
      children: [
        Row(
          children: List.generate(_stages.length * 2 - 1, (i) {
            if (i.isOdd) {
              final idx = i ~/ 2;
              return Expanded(
                child: Container(
                  height: 2,
                  color: idx < current ? color : Colors.grey.shade300,
                ),
              );
            }
            final idx = i ~/ 2;
            final done = idx < current;
            final active = idx == current;
            return Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? color
                    : active
                        ? color.withValues(alpha: 0.12)
                        : Colors.grey.shade200,
                border: active ? Border.all(color: color, width: 2) : null,
              ),
              child: done
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : Center(
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: active ? color : Colors.grey,
                        ),
                      ),
                    ),
            );
          }),
        ),
        const SizedBox(height: 4),
        Row(
          children: List.generate(_stages.length * 2 - 1, (i) {
            if (i.isOdd) return const Expanded(child: SizedBox());
            final idx = i ~/ 2;
            final done = idx < current;
            final active = idx == current;
            return SizedBox(
              width: 36,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _labels[idx],
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: done || active ? color : Colors.grey,
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ── Stage 1: Programada ───────────────────────────────────────────────────────

class _ProgramadaBody extends StatefulWidget {
  final VisitModel visit;
  final bool loading;
  final Future<void> Function(String eta) onStart;
  const _ProgramadaBody(
      {required this.visit, required this.loading, required this.onStart});

  @override
  State<_ProgramadaBody> createState() => _ProgramadaBodyState();
}

class _ProgramadaBodyState extends State<_ProgramadaBody> {
  TimeOfDay? _eta;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SiteRepository>().fetchSites();
    });
  }

  String get _etaLabel {
    if (_eta == null) return 'Seleccionar hora...';
    final h = _eta!.hour.toString().padLeft(2, '0');
    final m = _eta!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String get _etaValue {
    final h = _eta!.hour.toString().padLeft(2, '0');
    final m = _eta!.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showTimePicker() {
    final initial = _eta ?? TimeOfDay.now();
    final initialDateTime = DateTime(2000, 1, 1, initial.hour, initial.minute);
    showCupertinoModalPopup<void>(
      context: context,
      builder: (_) => Container(
        height: 260,
        color: CupertinoColors.systemBackground.resolveFrom(context),
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                child: const Text('Listo'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: initialDateTime,
                onDateTimeChanged: (dt) {
                  setState(() => _eta = TimeOfDay(hour: dt.hour, minute: dt.minute));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMaps(SiteModel site) async {
    final lat = site.latitude;
    final lon = site.longitude;
    // geo: abre la app nativa de mapas; el sistema elige Google Maps si está instalado
    final geoUri = Uri.parse('geo:$lat,$lon?q=$lat,$lon');
    try {
      await launchUrl(geoUri, mode: LaunchMode.externalNonBrowserApplication);
      return;
    } catch (_) {}
    // fallback: abre en el navegador
    try {
      final webUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lon');
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('No se pudo abrir mapas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sites = context.watch<SiteRepository>().sites;
    SiteModel? site;
    for (final s in sites) {
      if (s.id == widget.visit.siteId) {
        site = s;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(visit: widget.visit, site: site, onOpenMaps: site != null ? () => _openMaps(site!) : null),
        const SizedBox(height: 16),
        Material(
          color: AppTheme.surf(context),
          borderRadius: BorderRadius.circular(12),
          elevation: 1,
          shadowColor: Colors.black.withValues(alpha: 0.04),
          child: InkWell(
            onTap: _showTimePicker,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _eta != null
                      ? AppTheme.primary.withValues(alpha: 0.4)
                      : AppTheme.sep(context),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    size: 20,
                    color: _eta != null ? AppTheme.primary : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hora estimada de llegada *',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _etaLabel,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                _eta != null ? FontWeight.w600 : FontWeight.w400,
                            color: _eta != null ? null : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.grey.withValues(alpha: 0.5),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        const Text(
          'Cuando estés listo para movilizarte al sitio, presiona el botón.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey, fontSize: 14),
        ),
        const SizedBox(height: 20),
        _ActionButton(
          label: 'Iniciar movilización',
          icon: Icons.directions_car,
          loading: widget.loading,
          onPressed: _eta != null ? () => widget.onStart(_etaValue) : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Stage 2: En camino ────────────────────────────────────────────────────────

class _EnCaminoBody extends StatelessWidget {
  final VisitModel visit;
  final Map<String, File?> photos;
  final Map<String, File?> thumbPhotos;
  final Set<String> uploadingPhotos;
  final bool loading;
  final void Function(String type, File full, File thumb, double? lat, double? lon) onFileCaptured;
  final VoidCallback onArrive;

  const _EnCaminoBody({
    required this.visit,
    required this.photos,
    required this.thumbPhotos,
    required this.uploadingPhotos,
    required this.loading,
    required this.onFileCaptured,
    required this.onArrive,
  });

  bool get _canProceed =>
      photos['llegada'] != null && photos['vehiculo'] != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(visit: visit),
        const SizedBox(height: 16),
        const Text(
          'Registro de llegada',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Captura las imágenes antes de continuar.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        PhotoTile(
          label: 'Sitio',
          description: 'Vista principal del Sitio',
          fullFile: photos['llegada'],
          thumbFile: thumbPhotos['llegada'],
          required: true,
          uploading: uploadingPhotos.contains('llegada'),
          onFileCaptured: (full, thumb, lat, lon) =>
              onFileCaptured('llegada', full, thumb, lat, lon),
          descriptionColor: AppTheme.text(context),
        ),
        const SizedBox(height: 10),
        PhotoTile(
          label: 'Vehículo',
          description: 'Imagen vehículo de frente (patente)',
          fullFile: photos['vehiculo'],
          thumbFile: thumbPhotos['vehiculo'],
          required: true,
          uploading: uploadingPhotos.contains('vehiculo'),
          onFileCaptured: (full, thumb, lat, lon) =>
              onFileCaptured('vehiculo', full, thumb, lat, lon),
          descriptionColor: AppTheme.text(context),
        ),
        const Spacer(),
        _ActionButton(
          label: 'Llegada',
          icon: Icons.location_on,
          loading: loading,
          onPressed: _canProceed ? onArrive : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Stage 3: Llegada ──────────────────────────────────────────────────────────

class _LlegadaBody extends StatefulWidget {
  final VisitModel visit;
  final bool loading;
  final VoidCallback onBegin;

  const _LlegadaBody({
    required this.visit,
    required this.loading,
    required this.onBegin,
  });

  @override
  State<_LlegadaBody> createState() => _LlegadaBodyState();
}

class _LlegadaBodyState extends State<_LlegadaBody> {
  late Timer _clock;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = _now.hour.toString().padLeft(2, '0');
    final m = _now.minute.toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(visit: widget.visit),
        const SizedBox(height: 20),
        Center(
          child: Text(
            '$h:$m',
            style: TextStyle(
              fontSize: 72,
              fontWeight: FontWeight.w300,
              color: AppTheme.info,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const Spacer(),
        _ActionButton(
          label: 'Iniciar trabajos',
          icon: Icons.build,
          loading: widget.loading,
          onPressed: widget.onBegin,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Stage 4: Trabajando ───────────────────────────────────────────────────────

class _TrabajandoBody extends StatefulWidget {
  final VisitModel visit;
  final Map<String, File?> photos;
  final Map<String, File?> thumbPhotos;
  final Set<String> uploadingPhotos;
  final String formattedTime;
  final bool loading;
  final void Function(String type, File full, File thumb, double? lat, double? lon) onFileCaptured;
  final Future<void> Function(Map<String, String> descriptions) onFinish;

  const _TrabajandoBody({
    required this.visit,
    required this.photos,
    required this.thumbPhotos,
    required this.uploadingPhotos,
    required this.formattedTime,
    required this.loading,
    required this.onFileCaptured,
    required this.onFinish,
  });

  @override
  State<_TrabajandoBody> createState() => _TrabajandoBodyState();
}

class _TrabajandoBodyState extends State<_TrabajandoBody> {
  int _visibleCount = 2;
  static const int _maxCount = 10;

  final Map<String, TextEditingController> _descControllers = {};

  TextEditingController _controllerFor(String key) =>
      _descControllers.putIfAbsent(key, TextEditingController.new);

  @override
  void dispose() {
    for (final c in _descControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  int get _takenCount => List.generate(
        _visibleCount,
        (i) => 'trabajo_${i + 1}',
      ).where((k) => widget.photos[k] != null).length;

  bool get _canFinish => _takenCount >= 2;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Material(
          color: AppTheme.view.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.view.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Text(
                  'Tiempo trabajando',
                  style: TextStyle(
                      color: AppTheme.view.withValues(alpha: 0.7),
                      fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.formattedTime,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w300,
                    color: AppTheme.view,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Imágenes del Servicio',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 4),
        const Text(
          'Captura al menos 2 imágenes del servicio realizado.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        const SizedBox(height: 12),
        ...List.generate(_visibleCount, (i) {
          final n = i + 1;
          final key = 'trabajo_$n';
          final taken = widget.photos[key] != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PhotoTile(
                label: 'Imagen $n',
                description: 'Registro Imagen $n',
                fullFile: widget.photos[key],
                thumbFile: widget.thumbPhotos[key],
                required: n <= 2,
                uploading: widget.uploadingPhotos.contains(key),
                onFileCaptured: (full, thumb, lat, lon) =>
                    widget.onFileCaptured(key, full, thumb, lat, lon),
                descriptionColor: AppTheme.text(context),
              ),
              if (taken) ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _controllerFor(key),
                  decoration: InputDecoration(
                    hintText: 'Descripción de la imagen $n...',
                    hintStyle: TextStyle(
                      color: Colors.grey.withValues(alpha: 0.6),
                      fontSize: 13,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: AppTheme.surf(context),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.sep(context)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                          color: AppTheme.primary.withValues(alpha: 0.5)),
                    ),
                  ),
                  style: TextStyle(fontSize: 13, color: AppTheme.text(context)),
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                ),
              ],
              const SizedBox(height: 10),
            ],
          );
        }),
        if (_visibleCount < _maxCount)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: AppTheme.surf(context),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => setState(() => _visibleCount++),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.sep(context),
                      style: BorderStyle.solid,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_circle_outline,
                          color: AppTheme.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Agregar imagen (${_visibleCount + 1}/$_maxCount)',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 14),
        _ActionButton(
          label: 'Finalizar servicio',
          icon: Icons.verified,
          loading: widget.loading,
          onPressed: _canFinish
              ? () {
                  final descs = <String, String>{
                    for (final e in _descControllers.entries)
                      e.key: e.value.text.trim().isNotEmpty
                          ? e.value.text.trim()
                          : 'Imagen ${e.key.replaceFirst('trabajo_', '')}',
                  };
                  widget.onFinish(descs);
                }
              : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Stage 5: Comentarios ─────────────────────────────────────────────────────

class _ComentariosBody extends StatefulWidget {
  final VisitModel visit;
  final bool loading;
  final Future<void> Function(String notas) onDone;
  const _ComentariosBody({required this.visit, required this.loading, required this.onDone});

  @override
  State<_ComentariosBody> createState() => _ComentariosBodyState();
}

class _ComentariosBodyState extends State<_ComentariosBody> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InfoCard(visit: widget.visit),
        const SizedBox(height: 20),
        const Text(
          'Comentario / Observaciones',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _ctrl,
          autofocus: false,
          decoration: InputDecoration(
            hintText: 'Agrega un comentario o una observación...',
            hintStyle: TextStyle(
              color: Colors.grey.withValues(alpha: 0.6),
              fontSize: 13,
            ),
            alignLabelWithHint: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            filled: true,
            fillColor: AppTheme.surf(context),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: AppTheme.sep(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide:
                  BorderSide(color: AppTheme.primary.withValues(alpha: 0.5)),
            ),
          ),
          style: const TextStyle(fontSize: 14),
          maxLines: 6,
        ),
        const Spacer(),
        _ActionButton(
          label: 'Completar visita',
          icon: Icons.check_circle_outline,
          loading: widget.loading,
          onPressed: () => widget.onDone(_ctrl.text.trim()),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final VisitModel visit;
  final SiteModel? site;
  final VoidCallback? onOpenMaps;
  const _InfoCard({required this.visit, this.site, this.onOpenMaps});

  String _formatDate(String raw) {
    final p = raw.split('-');
    if (p.length != 3) return raw;
    return '${p[2]}-${p[1]}-${p[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surf(context),
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.sep(context)),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                visit.siteCode,
                style: TextStyle(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  fontFamily: 'Courier',
                ),
              ),
              const Spacer(),
              if (visit.siteOperatorCode.isNotEmpty)
                Text(
                  visit.siteOperatorCode,
                  style: TextStyle(
                    color: AppTheme.info,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            visit.siteName,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            visit.reason,
            style: const TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDate(visit.scheduledDate),
                      style: TextStyle(fontSize: 13, color: AppTheme.text(context)),
                    ),
                    if (site != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${site!.latitude.toStringAsFixed(6)}, ${site!.longitude.toStringAsFixed(6)}',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.withValues(alpha: 0.5),
                            fontFamily: 'Courier'),
                      ),
                    ],
                  ],
                ),
              ),
              if (onOpenMaps != null)
                GestureDetector(
                  onTap: onOpenMaps,
                  child: const _GoogleMapsPin(size: 36),
                ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool loading;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.loading,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && onPressed != null;
    return SizedBox(
      height: 50,
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor:
              enabled ? AppTheme.primary : Colors.grey.shade400,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: (loading || onPressed == null) ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ── Google Maps pin icon (SVG) ────────────────────────────────────────────────

class _GoogleMapsPin extends StatelessWidget {
  final double size;
  const _GoogleMapsPin({this.size = 36});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/google_maps.svg',
      width: size,
      height: size,
    );
  }
}
