.PHONY: build run clean

build:
	swift build -c release && bash scripts/bundle.sh

run: build
	-pkill -x Lumesent
	open Lumesent.app

clean:
	rm -rf .build Lumesent.app
