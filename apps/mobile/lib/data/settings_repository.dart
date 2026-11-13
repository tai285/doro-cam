// ignore_for_file: prefer_initializing_formals
import 'package:doro_cam/data/db/app_database.dart';

/// Keys of the device settings table.
abstract final class SettingKeys {
  static const accountId = 'account_id';

  /// SYNC-005: upload on Wi-Fi only (default on).
  static const wifiOnly = 'sync.wifi_only';

  /// PRIV-001: attach location to captures (default off).
  static const captureLocation = 'privacy.capture_location';

  /// Pause uploads below this battery percentage unless charging (docs/architecture/sync.md).
  static const lowBatteryPercent = 'sync.low_battery_percent';
}

/// Typed access to the key/value `settings` table.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Future<String?> read(String key) async {
    final row = await (_db.select(_db.settings)..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) =>
      _db.into(_db.settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  Future<void> remove(String key) => (_db.delete(_db.settings)..where((t) => t.key.equals(key))).go();

  /// Emits the current value and every later change.
  Stream<String?> watch(String key) =>
      (_db.select(_db.settings)..where((t) => t.key.equals(key))).watchSingleOrNull().map((row) => row?.value);

  Future<bool> readBool(String key, {required bool fallback}) async {
    final value = await read(key);
    return value == null ? fallback : value == 'true';
  }

  Future<void> writeBool(String key, {required bool value}) => write(key, value ? 'true' : 'false');

  /// SYNC-005: defaults to true.
  Future<bool> wifiOnly() => readBool(SettingKeys.wifiOnly, fallback: true);
  Future<void> setWifiOnly({required bool value}) => writeBool(SettingKeys.wifiOnly, value: value);

  /// PRIV-001: defaults to false.
  Future<bool> captureLocation() => readBool(SettingKeys.captureLocation, fallback: false);
  Future<void> setCaptureLocation({required bool value}) => writeBool(SettingKeys.captureLocation, value: value);

  Stream<bool> watchWifiOnly() => watch(SettingKeys.wifiOnly).map((value) => value == null ? true : value == 'true');
  Stream<bool> watchCaptureLocation() => watch(SettingKeys.captureLocation).map((value) => value == 'true');

  Future<int> lowBatteryPercent() async => int.tryParse(await read(SettingKeys.lowBatteryPercent) ?? '') ?? 15;
}
