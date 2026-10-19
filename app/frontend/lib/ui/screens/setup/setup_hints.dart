// Plain-language helpers for the setup flow: error hints and the
// user-facing names of the setup stages. Pure Dart so it can be unit tested.

/// Maps a raw setup/connection error to a plain-words explanation with the
/// most likely fix. Never returns an empty string: unknown errors get a
/// generic message pointing at the technical details.
String hintForSetupError(String error) {
  final e = error.toLowerCase();
  bool any(List<String> needles) => needles.any(e.contains);

  if (any(['unsupported server architecture', 'supported ubuntu/debian', 'only x86_64'])) {
    return 'This server type is not supported. Archangel needs Ubuntu or Debian on a standard (x86_64 or ARM) '
        'server. Create a new server with Ubuntu 22.04 or 24.04 and try again.';
  }
  if (any(['authentication', 'auth fail', 'permission denied (publickey', 'no supported authentication', 'publickey'])) {
    return 'The server refused your key. Check the username (ubuntu for Ubuntu images, opc for some Oracle '
        'images) and that this key was added when the server was created.';
  }
  if (any(['a password is required', 'no tty present', 'not in the sudoers', 'sudo:'])) {
    return 'This user is not allowed to run administrator commands without a password. Use a user that has '
        'passwordless sudo (ubuntu on Ubuntu images, opc on some Oracle images), or the root user.';
  }
  if (any(['host key', 'fingerprint'])) {
    return 'The server\'s identity could not be confirmed. If you did not rebuild this server recently, do not '
        'continue. Otherwise go back, check the address, and accept the new identity when asked.';
  }
  if (any(['[wireguard]', '51820', 'handshake', 'tunnel', 'wireguard'])) {
    return 'The private secure connection could not be set up or reached. Make sure UDP port 51820 is open in '
        'your provider\'s firewall (this is separate from the server\'s own firewall), then try again.';
  }
  if (any(['decrypt', 'passphrase', 'invalid private key', 'invalid key', 'failed to parse', 'unsupported key', 'bad key', 'pem key'])) {
    return 'Archangel could not read that key. Paste the whole private key including the BEGIN and END lines. '
        'If the key is locked with its own password, enter that as the key passphrase.';
  }
  if (any([
    'connection refused',
    'timed out',
    'timeout',
    'no route to host',
    'network is unreachable',
    'socketexception',
    'connection reset',
    'connection closed',
    'failed host lookup',
    'host unreachable',
  ])) {
    return 'Could not reach the server. Check the IP address and that port 22 is open in your provider\'s firewall.';
  }
  if (any(['download', 'checksum', 'release'])) {
    return 'The server could not download Archangel. Check that the server has internet access and try again in a '
        'few minutes.';
  }
  return 'Something went wrong while setting up the server. It is safe to try again. If it keeps failing, open '
      '"Technical details" below and share it when asking for help.';
}

/// True when the provider's own network firewall is the likely culprit, so
/// the step-by-step firewall help should be offered next to the error.
bool errorNeedsFirewallHelp(String error) {
  final e = error.toLowerCase();
  return const [
    '[wireguard]',
    '51820',
    'handshake',
    'tunnel',
    'wireguard',
    'connection refused',
    'timed out',
    'timeout',
    'no route to host',
    'network is unreachable',
  ].any(e.contains);
}

/// The stages of a setup run, in order, with the words shown to the user.
/// `connect` is the SSH connection made before the server-side stages.
const List<(String, String)> kSetupStages = [
  ('connect', 'Connecting to your server'),
  ('detect', 'Checking the server is supported'),
  ('upload', 'Copying the setup scripts'),
  ('baseline', 'Installing updates and the firewall'),
  ('wireguard', 'Setting up a private secure connection'),
  ('binary', 'Installing Archangel'),
  ('config', 'Writing the server settings'),
  ('service', 'Starting the Archangel server'),
  ('firewall', 'Opening the app port to your private connection'),
  ('pair', 'Pairing this device'),
];

/// Folds service stage names onto [kSetupStages] keys (the checksum step is
/// part of installing Archangel).
String normalizeSetupStage(String stage) => stage == 'verify' ? 'binary' : stage;

String setupStageLabel(String stage) {
  final key = normalizeSetupStage(stage);
  for (final s in kSetupStages) {
    if (s.$1 == key) return s.$2;
  }
  return 'Setting up your server';
}
