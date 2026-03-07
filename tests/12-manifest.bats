#!/usr/bin/env bats
# 12-manifest.bats — manifest support tests

load helpers/pkg-common

setup() {
	pkg_common_setup
}

teardown() {
	pkg_teardown
}

# ── pkg_manifest_load ──────────────────────────────────────────

@test "pkg_manifest_load: sources manifest file" {
	local manifest="${TEST_TMPDIR}/pkg.manifest"
	cat > "$manifest" <<'MANIFEST'
PKG_NAME="testapp"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Test application"
PKG_INSTALL_PATH="/usr/local/testapp"
MANIFEST

	pkg_manifest_load "$manifest"
	[[ "$PKG_NAME" = "testapp" ]]
	[[ "$PKG_VERSION" = "1.0.0" ]]
	[[ "$PKG_SUMMARY" = "Test application" ]]
	[[ "$PKG_INSTALL_PATH" = "/usr/local/testapp" ]]
}

@test "pkg_manifest_load: loads optional variables" {
	local manifest="${TEST_TMPDIR}/pkg.manifest"
	cat > "$manifest" <<'MANIFEST'
PKG_NAME="testapp"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Test"
PKG_INSTALL_PATH="/opt/testapp"
PKG_DESCRIPTION="A longer description of the test application"
PKG_LICENSE="GPL-2.0"
PKG_URL="https://example.com"
PKG_MAINTAINER="Test User <test@example.com>"
MANIFEST

	pkg_manifest_load "$manifest"
	[[ "$PKG_DESCRIPTION" = "A longer description of the test application" ]]
	[[ "$PKG_LICENSE" = "GPL-2.0" ]]
	[[ "$PKG_URL" = "https://example.com" ]]
	[[ "$PKG_MAINTAINER" = "Test User <test@example.com>" ]]
}

@test "pkg_manifest_load: fails with empty argument" {
	run pkg_manifest_load ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_manifest_load: fails when file not found" {
	run pkg_manifest_load "${TEST_TMPDIR}/nonexistent"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_manifest_load: handles manifest with comments" {
	local manifest="${TEST_TMPDIR}/pkg.manifest"
	cat > "$manifest" <<'MANIFEST'
# Project manifest
PKG_NAME="testapp"
# Version info
PKG_VERSION="2.0.0"
PKG_SUMMARY="Test"
PKG_INSTALL_PATH="/opt/testapp"
MANIFEST

	pkg_manifest_load "$manifest"
	[[ "$PKG_NAME" = "testapp" ]]
	[[ "$PKG_VERSION" = "2.0.0" ]]
}

# ── pkg_manifest_validate ─────────────────────────────────────

@test "pkg_manifest_validate: passes with all required variables" {
	PKG_NAME="testapp"
	PKG_VERSION="1.0.0"
	PKG_SUMMARY="Test application"
	PKG_INSTALL_PATH="/opt/testapp"

	run pkg_manifest_validate
	[[ "$status" -eq 0 ]]
}

@test "pkg_manifest_validate: fails when PKG_NAME missing" {
	unset PKG_NAME
	PKG_VERSION="1.0.0"
	PKG_SUMMARY="Test"
	PKG_INSTALL_PATH="/opt/testapp"

	run pkg_manifest_validate
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"PKG_NAME"* ]]
}

@test "pkg_manifest_validate: fails when PKG_VERSION missing" {
	PKG_NAME="testapp"
	unset PKG_VERSION
	PKG_SUMMARY="Test"
	PKG_INSTALL_PATH="/opt/testapp"

	run pkg_manifest_validate
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"PKG_VERSION"* ]]
}

@test "pkg_manifest_validate: fails when PKG_SUMMARY missing" {
	PKG_NAME="testapp"
	PKG_VERSION="1.0.0"
	unset PKG_SUMMARY
	PKG_INSTALL_PATH="/opt/testapp"

	run pkg_manifest_validate
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"PKG_SUMMARY"* ]]
}

@test "pkg_manifest_validate: fails when PKG_INSTALL_PATH missing" {
	PKG_NAME="testapp"
	PKG_VERSION="1.0.0"
	PKG_SUMMARY="Test"
	unset PKG_INSTALL_PATH

	run pkg_manifest_validate
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"PKG_INSTALL_PATH"* ]]
}

@test "pkg_manifest_validate: reports all missing variables at once" {
	unset PKG_NAME PKG_VERSION PKG_SUMMARY PKG_INSTALL_PATH

	run pkg_manifest_validate
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"PKG_NAME"* ]]
	[[ "$output" == *"PKG_VERSION"* ]]
	[[ "$output" == *"PKG_SUMMARY"* ]]
	[[ "$output" == *"PKG_INSTALL_PATH"* ]]
}

@test "pkg_manifest_validate: fails when PKG_NAME is empty string" {
	PKG_NAME=""
	PKG_VERSION="1.0.0"
	PKG_SUMMARY="Test"
	PKG_INSTALL_PATH="/opt/testapp"

	run pkg_manifest_validate
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"PKG_NAME"* ]]
}

@test "pkg_manifest_validate: end-to-end with pkg_manifest_load" {
	local manifest="${TEST_TMPDIR}/pkg.manifest"
	cat > "$manifest" <<'MANIFEST'
PKG_NAME="testapp"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Test application"
PKG_INSTALL_PATH="/opt/testapp"
MANIFEST

	pkg_manifest_load "$manifest"
	run pkg_manifest_validate
	[[ "$status" -eq 0 ]]
}
