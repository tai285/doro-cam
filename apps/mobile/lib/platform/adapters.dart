import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:doro_cam/api/auth_service.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';

/// Session token in the platform keystore (Keychain / Android Keystore): never in the database (AUTH-004).
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const String key = 'doro.session_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String token) => _storage.write(key: key, value: token);

  @override
  Future<void> delete() => _storage.delete(key: key);
}

/// Maps connectivity_plus results to what the sync policy needs.
NetworkKind networkKindOf(List<ConnectivityResult> results) {
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet)) {
    return NetworkKind.wifi;
  }
  if (results.contains(ConnectivityResult.mobile)) {
    return NetworkKind.cellular;
  }
  if (results.any(
    (r) => r != ConnectivityResult.none && r != ConnectivityResult.bluetooth,
  )) {
    return NetworkKind.cellular; // vpn / other: treat as metered, the safe choice for "Wi-Fi only"
  }
  return NetworkKind.none;
}

class PlusConnectivityMonitor implements ConnectivityMonitor {
  PlusConnectivityMonitor([Connectivity? connectivity])
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<NetworkKind> current() async =>
      networkKindOf(await _connectivity.checkConnectivity());

  @override
  Stream<NetworkKind> get changes =>
      _connectivity.onConnectivityChanged.map(networkKindOf).distinct();
}

class BatteryPowerMonitor implements PowerMonitor {
  BatteryPowerMonitor([Battery? battery]) : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<({int percent, bool charging})> current() async {
    final level = await _battery.batteryLevel;
    final state = await _battery.batteryState;
    return (
      percent: level,
      charging: state == BatteryState.charging || state == BatteryState.full,
    );
  }
}

/// A position for a capture. Only asked for when the user enabled location (PRIV-001).
class DeviceLocation {
  const DeviceLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    this.altitudeM,
  });
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final double? altitudeM;
}

abstract interface class LocationService {
  /// Whether the app currently holds location permission.
  Future<bool> hasPermission();

  /// Asks for permission (shown when the user turns the setting on). Returns whether it was granted.
  Future<bool> requestPermission();

  /// A recent fix, or null when permission or a fix is unavailable. Never throws.
  Future<DeviceLocation?> current();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<bool> hasPermission() async {
    final permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Future<bool> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  @override
  Future<DeviceLocation?> current() async {
    try {
      if (!await hasPermission()) {
        return null;
      }
      final last = await Geolocator.getLastKnownPosition();
      final position =
          last ??
          await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              timeLimit: Duration(seconds: 2),
            ),
          );
      return DeviceLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyM: position.accuracy,
        altitudeM: position.altitude,
      );
    } on Object {
      return null;
    }
  }
}

/// Visual/haptic/sound feedback hooks, replaceable in tests (CAM-051).
abstract interface class FeedbackService {
  Future<void> shutter({required bool sound});
  Future<void> select();
  Future<void> warn();
}

class SystemFeedbackService implements FeedbackService {
  const SystemFeedbackService();

  @override
  Future<void> shutter({required bool sound}) async {
    await HapticFeedback.mediumImpact();
    if (sound) {
      await SystemSound.play(SystemSoundType.click);
    }
  }

  @override
  Future<void> select() => HapticFeedback.selectionClick();

  @override
  Future<void> warn() => HapticFeedback.heavyImpact();
}

/// Shares files and text with the OS share sheet (export of originals).
abstract interface class ShareService {
  Future<void> shareFile(String path, {String? mime, String? text});
  Future<void> shareText(String text);
}

class SharePlusService implements ShareService {
  const SharePlusService();

  @override
  Future<void> shareFile(String path, {String? mime, String? text}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: mime)],
        text: text,
      ),
    );
  }

  @override
  Future<void> shareText(String text) async {
    await SharePlus.instance.share(ShareParams(text: text));
  }
}
