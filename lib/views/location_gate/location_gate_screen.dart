import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../repositories/auth_repository.dart';
import '../../repositories/theme_repository.dart';

class LocationGateScreen extends StatefulWidget {
  const LocationGateScreen({super.key});

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends State<LocationGateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (!mounted) return;

      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        context.go('/location-required', extra: perm == LocationPermission.deniedForever);
        return;
      }

      final repo = context.read<AuthRepository>();
      await repo.initialize();
      if (!mounted) return;

      if (repo.status == AuthStatus.authenticated) {
        final company = repo.currentUser?.company ?? 'default';
        context.read<ThemeRepository>().fetchTheme(company);

        final role = repo.currentUser?.role ?? '';
        context.go(role == 'viewer' ? '/dashboard' : '/visits');
      } else {
        context.go('/login');
      }
    } catch (_) {
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}
