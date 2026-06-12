SHELL := /bin/bash

.PHONY: build install install-local run test clean

build:
	cd macos && UNIVERSAL=false ./scripts/build-app.sh

install:
	./scripts/install-latest.sh

install-local: build
	mkdir -p "$$HOME/Applications"
	rm -rf "$$HOME/Applications/Shout Out.app"
	cp -R "macos/dist/Shout Out.app" "$$HOME/Applications/"
	defaults write com.ezraapple.shoutout requestPermissionsOnLaunch -bool true
	open "$$HOME/Applications/Shout Out.app"

run: build
	open "macos/dist/Shout Out.app"

test:
	./scripts/test.sh

clean:
	rm -rf macos/.build macos/dist
