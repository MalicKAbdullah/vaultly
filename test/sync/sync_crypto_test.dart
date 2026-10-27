import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';
import 'package:vaultkey/src/features/sync/crypto/pairing.dart';
import 'package:vaultkey/src/features/sync/crypto/sync_crypto.dart';
import 'package:vaultkey/src/features/sync/services/sync_exchange.dart';
import 'package:vaultkey/src/features/sync/services/sync_merge.dart';
import 'package:vaultkey/src/features/sync/services/sync_network.dart';

import '../fakes/fakes.dart';

/// Rewrites the n-th frame (header + payload) sent from A to B.
typedef Tamper = List<int> Function(int index, List<int> frame);

/// Two connected [FrameChannel]s over in-memory streams. Every frame A
/// sends is also recorded in [wire], which is what an eavesdropper sees.
final class Pipe {
  Pipe({Tamper? tamper}) {
    var index = 0;
    a = FrameChannel(
      input: _bToA.stream,
      output: (bytes) {
        final out = tamper == null ? bytes : tamper(index, bytes);
        index++;
        wire.add(Uint8List.fromList(out));
        _aToB.add(out);
      },
      close: _aToB.close,
    );
    b = FrameChannel(
      input: _aToB.stream,
      output: (bytes) {
        wire.add(Uint8List.fromList(bytes));
        _bToA.add(bytes);
      },
      close: _bToA.close,
    );
  }

  final _aToB = StreamController<List<int>>();
  final _bToA = StreamController<List<int>>();
  final wire = <Uint8List>[];
  late final FrameChannel a;
  late final FrameChannel b;
}

final _key = Uint8List.fromList(List.generate(32, (i) => i));
final _otherKey = Uint8List.fromList(List.generate(32, (i) => 255 - i));

Future<(SecureChannel, SecureChannel)> _connect(
  Pipe pipe, {
  List<int>? initiatorKey,
  List<int>? responderKey,
}) async {
  final responder = SyncHandshake.respond(
    channel: pipe.b,
    myId: 'phone-b',
    keyFor: (id) async => id == 'phone-a' ? (responderKey ?? _key) : null,
  );
  final initiator = SyncHandshake.initiate(
    channel: pipe.a,
    myId: 'phone-a',
    peerId: 'phone-b',
    pairingKey: initiatorKey ?? _key,
  );
  final results = await Future.wait(
    [initiator, responder.then((r) => r.$1)],
    eagerError: true,
  );
  return (results[0], results[1]);
}

bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  group('FrameChannel', () {
    test('delivers frames split across and merged within chunks', () async {
      final controller = StreamController<List<int>>();
      final sent = <List<int>>[];
      final channel = FrameChannel(
        input: controller.stream,
        output: sent.add,
        close: () async {},
      );
      final writer = FrameChannel(
        input: const Stream.empty(),
        output: sent.add,
        close: () async {},
      );
      writer.send([1, 2, 3]);
      writer.send(List.filled(300, 9));
      final bytes = [...sent[0], ...sent[1]];
      controller.add(bytes.sublist(0, 2));
      controller.add(bytes.sublist(2, 9));
      controller.add(bytes.sublist(9));
      expect(await channel.receive(), [1, 2, 3]);
      expect(await channel.receive(), List.filled(300, 9));
    });

    test('refuses an oversized frame header', () async {
      final controller = StreamController<List<int>>();
      final channel = FrameChannel(
        input: controller.stream,
        output: (_) {},
        close: () async {},
      );
      controller.add([0xFF, 0xFF, 0xFF, 0xFF]);
      await expectLater(
        channel.receive(),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('reports a closed connection', () async {
      final controller = StreamController<List<int>>();
      final channel = FrameChannel(
        input: controller.stream,
        output: (_) {},
        close: () async {},
      );
      unawaited(controller.close());
      await expectLater(
        channel.receive(),
        throwsA(isA<SyncProtocolException>()),
      );
    });
  });

  group('SyncHandshake + SecureChannel', () {
    test('round-trips data both ways with the pairing key', () async {
      final pipe = Pipe();
      final (a, b) = await _connect(pipe);
      await a.send(utf8.encode('hello from a'));
      await b.send(utf8.encode('hello from b'));
      expect(utf8.decode(await b.receive()), 'hello from a');
      expect(utf8.decode(await a.receive()), 'hello from b');
    });

    test('only ciphertext crosses the wire', () async {
      final pipe = Pipe();
      final (a, b) = await _connect(pipe);
      final secret = utf8.encode('correct horse battery staple');
      await a.send(secret);
      expect(await b.receive(), secret);
      for (final frame in pipe.wire) {
        expect(_contains(frame, secret), isFalse);
        expect(_contains(frame, _key), isFalse);
      }
    });

    test('a different pairing key is rejected', () async {
      final pipe = Pipe();
      await expectLater(
        _connect(pipe, responderKey: _otherKey),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('an unpaired device is refused', () async {
      final pipe = Pipe();
      final responder = SyncHandshake.respond(
        channel: pipe.b,
        myId: 'phone-b',
        keyFor: (_) async => null,
      );
      SyncHandshake.initiate(
        channel: pipe.a,
        myId: 'stranger',
        peerId: 'phone-b',
        pairingKey: _key,
      ).ignore();
      await expectLater(responder, throwsA(isA<SyncProtocolException>()));
      await pipe.b.close();
    });

    test('a flipped bit in an encrypted frame is rejected', () async {
      // Frames from A: 0 hello, 1 key confirmation, 2 first data frame.
      final pipe = Pipe(
        tamper: (i, f) => i == 2 ? ([...f]..[f.length - 1] ^= 0x01) : f,
      );
      final (a, b) = await _connect(pipe);
      await a.send(utf8.encode('payload'));
      await expectLater(b.receive(), throwsA(isA<SyncProtocolException>()));
    });

    test('a replayed frame is rejected', () async {
      List<int>? first;
      final pipe = Pipe(
        tamper: (i, f) {
          if (i == 2) first = f;
          return i == 3 ? first! : f;
        },
      );
      final (a, b) = await _connect(pipe);
      await a.send(utf8.encode('one'));
      await a.send(utf8.encode('two'));
      expect(utf8.decode(await b.receive()), 'one');
      await expectLater(b.receive(), throwsA(isA<SyncProtocolException>()));
    });

    test('a swapped hello key fails the handshake', () async {
      final pipe = Pipe(
        tamper: (i, f) {
          if (i != 0) return f;
          final json =
              jsonDecode(utf8.decode(f.sublist(4))) as Map<String, dynamic>;
          json['e'] = base64.encode(List.filled(32, 9));
          final body = utf8.encode(jsonEncode(json));
          final header = ByteData(4)..setUint32(0, body.length);
          return [...header.buffer.asUint8List(), ...body];
        },
      );
      await expectLater(_connect(pipe), throwsA(isA<SyncProtocolException>()));
    });
  });

  group('Pairing', () {
    Future<(PairingResult, PairingResult)> pair({
      Tamper? tamper,
      Uint8List? scannedSecret,
    }) async {
      final keyPair = await SyncPrimitives.x25519.newKeyPair();
      final invite = PairingInvite(
        deviceId: 'inviter',
        deviceName: 'Pixel',
        publicKey: await SyncPrimitives.publicKeyOf(keyPair),
        secret: SyncPrimitives.randomBytes(32),
        hosts: const ['192.168.1.20'],
        port: 4040,
      );
      final scanned = PairingInvite.parse(invite.toQr());
      final joinerView = scannedSecret == null
          ? scanned
          : PairingInvite(
              deviceId: scanned.deviceId,
              deviceName: scanned.deviceName,
              publicKey: scanned.publicKey,
              secret: scannedSecret,
              hosts: scanned.hosts,
              port: scanned.port,
            );
      final pipe = Pipe(tamper: tamper);
      final results = await Future.wait([
        Pairing.inviterHandshake(
          channel: pipe.b,
          keyPair: keyPair,
          invite: invite,
        ),
        Pairing.joinerHandshake(
          channel: pipe.a,
          invite: joinerView,
          myId: 'joiner',
          myName: 'iPhone',
        ),
      ], eagerError: true);
      return (results[0], results[1]);
    }

    test('both devices derive the same key and SAS', () async {
      final (inviter, joiner) = await pair();
      expect(inviter.syncKey, joiner.syncKey);
      expect(inviter.syncKey, hasLength(32));
      expect(inviter.sas, joiner.sas);
      expect(inviter.sas, matches(RegExp(r'^\d{6}$')));
      expect(inviter.peerId, 'joiner');
      expect(inviter.peerName, 'iPhone');
      expect(joiner.peerId, 'inviter');
      expect(joiner.peerName, 'Pixel');
    });

    test('a device that did not scan the code is refused', () async {
      await expectLater(
        pair(scannedSecret: Uint8List(32)),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('a substituted joiner key is caught', () async {
      await expectLater(
        pair(
          tamper: (i, f) {
            if (i != 0) return f;
            final json =
                jsonDecode(utf8.decode(f.sublist(4))) as Map<String, dynamic>;
            json['k'] = base64.encode(List.filled(32, 5));
            final body = utf8.encode(jsonEncode(json));
            final header = ByteData(4)..setUint32(0, body.length);
            return [...header.buffer.asUint8List(), ...body];
          },
        ),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('the invite QR round-trips and rejects other codes', () {
      final invite = PairingInvite(
        deviceId: 'id-1',
        deviceName: 'Pixel · AB12',
        publicKey: Uint8List(32)..[0] = 1,
        secret: Uint8List(32)..[1] = 2,
        hosts: const ['10.0.0.2', '192.168.0.4'],
        port: 51515,
      );
      final back = PairingInvite.parse(invite.toQr());
      expect(back.deviceName, 'Pixel · AB12');
      expect(back.publicKey, invite.publicKey);
      expect(back.secret, invite.secret);
      expect(back.hosts, invite.hosts);
      expect(back.port, 51515);
      expect(
        () => PairingInvite.parse('otpauth://totp/x?secret=AAAA'),
        throwsA(isA<SyncProtocolException>()),
      );
      expect(
        () => PairingInvite.parse('vaultly-pair://v1?d=x'),
        throwsA(isA<SyncProtocolException>()),
      );
    });

    test('confirmation succeeds only when both people accept', () async {
      Future<(bool, bool)> confirm(bool inviterOk, bool joinerOk) async {
        final (result, _) = await pair();
        final pipe = Pipe();
        final r = await Future.wait([
          Pairing.exchangeConfirmation(
            channel: pipe.b,
            result: result,
            inviter: true,
            accepted: inviterOk,
          ),
          Pairing.exchangeConfirmation(
            channel: pipe.a,
            result: result,
            inviter: false,
            accepted: joinerOk,
          ),
        ]);
        return (r[0], r[1]);
      }

      expect(await confirm(true, true), (true, true));
      expect(await confirm(true, false), (false, false));
      expect(await confirm(false, true), (false, false));
    });
  });

  group('SyncExchange', () {
    test('both sides end with the same merged vault', () async {
      final pipe = Pipe();
      final (a, b) = await _connect(pipe);
      final t = DateTime.utc(2026, 10, 3);
      final localA = SyncSnapshot(
        entries: [makeEntry(id: 'x', title: 'Only on A', updatedAt: t)],
        tombstones: const {},
      );
      final localB = SyncSnapshot(
        entries: [makeEntry(id: 'y', title: 'Only on B', updatedAt: t)],
        tombstones: const {},
      );
      final results = await Future.wait([
        SyncExchange.run(a, localA),
        SyncExchange.run(b, localB),
      ]);
      expect(
        results[0].snapshot.entries.map((e) => e.id).toSet(),
        {'x', 'y'},
      );
      expect(
        results[1].snapshot.entries.map((e) => e.id).toSet(),
        {'x', 'y'},
      );
      expect(results[0].changes, 2);
      for (final frame in pipe.wire) {
        expect(_contains(frame, utf8.encode('Only on A')), isFalse);
      }
    });
  });

  test('handshake and exchange over a real loopback TCP socket', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final responder = server.first.then((socket) async {
      final channel = SyncNetwork.channelFor(socket);
      final (secure, peer) = await SyncHandshake.respond(
        channel: channel,
        myId: 'phone-b',
        keyFor: (id) async => _key,
      );
      final got = await secure.receive();
      await secure.send(got.reversed.toList());
      await channel.close();
      return peer;
    });
    final channel = SyncNetwork.channelFor(
      await SyncNetwork.connect(['127.0.0.1'], server.port),
    );
    final secure = await SyncHandshake.initiate(
      channel: channel,
      myId: 'phone-a',
      peerId: 'phone-b',
      pairingKey: _key,
    );
    await secure.send([1, 2, 3]);
    expect(await secure.receive(), [3, 2, 1]);
    expect(await responder, 'phone-a');
    await channel.close();
  });
}
