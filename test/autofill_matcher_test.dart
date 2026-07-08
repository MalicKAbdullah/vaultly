import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/core/interfaces/autofill_bridge.dart';
import 'package:vaultkey/src/features/autofill/services/autofill_matcher.dart';

import 'fakes/fakes.dart';

void main() {
  group('AutofillMatcher.score', () {
    test('exact host match scores highest', () {
      final entry = makeEntry(url: 'https://github.com/login');
      expect(
        AutofillMatcher.score(
          entry,
          const AutofillFillRequest(domain: 'github.com'),
        ),
        100,
      );
    });

    test('www. and scheme differences do not matter', () {
      final entry = makeEntry(url: 'www.github.com');
      expect(
        AutofillMatcher.score(
          entry,
          const AutofillFillRequest(domain: 'github.com'),
        ),
        100,
      );
    });

    test('subdomain of the entry host is a suffix match', () {
      final entry = makeEntry(url: 'google.com');
      expect(
        AutofillMatcher.score(
          entry,
          const AutofillFillRequest(domain: 'accounts.google.com'),
        ),
        80,
      );
    });

    test('entry stored with a subdomain still matches the bare domain', () {
      final entry = makeEntry(url: 'accounts.google.com');
      expect(
        AutofillMatcher.score(
          entry,
          const AutofillFillRequest(domain: 'google.com'),
        ),
        80,
      );
    });

    test(
        'an unrelated host that merely ends with the same letters does '
        'not match', () {
      final entry = makeEntry(url: 'notgithub.com');
      expect(
        AutofillMatcher.score(
          entry,
          const AutofillFillRequest(domain: 'github.com'),
        ),
        0,
      );
    });

    test('title containing the domain base ranks below a host match', () {
      final byTitle = makeEntry(title: 'GitHub work account', url: '');
      final byHost = makeEntry(url: 'github.com');
      const request = AutofillFillRequest(domain: 'github.com');
      final titleScore = AutofillMatcher.score(byTitle, request);
      final hostScore = AutofillMatcher.score(byHost, request);
      expect(titleScore, greaterThan(0));
      expect(hostScore, greaterThan(titleScore));
    });

    test('app package segments match entry url and title', () {
      const request = AutofillFillRequest(package: 'com.github.android');
      expect(
        AutofillMatcher.score(makeEntry(url: 'github.com'), request),
        60,
      );
      expect(
        AutofillMatcher.score(
          makeEntry(title: 'GitHub', url: ''),
          request,
        ),
        40,
      );
    });

    test('generic package segments (com/android) never match', () {
      const request = AutofillFillRequest(package: 'com.android.settings');
      expect(
        AutofillMatcher.score(
          makeEntry(title: 'Company intranet', url: 'com.example'),
          request,
        ),
        0,
      );
    });

    test('no domain and no package means no match', () {
      expect(
        AutofillMatcher.score(makeEntry(), const AutofillFillRequest()),
        0,
      );
    });
  });

  group('AutofillMatcher.rank', () {
    test('orders by score and drops non-matches', () {
      final exact = makeEntry(id: '1', title: 'GitHub', url: 'github.com');
      final titleOnly =
          makeEntry(id: '2', title: 'GitHub backup codes', url: '');
      final unrelated = makeEntry(id: '3', title: 'Bank', url: 'bank.example');
      final ranked = AutofillMatcher.rank(
        [unrelated, titleOnly, exact],
        const AutofillFillRequest(domain: 'github.com'),
      );
      expect(ranked.map((e) => e.id), ['1', '2']);
    });

    test('ties are broken alphabetically by title', () {
      final b = makeEntry(id: 'b', title: 'Beta', url: 'site.example');
      final a = makeEntry(id: 'a', title: 'Alpha', url: 'site.example');
      final ranked = AutofillMatcher.rank(
        [b, a],
        const AutofillFillRequest(domain: 'site.example'),
      );
      expect(ranked.map((e) => e.id), ['a', 'b']);
    });

    test('returns empty when nothing matches (caller falls back to all)', () {
      final ranked = AutofillMatcher.rank(
        [makeEntry(url: 'bank.example')],
        const AutofillFillRequest(domain: 'github.com'),
      );
      expect(ranked, isEmpty);
    });
  });
}
