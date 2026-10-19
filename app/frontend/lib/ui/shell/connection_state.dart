import '../../services/wireguard_controller.dart';

/// What the app can honestly say about its connection to the server.
enum ConnectionPhase {
  /// No server on this device yet.
  notPaired,

  /// Bringing the secure connection up, or still finding out whether the
  /// server is reachable.
  starting,

  /// The secure connection is up but the server hasn't answered yet.
  reaching,

  /// The server answered.
  connected,

  /// The secure connection is up but the server keeps not answering.
  serverNotResponding,

  /// No secure connection and the server isn't reachable.
  offline,
}

/// How many failed health checks in a row before "reaching" turns into
/// "isn't answering".
const kHealthFailuresBeforeNotResponding = 3;

/// Derives the connection phase from the facts we have.
///
/// [reachable] is the latest unauthenticated /api/v1/health result (null =
/// not checked yet). A healthy server wins over the app's own tunnel state:
/// the tunnel may be managed by the OS WireGuard app, in which case our
/// controller says "down" while data flows fine.
ConnectionPhase deriveConnectionPhase({
  required bool paired,
  required TunnelStatus tunnel,
  required bool? reachable,
  int healthFailures = 0,
}) {
  if (!paired) return ConnectionPhase.notPaired;
  if (reachable == true) return ConnectionPhase.connected;
  switch (tunnel) {
    case TunnelStatus.connecting:
    case TunnelStatus.disconnecting:
      return ConnectionPhase.starting;
    case TunnelStatus.connected:
      return healthFailures >= kHealthFailuresBeforeNotResponding
          ? ConnectionPhase.serverNotResponding
          : ConnectionPhase.reaching;
    case TunnelStatus.disconnected:
    case TunnelStatus.error:
    case TunnelStatus.unsupported:
      // Until the first health check has come back we don't know yet.
      return reachable == null ? ConnectionPhase.starting : ConnectionPhase.offline;
  }
}

/// The words shown for [phase]; [serverName] is used by `connected`.
String connectionText(ConnectionPhase phase, {String? serverName}) => switch (phase) {
      ConnectionPhase.notPaired => 'No server yet',
      ConnectionPhase.starting => 'Starting secure connection…',
      ConnectionPhase.reaching => 'Secure connection up — reaching your server…',
      ConnectionPhase.connected =>
        serverName == null || serverName.trim().isEmpty ? 'Connected' : 'Connected to ${serverName.trim()}',
      ConnectionPhase.serverNotResponding => "Secure connection is up but your server isn't answering",
      ConnectionPhase.offline => 'Not connected',
    };

/// True for phases that are still changing (shown with a spinner).
bool connectionIsTransitional(ConnectionPhase phase) =>
    phase == ConnectionPhase.starting || phase == ConnectionPhase.reaching;
