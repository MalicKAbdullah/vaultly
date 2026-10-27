import 'package:core_theme/core_theme.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:vaultkey/src/features/importers/parsers/csv_importers.dart';
import 'package:vaultkey/src/features/importers/screens/import_preview_screen.dart';

/// Lets the user say which CSV column feeds which vault field, with the
/// first row shown as a sample, before previewing the import.
class CsvMappingScreen extends StatefulWidget {
  const CsvMappingScreen({
    required this.table,
    required this.suggested,
    super.key,
  });

  final CsvTable table;
  final CsvColumnMapping suggested;

  @override
  State<CsvMappingScreen> createState() => _CsvMappingScreenState();
}

class _CsvMappingScreenState extends State<CsvMappingScreen> {
  late CsvColumnMapping _mapping = widget.suggested;

  /// Sentinel for "not imported" in the column pickers.
  static const int _unused = -1;

  String _sample(int column) {
    for (final row in widget.table.rows) {
      if (column < row.length && row[column].trim().isNotEmpty) {
        return row[column].trim();
      }
    }
    return '';
  }

  void _continue() {
    final batch = CsvImporters.generic(widget.table, _mapping);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ImportPreviewScreen(batch: batch),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SuiteColors.of(context);
    final header = widget.table.header;
    final options = [
      const AppSelectOption(value: _unused, label: 'Not imported'),
      for (var i = 0; i < header.length; i++)
        AppSelectOption(
          value: i,
          label: header[i].isEmpty ? 'Column ${i + 1}' : header[i],
        ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Match columns')),
      bottomNavigationBar: BottomActionBar(
        primary: VaultButton(
          label: 'Continue',
          onPressed: _mapping.isUsable ? _continue : null,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          AppSpacing.sm,
          AppSpacing.gutter,
          AppSpacing.xl,
        ),
        children: [
          Text(
            'Tell Vaultly which column holds each detail. '
            '${widget.table.rows.length} rows found.',
            style: AppTextStyles.bodySmall.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          for (final field in ImportField.values) ...[
            AppSelectField<int>(
              label: field.label,
              options: options,
              value: _mapping.columns[field] ?? _unused,
              onChanged: (col) => setState(
                () => _mapping =
                    _mapping.withColumn(field, col == _unused ? null : col),
              ),
            ),
            if (_mapping.columns[field] case final col?)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.xs,
                  left: AppSpacing.md,
                ),
                child: Text(
                  field == ImportField.password || field == ImportField.totp
                      ? 'Sample hidden'
                      : 'Sample: ${_sample(col).isEmpty ? '(empty)' : _sample(col)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(color: c.textTertiary),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],
      ),
    );
  }
}
