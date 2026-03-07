#!/usr/bin/env bats
# 01-output.bats — output and messaging function tests

load helpers/pkg-common

setup() {
	pkg_common_setup
}

teardown() {
	pkg_teardown
}

# ── _pkg_color_init ──────────────────────────────────────────────

@test "_pkg_color_init: sets empty colors when PKG_NO_COLOR=1" {
	PKG_NO_COLOR=1
	_PKG_COLOR_INIT_DONE=""
	_pkg_color_init
	[[ -z "$_PKG_C_RED" ]]
	[[ -z "$_PKG_C_GREEN" ]]
	[[ -z "$_PKG_C_YELLOW" ]]
	[[ -z "$_PKG_C_BOLD" ]]
	[[ -z "$_PKG_C_RESET" ]]
}

@test "_pkg_color_init: is idempotent (cached after first call)" {
	PKG_NO_COLOR=1
	_PKG_COLOR_INIT_DONE=""
	_pkg_color_init
	[[ "$_PKG_COLOR_INIT_DONE" = "1" ]]

	# Second call should not re-initialize
	PKG_NO_COLOR=0
	_pkg_color_init
	# Still empty because first call cached with no-color
	[[ -z "$_PKG_C_RED" ]]
}

@test "_pkg_color_init: sets empty colors when stdout is not a terminal" {
	PKG_NO_COLOR=0
	_PKG_COLOR_INIT_DONE=""
	# In BATS, stdout is not a tty — colors should be empty
	_pkg_color_init
	[[ -z "$_PKG_C_RED" ]]
	[[ -z "$_PKG_C_GREEN" ]]
}

# ── pkg_header ───────────────────────────────────────────────────

@test "pkg_header: prints project name and version" {
	run pkg_header "BFD" "2.0.1" "install"
	[[ "$status" -eq 0 ]]
	# Output should contain project name and version
	local found=0
	local line
	for line in "${lines[@]}"; do
		if [[ "$line" == *"BFD 2.0.1"* ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_header: includes action in output" {
	run pkg_header "APF" "2.0.2" "upgrade"
	[[ "$status" -eq 0 ]]
	local found=0
	local line
	for line in "${lines[@]}"; do
		if [[ "$line" == *"upgrade"* ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_header: works without action argument" {
	run pkg_header "LMD" "2.0.1" ""
	[[ "$status" -eq 0 ]]
	local found=0
	local line
	for line in "${lines[@]}"; do
		if [[ "$line" == *"LMD 2.0.1"* ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_header: prints separator line" {
	run pkg_header "BFD" "2.0.1" "install"
	[[ "$status" -eq 0 ]]
	local found=0
	local line
	for line in "${lines[@]}"; do
		if [[ "$line" == *"-----"* ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_header: fails without project name" {
	run pkg_header "" "2.0.1" "install"
	[[ "$status" -eq 1 ]]
}

@test "pkg_header: fails without version" {
	run pkg_header "BFD" "" "install"
	[[ "$status" -eq 1 ]]
}

# ── pkg_info ─────────────────────────────────────────────────────

@test "pkg_info: prints message to stdout" {
	run pkg_info "Installing files"
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"Installing files"* ]]
}

@test "pkg_info: suppressed when PKG_QUIET=1" {
	PKG_QUIET=1
	run pkg_info "should not appear"
	[[ "$status" -eq 0 ]]
	[[ "${#lines[@]}" -eq 0 ]]
}

@test "pkg_info: not suppressed when PKG_QUIET=0" {
	PKG_QUIET=0
	run pkg_info "should appear"
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"should appear"* ]]
}

# ── pkg_warn ─────────────────────────────────────────────────────

@test "pkg_warn: prints warning to stderr" {
	run pkg_warn "something may be wrong"
	# BATS captures both stdout and stderr into output for run
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"warning:"* ]]
	[[ "${lines[0]}" == *"something may be wrong"* ]]
}

# ── pkg_error ────────────────────────────────────────────────────

@test "pkg_error: prints error to stderr" {
	run pkg_error "fatal problem"
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"error:"* ]]
	[[ "${lines[0]}" == *"fatal problem"* ]]
}

# ── pkg_success ──────────────────────────────────────────────────

@test "pkg_success: prints success message to stdout" {
	run pkg_success "all done"
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"all done"* ]]
}

# ── pkg_section ──────────────────────────────────────────────────

@test "pkg_section: prints section title" {
	run pkg_section "Dependencies"
	[[ "$status" -eq 0 ]]
	local found=0
	local line
	for line in "${lines[@]}"; do
		if [[ "$line" == *"Dependencies"* ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_section: fails without title" {
	run pkg_section ""
	[[ "$status" -eq 1 ]]
}

# ── pkg_item ─────────────────────────────────────────────────────

@test "pkg_item: prints aligned label and value" {
	run pkg_item "Version" "2.0.1"
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"Version:"* ]]
	[[ "${lines[0]}" == *"2.0.1"* ]]
}

@test "pkg_item: handles empty value" {
	run pkg_item "Status" ""
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"Status:"* ]]
}

@test "pkg_item: handles long label" {
	run pkg_item "Installation Path" "/usr/local/bfd"
	[[ "$status" -eq 0 ]]
	[[ "${lines[0]}" == *"Installation Path:"* ]]
	[[ "${lines[0]}" == *"/usr/local/bfd"* ]]
}

# ── Output functions: no color in non-tty ────────────────────────

@test "output functions produce clean text without escape sequences when PKG_NO_COLOR=1" {
	PKG_NO_COLOR=1
	_PKG_COLOR_INIT_DONE=""
	_pkg_color_init

	run pkg_info "clean text"
	# Verify no escape sequences (ESC = \033 = \x1b)
	local esc_pat=$'\033'
	[[ "${output}" != *"${esc_pat}"* ]]

	run pkg_warn "clean warning"
	[[ "${output}" != *"${esc_pat}"* ]]

	run pkg_error "clean error"
	[[ "${output}" != *"${esc_pat}"* ]]

	run pkg_success "clean success"
	[[ "${output}" != *"${esc_pat}"* ]]
}
