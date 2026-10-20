// The starter catalog shown first in "Run an app": well-known self-hosted
// apps with sensible defaults, so a beginner never has to know an image name,
// a port or where an app keeps its data. Pure Dart (no Flutter) so it is
// trivially testable.

import 'app_specs.dart';

/// One ready-made app. Everything here can still be changed in the form.
class AppPreset {
  const AppPreset({
    required this.id,
    required this.name,
    required this.blurb,
    required this.image,
    this.containerPort,
    this.hostPort,
    this.folders = const [],
    this.settings = const [],
  });

  /// Also the suggested container name.
  final String id;
  final String name;

  /// One plain sentence: what it is for.
  final String blurb;
  final String image;

  /// The port the app's web page listens on inside (null: no web page).
  final String? containerPort;

  /// Suggested port on the server (chosen to avoid clashes between presets).
  final String? hostPort;

  /// Where its data is kept, so it survives updates and removal.
  final List<FolderMapping> folders;
  final List<SettingEntry> settings;

  /// "Something else": the user types any image.
  bool get isCustom => id == customAppPresetId;
}

const customAppPresetId = 'custom';

const kAppCatalog = <AppPreset>[
  AppPreset(
    id: 'uptime-kuma',
    name: 'Uptime Kuma',
    blurb: 'Watches your websites and tells you when one goes down.',
    image: 'louislam/uptime-kuma:1',
    containerPort: '3001',
    hostPort: '3001',
    folders: [FolderMapping(hostPath: '/srv/uptime-kuma', containerPath: '/app/data')],
  ),
  AppPreset(
    id: 'vaultwarden',
    name: 'Vaultwarden',
    blurb: 'A password manager that works with the Bitwarden apps.',
    image: 'vaultwarden/server:latest',
    containerPort: '80',
    hostPort: '8081',
    folders: [FolderMapping(hostPath: '/srv/vaultwarden', containerPath: '/data')],
  ),
  AppPreset(
    id: 'nextcloud',
    name: 'Nextcloud',
    blurb: 'Your own files, calendar and contacts.',
    image: 'nextcloud:latest',
    containerPort: '80',
    hostPort: '8080',
    folders: [FolderMapping(hostPath: '/srv/nextcloud', containerPath: '/var/www/html')],
  ),
  AppPreset(
    id: 'jellyfin',
    name: 'Jellyfin',
    blurb: 'Stream your films, shows and music.',
    image: 'jellyfin/jellyfin:latest',
    containerPort: '8096',
    hostPort: '8096',
    folders: [
      FolderMapping(hostPath: '/srv/jellyfin/config', containerPath: '/config'),
      FolderMapping(hostPath: '/srv/media', containerPath: '/media'),
    ],
  ),
  AppPreset(
    id: 'syncthing',
    name: 'Syncthing',
    blurb: 'Keeps folders in sync between your devices.',
    image: 'syncthing/syncthing:latest',
    containerPort: '8384',
    hostPort: '8384',
    folders: [FolderMapping(hostPath: '/srv/syncthing', containerPath: '/var/syncthing')],
  ),
  AppPreset(
    id: 'website',
    name: 'Simple website',
    blurb: 'Serves the files in a folder as a website.',
    image: 'nginx:latest',
    containerPort: '80',
    hostPort: '8088',
    folders: [FolderMapping(hostPath: '/srv/website', containerPath: '/usr/share/nginx/html')],
  ),
  AppPreset(
    id: 'navidrome',
    name: 'Navidrome',
    blurb: 'Your music collection, playable anywhere.',
    image: 'deluan/navidrome:latest',
    containerPort: '4533',
    hostPort: '4533',
    folders: [
      FolderMapping(hostPath: '/srv/navidrome', containerPath: '/data'),
      FolderMapping(hostPath: '/srv/music', containerPath: '/music'),
    ],
  ),
  AppPreset(id: customAppPresetId, name: 'Something else', blurb: 'Any app from Docker Hub, by its image name.', image: ''),
];
