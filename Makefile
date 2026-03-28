.PHONY: build run clean dmg codesign-bootstrap release

build:
	swift build -c release && bash scripts/bundle.sh

codesign-bootstrap:
	@bash scripts/codesign-bootstrap.sh

# open can fail with LS error -600 right after rebuild/kill; -n + absolute path + fallback helps.
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

# Push a version tag to trigger the CI release workflow, wait for it, and print the release URL.
# Usage: make release VERSION=1.0.0  (v prefix added automatically)
release:
ifndef VERSION
	$(error VERSION is required. Usage: make release VERSION=1.0.0)
endif
	@TAG=$(VERSION); \
	case "$$TAG" in v*) ;; *) TAG="v$$TAG" ;; esac; \
	echo "Tagging $$TAG and pushing..."; \
	git tag $$TAG; \
	git push origin main; \
	git push origin $$TAG; \
	echo "Waiting for release workflow..."; \
	RUN_ID=$$(gh run list --workflow=release.yml --branch=$$TAG --limit=1 --json databaseId --jq '.[0].databaseId'); \
	if [ -z "$$RUN_ID" ]; then sleep 5; RUN_ID=$$(gh run list --workflow=release.yml --branch=$$TAG --limit=1 --json databaseId --jq '.[0].databaseId'); fi; \
	gh run watch $$RUN_ID --exit-status; \
	echo ""; \
	echo ""; \
	echo "Publish this release? [y/N]"; \
	read -r CONFIRM; \
	if [ "$$CONFIRM" = "y" ] || [ "$$CONFIRM" = "Y" ]; then \
		gh release edit $$TAG --draft=false; \
	else \
		echo "Release left as draft."; \
	fi; \
	echo "Release URL:"; \
	gh release view $$TAG --json url --jq '.url'
