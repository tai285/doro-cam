import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:doro_cam/features/camera/application/camera_controller.dart';
import 'package:doro_cam/features/settings/presentation/account_section.dart';
import 'package:doro_cam/platform/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Settings: backup, privacy, camera behaviour, account and the places that need a signed-in account.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _locationMessage;

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsRepositoryProvider);
    final wifiOnly = ref.watch(wifiOnlyProvider).value ?? true;
    final location = ref.watch(captureLocationProvider).value ?? false;
    final authentic = ref.watch(
      cameraControllerProvider.select((s) => s.authentic),
    );
    final signedIn = ref.watch(accountIdProvider).value != null;
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to camera',
          location: AppRoutes.camera,
        ),
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _Header('Backup'),
            SwitchListTile(
              key: const Key('wifi-only'),
              title: const Text('Upload on Wi-Fi only'),
              subtitle: const Text(
                'Photos and motion upload at original quality. Turn this off to also use mobile data.',
              ),
              value: wifiOnly,
              onChanged: (v) => settings.setWifiOnly(value: v),
            ),
            ListTile(
              key: const Key('open-sync'),
              leading: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Backup status'),
              subtitle: const Text('What’s uploaded, what’s waiting'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.sync),
            ),
            const _Header('Privacy'),
            SwitchListTile(
              key: const Key('capture-location'),
              title: const Text('Add location to photos'),
              subtitle: Text(
                _locationMessage ?? 'Off by default. When on, the place a photo was taken is saved with it and is never shared unless you allow it.',
              ),
              value: location,
              onChanged: (v) async {
                if (v &&
                    !await ref
                        .read(locationServiceProvider)
                        .requestPermission()) {
                  setState(
                    () => _locationMessage = 'Location access was not allowed, so photos won’t include a location.',
                  );
                  return;
                }
                setState(() => _locationMessage = null);
                await settings.setCaptureLocation(value: v);
              },
            ),
            const _Header('Camera'),
            SwitchListTile(
              key: const Key('authentic-mode'),
              title: const Text('Authentic constraints'),
              subtitle: const Text(
                'Keep each camera style true to its original: locked settings can’t be overridden.',
              ),
              value: authentic,
              onChanged: (v) => ref
                  .read(cameraControllerProvider.notifier)
                  .setAuthentic(value: v),
            ),
            ListTile(
              key: const Key('open-presets'),
              leading: const Icon(Icons.bookmarks_outlined),
              title: const Text('Presets'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.presets),
            ),
            const _Header('Account'),
            const AccountSection(),
            if (signedIn) ...<Widget>[
              const _Header('Share and explore'),
              ListTile(
                key: const Key('open-albums'),
                leading: const Icon(Icons.photo_album_outlined),
                title: const Text('Albums and trips'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.albums),
              ),
              ListTile(
                key: const Key('open-insights'),
                leading: const Icon(Icons.insights_outlined),
                title: const Text('Photography insights'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.insights),
              ),
            ],
            const _Header('About'),
            ListTile(
              title: const Text('Doro Cam'),
              subtitle: Text('Version ${ref.watch(appVersionProvider)}'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}
