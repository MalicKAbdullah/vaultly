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

  group('AutofillMatcher.score — browser web forms', () {
    // A login form inside Chrome: the package is the browser, the real
    // signal is the reported web domain.
    test('a browser request matches on the web domain, not the package', () {
      const request = AutofillFillRequest(
        domain: 'github.com',
        package: 'com.android.chrome',
      );
      expect(
        AutofillMatcher.score(makeEntry(url: 'github.com'), request),
        100,
      );
    });

    test('the browser package itself never matches a vault entry', () {
      // Entry that happens to look like a browser must not match just
      // because the request came from that browser.
      const request = AutofillFillRequest(package: 'com.android.chrome');
      expect(
        AutofillMatcher.score(
          makeEntry(title: 'Chrome tips', url: 'chrome.example'),
          request,
        ),
        0,
      );
    });

    test('a Firefox request with no domain does not match on the package', () {
      const request = AutofillFillRequest(package: 'org.mozilla.firefox');
      expect(
        AutofillMatcher.score(
          makeEntry(title: 'Mozilla account', url: 'mozilla.example'),
          request,
        ),
        0,
      );
    });

    test('anything whose package contains "browser" is treated as a browser',
        () {
      const request = AutofillFillRequest(
        package: 'com.some.unknownbrowser',
        domain: 'example.com',
      );
      // Domain still drives the match; the browser package adds nothing.
      expect(
        AutofillMatcher.score(makeEntry(url: 'example.com'), request),
        100,
      );
      expect(
        AutofillMatcher.score(
          makeEntry(title: 'unknownbrowser notes', url: ''),
          const AutofillFillRequest(package: 'com.some.unknownbrowser'),
        ),
        0,
      );
    });

    test('a subdomain web form still ranks against the base entry', () {
      const request = AutofillFillRequest(
        domain: 'accounts.google.com',
        package: 'com.android.chrome',
      );
      expect(
        AutofillMatcher.score(makeEntry(url: 'google.com'), request),
        80,
      );
    });

    test('rank picks the domain-matching entry for a browser request', () {
      final gh = makeEntry(id: 'gh', title: 'GitHub', url: 'github.com');
      final bank = makeEntry(id: 'bank', title: 'Bank', url: 'bank.example');
      final ranked = AutofillMatcher.rank(
        [bank, gh],
        const AutofillFillRequest(
          domain: 'github.com',
          package: 'com.android.chrome',
        ),
      );
      expect(ranked.map((e) => e.id), ['gh']);
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
