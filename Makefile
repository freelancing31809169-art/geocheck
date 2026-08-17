BINARY      := geocheck
PKG         := ./cmd/geocheck
MODULE      := github.com/remnawave/geocheck

# VERSION is the single source of truth for releases; the bump targets below
# rewrite it. The build stamp prefers `git describe` so untagged builds carry
# the commit, and falls back to the file when there is no tag yet.
#
# --verify keeps git quiet on stdout when there is no commit yet; without it
# `git rev-parse HEAD` prints "HEAD" *and* fails, and the two-word result
# silently corrupts the -X flags below.
RELEASE     := $(shell cat VERSION 2>/dev/null || echo 0.0.0)
VERSION     ?= $(firstword $(shell git describe --tags --always --dirty 2>/dev/null) v$(RELEASE))
COMMIT      ?= $(firstword $(shell git rev-parse --verify HEAD 2>/dev/null) none)
DATE        ?= $(shell date -u +%Y-%m-%dT%H:%M:%SZ)

# Docker Hub image. The published tag is :ing, which always points at the
# current release; :latest mirrors it.
IMAGE       ?= docker.io/remnawave/geocheck

LDFLAGS := -s -w \
	-X $(MODULE)/internal/version.Version=$(VERSION) \
	-X $(MODULE)/internal/version.Commit=$(COMMIT) \
	-X $(MODULE)/internal/version.Date=$(DATE)

GOFLAGS := -trimpath
DIST    := dist

PLATFORMS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64

.DEFAULT_GOAL := build

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Build the binary for the host platform
	CGO_ENABLED=0 go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o $(BINARY) $(PKG)

.PHONY: install
install: ## Install into GOBIN
	CGO_ENABLED=0 go install $(GOFLAGS) -ldflags '$(LDFLAGS)' $(PKG)

.PHONY: setcap
setcap: build ## Grant the binary raw-socket capability (Linux, needs sudo)
	@if [ "$$(uname -s)" != "Linux" ]; then \
		echo "setcap is Linux-only; on macOS run with sudo for full paths"; exit 0; \
	fi
	sudo setcap cap_net_raw+p ./$(BINARY)
	@echo "granted cap_net_raw to ./$(BINARY) (permitted-only, so it still runs if the cap is dropped)"

.PHONY: test
test: ## Run the tests
	go test -race -count=1 ./...

.PHONY: cover
cover: ## Run tests and open a coverage report
	go test -coverprofile=coverage.out ./...
	go tool cover -func=coverage.out | tail -1

.PHONY: lint
lint: ## Run golangci-lint if present, otherwise vet
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run ./...; \
	else \
		echo "golangci-lint not found, falling back to go vet"; go vet ./...; \
	fi

.PHONY: fmt
fmt: ## Format the source
	gofmt -w ./cmd ./internal

.PHONY: check
check: fmt lint test ## Format, lint and test

.PHONY: tidy
tidy: ## Tidy and verify modules
	go mod tidy
	go mod verify

.PHONY: run
run: ## Build and run against the default targets
	@$(MAKE) --no-print-directory build
	./$(BINARY)

.PHONY: clean
clean: ## Remove build artefacts
	rm -rf $(BINARY) $(DIST) coverage.out

.PHONY: release-snapshot
release-snapshot: ## Cross-compile every platform into dist/
	@rm -rf $(DIST) && mkdir -p $(DIST)
	@for platform in $(PLATFORMS); do \
		os=$${platform%/*}; arch=$${platform#*/}; \
		out=$(DIST)/$(BINARY)_$${os}_$${arch}; \
		echo "  building $$os/$$arch"; \
		CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch \
			go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o $$out $(PKG) || exit 1; \
	done
	@cd $(DIST) && shasum -a 256 * > checksums.txt 2>/dev/null || sha256sum * > checksums.txt
	@ls -lh $(DIST)

# ---- versioning and release -------------------------------------------
# `make bump-patch` rewrites VERSION and commits it; `make tag` turns that
# commit into an annotated tag and pushes, which is what triggers the release
# workflow. `make release-patch` does both in one step.

.PHONY: version
version: ## Print the current and build versions
	@echo "release: $(RELEASE)"
	@echo "build:   $(VERSION)"
	@echo "image:   $(IMAGE):ing"

# require-clean refuses to touch a tree with uncommitted work, so a bump commit
# can never sweep up unrelated changes.
.PHONY: require-clean
require-clean:
	@if [ -n "$$(git status --porcelain)" ]; then \
		echo "error: working tree is dirty; commit or stash first:"; \
		git status --short; \
		exit 1; \
	fi

.PHONY: bump-patch bump-minor bump-major
bump-patch: ## Bump the patch version and commit (0.1.0 -> 0.1.1)
	@$(MAKE) --no-print-directory do-bump PART=patch
bump-minor: ## Bump the minor version and commit (0.1.0 -> 0.2.0)
	@$(MAKE) --no-print-directory do-bump PART=minor
bump-major: ## Bump the major version and commit (0.1.0 -> 1.0.0)
	@$(MAKE) --no-print-directory do-bump PART=major

.PHONY: do-bump
do-bump: require-clean
	@set -e; \
	current=$$(cat VERSION); \
	case "$$current" in \
		[0-9]*.[0-9]*.[0-9]*) ;; \
		*) echo "error: VERSION ('$$current') is not MAJOR.MINOR.PATCH"; exit 1 ;; \
	esac; \
	major=$${current%%.*}; rest=$${current#*.}; minor=$${rest%%.*}; patch=$${rest#*.}; \
	case "$(PART)" in \
		major) major=$$((major + 1)); minor=0; patch=0 ;; \
		minor) minor=$$((minor + 1)); patch=0 ;; \
		patch) patch=$$((patch + 1)) ;; \
		*) echo "error: PART must be major, minor or patch"; exit 1 ;; \
	esac; \
	next="$$major.$$minor.$$patch"; \
	if git rev-parse -q --verify "refs/tags/v$$next" >/dev/null; then \
		echo "error: tag v$$next already exists"; exit 1; \
	fi; \
	echo "$$next" > VERSION; \
	git add VERSION; \
	git commit -q -m "chore(release): v$$next"; \
	echo "bumped $$current -> $$next and committed"; \
	echo "next: make tag"

.PHONY: tag
tag: require-clean ## Sign and push a tag for the current VERSION, triggering the release
	@set -e; \
	version=$$(cat VERSION); \
	if git rev-parse -q --verify "refs/tags/v$$version" >/dev/null; then \
		echo "error: tag v$$version already exists"; exit 1; \
	fi; \
	if [ -z "$$(git config user.signingkey)" ] && [ -z "$$(git config gpg.format)" ]; then \
		echo "error: releases are signed, but no signing key is configured."; \
		echo "  git config user.signingkey <key>   # and gpg.format ssh, if signing with SSH"; \
		exit 1; \
	fi; \
	echo "signing tag v$$version..."; \
	git tag -s "v$$version" -m "Release v$$version"; \
	git verify-tag "v$$version" >/dev/null 2>&1 \
		&& echo "signature verified" \
		|| { echo "error: tag was created but its signature does not verify"; exit 1; }; \
	git push origin --follow-tags; \
	echo "pushed signed tag v$$version; the release workflow publishes $(IMAGE):ing"

.PHONY: release-patch release-minor release-major
release-patch: bump-patch tag ## Bump the patch version, commit, tag and push
release-minor: bump-minor tag ## Bump the minor version, commit, tag and push
release-major: bump-major tag ## Bump the major version, commit, tag and push

.PHONY: untag
untag: ## Delete the current version's tag locally and on the remote
	@set -e; \
	version=$$(cat VERSION); \
	git tag -d "v$$version" 2>/dev/null || true; \
	git push --delete origin "v$$version" 2>/dev/null || true; \
	echo "removed tag v$$version"

# ---- documentation ----------------------------------------------------

.PHONY: demo
demo: ## Re-record the README animations with VHS (needs docker)
	./scripts/record-demo.sh

.PHONY: demo-preview
demo-preview: build ## Print the sample report the animations are recorded from
	./$(BINARY) --demo

# ---- geocheck.ing launcher --------------------------------------------

.PHONY: web
web: ## Build the Cloudflare Worker that serves geocheck.ing
	./scripts/build-worker.sh

.PHONY: web-check
web-check: web ## Lint the launcher script and check the Worker parses
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck scripts/geocheck.sh scripts/build-worker.sh; \
	else \
		docker run --rm -v "$(PWD):/mnt" -w /mnt koalaman/shellcheck:stable \
			scripts/geocheck.sh scripts/build-worker.sh; \
	fi
	@sh -n scripts/geocheck.sh
	@echo "launcher ok"

.PHONY: web-deploy
web-deploy: web-check ## Deploy the Worker to Cloudflare
	cd web && npx wrangler deploy

.PHONY: docker
docker: ## Build the container image for the host architecture
	docker build \
		--build-arg VERSION=$(VERSION) \
		--build-arg COMMIT=$(COMMIT) \
		--build-arg DATE=$(DATE) \
		-t $(IMAGE):$(RELEASE) -t $(IMAGE):ing .

.PHONY: docker-run
docker-run: docker ## Build and run the container image
	docker run --rm -it --network host $(IMAGE):ing

.PHONY: docker-push
docker-push: ## Build and push a multi-architecture image
	docker buildx build --platform linux/amd64,linux/arm64 \
		--build-arg VERSION=$(VERSION) \
		--build-arg COMMIT=$(COMMIT) \
		--build-arg DATE=$(DATE) \
		-t $(IMAGE):ing -t $(IMAGE):latest --push .
