.PHONY: app cli check format test

VERSION ?= $(shell git describe --tags --always --dirty)

# ARCHS selects the architectures bundled into SimSlim.app. Accepts `arm64`,
# `x86_64`, a comma/space-separated list of both, `universal` as shorthand for
# `arm64,x86_64`, or `all` for both plus one thin bundle per architecture.
# Empty (the default) builds only this machine's architecture.
#   make app                       # host architecture
#   make app ARCHS=arm64           # Apple silicon only
#   make app ARCHS=x86_64          # Intel only
#   make app ARCHS=arm64,x86_64    # universal
#   make app ARCHS=universal       # instead of arm64,x86_64
#   make app ARCHS=all             # universal + SimSlim-arm64.app + SimSlim-x86_64.app
ARCHS ?=

cli:
	go build -ldflags "-X main.version=$(VERSION)" -o simslim ./cmd/simslim

app:
	ARCHS="$(ARCHS)" ./scripts/build-app.sh

test:
	go test ./...

check: test
	go vet ./...
	xcrun swift-format lint --strict --recursive gui
	zsh -n scripts/build-app.sh
	plutil -lint gui/Info.plist

format:
	gofmt -w *.go
	xcrun swift-format format --in-place --recursive gui
