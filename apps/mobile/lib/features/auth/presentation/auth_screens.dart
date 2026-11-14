import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

String friendlyAuthError(Object error) {
  if (error is NetworkException) {
    return 'Can’t reach the server. Check your connection and try again. Your photos are safe on this phone.';
  }
  if (error is ApiException) {
    if (error.status == 401) return 'That email and password do not match.';
    if (error.status == 403 &&
        (error.code.contains('EMAIL_NOT_VERIFIED') ||
            error.message.toLowerCase().contains('verif'))) {
      return 'Please confirm your email address first. We sent you a link.';
    }
    if (error.isRateLimited) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.title,
    required this.children,
    this.back = AppRoutes.settings,
  });

  final String title;
  final List<Widget> children;
  final String back;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: AppBackButton(label: 'Back', location: back),
      title: Text(title),
    ),
    body: ListView(padding: const EdgeInsets.all(16), children: children),
  );
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .signIn(email: _email.text.trim(), password: _password.text);
      if (mounted) {
        context.go(AppRoutes.settings);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      title: 'Sign in',
      children: <Widget>[
        const Text(
          'Signing in backs up your photos at original quality. The camera and your library work without an account.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('password'),
          controller: _password,
          obscureText: true,
          autofillHints: const <String>[AutofillHints.password],
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('auth-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sign-in-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Signing in…' : 'Sign in'),
        ),
        TextButton(
          key: const Key('to-forgot'),
          onPressed: () => context.push(AppRoutes.forgotPassword),
          child: const Text('Forgot your password?'),
        ),
        TextButton(
          key: const Key('to-sign-up'),
          onPressed: () => context.push(AppRoutes.signUp),
          child: const Text('Create an account'),
        ),
      ],
    );
  }
}

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _done = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_password.text.length < 10) {
      setState(() => _error = 'Use a password of at least 10 characters.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(authServiceProvider)
          .signUp(
            name: _name.text.trim(),
            email: _email.text.trim(),
            password: _password.text,
          );
      if (mounted) {
        setState(() => _done = true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) {
      return _AuthScaffold(
        title: 'Check your email',
        back: AppRoutes.signIn,
        children: <Widget>[
          Text(
            'We sent a confirmation link to ${_email.text.trim()}. Open it, then sign in.',
            key: const Key('check-email'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('go-sign-in'),
            onPressed: () => context.go(AppRoutes.signIn),
            child: const Text('Go to sign in'),
          ),
        ],
      );
    }
    return _AuthScaffold(
      title: 'Create account',
      back: AppRoutes.signIn,
      children: <Widget>[
        TextField(
          key: const Key('name'),
          controller: _name,
          autofillHints: const <String>[AutofillHints.name],
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const <String>[AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('password'),
          controller: _password,
          obscureText: true,
          autofillHints: const <String>[AutofillHints.newPassword],
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'At least 10 characters.',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('auth-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('sign-up-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(_busy ? 'Creating…' : 'Create account'),
        ),
      ],
    );
  }
}

/// Request a reset link, then choose a new password with the token from the email (AUTH-006).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _token = TextEditingController();
  final _password = TextEditingController();
  bool _sent = false;
  bool _reset = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(
    Future<void> Function() action,
    void Function() onDone,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) {
        setState(onDone);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = friendlyAuthError(error));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.read(authServiceProvider);
    if (_reset) {
      return _AuthScaffold(
        title: 'Password updated',
        back: AppRoutes.signIn,
        children: <Widget>[
          const Text(
            'Your password was changed. Sign in with the new one.',
            key: Key('reset-done'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go(AppRoutes.signIn),
            child: const Text('Sign in'),
          ),
        ],
      );
    }
    return _AuthScaffold(
      title: 'Reset password',
      back: AppRoutes.signIn,
      children: <Widget>[
        TextField(
          key: const Key('email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('send-reset'),
          onPressed: _busy
              ? null
              : () => _run(
                  () => auth.requestPasswordReset(
                    _email.text.trim(),
                    redirectTo: 'doro://reset-password',
                  ),
                  () => _sent = true,
                ),
          child: const Text('Send reset link'),
        ),
        if (_sent) ...<Widget>[
          const SizedBox(height: 16),
          const Text(
            'If an account exists for that email, we sent a link. Paste the code from it below, or open the link on this phone.',
            key: Key('reset-sent'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('reset-token'),
            controller: _token,
            decoration: const InputDecoration(
              labelText: 'Code from the email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('new-password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'New password',
              helperText: 'At least 10 characters.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('reset-submit'),
            onPressed: _busy
                ? null
                : () => _run(
                    () => auth.resetPassword(
                      token: _token.text.trim(),
                      newPassword: _password.text,
                    ),
                    () => _reset = true,
                  ),
            child: const Text('Update password'),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              _error!,
              key: const Key('auth-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
