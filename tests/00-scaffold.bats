#!/usr/bin/env bats
# 00-scaffold.bats — validate project skeleton

load helpers/pkg-common

setup() {
	pkg_common_setup
}

teardown() {
	pkg_teardown
}

@test "PKG_LIB_VERSION is set and follows semver" {
	[[ -n "$EXPECTED_VERSION" ]]
	local semver_pat='^[0-9]+\.[0-9]+\.[0-9]+$'
	[[ "$EXPECTED_VERSION" =~ $semver_pat ]]
}

@test "source guard prevents double-sourcing side effects" {
	local ver_before="$PKG_LIB_VERSION"
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/pkg_lib.sh"
	[[ "$PKG_LIB_VERSION" == "$ver_before" ]]
}
