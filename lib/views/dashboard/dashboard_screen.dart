import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../config/constants.dart';
import '../../repositories/auth_repository.dart';
import '../../services/api_client.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchStats();
  }

  Future<void> _fetchStats() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final resp =
          await context.read<ApiClient>().get('${Constants.dashboardPath}stats/');
      if (resp.statusCode == 200) {
        setState(() {
          _stats   = jsonDecode(resp.body) as Map<String, dynamic>;
          _loading = false;
        });
      } else {
        setState(() {
          _error   = 'Error ${resp.statusCode}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error   = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authRepo = context.watch<AuthRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          TextButton(
            onPressed: () async {
              await authRepo.logout();
              if (context.mounted) context.go('/login');
            },
            child: const Text('Salir',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _fetchStats)
              : _StatsView(stats: _stats!),
    );
  }
}

class _StatsView extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _StatsView({required this.stats});

  @override
  Widget build(BuildContext context) {
    final byStatus    = (stats['by_status']  as Map<String, dynamic>?) ?? {};
    final byCompany   = (stats['by_company'] as Map<String, dynamic>?) ?? {};
    final topTechs    = (stats['top_techs']  as List<dynamic>?) ?? [];
    final avgDuration = stats['avg_duration'] as num?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(child: _StatCard(
              label: 'Total',
              value: '${stats['total'] ?? 0}',
              color: AppTheme.info,
            )),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(
              label: 'Duración media',
              value: avgDuration != null ? '${avgDuration}m' : '—',
              color: AppTheme.success,
            )),
          ],
        ),
        const SizedBox(height: 20),

        if (byStatus.isNotEmpty) ...[
          const _SectionHeader('Por estado'),
          ...byStatus.entries.map((e) => _BarRow(
            label: _statusLabel(e.key),
            count: (e.value as num).toInt(),
            total: (stats['total'] as num?)?.toInt() ?? 1,
            color: _statusColor(e.key),
          )),
          const SizedBox(height: 20),
        ],

        if (byCompany.isNotEmpty) ...[
          const _SectionHeader('Por empresa'),
          ...byCompany.entries.map((e) => _BarRow(
            label: e.key.toUpperCase(),
            count: (e.value as num).toInt(),
            total: (stats['total'] as num?)?.toInt() ?? 1,
            color: e.key == 'wom' ? AppTheme.primary : const Color(0xFFF15A22),
          )),
          const SizedBox(height: 20),
        ],

        if (topTechs.isNotEmpty) ...[
          const _SectionHeader('Top técnicos'),
          ...topTechs.asMap().entries.map((entry) {
            final tech  = entry.value as Map<String, dynamic>;
            final name  =
                '${tech['technician__first_name'] ?? ''} ${tech['technician__last_name'] ?? ''}'
                    .trim();
            final email = tech['technician__email'] as String? ?? '';
            final count = (tech['count'] as num).toInt();
            return _TechRow(
              rank: entry.key + 1,
              name: name.isEmpty ? email : name,
              email: name.isEmpty ? '' : email,
              count: count,
            );
          }),
        ],
      ],
    );
  }

  String _statusLabel(String s) => switch (s) {
        'pendiente_aprobacion' => 'Pendiente',
        'programada'           => 'Programada',
        'rechazada'            => 'Rechazada',
        'en_camino'            => 'En camino',
        'llegada'              => 'En el sitio',
        'trabajando'           => 'Trabajando',
        'completada'           => 'Completada',
        'cancelada'            => 'Cancelada',
        _                      => s,
      };

  Color _statusColor(String s) => switch (s) {
        'pendiente_aprobacion' => AppTheme.warning,
        'programada'           => AppTheme.info,
        'en_camino'            => AppTheme.info,
        'llegada'              => AppTheme.primary,
        'trabajando'           => AppTheme.success,
        'completada'           => Colors.grey,
        _                      => AppTheme.error,
      };
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.03),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(fontSize: 13, color: Colors.grey)),
        ],
      ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      );
}

class _BarRow extends StatelessWidget {
  final String label;
  final int count;
  final int total;
  final Color color;
  const _BarRow(
      {required this.label,
      required this.count,
      required this.total,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
              width: 90,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: [
                    if (fraction > 0)
                      Flexible(
                        flex: (fraction * 1000).toInt(),
                        child: Container(color: color),
                      ),
                    if (fraction < 1)
                      Flexible(
                        flex: ((1 - fraction) * 1000).toInt(),
                        child: Container(
                          color: color.withValues(alpha: 0.12),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: Text(
              '$count',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechRow extends StatelessWidget {
  final int rank;
  final String name;
  final String email;
  final int count;
  const _TechRow(
      {required this.rank,
      required this.name,
      required this.email,
      required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surf(context),
        borderRadius: BorderRadius.circular(10),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.03),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.sep(context)),
          ),
          child: Row(
        children: [
          Material(
            color: rank == 1
                ? const Color(0xFFFFD700)
                : rank == 2
                    ? Colors.grey.shade300
                    : AppTheme.surfSec(context),
            shape: const CircleBorder(),
            child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                child: Text(
                  '$rank',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                if (email.isNotEmpty)
                  Text(email,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Material(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                '$count visitas',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary),
              ),
            ),
          ),
        ],
      ),
      ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 12),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 20),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onRetry,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
