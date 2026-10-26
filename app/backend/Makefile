.PHONY: build-linux-amd64 build-linux-arm64 run test vet

# CGO_ENABLED=0 forces a fully static binary (Go's net package otherwise
# links against glibc for cgo-based DNS resolution) - the point of a static
# binary is being able to scp one file to the server with zero runtime
# dependencies, so this isn't optional.

# One version for the whole product: the semver part of `version:` in
# app/frontend/pubspec.yaml (e.g. "0.8.0+2" -> "0.8.0"). Override with
# `make build-linux-amd64 VERSION=1.2.3`.
VERSION ?= $(shell sed -n -E 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' ../frontend/pubspec.yaml 2>/dev/null)
LDFLAGS = -ldflags "-X 'github.com/dwaipayanray95/project-archangel/backend/internal/version.Version=$(VERSION)'"

# AMD Micro box (Archangel-Mk1)
build-linux-amd64:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o bin/archangeld-amd64 ./cmd/archangeld

# Ampere A1 box, once allocated
build-linux-arm64:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o bin/archangeld-arm64 ./cmd/archangeld

run:
	go run ./cmd/archangeld -config config.yaml

vet:
	go vet ./...

test:
	go test ./...
