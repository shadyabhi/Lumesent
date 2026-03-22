.PHONY: build run clean dmg codesign-bootstrap

build:
	swift build -c release && bash scripts/bundle.sh

codesign-bootstrap:
	@bash scripts/codesign-bootstrap.sh

run: build
	pkill -x Lumesent 2>/dev/null || true
	open Lumesent.app

# DMG target. Uses bundle.sh's identity resolution (Apple Development if available, ad-hoc otherwise).
# For explicit ad-hoc: CODESIGN_IDENTITY="-" make dmg
# CI imports the same cert into a temp keychain, then runs this same target.
dmg: build
	bash scripts/make-dmg.sh

clean:
	rm -rf .build Lumesent.app Lumesent-*.dmg
