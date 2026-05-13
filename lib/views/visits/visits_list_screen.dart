import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/user.dart';
import '../../models/visit.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/site_repository.dart';
import '../../repositories/visit_repository.dart';

class VisitsListScreen extends StatefulWidget {
  const VisitsListScreen({super.key});

  @override
  State<VisitsListScreen> createState() => _VisitsListScreenState();
}

class _VisitsListScreenState extends State<VisitsListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.read<AuthRepository>().isPendingApproval) {
        context.read<VisitRepository>().fetchVisits();
        context.read<SiteRepository>().fetchSites();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final authRepo  = context.watch<AuthRepository>();
    final visitRepo = context.watch<VisitRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Visitas'),
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
      body: Column(
        children: [
          if (authRepo.currentUser != null)
            _ProfileCard(user: authRepo.currentUser!),
          Expanded(
            child: visitRepo.loading
                ? const Center(child: CircularProgressIndicator())
                : visitRepo.error != null
                    ? _ErrorView(
                        error: visitRepo.error!,
                        onRetry: visitRepo.fetchVisits,
                      )
                    : Builder(builder: (context) {
                            final visible = visitRepo.visits.where(
                              (v) =>
                                  v.status != VisitStatus.pendienteAprobacion &&
                                  v.status != VisitStatus.rechazada,
                            ).toList()
                              ..sort((a, b) => a.status.sortOrder
                                  .compareTo(b.status.sortOrder));
                            return RefreshIndicator(
                              onRefresh: visitRepo.fetchVisits,
                              color: AppTheme.primary,
                              child: visible.isEmpty
                                  ? const SingleChildScrollView(
                                      physics: AlwaysScrollableScrollPhysics(),
                                      child: _EmptyView(),
                                    )
                                  : CustomScrollView(
                                      slivers: [
                                        SliverPadding(
                                          padding: const EdgeInsets.fromLTRB(
                                              16, 16, 16, 32),
                                          sliver: SliverList(
                                            delegate: SliverChildBuilderDelegate(
                                              (ctx, i) {
                                                final visit = visible[i];
                                                return Padding(
                                                  padding: const EdgeInsets.only(
                                                      bottom: 10),
                                                  child: _VisitTile(
                                                    visit: visit,
                                                    onTap: visit.status.isActionable
                                                        ? () {
                                                            visitRepo.setActiveVisit(visit);
                                                            context.push('/visits/execute');
                                                          }
                                                        : null,
                                                  ),
                                                );
                                              },
                                              childCount: visible.length,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            );
                          }),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final UserModel user;
  const _ProfileCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surf(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppTheme.sep(context)),
          ),
        ),
        child: Row(
        children: [
          _Avatar(user: user),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (user.cargo.isNotEmpty)
                  Text(
                    user.cargo,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final UserModel user;
  const _Avatar({required this.user});

  @override
  Widget build(BuildContext context) {
    final photoUrl = user.photoUrl;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _InitialsAvatar(user: user),
        ),
      );
    }
    return _InitialsAvatar(user: user);
  }
}

class _InitialsAvatar extends StatelessWidget {
  final UserModel user;
  const _InitialsAvatar({required this.user});

  String get _initials {
    final f = user.firstName.isNotEmpty ? user.firstName[0] : '';
    final l = user.lastName.isNotEmpty  ? user.lastName[0]  : '';
    final initials = '$f$l'.toUpperCase();
    return initials.isNotEmpty ? initials : user.email[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.primary.withValues(alpha: 0.15),
      shape: const CircleBorder(),
      child: SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Text(
            _initials,
            style: TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _VisitTile extends StatelessWidget {
  final VisitModel visit;
  final VoidCallback? onTap;
  const _VisitTile({required this.visit, this.onTap});

  String get _formattedDate {
    final parts = visit.scheduledDate.split('-');
    if (parts.length != 3) return visit.scheduledDate;
    final yy = parts[0].length == 4 ? parts[0].substring(2) : parts[0];
    return '${parts[2]}-${parts[1]}-$yy';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surf(context),
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.04),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.sep(context)),
          ),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
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
                      if (visit.siteOperatorCode.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          visit.siteOperatorCode,
                          style: TextStyle(
                            color: AppTheme.info,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ],
                      if (visit.siteName.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            visit.siteName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    visit.reason,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        _formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.text(context),
                        ),
                      ),
                      const Spacer(),
                      _StatusBadge(status: visit.status),
                      if (onTap != null && visit.status != VisitStatus.completada) ...[
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 14,
                          color: AppTheme.text(context),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final VisitStatus status;
  const _StatusBadge({required this.status});

  static const _steps = [
    VisitStatus.programada,
    VisitStatus.enCamino,
    VisitStatus.llegada,
    VisitStatus.trabajando,
    VisitStatus.completada,
  ];

  Color get _color => switch (status) {
        VisitStatus.pendienteAprobacion => AppTheme.warning,
        VisitStatus.programada          => AppTheme.info,
        VisitStatus.completada          => AppTheme.success,
        VisitStatus.cancelada           => AppTheme.error,
        VisitStatus.rechazada           => AppTheme.error,
        _                               => AppTheme.warning,
      };

  String? get _step {
    if (status == VisitStatus.programada) return null;
    if (status == VisitStatus.completada) return null;
    final idx = _steps.indexOf(status);
    if (idx < 0) return null;
    return '${idx + 1}/${_steps.length}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color;
    final step = _step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (step != null) ...[
          Text(
            step,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Material(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(
                Icons.calendar_month,
                size: 36,
                color: AppTheme.primary.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sin visitas asignadas',
            style: TextStyle(color: Colors.grey, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'El coordinador programa los servicios desde el portal web.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
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
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
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
