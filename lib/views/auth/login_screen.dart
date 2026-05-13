import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../config/app_theme.dart';
import '../../models/login_result.dart';
import '../../repositories/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  final String? initialEmail;
  const LoginScreen({super.key, this.initialEmail});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null) {
      _emailCtrl.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completa todos los campos');
      return;
    }

    setState(() { _loading = true; _error = null; });
    final result = await context.read<AuthRepository>().login(email, password);
    if (!mounted) return;
    setState(() => _loading = false);

    switch (result) {
      case LoginSuccess(:final role):
        context.go(role == 'viewer' ? '/dashboard' : '/visits');
      case LoginDeviceNotRegistered():
        context.go('/activate', extra: result);
      case LoginPendingApproval(:final userId):
        final authRepo = context.read<AuthRepository>();
        authRepo.setPendingApproval(email, password, userId);
        if (!mounted) return;
        context.go('/visits');
      case LoginDeviceUnauthorized():
        setState(() => _error = 'Dispositivo no autorizado. Contacta a tu manager.');
      case LoginError(:final message):
        setState(() => _error = message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.bg(context),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App icon
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Center(
                      child: Text(
                        'SV',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'SiteVisit',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Grouped input card
                _GroupedInputCard(
                  children: [
                    _InputRow(
                      label: 'Email',
                      child: TextField(
                        controller: _emailCtrl,
                        decoration: InputDecoration(
                          hintText: 'correo@empresa.com',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: AppTheme.placeholder(context),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        style: TextStyle(fontSize: 15, color: AppTheme.text(context)),
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                      ),
                    ),
                    Divider(height: 0.5, thickness: 0.5,
                        indent: 114, color: AppTheme.sep(context)),
                    _InputRow(
                      label: 'Contraseña',
                      child: TextField(
                        controller: _passwordCtrl,
                        decoration: InputDecoration(
                          hintText: '••••••••',
                          hintStyle: TextStyle(
                            fontSize: 15,
                            color: AppTheme.placeholder(context),
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 14),
                        ),
                        style: TextStyle(fontSize: 15, color: AppTheme.text(context)),
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                      ),
                    ),
                  ],
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: AppTheme.error, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: AppTheme.primary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text(
                          'Ingresar',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                if (!_loading)
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: Text(
                      'Registrarse',
                      style: TextStyle(color: AppTheme.primary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _GroupedInputCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupedInputCard({required this.children});

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.surf(context),
    borderRadius: BorderRadius.circular(12),
    elevation: 2,
    shadowColor: Colors.black.withValues(alpha: 0.06),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

class _InputRow extends StatelessWidget {
  final String label;
  final Widget child;
  const _InputRow({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 100,
        padding: const EdgeInsets.only(left: 14),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      Expanded(child: child),
    ],
  );
}
