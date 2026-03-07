#!/usr/bin/env bats
# 02-os-detect.bats — OS/platform detection tests

load helpers/pkg-common

setup() {
	pkg_common_setup
}

teardown() {
	pkg_teardown
}

# ── pkg_detect_os ────────────────────────────────────────────────

@test "pkg_detect_os: sets _PKG_OS_FAMILY to a known value" {
	pkg_detect_os
	# On any Linux system, family should be set
	[[ -n "$_PKG_OS_FAMILY" ]]
	# Should be one of the known families (or unknown for edge cases)
	local fam_pat='^(rhel|debian|gentoo|slackware|freebsd|unknown)$'
	[[ "$_PKG_OS_FAMILY" =~ $fam_pat ]]
}

@test "pkg_detect_os: sets _PKG_OS_ID" {
	pkg_detect_os
	[[ -n "$_PKG_OS_ID" ]]
}

@test "pkg_detect_os: sets _PKG_OS_NAME" {
	pkg_detect_os
	[[ -n "$_PKG_OS_NAME" ]]
	[[ "$_PKG_OS_NAME" != "unknown" ]]
}

@test "pkg_detect_os: is cached (idempotent)" {
	pkg_detect_os
	local first_family="$_PKG_OS_FAMILY"
	local first_id="$_PKG_OS_ID"

	# Second call should return same results
	pkg_detect_os
	[[ "$_PKG_OS_FAMILY" = "$first_family" ]]
	[[ "$_PKG_OS_ID" = "$first_id" ]]
}

@test "pkg_detect_os: sets _PKG_OS_DETECT_DONE" {
	_PKG_OS_DETECT_DONE=""
	pkg_detect_os
	[[ "$_PKG_OS_DETECT_DONE" = "1" ]]
}

# ── pkg_detect_init ──────────────────────────────────────────────

@test "pkg_detect_init: sets _PKG_INIT_SYSTEM" {
	pkg_detect_init
	[[ -n "$_PKG_INIT_SYSTEM" ]]
	local init_pat='^(systemd|sysv|upstart|rc\.local|unknown)$'
	[[ "$_PKG_INIT_SYSTEM" =~ $init_pat ]]
}

@test "pkg_detect_init: is cached (idempotent)" {
	pkg_detect_init
	local first="$_PKG_INIT_SYSTEM"
	pkg_detect_init
	[[ "$_PKG_INIT_SYSTEM" = "$first" ]]
}

@test "pkg_detect_init: sets _PKG_INIT_DETECT_DONE" {
	_PKG_INIT_DETECT_DONE=""
	pkg_detect_init
	[[ "$_PKG_INIT_DETECT_DONE" = "1" ]]
}

# ── pkg_detect_pkgmgr ───────────────────────────────────────────

@test "pkg_detect_pkgmgr: sets _PKG_PKGMGR" {
	pkg_detect_pkgmgr
	[[ -n "$_PKG_PKGMGR" ]]
	local mgr_pat='^(dnf|yum|apt|emerge|pkg|slackpkg|unknown)$'
	[[ "$_PKG_PKGMGR" =~ $mgr_pat ]]
}

@test "pkg_detect_pkgmgr: is cached (idempotent)" {
	pkg_detect_pkgmgr
	local first="$_PKG_PKGMGR"
	pkg_detect_pkgmgr
	[[ "$_PKG_PKGMGR" = "$first" ]]
}

@test "pkg_detect_pkgmgr: sets _PKG_PKGMGR_DETECT_DONE" {
	_PKG_PKGMGR_DETECT_DONE=""
	pkg_detect_pkgmgr
	[[ "$_PKG_PKGMGR_DETECT_DONE" = "1" ]]
}

# ── pkg_is_systemd ───────────────────────────────────────────────

@test "pkg_is_systemd: returns consistent with _PKG_INIT_SYSTEM" {
	pkg_detect_init
	if [[ "$_PKG_INIT_SYSTEM" = "systemd" ]]; then
		pkg_is_systemd
	else
		! pkg_is_systemd
	fi
}

@test "pkg_is_systemd: auto-detects init system if not already done" {
	_PKG_INIT_DETECT_DONE=""
	_PKG_INIT_SYSTEM=""
	# Should auto-detect without explicit pkg_detect_init call
	pkg_is_systemd || true
	[[ -n "$_PKG_INIT_SYSTEM" ]]
}

# ── pkg_os_family ────────────────────────────────────────────────

@test "pkg_os_family: echoes family string" {
	run pkg_os_family
	[[ "$status" -eq 0 ]]
	[[ -n "$output" ]]
	local fam_pat='^(rhel|debian|gentoo|slackware|freebsd|unknown)$'
	[[ "$output" =~ $fam_pat ]]
}

@test "pkg_os_family: auto-detects OS if not already done" {
	_PKG_OS_DETECT_DONE=""
	_PKG_OS_FAMILY=""
	run pkg_os_family
	[[ "$status" -eq 0 ]]
	[[ -n "$output" ]]
}

# ── Detection state isolation ────────────────────────────────────

@test "detection functions do not interfere with each other" {
	# Run all three detection functions
	pkg_detect_os
	pkg_detect_init
	pkg_detect_pkgmgr

	# All should have populated their values
	[[ -n "$_PKG_OS_FAMILY" ]]
	[[ -n "$_PKG_INIT_SYSTEM" ]]
	[[ -n "$_PKG_PKGMGR" ]]

	# All done flags should be set
	[[ "$_PKG_OS_DETECT_DONE" = "1" ]]
	[[ "$_PKG_INIT_DETECT_DONE" = "1" ]]
	[[ "$_PKG_PKGMGR_DETECT_DONE" = "1" ]]
}

# ── Container/Docker detection ───────────────────────────────────

@test "pkg_detect_os: detects correct family for current container OS" {
	pkg_detect_os
	# This test runs in a Docker container — verify family matches
	if [[ -f /etc/debian_version ]]; then
		[[ "$_PKG_OS_FAMILY" = "debian" ]]
	elif [[ -f /etc/redhat-release ]]; then
		[[ "$_PKG_OS_FAMILY" = "rhel" ]]
	elif [[ -f /etc/gentoo-release ]]; then
		[[ "$_PKG_OS_FAMILY" = "gentoo" ]]
	elif [[ -f /etc/slackware-version ]]; then
		[[ "$_PKG_OS_FAMILY" = "slackware" ]]
	fi
	# If none match, the test is inconclusive (but should not fail)
}
