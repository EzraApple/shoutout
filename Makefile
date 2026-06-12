SHELL := /bin/bash

.PHONY: build install install-local reset-permissions run test clean

build:
	cd macos && UNIVERSAL=false ./scripts/build-app.sh

install:
	./scripts/install-latest.sh

install-local: build
	mkdir -p "$$HOME/Applications"
	pkill -x ShoutOut >/dev/null 2>&1 || true
	rm -rf "$$HOME/Applications/Shout Out.app"
	cp -R "macos/dist/Shout Out.app" "$$HOME/Applications/"
	xattr -dr com.apple.quarantine "$$HOME/Applications/Shout Out.app" >/dev/null 2>&1 || true
	defaults write com.ezraapple.shoutout requestPermissionsOnLaunch -bool true
	open "$$HOME/Applications/Shout Out.app"

reset-permissions:
	tccutil reset Accessibility com.ezraapple.shoutout || true
	tccutil reset ListenEvent com.ezraapple.shoutout || true
	defaults write com.ezraapple.shoutout requestPermissionsOnLaunch -bool true

run: build
	open "macos/dist/Shout Out.app"

test:
	./scripts/test.sh

clean:
	rm -rf macos/.build macos/dist
