/// "owner/repo" on GitHub that this build checks for releases and downloads
/// backend binaries from.
///
/// Forks build with their own repo:
/// `flutter build <platform> --dart-define=ARCHANGEL_REPO=you/your-fork`
const kGithubRepoSlug = String.fromEnvironment('ARCHANGEL_REPO', defaultValue: 'dwaipayanray95/Project-Archangel');
