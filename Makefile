# Local entry points that run what CI runs. `make help` lists them.
#
#   make check     fast repository checks: CI's preflight, also the pre-commit hook
#   make test      check + CadenceCore + web suites (no Xcode needed)
#   make native    iPhone build + watch UI tests on simulators (macOS + Xcode)
#   make signing   live signing preflight against the certs repo and Apple
#   make hooks     install the pre-commit and pre-push hooks
#
# Before merging anything that can ship: `make test`, `make native` when
# native code changed, and `make signing` when targets, App IDs, entitlements
# or signing changed.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Match CI's Ruby 3 (macOS's system Ruby is 2.6): prefer Homebrew's.
RUBY_BIN := $(firstword $(wildcard /opt/homebrew/opt/ruby/bin /usr/local/opt/ruby/bin))
ifneq ($(RUBY_BIN),)
export PATH := $(RUBY_BIN):$(PATH)
endif

PHONE_SIM ?= iPhone 17
WATCH_SIM ?= Apple Watch SE 3 (40mm)
DERIVED   ?= build/DerivedData

.PHONY: help check test test-core test-web native native-phone native-watch signing hooks

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-13s %s\n", $$1, $$2}'

check: ## Fast repository checks (CI preflight; also the pre-commit hook)
	bash .github/scripts/preflight.sh

test: check test-core test-web ## Everything that runs without Xcode

test-core: ## CadenceCore unit tests
	cd CadenceCore && swift test

test-web: ## Web parity, migration and smoke tests
	cd web && { [ -d node_modules ] || npm ci; } && npm test

native: native-phone native-watch ## iPhone build and watch UI tests (macOS + Xcode)

Cadence.xcodeproj: project.yml
	xcodegen generate --quiet

native-phone: Cadence.xcodeproj ## Build the iPhone app (embeds the watch app and widgets)
	xcodebuild build -project Cadence.xcodeproj -scheme Cadence \
	  -destination 'platform=iOS Simulator,name=$(PHONE_SIM)' \
	  -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO -quiet

native-watch: Cadence.xcodeproj ## Watch UI tests on a booted watch simulator
	@id="$$(xcrun simctl list devices available -j | ruby -rjson -e 'd = JSON.parse(STDIN.read)["devices"].flat_map { |r, l| r.include?("watchOS") ? l : [] }; m = d.find { |x| x["name"] == ARGV[0] } || d.first; puts m && m["udid"]' '$(WATCH_SIM)')"; \
	  [ -n "$$id" ] || { echo "no watchOS simulator installed" >&2; exit 1; }; \
	  xcrun simctl boot "$$id" 2>/dev/null || true; xcrun simctl bootstatus "$$id" -b >/dev/null; \
	  xcodebuild test -project Cadence.xcodeproj -scheme CadenceWatch \
	    -destination "platform=watchOS Simulator,id=$$id" \
	    -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO -quiet

signing: ## Live signing preflight (certs repo via gh; Apple checks need ASC_* env)
	SIGNING_PREFLIGHT=local ruby .github/scripts/check-signing-material.rb

hooks: ## Install the pre-commit (make check) and pre-push (make test) hooks
	@command -v pre-commit >/dev/null || { echo "install pre-commit first: brew install pre-commit" >&2; exit 1; }
	pre-commit install --hook-type pre-commit --hook-type pre-push
