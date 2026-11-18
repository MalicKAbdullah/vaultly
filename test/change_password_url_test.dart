import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/health/services/change_password_url.dart';

void main() {
  String? url(String s) => ChangePasswordUrl.forEntry(s)?.toString();

  test('a bare host', () {
    expect(url('github.com'), 'https://github.com/.well-known/change-password');
  });

  test('a full URL keeps only the host', () {
    expect(
      url('https://accounts.google.com/signin/v2?x=1#top'),
      'https://accounts.google.com/.well-known/change-password',
    );
  });

  test('http is upgraded to https', () {
    expect(
      url('http://example.org/login'),
      'https://example.org/.well-known/change-password',
    );
  });

  test('a port is kept, a host with a path and no scheme works', () {
    expect(
      url('example.org:8443/account'),
      'https://example.org:8443/.well-known/change-password',
    );
  });

  test('an international host name is kept as written', () {
    expect(
      Uri.parse(url('https://bücher.example')!).host,
      isNotEmpty,
    );
  });

  test('no website means no URL', () {
    expect(url(''), isNull);
    expect(url('   '), isNull);
  });
}
