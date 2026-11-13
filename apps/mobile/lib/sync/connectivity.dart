// ignore_for_file: prefer_initializing_formals
import 'dart:async';

/// What kind of network the device is on right now.
enum NetworkKind {
  none,
  wifi,

  /// Metered (mobile data).
  cellular,
}

/// Reports connectivity. The app provides a platform implementation (connectivity_plus); the
/// sync code only depends on this interface so it runs unchanged in tests.
abstract interface class ConnectivityMonitor {
  Future<NetworkKind> current();
  Stream<NetworkKind> get changes;
}

/// Battery state, for the "pause below a low-battery threshold unless charging" policy.
abstract interface class PowerMonitor {
  Future<({int percent, bool charging})> current();
}

/// Never reports a low battery.
class UnlimitedPower implements PowerMonitor {
  const UnlimitedPower();

  @override
  Future<({int percent, bool charging})> current() async => (percent: 100, charging: true);
}

/// Whether uploads may run now (docs/architecture/sync.md "Policy"): connected; Wi-Fi only unless the
/// user allows mobile data (SYNC-005); not at a very low battery unless charging.
class UploadPolicy {
  const UploadPolicy();

  bool allows({required NetworkKind network, required bool wifiOnly, required ({int percent, bool charging}) power, required int lowBatteryPercent}) {
    if (network == NetworkKind.none) {
      return false;
    }
    if (wifiOnly && network != NetworkKind.wifi) {
      return false;
    }
    if (!power.charging && power.percent < lowBatteryPercent) {
      return false;
    }
    return true;
  }
}
