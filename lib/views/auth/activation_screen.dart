import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/login_result.dart';
import '../../repositories/auth_repository.dart';
import '../../services/camera_service.dart';

class ActivationScreen extends StatefulWidget {
  final LoginDeviceNotRegistered deviceInfo;
  const ActivationScreen({super.key, required this.deviceInfo});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  File? _photo;
  bool _loading = false;
  String? _error;

  Future<void> _takePhoto() async {
    final file = await context.read<CameraService>().capturePhoto();
    if (file != null) setState(() { _photo = file; _error = null; });
  }

  Future<void> _submit() async {
    if (_photo == null) {
      setState(() => _error = 'Debes tomar una foto para activar tu cuenta');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final ok = await context.read<AuthRepository>().activate(widget.deviceInfo, _photo!.path);
    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      context.go('/pending-approval');
    } else {
      setState(() => _error = 'Error al registrar el dispositivo. Intenta nuevamente.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.bg(context),
    appBar: AppBar(
      title: const Text('Activar cuenta'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'Para activar tu cuenta, necesitamos tomar una foto de verificación y registrar este dispositivo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            Material(
              color: AppTheme.surf(context),
              borderRadius: BorderRadius.circular(14),
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.05),
              child: InkWell(
                onTap: _takePhoto,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 220,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _photo != null
                          ? AppTheme.primary.withValues(alpha: 0.3)
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: _photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: Image.file(_photo!, fit: BoxFit.cover),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.camera_alt_outlined,
                              size: 48,
                              color: AppTheme.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Toca para tomar foto',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_photo != null)
              TextButton(
                onPressed: _takePhoto,
                child: Text('Tomar otra foto',
                    style: TextStyle(color: AppTheme.primary)),
              ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Material(
                color: AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _error!,
                    style: TextStyle(color: AppTheme.error, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _submit,
                child: const Text(
                  'Activar dispositivo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}
