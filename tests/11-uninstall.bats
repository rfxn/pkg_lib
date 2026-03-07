#!/usr/bin/env bats
# 11-uninstall.bats — uninstall primitive tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create mock install tree for uninstall tests
	MOCK_INSTALL="${TEST_TMPDIR}/install"
	mkdir -p "${MOCK_INSTALL}/bin"
	mkdir -p "${MOCK_INSTALL}/conf"
	mkdir -p "${MOCK_INSTALL}/lib"
	echo '#!/bin/bash' > "${MOCK_INSTALL}/bin/myapp"
	echo 'key=value' > "${MOCK_INSTALL}/conf/app.conf"
	echo 'helper' > "${MOCK_INSTALL}/lib/helper.sh"
	export MOCK_INSTALL
}

teardown() {
	pkg_teardown
}

# ── pkg_uninstall_confirm ──────────────────────────────────────

@test "pkg_uninstall_confirm: accepts y" {
	run bash -c '. "'"${PROJECT_ROOT}"'/files/pkg_lib.sh" && echo "y" | pkg_uninstall_confirm "TestApp"'
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_confirm: accepts Y" {
	run bash -c '. "'"${PROJECT_ROOT}"'/files/pkg_lib.sh" && echo "Y" | pkg_uninstall_confirm "TestApp"'
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_confirm: rejects n" {
	run bash -c '. "'"${PROJECT_ROOT}"'/files/pkg_lib.sh" && echo "n" | pkg_uninstall_confirm "TestApp"'
	[[ "$status" -eq 1 ]]
}

@test "pkg_uninstall_confirm: rejects empty input" {
	run bash -c '. "'"${PROJECT_ROOT}"'/files/pkg_lib.sh" && echo "" | pkg_uninstall_confirm "TestApp"'
	[[ "$status" -eq 1 ]]
}

@test "pkg_uninstall_confirm: rejects arbitrary text" {
	run bash -c '. "'"${PROJECT_ROOT}"'/files/pkg_lib.sh" && echo "maybe" | pkg_uninstall_confirm "TestApp"'
	[[ "$status" -eq 1 ]]
}

@test "pkg_uninstall_confirm: fails with empty project name" {
	run pkg_uninstall_confirm ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_uninstall_files ────────────────────────────────────────

@test "pkg_uninstall_files: removes files" {
	local f1="${TEST_TMPDIR}/file1"
	local f2="${TEST_TMPDIR}/file2"
	echo "data" > "$f1"
	echo "data" > "$f2"

	run pkg_uninstall_files "$f1" "$f2"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$f1" ]]
	[[ ! -f "$f2" ]]
}

@test "pkg_uninstall_files: removes directories" {
	local d1="${TEST_TMPDIR}/dir1"
	mkdir -p "${d1}/sub"
	echo "data" > "${d1}/sub/file"

	run pkg_uninstall_files "$d1"
	[[ "$status" -eq 0 ]]
	[[ ! -d "$d1" ]]
}

@test "pkg_uninstall_files: removes symlinks" {
	local target="${TEST_TMPDIR}/target"
	local link="${TEST_TMPDIR}/link"
	echo "data" > "$target"
	ln -s "$target" "$link"

	run pkg_uninstall_files "$link"
	[[ "$status" -eq 0 ]]
	[[ ! -L "$link" ]]
	[[ -f "$target" ]]  # target preserved
}

@test "pkg_uninstall_files: skips nonexistent paths silently" {
	run pkg_uninstall_files "${TEST_TMPDIR}/nonexistent"
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_files: mixed existing and nonexistent" {
	local f1="${TEST_TMPDIR}/exists"
	echo "data" > "$f1"

	run pkg_uninstall_files "$f1" "${TEST_TMPDIR}/gone"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$f1" ]]
}

@test "pkg_uninstall_files: fails with no arguments" {
	run pkg_uninstall_files
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_uninstall_man ──────────────────────────────────────────

@test "pkg_uninstall_man: removes man page from standard location" {
	local mandir="${TEST_TMPDIR}/man/man8"
	mkdir -p "$mandir"
	echo ".TH TEST 8" > "${mandir}/myapp.8"
	echo ".TH TEST 8" | gzip > "${mandir}/myapp.8.gz"

	# We cannot test /usr/share/man removal without root; test the function signature
	run pkg_uninstall_man "8" "myapp"
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_man: fails with empty section" {
	run pkg_uninstall_man "" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_uninstall_man: fails with empty name" {
	run pkg_uninstall_man "8" ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_uninstall_cron ─────────────────────────────────────────

@test "pkg_uninstall_cron: removes cron files" {
	local cron1="${TEST_TMPDIR}/cron1"
	local cron2="${TEST_TMPDIR}/cron2"
	echo "* * * * * /usr/sbin/myapp" > "$cron1"
	echo "0 0 * * * /usr/sbin/cleanup" > "$cron2"

	run pkg_uninstall_cron "$cron1" "$cron2"
	[[ "$status" -eq 0 ]]
	[[ ! -f "$cron1" ]]
	[[ ! -f "$cron2" ]]
}

@test "pkg_uninstall_cron: skips nonexistent files" {
	run pkg_uninstall_cron "${TEST_TMPDIR}/gone1" "${TEST_TMPDIR}/gone2"
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_cron: removes symlink cron files" {
	local target="${TEST_TMPDIR}/cron-target"
	local link="${TEST_TMPDIR}/cron-link"
	echo "cron data" > "$target"
	ln -s "$target" "$link"

	run pkg_uninstall_cron "$link"
	[[ "$status" -eq 0 ]]
	[[ ! -L "$link" ]]
}

@test "pkg_uninstall_cron: fails with no arguments" {
	run pkg_uninstall_cron
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_uninstall_logrotate ────────────────────────────────────

@test "pkg_uninstall_logrotate: runs without error" {
	# Cannot test actual /etc/logrotate.d removal without root
	run pkg_uninstall_logrotate "myapp"
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_logrotate: fails with empty name" {
	run pkg_uninstall_logrotate ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_uninstall_completion ───────────────────────────────────

@test "pkg_uninstall_completion: runs without error" {
	# Cannot test actual /etc/bash_completion.d removal without root
	run pkg_uninstall_completion "myapp"
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_completion: fails with empty name" {
	run pkg_uninstall_completion ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_uninstall_sysconfig ────────────────────────────────────

@test "pkg_uninstall_sysconfig: runs without error" {
	# Cannot test actual /etc/sysconfig or /etc/default removal without root
	run pkg_uninstall_sysconfig "myapp"
	[[ "$status" -eq 0 ]]
}

@test "pkg_uninstall_sysconfig: fails with empty name" {
	run pkg_uninstall_sysconfig ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}
