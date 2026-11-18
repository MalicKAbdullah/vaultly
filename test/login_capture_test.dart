import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/services/login_capture.dart';
import 'package:vaultkey/src/features/vault/models/vault_entry.dart';

import 'fakes/fakes.dart';

void main() {
  final github = makeEntry(
    id: 'gh',
    title: 'GitHub',
    username: 'Ada',
    password: 'old',
    url: 'github.com',
  );
  final work = makeEntry(
    id: 'gh2',
    title: 'GitHub work',
    username: 'ada-work',
    password: 'w',
    url: 'github.com',
  );
  const web = CapturedLogin(
    username: 'ada',
    password: 'new',
    host: 'github.com',
  );

  test('the same login is already saved', () {
    final d = LoginCapture.decide(
        [github],
        const CapturedLogin(
          username: 'ADA',
          password: 'old',
          host: 'github.com',
        ));
    expect(d, isA<AlreadySaved>());
  });

  test('the same account with a new password is an update', () {
    final d = LoginCapture.decide([github, work], web);
    expect((d as UpdatePassword).entry.id, 'gh');
  });

  test('another account on the same site is saved as new', () {
    final d = LoginCapture.decide(
      [github],
      const CapturedLogin(username: 'bob', password: 'p', host: 'github.com'),
    );
    expect(d, isA<SaveNew>());
    expect((d as SaveNew).title, 'github.com');
    expect(d.url, 'github.com');
  });

  test('a password-only step belongs to the only entry there is', () {
    final d = LoginCapture.decide(
      [github],
      const CapturedLogin(username: '', password: 'new', host: 'github.com'),
    );
    expect((d as UpdatePassword).entry.id, 'gh');
    final two = LoginCapture.decide(
      [github, work],
      const CapturedLogin(username: '', password: 'new', host: 'github.com'),
    );
    expect(two, isA<SaveNew>());
  });

  test('a title-only match is not the same site', () {
    final d = LoginCapture.decide(
      [makeEntry(id: 'x', title: 'github fan club', username: 'ada', url: '')],
      web,
    );
    expect(d, isA<SaveNew>());
  });

  test('passkeys and non-logins are never updated', () {
    final note = makeEntry(
      id: 'n',
      username: 'ada',
      url: 'github.com',
      category: EntryCategory.note,
    );
    expect(LoginCapture.decide([note], web), isA<SaveNew>());
  });

  test('a fix target wins over the username rule', () {
    final d = LoginCapture.decide(
      [github, work],
      const CapturedLogin(username: 'ada', password: 'new', host: 'github.com'),
      fixEntryId: 'gh2',
    );
    expect((d as UpdatePassword).entry.id, 'gh2');
  });

  test('an app is saved under a name taken from its package', () {
    final d = LoginCapture.decide(
      const [],
      const CapturedLogin(
        username: 'u',
        password: 'p',
        package: 'com.example.shopfast',
      ),
    );
    expect((d as SaveNew).title, 'Shopfast');
    expect(d.url, '');
  });
}
