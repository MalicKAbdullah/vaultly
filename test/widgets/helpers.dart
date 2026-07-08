import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';
import 'package:vaultkey/src/features/vault/providers/vault_providers.dart';

/// A [VaultNotifier] whose vault lives purely in memory: no session, no
/// repository, no encryption. Widget tests seed it with entries.
class FakeVaultNotifier extends VaultNotifier {
  FakeVaultNotifier(this.seed);

  final List<VaultEntry> seed;

  @override
  Future<List<VaultEntry>> build() async => seed;

  @override
  Future<void> commit(List<VaultEntry> entries) async {
    state = AsyncData(entries);
  }
}
