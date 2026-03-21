.PHONY: build run clean dmg codesign-bootstrap

build:
	swift build -c release && bash scripts/bundle.sh

codesign-bootstrap:
	@bash scripts/codesign-bootstrap.sh

run: build
	pkill -x Lumesent 2>/dev/null || true
	open Lumesent.app

# Release DMG uses ad-hoc signing (no paid Apple Developer Program needed).
# Users bypass Gatekeeper once via right-click → Open or: xattr -cr Lumesent.app
dmg:
	swift build -c release && CODESIGN_IDENTITY="-" bash scripts/bundle.sh
	bash scripts/make-dmg.sh

clean:
	rm -rf .build Lumesent.app Lumesent-*.dmg
