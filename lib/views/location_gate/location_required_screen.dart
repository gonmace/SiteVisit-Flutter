import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

class LocationRequiredScreen extends StatelessWidget {
  final bool isPermanent;
  const LocationRequiredScreen({super.key, required this.isPermanent});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.location_off, size: 64, color: Colors.grey),
            const SizedBox(height: 24),
            const Text(
              'Ubicación requerida',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'SiteVisit necesita acceso a tu ubicación para registrar visitas técnicas.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            if (isPermanent)
              FilledButton(
                onPressed: () async {
                  await Geolocator.openAppSettings();
                },
                child: const Text('Abrir configuración'),
              )
            else
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Reintentar'),
              ),
          ],
        ),
      ),
    ),
  );
}
