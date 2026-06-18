SHELL := /bin/bash

MACOS_DIR := apps/macos
APP_NAME := ShoutOut
BUNDLE_ID := com.ezraapple.shoutout
INSTALLED_APP := $$HOME/Applications/$(APP_NAME).app
DIST_APP := $(MACOS_DIR)/dist/$(APP_NAME).app
UNIVERSAL ?= false

.PHONY: build install install-local restart-local reset-permissions run test clean release-dmg web-check

build:
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

release-dmg:
	cd "$(MACOS_DIR)" && UNIVERSAL="$(UNIVERSAL)" ./scripts/release.sh

web-check:
	test -f apps/web/index.html
	test -f apps/web/package.json
	test -f apps/web/src/styles.css
	test -f apps/web/src/main.ts
	test -f apps/web/public/assets/site-icon-v2.png

clean:
	rm -rf "$(MACOS_DIR)/.build" "$(MACOS_DIR)/dist"
