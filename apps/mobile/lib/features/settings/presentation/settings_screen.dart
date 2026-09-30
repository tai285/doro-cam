import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:flutter/material.dart';

/// Placeholder. Account, sync, privacy and storage settings arrive in later phases.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: 'Back to camera', location: AppRoutes.camera),
        title: const Text('Settings'),
      ),
      body: const Center(child: Text('Settings')),
    );
  }
}
