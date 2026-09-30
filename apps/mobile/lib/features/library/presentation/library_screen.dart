import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:flutter/material.dart';

/// Placeholder. The local library grid arrives with LIB-T-001.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: 'Back to camera', location: AppRoutes.camera),
        title: const Text('Library'),
      ),
      body: const Center(child: Text('No memories yet')),
    );
  }
}
