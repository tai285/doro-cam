import 'dart:convert';

import 'package:doro_cam/data/account_context.dart';
import 'package:doro_cam/data/settings_repository.dart';
import 'package:doro_cam/sync/connectivity.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/support.dart';

void main() {
  late Env env;
  setUp(() async => env = await Env.create());
  tearDown(() => env.close());

  group('SettingsRepository', () {
    test('[SYNC-005] Wi-Fi-only defaults to on and can be switched off and on', () async {
      expect(await env.settings.wifiOnly(), isTrue);
      await env.settings.setWifiOnly(value: false);
      expect(await env.settings.wifiOnly(), isFalse);
      await env.settings.setWifiOnly(value: true);
      expect(await env.settings.wifiOnly(), isTrue);
    });

    test('[PRIV-001] location capture defaults to off', () async {
      expect(await env.settings.captureLocation(), isFalse);
      await env.settings.setCaptureLocation(value: true);
      expect(await env.settings.captureLocation(), isTrue);
    });

    test('read, write, overwrite and remove a raw key', () async {
      expect(await env.settings.read('k'), isNull);
      await env.settings.write('k', 'a');
      await env.settings.write('k', 'b');
      expect(await env.settings.read('k'), 'b');
      await env.settings.remove('k');
      expect(await env.settings.read('k'), isNull);
    });

    test('watch emits the current value and later changes', () async {
      final seen = <bool>[];
      final sub = env.settings.watchWifiOnly().listen(seen.add);
      await pumpEventQueue();
      await env.settings.setWifiOnly(value: false);
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [true, false]);
      final location = <bool>[];
      final sub2 = env.settings.watchCaptureLocation().listen(location.add);
      await pumpEventQueue();
      await env.settings.setCaptureLocation(value: true);
      await pumpEventQueue();
      await sub2.cancel();
      expect(location, [false, true]);
    });

    test('the low-battery threshold defaults to 15% and honors a stored value', () async {
      expect(await env.settings.lowBatteryPercent(), 15);
      await env.settings.write(SettingKeys.lowBatteryPercent, '30');
      expect(await env.settings.lowBatteryPercent(), 30);
      await env.settings.write(SettingKeys.lowBatteryPercent, 'junk');
      expect(await env.settings.lowBatteryPercent(), 15);
    });
  });

  group('AccountContext', () {
    test('[AUTH-005] starts anonymous, persists the account, and restores it', () async {
      expect(env.account.isSignedIn, isFalse);
      final changes = <String?>[];
      final sub = env.account.changes.listen(changes.add);
      await env.account.setAccount('u1');
      await env.account.setAccount('u1'); // no change, no event
      await pumpEventQueue();
      expect(env.account.accountId, 'u1');
      expect(await env.settings.read(SettingKeys.accountId), 'u1');

      final restored = await AccountContext.restore(env.settings);
      expect(restored.accountId, 'u1');
      await env.account.setAccount(null);
      await pumpEventQueue();
      expect(await env.settings.read(SettingKeys.accountId), isNull);
      expect(changes, ['u1', null]);
      await sub.cancel();
      await restored.dispose();
    });
  });

  group('UploadPolicy (SYNC-005)', () {
    const policy = UploadPolicy();
    const full = (percent: 100, charging: false);

    bool allows(NetworkKind n, {bool wifiOnly = true, ({int percent, bool charging}) power = full}) =>
        policy.allows(network: n, wifiOnly: wifiOnly, power: power, lowBatteryPercent: 15);

    test('never uploads while offline', () {
      expect(allows(NetworkKind.none, wifiOnly: false), isFalse);
    });
    test('Wi-Fi only blocks mobile data but allows Wi-Fi', () {
      expect(allows(NetworkKind.cellular), isFalse);
      expect(allows(NetworkKind.wifi), isTrue);
    });
    test('with Wi-Fi-only off, mobile data is allowed', () {
      expect(allows(NetworkKind.cellular, wifiOnly: false), isTrue);
    });
    test('a low battery pauses uploads unless charging', () {
      expect(allows(NetworkKind.wifi, power: (percent: 14, charging: false)), isFalse);
      expect(allows(NetworkKind.wifi, power: (percent: 15, charging: false)), isTrue);
      expect(allows(NetworkKind.wifi, power: (percent: 5, charging: true)), isTrue);
    });
    test('UnlimitedPower never limits', () async {
      expect((await const UnlimitedPower().current()).charging, isTrue);
    });
  });

  group('PresetRepository (EXP-006, EXP-007)', () {
    test('[EXP-007] creates, lists, edits, renames and deletes presets', () async {
      final a = await env.presets.save(name: ' Street 35 ', experienceId: 'mirrorless', intent: {'scenario': 'street'}, profileId: 'warm-film', profileVersion: 1, live: true);
      env.clock.advance(const Duration(minutes: 1));
      final b = await env.presets.save(name: 'Portrait', experienceId: 'instant', intent: const {});
      expect(a.name, 'Street 35');
      expect((await env.presets.list()).map((p) => p.name), ['Street 35', 'Portrait']);
      expect(jsonDecode(a.intentJson), {'scenario': 'street'});
      expect([a.live, a.profileId, a.source, a.dirty], [true, 'warm-film', 'user', true]);

      final renamed = await env.presets.save(id: a.id, name: 'Street 28', experienceId: 'mirrorless', intent: {'scenario': 'street'}, profileId: 'warm-film', profileVersion: 1, live: true);
      expect(renamed.name, 'Street 28');
      expect(renamed.createdAt, a.createdAt);

      expect(await env.presets.delete(b.id), isTrue);
      expect(await env.presets.delete(b.id), isFalse);
      expect(await env.presets.delete('nope'), isFalse);
      expect((await env.presets.list()).map((p) => p.id), [a.id]);
    });

    test('names must be 1 to 80 characters', () async {
      await expectLater(env.presets.save(name: '   ', experienceId: 'x', intent: const {}), throwsArgumentError);
      await expectLater(env.presets.save(name: 'x' * 81, experienceId: 'x', intent: const {}), throwsArgumentError);
    });

    test('[SYNC-002] anonymous changes are not queued; signed-in ones replace earlier queued ops for the preset', () async {
      await env.presets.save(name: 'Local', experienceId: 'x', intent: const {});
      expect(await env.db.select(env.db.outbox).get(), isEmpty);

      await env.account.setAccount('u1');
      final p = await env.presets.save(name: 'One', experienceId: 'x', intent: const {});
      await env.presets.save(id: p.id, name: 'Two', experienceId: 'x', intent: const {});
      var ops = await env.db.select(env.db.outbox).get();
      expect(ops.map((o) => o.op), ['upsert']);
      await env.presets.delete(p.id);
      ops = await env.db.select(env.db.outbox).get();
      expect(ops.map((o) => o.op), ['delete']);
    });

    test('watch emits as presets change, and get returns a single row', () async {
      final names = <List<String>>[];
      final sub = env.presets.watch().listen((rows) => names.add([for (final r in rows) r.name]));
      await pumpEventQueue();
      final p = await env.presets.save(name: 'A', experienceId: 'x', intent: const {});
      await pumpEventQueue();
      await sub.cancel();
      expect(names, [<String>[], ['A']]);
      expect((await env.presets.get(p.id))!.name, 'A');
      expect(await env.presets.get('nope'), isNull);
    });

    test('saving a deleted preset again brings it back', () async {
      final p = await env.presets.save(name: 'A', experienceId: 'x', intent: const {});
      await env.presets.delete(p.id);
      await env.presets.save(id: p.id, name: 'A2', experienceId: 'x', intent: const {});
      expect((await env.presets.list()).single.name, 'A2');
    });
  });
}
