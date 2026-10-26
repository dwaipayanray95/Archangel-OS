package version

// Version is injected at build time from the semver part of `version:` in
// app/frontend/pubspec.yaml (the one version for the whole product) via
// -ldflags "-X 'github.com/dwaipayanray95/project-archangel/backend/internal/version.Version=...'".
// See the Makefile. The value below is only what a plain `go build` reports.
var Version = "0.0.0-dev"
