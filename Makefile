SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)
MIX ?= /Users/abby/.local/share/mise/shims/mix

.PHONY: help setup-hooks push-and-publish publish-release release test credo check format clean deps

help:
	@echo "Bot Army Skills"
	@echo ""
	@echo "Available targets:"
	@echo "  make setup-hooks    - Configure git to use tracked hooks"
	@echo "  make test           - Run tests"
	@echo "  make credo          - Run linter"
	@echo "  make check          - Run all checks (test, credo)"
	@echo "  make format         - Format Elixir code"
	@echo "  make deps           - Fetch dependencies"
	@echo "  make clean          - Clean build artifacts"
	@echo "  make release        - Build OTP release"
	@echo "  make publish-release - Build and publish release to GitHub"
	@echo "  make push-and-publish - Push then publish release"

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

deps:
	$(MIX) deps.get

test:
	$(MIX) test

credo:
	$(MIX) credo --strict

check: test credo

format:
	$(MIX) format

clean:
	$(MIX) clean

release:
	@echo "Building OTP release..."
	MIX_ENV=prod $(MIX) release

publish-release: release
	@echo "==============================================="
	@echo "Publishing release to GitHub"
	@echo "==============================================="
	@echo ""

	@set -e; \
	VERSION=$$(sed -n 's/^[[:space:]]*version:[[:space:]]*"\([^"]*\)".*/\1/p' mix.exs | head -n 1); \
	if [ -z "$$VERSION" ]; then echo "Failed to resolve version from mix.exs"; exit 1; fi; \
	TARBALL=skills_bot-$$VERSION.tar.gz; \
	echo "Version: $$VERSION"; \
	echo "Creating release tarball..."; \
	tar -czf "$$TARBALL" -C _build/prod/rel skills_bot/; \
	echo "✓ Tarball created: $$TARBALL"; \
	echo ""; \
	echo "Creating GitHub release v$$VERSION..."; \
	if gh release view "v$$VERSION" >/dev/null 2>&1; then \
		gh release upload "v$$VERSION" "$$TARBALL" --clobber; \
		echo "✓ Uploaded $$TARBALL to existing release v$$VERSION"; \
	else \
		gh release create "v$$VERSION" "$$TARBALL" --title "v$$VERSION" --notes "Release v$$VERSION"; \
		echo "✓ Created release v$$VERSION and uploaded $$TARBALL"; \
	fi; \
	echo ""; \
	echo "✓ Release published successfully"

push-and-publish:
	@git push && $(MAKE) publish-release