enum VisitStatus {
  pendienteAprobacion, programada, enCamino, llegada, trabajando, finalizando, completada, cancelada, rechazada;

  String get apiName => switch (this) {
    VisitStatus.pendienteAprobacion => 'pendiente_aprobacion',
    VisitStatus.programada          => 'programada',
    VisitStatus.enCamino            => 'en_camino',
    VisitStatus.llegada             => 'llegada',
    VisitStatus.trabajando          => 'trabajando',
    VisitStatus.finalizando         => 'finalizando',
    VisitStatus.completada          => 'completada',
    VisitStatus.cancelada           => 'cancelada',
    VisitStatus.rechazada           => 'rechazada',
  };

  static VisitStatus fromString(String s) => values.firstWhere(
    (v) => v.apiName == s,
    orElse: () => programada,
  );

  String get label => switch (this) {
    VisitStatus.pendienteAprobacion => 'Pendiente',
    VisitStatus.programada          => 'Programado',
    VisitStatus.enCamino            => 'Inicio',
    VisitStatus.llegada             => 'Sitio',
    VisitStatus.trabajando          => 'Servicios',
    VisitStatus.finalizando         => 'Finalizando',
    VisitStatus.completada          => 'Completada',
    VisitStatus.cancelada           => 'Cancelada',
    VisitStatus.rechazada           => 'Rechazada',
  };

  bool get isActionable =>
      this == VisitStatus.programada  ||
      this == VisitStatus.enCamino    ||
      this == VisitStatus.llegada     ||
      this == VisitStatus.trabajando  ||
      this == VisitStatus.finalizando;

  // 0 = ejecutando, 1 = programada, 2 = pendiente/rechazada, 3 = terminadas
  int get sortOrder => switch (this) {
    VisitStatus.enCamino            => 0,
    VisitStatus.llegada             => 0,
    VisitStatus.trabajando          => 0,
    VisitStatus.finalizando         => 0,
    VisitStatus.programada          => 1,
    VisitStatus.pendienteAprobacion => 2,
    VisitStatus.completada          => 3,
    VisitStatus.cancelada           => 3,
    VisitStatus.rechazada           => 3,
  };
}

class VisitModel {
  final int id;
  final int siteId;
  final String siteCode;
  final String siteOperatorCode;
  final String siteName;
  final VisitStatus status;
  final String reason;
  final String scheduledDate;
  final String? eta;
  final DateTime? horaInicioTrabajos;
  final DateTime? horaFinTrabajos;
  final String notas;

  const VisitModel({
    required this.id,
    required this.siteId,
    required this.siteCode,
    required this.siteOperatorCode,
    required this.siteName,
    required this.status,
    required this.reason,
    required this.scheduledDate,
    this.eta,
    this.horaInicioTrabajos,
    this.horaFinTrabajos,
    this.notas = '',
  });

  factory VisitModel.fromJson(Map<String, dynamic> json) => VisitModel(
    id:            (json['id'] as int?) ?? 0,
    siteId:        (json['site'] as int?) ?? 0,
    siteCode:          json['site_code']          as String? ?? '',
    siteOperatorCode:  json['site_operator_code'] as String? ?? '',
    siteName:          json['site_name']          as String? ?? '',
    status:        VisitStatus.fromString((json['status'] as String?) ?? 'programada'),
    reason:        json['reason'] as String? ?? '',
    scheduledDate: json['scheduled_date'] as String? ?? '',
    eta:           json['eta'] as String?,
    horaInicioTrabajos: json['hora_inicio_trabajos'] != null
        ? DateTime.tryParse(json['hora_inicio_trabajos'] as String)
        : null,
    horaFinTrabajos: json['hora_fin_trabajos'] != null
        ? DateTime.tryParse(json['hora_fin_trabajos'] as String)
        : null,
    notas: json['notas'] as String? ?? '',
  );

  VisitModel copyWith({VisitStatus? status, DateTime? horaInicioTrabajos, DateTime? horaFinTrabajos, String? notas}) =>
      VisitModel(
        id: id, siteId: siteId, siteCode: siteCode, siteOperatorCode: siteOperatorCode, siteName: siteName,
        status: status ?? this.status,
        reason: reason, scheduledDate: scheduledDate, eta: eta,
        horaInicioTrabajos: horaInicioTrabajos ?? this.horaInicioTrabajos,
        horaFinTrabajos:    horaFinTrabajos    ?? this.horaFinTrabajos,
        notas: notas ?? this.notas,
      );
}
