import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:wireguard_flutter/wireguard_flutter.dart';

import 'local_kv_store.dart';
import 'macos_wireguard_channel.dart';
import 'tunnel_config.dart';

/// Our own status enum, decoupled from wireguard_flutter's [VpnStage] so
/// the UI (top bar pill, Settings) never depends on the plugin directly.
enum TunnelStatus { disconnected, connecting, connected, disconnecting, error, unsupported }

const _kInterfaceName = 'archangel';
const kWgConfigStorageKey = 'wg_tunnel_config';

/// Same bundle identifier the iOS Packet Tunnel Provider extension must be
/// registered under in Xcode, if that platform is ever added. Unused on
/// every platform this app actually targets, but wireguard_flutter's API
/// requires a value regardless.
const _kProviderBundleId = 'dev.archangel.archangel.tunnel';

final _store = LocalKvStore.instance;

/// Wraps the platform's WireGuard backend behind a small app-specific API:
/// load/save the paired config, connect/disconnect, and a status stream
/// the UI observes.
///
/// Platform backends:
///  - Android: wireguard_flutter's real VpnService backend - works out of
///    the box.
///  - Windows: wireguard_flutter bundles the official WireGuardNT
///    tunnel.dll/wireguard.dll and creates a Windows service to run the
///    tunnel - this requires the app to be running elevated (see
///    windows/runner's app manifest).
///  - Linux: wireguard_flutter shells out to wg-quick directly - requires
///    `wireguard-tools` installed and passwordless (or interactive) root.
///  - macOS: a bundled wireguard-go binary driven directly via
///    macos/Runner/WireGuardMacOS.swift, deliberately bypassing
///    wireguard_flutter's NetworkExtension-based darwin backend (which
///    needs a separate Packet Tunnel Provider Xcode target and a paid
///    Apple Developer Program membership - see WIREGUARD.md for why the
///    direct-utun approach avoids that, and its current unverified
///    status).
class WireGuardController extends ChangeNotifier {
  final _wg = WireGuardFlutter.instance;
  final _macos = MacosWireGuardChannel();
  StreamSubscription<VpnStage>? _sub;
  bool get _useMacosChannel => Platform.isMacOS;

  TunnelStatus _status = TunnelStatus.disconnected;
  TunnelStatus get status => _status;

  TunnelConfig? _config;
  TunnelConfig? get config => _config;
  bool get isPaired => _config != null;

  String? _lastError;
  String? get lastError => _lastError;

  bool _isMacosHelperInstalled = false;
  bool get isMacosHelperInstalled => _isMacosHelperInstalled;

  bool _installingMacosHelper = false;
  bool get installingMacosHelper => _installingMacosHelper;

  bool _initialized = false;

  /// True once [bootstrap] has finished loading the saved config (whether
  /// or not one exists) - lets the app's root router wait for this before
  /// deciding whether to show the setup wizard, instead of flashing it
  /// for an already-paired user while storage is still being read.
  bool _bootstrapped = false;
  bool get isBootstrapped => _bootstrapped;

  Future<void> bootstrap() async {
    if (_initialized) return;
    _initialized = true;

    // _bootstrapped must become true exactly once no matter what happens
    // above, including an exception type nothing here anticipates -
    // main.dart's _RootRouter waits on it before showing anything but a
    // loading spinner, so a bug that skipped this would strand every
    // user on that spinner forever with no path to the wizard or the app
    // shell.
    try {
      await _loadSavedConfig();

      if (_useMacosChannel) {
        // No stage stream on this backend yet - status is set directly by
        // connect()/disconnect() below instead of an event stream.
        _status = TunnelStatus.disconnected;
        await checkMacosHelper();
        return;
      }

      try {
        await _wg.initialize(interfaceName: _kInterfaceName);
        _sub = _wg.vpnStageSnapshot.listen(_onStageChanged, onError: (_) {});
        unawaited(_wg.refreshStage());
      } catch (e) {
        // Most commonly hit on Linux without wireguard-tools installed.
        _status = TunnelStatus.unsupported;
        _lastError = e.toString();
      }
    } finally {
      _bootstrapped = true;
      notifyListeners();
    }
  }

  void _onStageChanged(VpnStage stage) {
    _status = switch (stage) {
      VpnStage.connected => TunnelStatus.connected,
      VpnStage.connecting ||
      VpnStage.preparing ||
      VpnStage.authenticating ||
      VpnStage.waitingConnection ||
      VpnStage.reconnect => TunnelStatus.connecting,
      VpnStage.disconnecting || VpnStage.exiting => TunnelStatus.disconnecting,
      VpnStage.disconnected || VpnStage.noConnection => TunnelStatus.disconnected,
      VpnStage.denied => TunnelStatus.error,
    };
    if (stage == VpnStage.denied) {
      _lastError =
          Platform.isWindows
              ? 'Permission denied creating the tunnel service - Archangel needs to run as Administrator on Windows.'
              : 'Permission denied starting the VPN tunnel.';
    }
    notifyListeners();
  }

  Future<void> _loadSavedConfig() async {
    try {
      final raw = await _store.read(kWgConfigStorageKey);
      if (raw != null) _config = TunnelConfig.parse(raw);
    } catch (e) {
      _lastError = 'Saved tunnel config could not be read: $e';
    }
  }

  /// Parses, persists (see local_kv_store.dart for how/why), and stores
  /// [wgQuickText] as the paired config. Does not connect automatically.
  Future<void> pair(String wgQuickText) async {
    final parsed = TunnelConfig.parse(wgQuickText); // throws FormatException on bad input
    await _store.write(kWgConfigStorageKey, wgQuickText);
    _config = parsed;
    notifyListeners();
  }

  Future<void> unpair() async {
    if (_status == TunnelStatus.connected || _status == TunnelStatus.connecting) {
      await disconnect();
    }
    await _store.delete(kWgConfigStorageKey);
    _config = null;
    notifyListeners();
  }

  Future<void> connect() async {
    final cfg = _config;
    if (cfg == null) {
      _lastError = 'No paired tunnel config - pair a device first.';
      notifyListeners();
      return;
    }
    _lastError = null;

    if (_useMacosChannel) {
      _status = TunnelStatus.connecting;
      notifyListeners();
      try {
        await _macos.connect(cfg.toWgQuickConfig());
        _status = TunnelStatus.connected;
      } catch (e) {
        _status = TunnelStatus.error;
        _lastError = e.toString();
      }
      notifyListeners();
      return;
    }

    _status = TunnelStatus.connecting;
    notifyListeners();
    try {
      await _wg.startVpn(
        serverAddress: cfg.serverAddress,
        wgQuickConfig: cfg.toWgQuickConfig(),
        providerBundleIdentifier: _kProviderBundleId,
      );
      // vpnStageSnapshot (subscribed in bootstrap()) takes it from here -
      // this optimistic update just avoids a stale status between the
      // call above returning and the stream's first real update arriving.
    } catch (e) {
      _status = TunnelStatus.error;
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    if (_useMacosChannel) {
      try {
        await _macos.disconnect();
      } catch (e) {
        _lastError = e.toString();
      }
      _status = TunnelStatus.disconnected;
      notifyListeners();
      return;
    }

    try {
      await _wg.stopVpn();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
    }
  }

  Future<void> checkMacosHelper() async {
    if (!_useMacosChannel) return;
    try {
      _isMacosHelperInstalled = await _macos.isHelperInstalled();
      notifyListeners();
    } catch (_) {}
  }

  Future<bool> installMacosHelper() async {
    if (!_useMacosChannel) return false;
    _installingMacosHelper = true;
    _lastError = null;
    notifyListeners();
    try {
      await _macos.installHelper();
      _isMacosHelperInstalled = await _macos.isHelperInstalled();
      return _isMacosHelperInstalled;
    } catch (e) {
      _lastError = 'Failed to enable seamless tunnel: $e';
      return false;
    } finally {
      _installingMacosHelper = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
