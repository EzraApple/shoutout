SHELL := /bin/bash

MACOS_DIR := apps/macos
APP_NAME := ShoutOut
BUNDLE_ID := com.ezraapple.shoutout
INSTALLED_APP := $$HOME/Applications/$(APP_NAME).app
DIST_APP := $(MACOS_DIR)/dist/$(APP_NAME).app
UNIVERSAL ?= false

.PHONY: build sync-assets install install-local onboarding-local restart-local reset-permissions run test test-language-pass clean release-preflight release-verify-live release-dmg notary-credentials sparkle-public-key sparkle-appcast blob-upload-dmg web-check web-build web-dev

sync-assets:
	python3 ./scripts/sync-mascot-assets.py

build: sync-assets
	cd "$(MACOS_DIR)" && UNIVERSAL="$(UNIVERSAL)" ./scripts/build-app.sh

install:
	./scripts/install-latest.sh

install-local: build
	mkdir -p "$$HOME/Applications"
	pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	rm -rf "$$HOME/Applications/Shout Out.app"
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(DIST_APP)" "$$HOME/Applications/"
	xattr -dr com.apple.quarantine "$(INSTALLED_APP)" >/dev/null 2>&1 || true
	defaults write "$(BUNDLE_ID)" requestPermissionsOnLaunch -bool true
	open "$(INSTALLED_APP)"

onboarding-local: build
	mkdir -p "$$HOME/Applications"
	pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	rm -rf "$$HOME/Applications/Shout Out.app"
	rm -rf "$(INSTALLED_APP)"
	rm -rf "$$HOME/Library/Application Support/$(BUNDLE_ID)"
	rm -rf "$$HOME/Library/Logs/$(APP_NAME)"
	defaults delete "$(BUNDLE_ID)" >/dev/null 2>&1 || true
	tccutil reset Microphone "$(BUNDLE_ID)" >/dev/null 2>&1 || true
	tccutil reset SpeechRecognition "$(BUNDLE_ID)" >/dev/null 2>&1 || true
	tccutil reset Accessibility "$(BUNDLE_ID)" >/dev/null 2>&1 || true
	tccutil reset ListenEvent "$(BUNDLE_ID)" >/dev/null 2>&1 || true
	cp -R "$(DIST_APP)" "$$HOME/Applications/"
	xattr -dr com.apple.quarantine "$(INSTALLED_APP)" >/dev/null 2>&1 || true
	open -n "$(INSTALLED_APP)"

restart-local: build
	mkdir -p "$$HOME/Applications"
	pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	rm -rf "$$HOME/Applications/Shout Out.app"
	rm -rf "$(INSTALLED_APP)"
	cp -R "$(DIST_APP)" "$$HOME/Applications/"
	xattr -dr com.apple.quarantine "$(INSTALLED_APP)" >/dev/null 2>&1 || true
	defaults write "$(BUNDLE_ID)" hasCompletedOnboarding -bool true
	defaults write "$(BUNDLE_ID)" requestPermissionsOnLaunch -bool false
	open -n "$(INSTALLED_APP)"

reset-permissions:
	tccutil reset Accessibility "$(BUNDLE_ID)" || true
	tccutil reset ListenEvent "$(BUNDLE_ID)" || true
	defaults write "$(BUNDLE_ID)" requestPermissionsOnLaunch -bool true

run: build
	open "$(DIST_APP)"

test:
	./scripts/test.sh

test-language-pass:
	cd "$(MACOS_DIR)" && ./scripts/run-language-pass-smoke.sh

release-preflight:
	python3 ./scripts/check-release-metadata.py
	cd "$(MACOS_DIR)" && ./scripts/release-preflight.sh
	./scripts/verify-live-release.sh

release-verify-live:
	./scripts/verify-live-release.sh

release-dmg: sync-assets
	cd "$(MACOS_DIR)" && UNIVERSAL="$(UNIVERSAL)" ./scripts/release.sh

notary-credentials:
	cd "$(MACOS_DIR)" && ./scripts/store-notary-credentials.sh

sparkle-public-key:
	cd "$(MACOS_DIR)" && ./scripts/sparkle-public-key.sh

sparkle-appcast:
	cd "$(MACOS_DIR)" && ./scripts/generate-appcast.sh

blob-upload-dmg:
	SPARKLE_STAGE_WEB_PUBLIC=false $(MAKE) sparkle-appcast
	@set -euo pipefail; \
	ENV_FILE="$$(mktemp)"; \
	trap 'rm -f "$$ENV_FILE"' EXIT; \
	cd apps/web; \
	npx vercel env pull "$$ENV_FILE" --environment production --yes; \
	set -a; \
	source "$$ENV_FILE"; \
	set +a; \
	python3 ../macos/scripts/sparkle-release-artifacts.py upload ../macos/dist/sparkle-release.json

web-check:
	test -f apps/web/index.html
	test -f apps/web/package.json
	test -f apps/web/src/styles.css
	test -f apps/web/src/main.ts
	test -f apps/web/public/assets/site-icon-v2.png

web-build:
	cd apps/web && npm run build

web-dev:
	cd apps/web && npm run dev

clean:
	rm -rf "$(MACOS_DIR)/.build" "$(MACOS_DIR)/dist"
