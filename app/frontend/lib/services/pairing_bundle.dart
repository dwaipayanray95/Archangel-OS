import 'dart:convert';

import 'tunnel_config.dart';

/// One parsed pairing bundle from `archangeld pair <name> [--qr]`: a single
/// base64(JSON) blob carrying both the WireGuard tunnel config and the
/// archangeld host/token, so pairing a device is one paste (or, on
/// Android, one QR scan) instead of two separate manual steps.
///
/// Matches the backend's `pairingBundle` struct in
/// app/backend/cmd/archangeld/main.go - keep the two in sync.
class PairingBundle {
  final String name;
  final String host;
  final String token;
  final TunnelConfig tunnel;

  const PairingBundle({required this.name, required this.host, required this.token, required this.tunnel});

  /// Parses a bundle string as printed/QR-encoded by `archangeld pair`.
  /// Throws [FormatException] with a human-readable message on anything
  /// that isn't a valid, current bundle.
  factory PairingBundle.parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Pairing code is empty');
    }

    late final Map<String, dynamic> json;
    try {
      final decodedBytes = base64.decode(_normalizeBase64(trimmed));
      json = jsonDecode(utf8.decode(decodedBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw const FormatException('Not a valid pairing code - paste the exact string `archangeld pair` printed, or scan its QR code.');
    }

    if (json['v'] != 1) {
      throw FormatException('Unsupported pairing bundle version: ${json['v']}');
    }

    final name = json['name'] as String?;
    final host = json['host'] as String?;
    final token = json['token'] as String?;
    final wg = json['wg'] as Map<String, dynamic>?;
    if (name == null || host == null || token == null || wg == null) {
      throw const FormatException('Pairing code is missing required fields');
    }

    final privateKey = wg['private_key'] as String?;
    final address = wg['address'] as String?;
    final serverPublicKey = wg['server_public_key'] as String?;
    final endpoint = wg['endpoint'] as String?;
    final allowedIps = (wg['allowed_ips'] as List?)?.cast<String>();
    if (privateKey == null || address == null || serverPublicKey == null || endpoint == null) {
      throw const FormatException('Pairing code is missing WireGuard fields');
    }

    final tunnel = TunnelConfig(
      interfacePrivateKey: privateKey,
      interfaceAddress: address,
      peerPublicKey: serverPublicKey,
      peerEndpoint: endpoint,
      peerAllowedIps: (allowedIps == null || allowedIps.isEmpty) ? '0.0.0.0/0' : allowedIps.join(', '),
      peerPersistentKeepalive: 25,
    );

    return PairingBundle(name: name, host: host, token: token, tunnel: tunnel);
  }

  /// `base64.decode` requires correct padding; pasted/scanned text
  /// sometimes loses trailing `=` characters (e.g. copied from a UI that
  /// trims whitespace-like characters), so pad it back out rather than
  /// making the user get it byte-perfect.
  static String _normalizeBase64(String s) {
    final mod = s.length % 4;
    if (mod == 0) return s;
    return s + '=' * (4 - mod);
  }
}
