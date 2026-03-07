#!/bin/bash
# pkg-common.bash — shared BATS helper for pkg_lib tests
# Sources pkg_lib.sh and provides setup/teardown functions.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
export PROJECT_ROOT

# Source library under test
# shellcheck disable=SC1091
source "${PROJECT_ROOT}/files/pkg_lib.sh"

# Expected version from sourced library — tests use this instead of hardcoded strings
EXPECTED_VERSION="$PKG_LIB_VERSION"
export EXPECTED_VERSION

# Load bats-support and bats-assert if available
if [[ -d /usr/local/lib/bats/bats-support ]]; then
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-support/load.bash
	# shellcheck disable=SC1091
	source /usr/local/lib/bats/bats-assert/load.bash
fi

pkg_common_setup() {
	TEST_TMPDIR=$(mktemp -d)
	export TEST_TMPDIR

	# Reset source guard to allow re-sourcing for clean state
	_PKG_LIB_LOADED=""

	# Reset all detection caches so each test starts fresh
	_PKG_COLOR_INIT_DONE=""
	_PKG_C_RED=""
	_PKG_C_GREEN=""
	_PKG_C_YELLOW=""
	_PKG_C_BOLD=""
	_PKG_C_RESET=""
	_PKG_OS_DETECT_DONE=""
	_PKG_OS_FAMILY=""
	_PKG_OS_ID=""
	_PKG_OS_VERSION=""
	_PKG_OS_NAME=""
	_PKG_INIT_DETECT_DONE=""
	_PKG_INIT_SYSTEM=""
	_PKG_PKGMGR_DETECT_DONE=""
	_PKG_PKGMGR=""
	_PKG_DEPS_MISSING=0

	# Reset backup defaults so each test starts clean
	PKG_BACKUP_METHOD="move"
	PKG_BACKUP_SYMLINK=".bk.last"
	PKG_BACKUP_PRUNE_DAYS="0"

	# Disable color output for reproducible test results
	PKG_NO_COLOR=1
	export PKG_NO_COLOR

	# Re-source library with clean state
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/pkg_lib.sh"

	# Export temp dir for test use
	PKG_TMPDIR="$TEST_TMPDIR"
	export PKG_TMPDIR
}

pkg_teardown() {
	rm -rf "$TEST_TMPDIR"
}
