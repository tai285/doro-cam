import 'package:doro_cam/app/router.dart';
import 'package:doro_cam/app/widgets/app_back_button.dart';
import 'package:flutter/material.dart';

/// Placeholder. Memory detail arrives with LIB-T-002.
class MemoryDetailScreen extends StatelessWidget {
  const MemoryDetailScreen({required this.memoryId, super.key});

  final String memoryId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(label: 'Back to library', location: AppRoutes.library),
        title: const Text('Memory'),
      ),
      body: Center(child: Text('Memory $memoryId')),
    );
  }
}
