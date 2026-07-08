import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/features/generator/widgets/generator_panel.dart';

/// Full-screen password generator tab.
class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Generator')),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(AppSpacing.md),
        child: GeneratorPanel(),
      ),
    );
  }
}
