import 'dart:convert';

import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:doro_cam/data/db/app_database.dart';
import 'package:doro_cam/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Rename and delete presets (EXP-007). They sync through the account like everything else.
class PresetsScreen extends ConsumerWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = (ref.watch(presetsProvider).value ?? const <PresetRow>[])
        .where((p) => p.deletedAt == null)
        .toList();
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(
          label: 'Back to settings',
          location: AppRoutes.settings,
        ),
        title: const Text('Presets'),
      ),
      body: presets.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No presets yet. Set up the camera the way you like, then choose “Presets → Save current settings”.',
                  key: Key('presets-empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: <Widget>[
                for (final preset in presets)
                  ListTile(
                    key: Key('preset-row-${preset.id}'),
                    title: Text(preset.name),
                    subtitle: Text(
                      '${preset.experienceId}${preset.profileId == null ? '' : ' · ${preset.profileId}'}${preset.live ? ' · LIVE' : ''}${preset.source == 'suggested' ? ' · suggested' : ''}',
                    ),
                    trailing: Wrap(
                      children: <Widget>[
                        IconButton(
                          key: Key('rename-${preset.id}'),
                          tooltip: 'Rename ${preset.name}',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _rename(context, ref, preset),
                        ),
                        IconButton(
                          key: Key('delete-${preset.id}'),
                          tooltip: 'Delete ${preset.name}',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(context, ref, preset),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _rename(
    BuildContext context,
    WidgetRef ref,
    PresetRow preset,
  ) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: preset.name),
    );
    if (name != null && name.isNotEmpty) {
      await ref
          .read(presetRepositoryProvider)
          .save(
            id: preset.id,
            name: name,
            experienceId: preset.experienceId,
            intent: jsonDecodeObject(preset.intentJson),
            profileId: preset.profileId,
            profileVersion: preset.profileVersion,
            live: preset.live,
            source: preset.source,
          );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    PresetRow preset,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${preset.name}”?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('delete-preset-confirm'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok ?? false) {
      await ref.read(presetRepositoryProvider).delete(preset.id);
    }
  }
}

Map<String, Object?> jsonDecodeObject(String source) {
  try {
    return Map<String, Object?>.from(
      jsonDecode(source) as Map<Object?, Object?>,
    );
  } on Object {
    return <String, Object?>{};
  }
}

/// Owns its text controller, so it is disposed only after the dialog has fully left the screen.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename preset'),
    content: TextField(
      key: const Key('rename-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 80,
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const Key('rename-save'),
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Save'),
      ),
    ],
  );
}
