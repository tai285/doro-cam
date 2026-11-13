// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:doro_cam/api/api_exception.dart';
import 'package:doro_cam/api/api_models.dart';
import 'package:doro_cam/api/doro_api_client.dart';
import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/memory_repository.dart';

/// Where the session token is kept. The app supplies a secure-storage implementation
/// (Keychain / Keystore); tests use [InMemoryTokenStore].
abstract interface class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

class InMemoryTokenStore implements TokenStore {
  InMemoryTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> delete() async => _token = null;
}

/// Sign-in state of the device (AUTH-001, AUTH-004, AUTH-005, AUTH-006). The camera and the local
/// library never require it; signing in claims what was captured anonymously so it uploads.
class AuthService {
  AuthService({
    required DoroApiClient client,
    required TokenStore tokens,
    required AccountContext account,
    required MemoryRepository memories,
  }) : _client = client,
       _tokens = tokens,
       _account = account,
       _memories = memories {
    _unauthorizedSubscription = _client.unauthorized.listen((_) => unawaited(_endSessionLocally()));
  }

  final DoroApiClient _client;
  final TokenStore _tokens;
  final AccountContext _account;
  final MemoryRepository _memories;
  late final StreamSubscription<void> _unauthorizedSubscription;

  Account? _current;

  /// The signed-in account, or null.
  Account? get current => _current;

  /// Emits the account id (or null) whenever the signed-in account changes.
  Stream<String?> get accountChanges => _account.changes;

  /// Creates an account. The user must confirm their email before signing in (AUTH-001).
  Future<void> signUp({required String name, required String email, required String password}) =>
      _client.signUp(name: name, email: email, password: password);

  /// Signs in, stores the device token, and claims anonymous captures for upload.
  Future<Account> signIn({required String email, required String password}) async {
    final token = await _client.signIn(email: email, password: password);
    await _tokens.write(token);
    try {
      final account = await _client.me();
      await _activate(account);
      return account;
    } on Object {
      await _tokens.delete();
      rethrow;
    }
  }

  /// Restores the session at app start. Returns null when signed out or the session was revoked.
  /// A network failure keeps the signed-in state so the app works offline (NFR-001).
  Future<Account?> restore() async {
    if (await _tokens.read() == null) {
      return null;
    }
    try {
      final account = await _client.me();
      await _activate(account);
      return account;
    } on ApiException catch (error) {
      if (error.isUnauthenticated) {
        await _endSessionLocally();
        return null;
      }
      rethrow;
    } on NetworkException {
      return _current;
    }
  }

  Future<void> signOut() async {
    try {
      await _client.signOut();
    } on NetworkException {
      // Offline sign-out still ends the local session; the server session expires on its own.
    } on ApiException {
      // The session was already gone.
    }
    await _endSessionLocally();
  }

  Future<void> requestPasswordReset(String email, {required String redirectTo}) =>
      _client.requestPasswordReset(email: email, redirectTo: redirectTo);

  Future<void> resetPassword({required String token, required String newPassword}) =>
      _client.resetPassword(token: token, newPassword: newPassword);

  Future<List<DeviceSession>> sessions() => _client.sessions();

  Future<void> revokeSession(String id) => _client.revokeSession(id);

  Future<DateTime> requestAccountDeletion(String password) => _client.requestDeletion(password);

  Future<void> cancelAccountDeletion() => _client.cancelDeletion();

  /// Refreshes the account (storage usage, deletion state).
  Future<Account> refresh() async {
    final account = await _client.me();
    _current = account;
    return account;
  }

  Future<void> _activate(Account account) async {
    _current = account;
    await _account.setAccount(account.id);
    await _memories.claimAnonymous(account.id);
  }

  Future<void> _endSessionLocally() async {
    await _tokens.delete();
    _current = null;
    await _account.setAccount(null);
  }

  Future<void> dispose() => _unauthorizedSubscription.cancel();
}
