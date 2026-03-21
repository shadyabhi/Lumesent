.PHONY: build run clean dmg

build:
	swift build -c release && bash scripts/bundle.sh

run: build
	-pkill -x Lumesent
	open Lumesent.app

dmg: build
	bash scripts/make-dmg.sh

clean:
	rm -rf .build Lumesent.app Lumesent-Installer.dmg
