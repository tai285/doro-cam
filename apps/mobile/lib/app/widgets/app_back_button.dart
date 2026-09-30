import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Back navigation to an explicit [location] (screens are top-level routes, not a stack).
///
/// The label is on the icon's semantics as well as the tooltip: a tooltip alone leaves the
/// accessibility node without a name on some platforms (NFR-007).
class AppBackButton extends StatelessWidget {
  const AppBackButton({required this.label, required this.location, super.key});

  final String label;
  final String location;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      icon: Icon(Icons.arrow_back, semanticLabel: label),
      onPressed: () => context.go(location),
    );
  }
}
