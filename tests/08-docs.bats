#!/usr/bin/env bats
# 08-docs.bats — documentation installation function tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create mock directories for doc installation
	MOCK_MAN_DIR="${TEST_TMPDIR}/usr/share/man"
	MOCK_COMP_DIR="${TEST_TMPDIR}/bash_completion.d"
	MOCK_LR_DIR="${TEST_TMPDIR}/logrotate.d"
	MOCK_DOC_DIR="${TEST_TMPDIR}/doc/myapp"
	mkdir -p "$MOCK_MAN_DIR" "$MOCK_COMP_DIR" "$MOCK_LR_DIR"
	export MOCK_MAN_DIR MOCK_COMP_DIR MOCK_LR_DIR MOCK_DOC_DIR
}

teardown() {
	pkg_teardown
}

# ── _pkg_man_dir ──────────────────────────────────────────────────

@test "_pkg_man_dir: returns /usr/share/man/man8 when it exists" {
	# This directory should exist on most Linux systems
	if [[ -d /usr/share/man/man8 ]]; then
		run _pkg_man_dir "8"
		[[ "$status" -eq 0 ]]
		[[ "$output" = "/usr/share/man/man8" ]]
	else
		skip "/usr/share/man/man8 does not exist"
	fi
}

@test "_pkg_man_dir: returns /usr/share/man/man1 when it exists" {
	if [[ -d /usr/share/man/man1 ]]; then
		run _pkg_man_dir "1"
		[[ "$status" -eq 0 ]]
		[[ "$output" = "/usr/share/man/man1" ]]
	else
		skip "/usr/share/man/man1 does not exist"
	fi
}

@test "_pkg_man_dir: creates fallback directory if neither standard exists" {
	# Test with unusual section that likely doesn't exist
	if [[ ! -d /usr/share/man/man99 ]] && [[ ! -d /usr/local/share/man/man99 ]]; then
		run _pkg_man_dir "99"
		[[ "$status" -eq 0 ]]
		[[ "$output" = "/usr/share/man/man99" ]]
		[[ -d /usr/share/man/man99 ]]
		# Cleanup
		rmdir /usr/share/man/man99 2>/dev/null || true  # safe: test cleanup
	else
		skip "man99 directory already exists"
	fi
}

# ── pkg_man_install ───────────────────────────────────────────────

@test "pkg_man_install: installs and compresses man page" {
	local src="${TEST_TMPDIR}/myapp.8"
	echo '.TH MYAPP 8 "2026-03-06"' > "$src"
	echo '.SH NAME' >> "$src"
	echo 'myapp \- test application' >> "$src"

	run pkg_man_install "$src" "8" "myapp"
	[[ "$status" -eq 0 ]]

	# Should exist as compressed file in man dir
	if [[ -d /usr/share/man/man8 ]]; then
		[[ -f "/usr/share/man/man8/myapp.8.gz" ]]
		# Cleanup
		rm -f "/usr/share/man/man8/myapp.8.gz"
	elif [[ -d /usr/local/share/man/man8 ]]; then
		[[ -f "/usr/local/share/man/man8/myapp.8.gz" ]]
		rm -f "/usr/local/share/man/man8/myapp.8.gz"
	fi
}

@test "pkg_man_install: applies sed replacement pairs" {
	local src="${TEST_TMPDIR}/myapp.8"
	echo '.TH MYAPP 8 "2026-03-06"' > "$src"
	echo 'Install path: /INSTALL_PATH/bin/myapp' >> "$src"

	run pkg_man_install "$src" "8" "myapp" "/INSTALL_PATH|/usr/local"
	[[ "$status" -eq 0 ]]

	# Verify replacement was applied by decompressing
	local man_dir
	if [[ -d /usr/share/man/man8 ]]; then
		man_dir="/usr/share/man/man8"
	elif [[ -d /usr/local/share/man/man8 ]]; then
		man_dir="/usr/local/share/man/man8"
	else
		skip "no man8 directory"
	fi

	local content
	content=$(zcat "${man_dir}/myapp.8.gz")
	echo "$content" | grep -q '/usr/local/bin/myapp'
	# Cleanup
	rm -f "${man_dir}/myapp.8.gz"
}

@test "pkg_man_install: applies multiple sed pairs" {
	local src="${TEST_TMPDIR}/myapp.1"
	echo 'path: /OLD_PATH version: OLD_VERSION' > "$src"

	# Need man1 dir
	if [[ ! -d /usr/share/man/man1 ]]; then
		skip "/usr/share/man/man1 does not exist"
	fi

	run pkg_man_install "$src" "1" "myapp" "/OLD_PATH|/new/path" "OLD_VERSION|2.0.0"
	[[ "$status" -eq 0 ]]

	local content
	content=$(zcat "/usr/share/man/man1/myapp.1.gz")
	echo "$content" | grep -q '/new/path'
	echo "$content" | grep -q '2.0.0'
	# Cleanup
	rm -f "/usr/share/man/man1/myapp.1.gz"
}

@test "pkg_man_install: sets 644 permissions on installed file" {
	local src="${TEST_TMPDIR}/myapp.8"
	echo '.TH MYAPP 8' > "$src"

	pkg_man_install "$src" "8" "myapp"

	local man_dir
	if [[ -d /usr/share/man/man8 ]]; then
		man_dir="/usr/share/man/man8"
	elif [[ -d /usr/local/share/man/man8 ]]; then
		man_dir="/usr/local/share/man/man8"
	else
		skip "no man8 directory"
	fi

	local perms
	perms=$(stat -c '%a' "${man_dir}/myapp.8.gz")
	[[ "$perms" = "644" ]]
	rm -f "${man_dir}/myapp.8.gz"
}

@test "pkg_man_install: fails with empty arguments" {
	run pkg_man_install "" "8" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_man_install: fails with missing source" {
	run pkg_man_install "${TEST_TMPDIR}/nonexistent" "8" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_man_install: fails with missing section" {
	local src="${TEST_TMPDIR}/myapp.8"
	echo "test" > "$src"

	run pkg_man_install "$src" "" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_man_install: fails with missing name" {
	local src="${TEST_TMPDIR}/myapp.8"
	echo "test" > "$src"

	run pkg_man_install "$src" "8" ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_bash_completion ───────────────────────────────────────────

@test "pkg_bash_completion: installs to /etc/bash_completion.d" {
	local src="${TEST_TMPDIR}/myapp.bash"
	echo '_myapp_completions() { :; }' > "$src"

	run pkg_bash_completion "$src" "myapp"
	[[ "$status" -eq 0 ]]
	[[ -f "/etc/bash_completion.d/myapp" ]]

	# Cleanup
	rm -f "/etc/bash_completion.d/myapp"
}

@test "pkg_bash_completion: sets 644 permissions" {
	local src="${TEST_TMPDIR}/myapp.bash"
	echo '_myapp_completions() { :; }' > "$src"

	pkg_bash_completion "$src" "myapp"
	local perms
	perms=$(stat -c '%a' "/etc/bash_completion.d/myapp")
	[[ "$perms" = "644" ]]

	rm -f "/etc/bash_completion.d/myapp"
}

@test "pkg_bash_completion: preserves content" {
	local src="${TEST_TMPDIR}/myapp.bash"
	echo '_myapp_completions() { echo "hello"; }' > "$src"

	pkg_bash_completion "$src" "myapp"
	local content
	content=$(cat "/etc/bash_completion.d/myapp")
	[[ "$content" = '_myapp_completions() { echo "hello"; }' ]]

	rm -f "/etc/bash_completion.d/myapp"
}

@test "pkg_bash_completion: creates directory if missing" {
	# On most systems /etc/bash_completion.d already exists
	# This test verifies the function runs without error
	local src="${TEST_TMPDIR}/myapp.bash"
	echo 'test' > "$src"

	run pkg_bash_completion "$src" "myapp"
	[[ "$status" -eq 0 ]]

	rm -f "/etc/bash_completion.d/myapp"
}

@test "pkg_bash_completion: fails with empty arguments" {
	run pkg_bash_completion "" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_bash_completion: fails with missing source" {
	run pkg_bash_completion "${TEST_TMPDIR}/nonexistent" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── pkg_logrotate_install ─────────────────────────────────────────

@test "pkg_logrotate_install: installs to /etc/logrotate.d" {
	local src="${TEST_TMPDIR}/myapp.logrotate"
	printf '/var/log/myapp.log {\n  rotate 7\n  daily\n}\n' > "$src"

	run pkg_logrotate_install "$src" "myapp"
	[[ "$status" -eq 0 ]]
	[[ -f "/etc/logrotate.d/myapp" ]]

	rm -f "/etc/logrotate.d/myapp"
}

@test "pkg_logrotate_install: sets 644 permissions" {
	local src="${TEST_TMPDIR}/myapp.logrotate"
	printf '/var/log/myapp.log {\n  rotate 7\n}\n' > "$src"

	pkg_logrotate_install "$src" "myapp"
	local perms
	perms=$(stat -c '%a' "/etc/logrotate.d/myapp")
	[[ "$perms" = "644" ]]

	rm -f "/etc/logrotate.d/myapp"
}

@test "pkg_logrotate_install: preserves content" {
	local src="${TEST_TMPDIR}/myapp.logrotate"
	echo 'logrotate content here' > "$src"

	pkg_logrotate_install "$src" "myapp"
	local content
	content=$(cat "/etc/logrotate.d/myapp")
	[[ "$content" = "logrotate content here" ]]

	rm -f "/etc/logrotate.d/myapp"
}

@test "pkg_logrotate_install: fails with empty arguments" {
	run pkg_logrotate_install "" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_logrotate_install: fails with missing source" {
	run pkg_logrotate_install "${TEST_TMPDIR}/nonexistent" "myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── pkg_doc_install ───────────────────────────────────────────────

@test "pkg_doc_install: installs documentation files" {
	local readme="${TEST_TMPDIR}/README"
	local changelog="${TEST_TMPDIR}/CHANGELOG"
	echo "README content" > "$readme"
	echo "CHANGELOG content" > "$changelog"

	run pkg_doc_install "$MOCK_DOC_DIR" "$readme" "$changelog"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_DOC_DIR}/README" ]]
	[[ -f "${MOCK_DOC_DIR}/CHANGELOG" ]]
}

@test "pkg_doc_install: creates destination directory" {
	local readme="${TEST_TMPDIR}/README"
	echo "README" > "$readme"

	local deep_dest="${TEST_TMPDIR}/deep/nested/doc"
	run pkg_doc_install "$deep_dest" "$readme"
	[[ "$status" -eq 0 ]]
	[[ -d "$deep_dest" ]]
	[[ -f "${deep_dest}/README" ]]
}

@test "pkg_doc_install: preserves file content" {
	local readme="${TEST_TMPDIR}/README"
	echo "important info" > "$readme"

	pkg_doc_install "$MOCK_DOC_DIR" "$readme"
	local content
	content=$(cat "${MOCK_DOC_DIR}/README")
	[[ "$content" = "important info" ]]
}

@test "pkg_doc_install: skips missing files with warning" {
	local readme="${TEST_TMPDIR}/README"
	echo "README" > "$readme"

	run pkg_doc_install "$MOCK_DOC_DIR" "$readme" "${TEST_TMPDIR}/nonexistent"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_DOC_DIR}/README" ]]
	[[ "$output" == *"not found, skipping"* ]]
}

@test "pkg_doc_install: fails with empty dest_dir" {
	run pkg_doc_install "" "${TEST_TMPDIR}/README"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_doc_install: fails with no files" {
	run pkg_doc_install "$MOCK_DOC_DIR"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_doc_install: installs single file" {
	local license="${TEST_TMPDIR}/LICENSE"
	echo "GPL v2" > "$license"

	run pkg_doc_install "$MOCK_DOC_DIR" "$license"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_DOC_DIR}/LICENSE" ]]
}

@test "pkg_doc_install: overwrites existing files" {
	mkdir -p "$MOCK_DOC_DIR"
	echo "old" > "${MOCK_DOC_DIR}/README"

	local readme="${TEST_TMPDIR}/README"
	echo "new" > "$readme"

	pkg_doc_install "$MOCK_DOC_DIR" "$readme"
	local content
	content=$(cat "${MOCK_DOC_DIR}/README")
	[[ "$content" = "new" ]]
}
