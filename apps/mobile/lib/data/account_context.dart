// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:doro_cam/data/settings_repository.dart';

/// Who is signed in on this device, as far as local data is concerned. Null means anonymous: the
/// camera and the local library work without an account (AUTH-005) and captures are held until
/// sign-in (docs/specs/upload-sync.md "Anonymous captures").
class AccountContext {
  AccountContext(this._settings, {String? initial}) : _accountId = initial;

  /// Restores the account that was signed in when the app last ran.
  static Future<AccountContext> restore(SettingsRepository settings) async =>
      AccountContext(settings, initial: await settings.read(SettingKeys.accountId));

  final SettingsRepository _settings;
  final StreamController<String?> _changes = StreamController<String?>.broadcast();
  String? _accountId;

  String? get accountId => _accountId;
  bool get isSignedIn => _accountId != null;

  /// Emits the new account id (or null) whenever it changes.
  Stream<String?> get changes => _changes.stream;

  Future<void> setAccount(String? accountId) async {
    if (accountId == _accountId) {
      return;
    }
    _accountId = accountId;
    if (accountId == null) {
      await _settings.remove(SettingKeys.accountId);
    } else {
      await _settings.write(SettingKeys.accountId, accountId);
    }
    if (!_changes.isClosed) {
      _changes.add(accountId);
    }
  }

  Future<void> dispose() => _changes.close();
}
