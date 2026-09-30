import 'package:doro_cam/app/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Placeholder home screen. The viewfinder and controls arrive with CAM-T-007.
class CameraScreen extends StatelessWidget {
  const CameraScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Expanded(
              child: Center(child: Text('Camera', key: Key('camera-title'))),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () => context.go(AppRoutes.library),
                    child: const Text('Library'),
                  ),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.settings),
                    child: const Text('Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
