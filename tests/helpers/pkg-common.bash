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
	# shellcheck disable=SC1091
	source "${PROJECT_ROOT}/files/pkg_lib.sh"

	# Export temp dir for test use
	PKG_TMPDIR="$TEST_TMPDIR"
	export PKG_TMPDIR
}

pkg_teardown() {
	rm -rf "$TEST_TMPDIR"
}
