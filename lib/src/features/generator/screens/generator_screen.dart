import 'package:core_theme/core_theme.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/core/ui/vault_ui.dart';
import 'package:vaultkey/src/features/generator/widgets/generator_panel.dart';

/// Full-screen password generator tab.
class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(bottom: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TabHeader(eyebrow: 'Strong and random', title: 'Generator'),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: GeneratorPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
