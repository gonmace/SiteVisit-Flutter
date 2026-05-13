import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/login_result.dart';
import '../../models/technician_search_result.dart';
import '../../repositories/auth_repository.dart';
import 'selfie_screen.dart';

enum _RegStep { email, form }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl    = TextEditingController();
  final _nameCtrl     = TextEditingController();
  final _rutCtrl      = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _cargoCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  _RegStep _step   = _RegStep.email;
  TechnicianSearchResult? _tech;
  String _company  = 'wom';
  File?  _selfie;
  bool   _loading  = false;
  String? _error;
  bool _obscurePassword = true;
  bool _registered = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    _rutCtrl.dispose();
    _phoneCtrl.dispose();
    _cargoCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ── Email lookup ────────────────────────────────────────────────────────────

  Future<void> _lookupEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Ingresa un correo electrónico válido');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final tech = await context.read<AuthRepository>().lookupByEmail(email);
      if (!mounted) return;
      if (tech == null) {
        setState(() =>
            _error = 'No se encontró un técnico con ese correo.\nContacta a tu manager.');
      } else {
        setState(() {
          _tech      = tech;
          _company   = tech.company.isNotEmpty ? tech.company : 'wom';
          _nameCtrl.text  = tech.fullName.trim();
          _cargoCtrl.text = tech.cargo;
          _step  = _RegStep.form;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(
          () => _error = 'Error de conexión. Verifica tu red e intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Selfie ──────────────────────────────────────────────────────────────────

  Future<void> _takeSelfie() async {
    final file = await Navigator.of(context).push<File>(
      MaterialPageRoute(builder: (_) => const SelfieScreen()),
    );
    if (file != null && mounted) setState(() { _selfie = file; _error = null; });
  }

  // ── RUT validation ──────────────────────────────────────────────────────────

  static String? _validateRut(String raw) {
    final clean = raw.replaceAll('.', '').replaceAll(' ', '').toUpperCase();
    if (clean.length < 3) return 'RUT demasiado corto';
    final dash = clean.indexOf('-');
    if (dash == -1) return 'Formato inválido (ej: 12.345.678-9)';
    final digits   = clean.substring(0, dash);
    final verifier = clean.substring(dash + 1);
    if (digits.isEmpty || verifier.isEmpty) return 'Formato inválido';
    if (!RegExp(r'^\d+$').hasMatch(digits)) return 'El RUT solo debe contener números';
    if (!RegExp(r'^[\dK]$').hasMatch(verifier)) {
      return 'Dígito verificador inválido (0-9 o K)';
    }

    int sum  = 0;
    int mult = 2;
    for (int i = digits.length - 1; i >= 0; i--) {
      sum += int.parse(digits[i]) * mult;
      mult = mult == 7 ? 2 : mult + 1;
    }
    final rem      = 11 - (sum % 11);
    final expected = rem == 11 ? '0' : rem == 10 ? 'K' : rem.toString();
    if (verifier != expected) return 'RUT inválido — dígito verificador no coincide';
    return null;
  }

  // ── Error extraction ────────────────────────────────────────────────────────

  static String _extractApiError(Map<String, dynamic> data) {
    if (data['detail'] != null) return data['detail'].toString();
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) return '${entry.key}: ${value.first}';
      if (value is String && value.isNotEmpty) return '${entry.key}: $value';
    }
    return 'Error al registrar la cuenta';
  }

  // ── Submit ──────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_tech == null) return;

    final parts     = _nameCtrl.text.trim().split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first : '';
    final lastName  = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final rut       = _rutCtrl.text.trim();
    final phone     = _phoneCtrl.text.trim();
    final cargo     = _cargoCtrl.text.trim();
    final password  = _passwordCtrl.text;

    final rutError = _validateRut(rut);
    if (rutError != null) { setState(() => _error = rutError); return; }
    if (password.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres');
      return;
    }
    if (_selfie == null) {
      setState(() => _error = 'Debes tomar una selfie para continuar');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final authRepo = context.read<AuthRepository>();

      final claimData = await authRepo.claimTechnician(
        userId:    _tech!.id,
        password:  password,
        company:   _company,
        rut:       rut,
        firstName: firstName,
        lastName:  lastName,
        phone:     phone,
        cargo:     cargo,
      );
      if (!mounted) return;

      final detail = claimData['detail']?.toString() ?? '';
      if (detail == 'already_activated') {
        setState(() =>
            _error = 'Esta cuenta ya fue activada. Inicia sesión directamente.');
        return;
      }
      if (detail != 'claimed') {
        setState(() => _error = _extractApiError(claimData));
        return;
      }

      final ok = await authRepo.activate(
        LoginDeviceNotRegistered(
          userId:   _tech!.id,
          email:    _tech!.email,
          password: password,
        ),
        _selfie!.path,
      );
      if (!mounted) return;

      if (ok) {
        setState(() => _registered = true);
      } else {
        setState(
            () => _error = 'Error al registrar el dispositivo. Intenta de nuevo.');
      }
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString().replaceFirst('Exception: ', '');
      setState(() => _error = switch (raw) {
            'rut_duplicate'     => 'El RUT ingresado ya está registrado en otra cuenta.',
            'already_activated' =>
              'Esta cuenta ya fue activada. Inicia sesión directamente.',
            _ => raw,
          });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.bg(context),
    appBar: AppBar(
      title: Text(_step == _RegStep.email ? 'Registro' : 'Completa tu perfil'),
      leading: _step == _RegStep.form
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () =>
                  setState(() { _step = _RegStep.email; _error = null; }),
            )
          : null,
      automaticallyImplyLeading: _step != _RegStep.form,
    ),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: _registered
                ? _buildSuccessStep()
                : _step == _RegStep.email
                    ? _buildEmailStep()
                    : _buildFormStep(),
          ),
        ),
      ),
    ),
  );

  // ── Step 1 ──────────────────────────────────────────────────────────────────

  Widget _buildEmailStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Center(
            child: Text('SV',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Habilitar Cuenta',
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.text(context)),
          textAlign: TextAlign.center),
      const SizedBox(height: 8),
      const Text(
        'Ingresa el correo con el que tu manager te dio de alta en el sistema',
        style: TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 32),
      _InputCard(
        child: TextField(
          controller: _emailCtrl,
          decoration: InputDecoration(
            hintText: 'correo@empresa.com',
            hintStyle: const TextStyle(fontSize: 16, color: Color(0xFFC7C7CC)),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          style: TextStyle(fontSize: 16, color: AppTheme.text(context)),
          onSubmitted: (_) => _loading ? null : _lookupEmail(),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: 14),
        _ErrorBanner(_error!),
      ],
      const SizedBox(height: 24),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else
        _PrimaryButton(label: 'Continuar', onPressed: _lookupEmail),
    ],
  );

  // ── Step 2 ──────────────────────────────────────────────────────────────────

  Widget _buildFormStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      // Selfie avatar
      Center(
        child: GestureDetector(
          onTap: _takeSelfie,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selfie != null
                      ? AppTheme.success.withValues(alpha: 0.08)
                      : AppTheme.surfSec(context),
                  border: Border.all(
                    color: _selfie != null
                        ? AppTheme.success.withValues(alpha: 0.4)
                        : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
                child: _selfie != null
                    ? ClipOval(
                        child: Image.file(_selfie!,
                            fit: BoxFit.cover, width: 100, height: 100))
                    : (_tech?.photoUrl != null && _tech!.photoUrl!.isNotEmpty)
                        ? ClipOval(
                            child: Image.network(
                              _tech!.photoUrl!,
                              fit: BoxFit.cover,
                              width: 100,
                              height: 100,
                              errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 48,
                                  color: Color(0xFF8E8E93)),
                            ),
                          )
                        : const Icon(Icons.person,
                            size: 48, color: Color(0xFF8E8E93)),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _selfie != null ? AppTheme.success : AppTheme.primary,
                    border: Border.all(
                        color: AppTheme.bg(context), width: 2),
                  ),
                  child: Icon(
                    _selfie != null ? Icons.check : Icons.camera_alt,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Center(
        child: Text(
          _selfie != null
              ? 'Toca para retomar'
              : (_tech?.photoUrl != null && _tech!.photoUrl!.isNotEmpty)
                  ? 'Toca para reemplazar tu foto *'
                  : 'Toca para tomar selfie *',
          style: TextStyle(
            fontSize: 13,
            color: _selfie != null ? AppTheme.success : Colors.grey,
          ),
        ),
      ),
      const SizedBox(height: 28),

      // Name
      const _FieldLabel('NOMBRE COMPLETO'),
      const SizedBox(height: 6),
      _InputCard(
        child: TextField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            hintText: 'Nombre y apellido',
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          style: TextStyle(fontSize: 15, color: AppTheme.text(context)),
        ),
      ),
      const SizedBox(height: 16),

      // RUT
      const _FieldLabel('RUT'),
      const SizedBox(height: 6),
      _InputCard(
        child: TextField(
          controller: _rutCtrl,
          decoration: const InputDecoration(
            hintText: '12.345.678-9',
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          textInputAction: TextInputAction.next,
          inputFormatters: [_RutInputFormatter()],
          keyboardType: const TextInputType.numberWithOptions(
              signed: false, decimal: false),
          autofillHints: const [],
          enableSuggestions: false,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      const SizedBox(height: 16),

      // Phone
      const _FieldLabel('TELÉFONO'),
      const SizedBox(height: 6),
      _InputCard(
        child: TextField(
          controller: _phoneCtrl,
          decoration: const InputDecoration(
            hintText: '+56 9 1234 5678',
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [],
          enableSuggestions: false,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      const SizedBox(height: 16),

      // Cargo
      const _FieldLabel('CARGO'),
      const SizedBox(height: 6),
      _InputCard(
        child: TextField(
          controller: _cargoCtrl,
          decoration: const InputDecoration(
            hintText: 'Técnico, Supervisor…',
            border: InputBorder.none,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          ),
          textInputAction: TextInputAction.next,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      const SizedBox(height: 16),

      // Company
      const _FieldLabel('EMPRESA'),
      const SizedBox(height: 6),
      Material(
        color: AppTheme.surf(context),
        borderRadius: BorderRadius.circular(12),
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.sep(context)),
          ),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'wom',
                label:
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('WOM'))),
            ButtonSegment(
                value: 'pti',
                label:
                    Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('PTI'))),
          ],
          selected: {_company},
          onSelectionChanged: (s) => setState(() => _company = s.first),
          style: ButtonStyle(
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ),
      ),
      const SizedBox(height: 16),

      // Password
      const _FieldLabel('CONTRASEÑA'),
      const SizedBox(height: 6),
      _InputCard(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _passwordCtrl,
                decoration: const InputDecoration(
                  hintText: 'Mínimo 8 caracteres',
                  border: InputBorder.none,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                style: const TextStyle(fontSize: 15),
                onSubmitted: (_) => _loading ? null : _submit(),
              ),
            ),
            IconButton(
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                size: 20,
                color: const Color(0xFF8E8E93),
              ),
            ),
          ],
        ),
      ),

      if (_error != null) ...[
        const SizedBox(height: 16),
        _ErrorBanner(_error!),
      ],

      const SizedBox(height: 28),
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else
        _PrimaryButton(label: 'Registrarse', onPressed: _submit),
      const SizedBox(height: 16),
    ],
  );

  // ── Step 3: Éxito ────────────────────────────────────────────────────────────

  Widget _buildSuccessStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 32),
      Center(
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline,
              size: 48, color: AppTheme.success),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'Cuenta registrada',
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      Text(
        'Tus datos fueron enviados correctamente.\nEl coordinador revisará tu solicitud y habilitará tu acceso.',
        style: TextStyle(fontSize: 14, color: AppTheme.textSec(context), height: 1.5),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 40),
      _PrimaryButton(
        label: 'Ir al inicio de sesión',
        onPressed: () => context.go('/login', extra: _tech!.email),
      ),
    ],
  );
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
      color: Colors.grey,
    ),
  );
}

class _InputCard extends StatelessWidget {
  final Widget child;
  const _InputCard({required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surf(context),
    borderRadius: BorderRadius.circular(12),
    elevation: 1,
    shadowColor: Colors.black.withValues(alpha: 0.04),
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.sep(context)),
      ),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(12), child: child),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => FilledButton(
    style: FilledButton.styleFrom(
      backgroundColor: AppTheme.primary,
      minimumSize: const Size.fromHeight(50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    onPressed: onPressed,
    child: Text(label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
  );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppTheme.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppTheme.error.withValues(alpha: 0.2)),
    ),
    child: Text(
      message,
      style: TextStyle(color: AppTheme.error, fontSize: 13, height: 1.4),
      textAlign: TextAlign.center,
    ),
  );
}

// ── RUT auto-formatter ─────────────────────────────────────────────────────────

class _RutInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue old, TextEditingValue next) {
    final raw = next.text.replaceAll(RegExp(r'[^\dkK]'), '').toUpperCase();
    if (raw.isEmpty) return next.copyWith(text: '');

    final body     = raw.length > 1 ? raw.substring(0, raw.length - 1) : raw;
    final verifier = raw.length > 1 ? raw[raw.length - 1] : '';

    final buf = StringBuffer();
    for (int i = 0; i < body.length; i++) {
      if (i > 0 && (body.length - i) % 3 == 0) buf.write('.');
      buf.write(body[i]);
    }

    final formatted =
        verifier.isNotEmpty ? '${buf.toString()}-$verifier' : buf.toString();
    return next.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
