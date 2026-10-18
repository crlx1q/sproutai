import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../providers/auth_provider.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isLogin = true;
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authProvider.notifier);
      if (_isLogin) {
        await auth.login(_email.text.trim(), _password.text);
      } else {
        await auth.register(
          _name.text.trim(),
          _email.text.trim(),
          _password.text,
        );
      }
      // Роутер сам уведёт на /home по смене auth-состояния.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        'assets/logo.png',
                        width: 68,
                        height: 68,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isLogin ? 'С возвращением!' : 'Создайте аккаунт',
                    style: theme.textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isLogin ? 'Ваш сад скучал.' : 'И начните растить с умом.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 36),
                  if (!_isLogin) ...[
                    TextFormField(
                      controller: _name,
                      enabled: !_busy,
                      autofillHints: const [AutofillHints.name],
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Имя'),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Введите имя'
                          : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _email,
                    enabled: !_busy,
                    autocorrect: false,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(hintText: 'Email'),
                    validator: (v) =>
                        (v == null ||
                            !RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(v.trim()))
                        ? 'Введите корректный email'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: _isLogin
                        ? const [AutofillHints.password]
                        : const [AutofillHints.newPassword],
                    onFieldSubmitted: (_) => _submit(),
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      hintText: 'Пароль',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                          color: theme.colorScheme.outline,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6)
                        ? 'Минимум 6 символов'
                        : null,
                  ),
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isLogin ? 'Войти' : 'Зарегистрироваться'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                            _isLogin = !_isLogin;
                            _formKey.currentState?.reset();
                          }),
                    child: Text(
                      _isLogin
                          ? 'Нет аккаунта? Зарегистрируйтесь'
                          : 'Уже есть аккаунт? Войти',
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
}
