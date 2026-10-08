SCRIPTS_DIRECTORY ?= $(abspath $(CURDIR)/../scripts)

.PHONY: help push-and-publish publish-release release test check format clean deps _compile-impl

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

deps:
	$(MIX) deps.get

test:
	$(MIX) test

# Called by the shared `compile` target (bot_army_infra/make/common.mk), which
# `make push` depends on. Without it `make push` dies with
# "No rule to make target '_compile-impl'".
_compile-impl:
	@LOG_FILE="/tmp/compile-full-$$(date +%s).log"; \
	echo "Compiling and logging to $$LOG_FILE..."; \
	set -o pipefail; \
	$(MIX) compile 2>&1 | tee "$$LOG_FILE"; \
	rc=$$?; \
	echo "✓ Compilation log: $$LOG_FILE"; \
	exit $$rc

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

	@$(MAKE) publish-deploy-event TARGET=air
push-and-publish:
	@git push && $(MAKE) publish-release


# ── Shared targets (push, git-push, credo, setup-hooks, compile, pre-push-cleanup,
# bump-version, sync-hook). Defined once in bot_army_infra so they cannot drift
# per repo.
# * ergon-skills-base had NO push / git-jush / bump-version target: the standard fleet
# driver (bump → push → publish → deploy) could not drive it at all.
#
# No version bump: build tooling only; the release artifact is unchanged.
BOT_ARMY_COMMON_MK := $(abspath $(CURDIR)/../bot_army_infra/make/common.mk)
ifeq ($(wildcard $(BOT_ARMY_COMMON_MK)),)
$(warning bot_army_infra not found at $(BOT_ARMY_COMMON_MK) - shared targets unavailable)
else
include $(BOT_ARMY_COMMON_MK)
endif
