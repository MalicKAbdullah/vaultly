import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;
import 'package:vaultkey/src/features/sync/crypto/frame_channel.dart';

/// A device announcing itself for sync on the local network.
final class SyncPeerAnnouncement {
  const SyncPeerAnnouncement({
    required this.deviceId,
    required this.hosts,
    required this.port,
  });

  final String deviceId;
  final List<String> hosts;
  final int port;
}

/// Local-network plumbing: TCP listeners, outgoing connections, and mDNS /
/// NSD announcement and discovery of `_vaultly._tcp`. Not unit-tested
/// (platform channels and real networking); the protocol above it is.
abstract final class SyncNetwork {
  static const String serviceType = '_vaultly._tcp';

  /// Wraps [socket] in a [FrameChannel].
  static FrameChannel channelFor(Socket socket) {
    socket.setOption(SocketOption.tcpNoDelay, true);
    return FrameChannel(
      input: socket,
      output: socket.add,
      close: () async {
        await socket.flush().catchError((Object _) {});
        socket.destroy();
      },
    );
  }

  /// Non-loopback IPv4 addresses of this device (Wi-Fi, hotspot, Ethernet).
  static Future<List<String>> localAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
  }

  /// Connects to the first of [hosts] that answers on [port].
  static Future<Socket> connect(List<String> hosts, int port) async {
    for (final host in hosts) {
      try {
        return await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 4),
        );
      } on SocketException {
        continue;
      }
    }
    throw const SyncProtocolException(
      'Could not reach the other device. Check both are on the same Wi-Fi.',
    );
  }

  /// Announces this device ([deviceId] in the TXT record) on [port].
  static Future<nsd.Registration> announce({
    required String deviceId,
    required int port,
  }) =>
      nsd.register(nsd.Service(
        name: 'Vaultly ${deviceId.substring(0, 8)}',
        type: serviceType,
        port: port,
        txt: {'id': Uint8List.fromList(utf8.encode(deviceId))},
      ));

  static Future<void> withdraw(nsd.Registration registration) =>
      nsd.unregister(registration);

  /// Reports every Vaultly device that appears on the network.
  static Future<nsd.Discovery> discover(
    void Function(SyncPeerAnnouncement peer) onFound,
  ) async {
    final discovery = await nsd.startDiscovery(
      serviceType,
      ipLookupType: nsd.IpLookupType.v4,
    );
    discovery.addServiceListener((service, status) {
      if (status != nsd.ServiceStatus.found) return;
      final id = service.txt?['id'];
      final port = service.port;
      if (id == null || port == null) return;
      final hosts = [
        for (final a in service.addresses ?? const <InternetAddress>[])
          a.address,
        if (service.host != null) service.host!,
      ];
      if (hosts.isEmpty) return;
      onFound(SyncPeerAnnouncement(
        deviceId: utf8.decode(id, allowMalformed: true),
        hosts: hosts,
        port: port,
      ));
    });
    return discovery;
  }

  static Future<void> stopDiscovery(nsd.Discovery discovery) =>
      nsd.stopDiscovery(discovery);
}
