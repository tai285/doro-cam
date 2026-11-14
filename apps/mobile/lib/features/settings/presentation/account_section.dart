import 'package:doro_cam/api/api_models.dart';
import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/auth/presentation/auth_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

String formatBytes(int bytes) {
  const units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value >= 100 || unit == 0 ? value.round() : value.toStringAsFixed(value >= 10 ? 1 : 2)} ${units[unit]}';
}

final _accountProvider = FutureProvider.autoDispose<Account?>((ref) async {
  final accountId = ref.watch(accountIdProvider).value;
  if (accountId == null) {
    return null;
  }
  final auth = ref.read(authServiceProvider);
  try {
    return await auth.refresh();
  } on Object {
    return auth.current; // offline: show what we last knew
  }
});

final _sessionsProvider = FutureProvider.autoDispose<List<DeviceSession>>((
  ref,
) async {
  if (ref.watch(accountIdProvider).value == null) {
    return const <DeviceSession>[];
  }
  return ref.read(authServiceProvider).sessions();
});

/// Sign-in prompt or the account: storage, devices, sign-out and deletion (AUTH-004, AUTH-005, WEB-005/006, PRIV-004).
class AccountSection extends ConsumerStatefulWidget {
  const AccountSection({super.key});

  @override
  ConsumerState<AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends ConsumerState<AccountSection> {
  String? _message;

  @override
  Widget build(BuildContext context) {
    final accountId = ref.watch(accountIdProvider).value;
    if (accountId == null) {
      return Column(
        children: <Widget>[
          const ListTile(
            title: Text('You’re not signed in'),
            subtitle: Text(
              'Everything works without an account. Sign in to back up your photos and see them on the web.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  key: const Key('settings-sign-in'),
                  onPressed: () => context.push(AppRoutes.signIn),
                  child: const Text('Sign in'),
                ),
                OutlinedButton(
                  key: const Key('settings-sign-up'),
                  onPressed: () => context.push(AppRoutes.signUp),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    final account = ref.watch(_accountProvider).value;
    final sessions =
        ref.watch(_sessionsProvider).value ?? const <DeviceSession>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          key: const Key('account-info'),
          title: Text(account?.name ?? 'Signed in'),
          subtitle: Text(account?.email ?? ''),
        ),
        if (account != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Storage: ${formatBytes(account.usedBytes)} of ${formatBytes(account.quotaBytes)} used',
                  key: const Key('storage-text'),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: account.quotaBytes == 0
                      ? 0
                      : (account.usedBytes / account.quotaBytes)
                            .clamp(0, 1)
                            .toDouble(),
                  semanticsLabel: 'Storage used',
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Signed-in devices',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final session in sessions)
          ListTile(
            key: Key('session-${session.id}'),
            title: Text(session.userAgent ?? 'Unknown device'),
            subtitle: Text(
              session.current
                  ? 'This device'
                  : 'Signed in ${session.createdAt.toLocal().toString().substring(0, 10)}',
            ),
            trailing: session.current
                ? null
                : TextButton(
                    onPressed: () async {
                      await ref
                          .read(authServiceProvider)
                          .revokeSession(session.id);
                      ref.invalidate(_sessionsProvider);
                    },
                    child: const Text('Sign out'),
                  ),
          ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: <Widget>[
              OutlinedButton(
                key: const Key('sign-out'),
                onPressed: () async {
                  await ref.read(authServiceProvider).signOut();
                  if (mounted) {
                    setState(
                      () => _message = 'Signed out. Photos stay on this phone.',
                    );
                  }
                },
                child: const Text('Sign out'),
              ),
              if (account?.deletionScheduledFor == null)
                OutlinedButton(
                  key: const Key('delete-account'),
                  onPressed: () => _deleteDialog(context),
                  child: const Text('Delete account'),
                )
              else
                FilledButton(
                  key: const Key('cancel-deletion'),
                  onPressed: () async {
                    await ref.read(authServiceProvider).cancelAccountDeletion();
                    ref.invalidate(_accountProvider);
                  },
                  child: const Text('Cancel deletion'),
                ),
            ],
          ),
        ),
        if (account?.deletionScheduledFor != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Your account will be deleted on ${account!.deletionScheduledFor!.toLocal().toString().substring(0, 10)}.',
              key: const Key('deletion-scheduled'),
            ),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(_message!, key: const Key('account-message')),
          ),
      ],
    );
  }

  Future<void> _deleteDialog(BuildContext context) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => const _DeleteAccountDialog(),
    );
    if (done ?? false) {
      ref.invalidate(_accountProvider);
    }
  }
}

/// Owns its controller, so it is disposed only after the dialog has fully left the screen.
class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final TextEditingController _password = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final navigator = Navigator.of(context);
    try {
      await ref
          .read(authServiceProvider)
          .requestAccountDeletion(_password.text);
      navigator.pop(true);
    } on Object catch (e) {
      if (mounted) {
        setState(
          () => _error = friendlyAuthError(e).replaceFirst(
            'That email and password do not match.',
            'That password is not correct.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'This permanently deletes your account and every backed-up photo after 7 days. Photos on this phone stay. You can cancel during those 7 days.',
          ),
          TextField(
            key: const Key('delete-password'),
            controller: _password,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm your password',
            ),
          ),
          if (_error != null) Text(_error!, key: const Key('delete-error')),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('delete-confirm'),
          onPressed: _confirm,
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
