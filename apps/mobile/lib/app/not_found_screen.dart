import 'package:doro_cam/app/router.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({required this.location, super.key});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('There is nothing at $location'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppRoutes.camera),
              child: const Text('Back to camera'),
            ),
          ],
        ),
      ),
    );
  }
}
