#!/usr/bin/env bats
# 03-deps.bats — dependency checking tests

load helpers/pkg-common

setup() {
	pkg_common_setup
}

teardown() {
	pkg_teardown
}

# ── pkg_dep_hint ─────────────────────────────────────────────────

@test "pkg_dep_hint: returns install command for detected package manager" {
	pkg_detect_pkgmgr
	run pkg_dep_hint "bash" "bash"
	[[ "$status" -eq 0 ]]
	[[ -n "$output" ]]
	# Should contain the package name or a generic fallback
	[[ "$output" == *"bash"* ]] || [[ "$output" == *"install package"* ]]
}

@test "pkg_dep_hint: uses apt for debian systems" {
	_PKG_PKGMGR_DETECT_DONE=1
	_PKG_PKGMGR="apt"
	run pkg_dep_hint "vim-common" "vim"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "apt-get install vim" ]]
}

@test "pkg_dep_hint: uses yum for yum systems" {
	_PKG_PKGMGR_DETECT_DONE=1
	_PKG_PKGMGR="yum"
	run pkg_dep_hint "vim-enhanced" "vim"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "yum install vim-enhanced" ]]
}

@test "pkg_dep_hint: uses dnf for dnf systems" {
	_PKG_PKGMGR_DETECT_DONE=1
	_PKG_PKGMGR="dnf"
	run pkg_dep_hint "vim-enhanced" "vim"
	[[ "$status" -eq 0 ]]
	[[ "$output" == "dnf install vim-enhanced" ]]
}

@test "pkg_dep_hint: falls back to generic hint for unknown manager" {
	_PKG_PKGMGR_DETECT_DONE=1
	_PKG_PKGMGR="unknown"
	run pkg_dep_hint "pkg_rpm" "pkg_deb"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"install package"* ]]
}

# ── pkg_check_dep ────────────────────────────────────────────────

@test "pkg_check_dep: returns 0 for present binary" {
	run pkg_check_dep "bash" "bash" "bash" "required"
	[[ "$status" -eq 0 ]]
}

@test "pkg_check_dep: returns 1 for missing binary" {
	run pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "required"
	[[ "$status" -eq 1 ]]
}

@test "pkg_check_dep: prints error for missing required dep" {
	run pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "required"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"error:"* ]]
	[[ "$output" == *"missing required dependency"* ]]
}

@test "pkg_check_dep: prints warning for missing recommended dep" {
	run pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "recommended"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"warning:"* ]]
	[[ "$output" == *"missing recommended dependency"* ]]
}

@test "pkg_check_dep: prints info for missing optional dep" {
	run pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "optional"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"optional dependency not found"* ]]
}

@test "pkg_check_dep: sets _PKG_DEPS_MISSING for required dep" {
	_PKG_DEPS_MISSING=0
	pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "required" 2>/dev/null || true
	[[ "$_PKG_DEPS_MISSING" -eq 1 ]]
}

@test "pkg_check_dep: does not set _PKG_DEPS_MISSING for recommended dep" {
	_PKG_DEPS_MISSING=0
	pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "recommended" 2>/dev/null || true
	[[ "$_PKG_DEPS_MISSING" -eq 0 ]]
}

@test "pkg_check_dep: does not set _PKG_DEPS_MISSING for optional dep" {
	_PKG_DEPS_MISSING=0
	pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" "optional" 2>/dev/null || true
	[[ "$_PKG_DEPS_MISSING" -eq 0 ]]
}

@test "pkg_check_dep: defaults to required level" {
	_PKG_DEPS_MISSING=0
	pkg_check_dep "nonexistent_binary_xyz123" "pkg" "pkg" 2>/dev/null || true
	[[ "$_PKG_DEPS_MISSING" -eq 1 ]]
}

@test "pkg_check_dep: fails with empty binary name" {
	run pkg_check_dep "" "pkg" "pkg" "required"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires binary name"* ]]
}

@test "pkg_check_dep: includes install hint in output" {
	run pkg_check_dep "nonexistent_binary_xyz123" "myrpm" "mydeb" "required"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"install"* ]]
}

# ── pkg_check_deps ───────────────────────────────────────────────

@test "pkg_check_deps: returns 0 when all deps present" {
	# Use binaries that exist everywhere
	TEST_DEP_BINS=("bash" "cat" "grep")
	TEST_DEP_RPMS=("bash" "coreutils" "grep")
	TEST_DEP_DEBS=("bash" "coreutils" "grep")
	TEST_DEP_LEVELS=("required" "required" "required")

	run pkg_check_deps "TEST"
	[[ "$status" -eq 0 ]]
}

@test "pkg_check_deps: returns 1 when any dep missing" {
	TEST_DEP_BINS=("bash" "nonexistent_binary_xyz123")
	TEST_DEP_RPMS=("bash" "missing-pkg")
	TEST_DEP_DEBS=("bash" "missing-pkg")
	TEST_DEP_LEVELS=("required" "required")

	run pkg_check_deps "TEST"
	[[ "$status" -eq 1 ]]
}

@test "pkg_check_deps: handles mixed levels" {
	TEST_DEP_BINS=("bash" "nonexistent_binary_xyz123")
	TEST_DEP_RPMS=("bash" "missing-pkg")
	TEST_DEP_DEBS=("bash" "missing-pkg")
	TEST_DEP_LEVELS=("required" "optional")

	run pkg_check_deps "TEST"
	# Returns 1 because at least one dep is missing (even optional)
	[[ "$status" -eq 1 ]]
}

@test "pkg_check_deps: returns 0 for empty dep list" {
	TEST_DEP_BINS=()
	TEST_DEP_RPMS=()
	TEST_DEP_DEBS=()
	TEST_DEP_LEVELS=()

	run pkg_check_deps "TEST"
	[[ "$status" -eq 0 ]]
}

@test "pkg_check_deps: fails with empty prefix" {
	run pkg_check_deps ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"requires a variable prefix"* ]]
}

@test "pkg_check_deps: checks all deps even when first fails" {
	TEST_DEP_BINS=("nonexistent_xyz1" "nonexistent_xyz2" "bash")
	TEST_DEP_RPMS=("pkg1" "pkg2" "bash")
	TEST_DEP_DEBS=("pkg1" "pkg2" "bash")
	TEST_DEP_LEVELS=("recommended" "recommended" "required")

	run pkg_check_deps "TEST"
	[[ "$status" -eq 1 ]]
	# Should mention both missing deps
	[[ "$output" == *"nonexistent_xyz1"* ]]
	[[ "$output" == *"nonexistent_xyz2"* ]]
}

# ── Integration: dep check + pkg manager ─────────────────────────

@test "pkg_check_dep: includes correct package manager hint" {
	pkg_detect_pkgmgr
	run pkg_check_dep "nonexistent_binary_xyz123" "myrpm" "mydeb" "required"
	[[ "$status" -eq 1 ]]
	if [[ "$_PKG_PKGMGR" = "apt" ]]; then
		[[ "$output" == *"apt-get install mydeb"* ]]
	elif [[ "$_PKG_PKGMGR" = "yum" ]]; then
		[[ "$output" == *"yum install myrpm"* ]]
	elif [[ "$_PKG_PKGMGR" = "dnf" ]]; then
		[[ "$output" == *"dnf install myrpm"* ]]
	fi
}
