# Maintainer interface for the native SDKs published from this repository.
#
# These targets build and package artifacts locally; publishing is done by the
# workflows in .github/workflows. Consumers never call these — they download
# the published archives instead.

GO ?= go
BASH ?= $(dir $(shell command -v sh))bash
RECORD_ARCH ?= $(shell $(GO) env GOARCH)
RE2_PLATFORM ?= $(shell bash -c 'case "$$(uname -s)-$$(uname -m)" in Linux-x86_64) echo linux_amd64;; Linux-aarch64) echo linux_arm64;; Darwin-x86_64) echo darwin_amd64;; Darwin-arm64) echo darwin_arm64;; MINGW*|MSYS*) echo windows_amd64;; *) echo unsupported;; esac')

.PHONY: help record-native-source record-native-package re2-static

help:
	@echo "native SDK targets:"
	@echo "  make record-native-source   Build the recorder SDK from pinned sources"
	@echo "  make record-native-package  Package a source-built recorder SDK"
	@echo "  make re2-static             Build and package one platform's static RE2 SDK"
	@echo ""
	@echo "Variables:"
	@echo "  RECORD_ARCH=amd64|arm64    Recorder SDK target architecture"
	@echo "  RE2_PLATFORM=linux_amd64   Static RE2 SDK target platform"

record-native-source:
	GOARCH="$(RECORD_ARCH)" "$(BASH)" .github/native/record.sh build

record-native-package:
	GOARCH="$(RECORD_ARCH)" "$(BASH)" .github/native/record.sh package

re2-static:
ifeq ($(RE2_PLATFORM),unsupported)
	@echo "static RE2 SDK is not supported on this host" >&2
	@exit 1
else
	"$(BASH)" scripts/build-static.sh "$(RE2_PLATFORM)"
endif
