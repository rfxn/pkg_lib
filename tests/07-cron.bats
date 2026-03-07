#!/usr/bin/env bats
# 07-cron.bats — cron management function tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create mock cron directories
	MOCK_CROND="${TEST_TMPDIR}/cron.d"
	MOCK_CRON_DAILY="${TEST_TMPDIR}/cron.daily"
	mkdir -p "$MOCK_CROND" "$MOCK_CRON_DAILY"
	export MOCK_CROND MOCK_CRON_DAILY
}

teardown() {
	pkg_teardown
}

# ── pkg_cron_install ──────────────────────────────────────────────

@test "pkg_cron_install: installs cron file to cron.d" {
	local src="${TEST_TMPDIR}/mycron"
	echo "*/5 * * * * root /usr/local/bin/myapp" > "$src"

	run pkg_cron_install "$src" "${MOCK_CROND}/myapp"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_CROND}/myapp" ]]
}

@test "pkg_cron_install: sets 644 mode for cron.d" {
	local src="${TEST_TMPDIR}/mycron"
	echo "*/5 * * * * root /usr/local/bin/myapp" > "$src"

	pkg_cron_install "$src" "${MOCK_CROND}/myapp"
	local perms
	perms=$(stat -c '%a' "${MOCK_CROND}/myapp")
	[[ "$perms" = "644" ]]
}

@test "pkg_cron_install: sets 755 mode for cron.daily" {
	local src="${TEST_TMPDIR}/mycron"
	echo "#!/bin/bash" > "$src"
	echo "/usr/local/bin/myapp --daily" >> "$src"

	pkg_cron_install "$src" "${MOCK_CRON_DAILY}/myapp"
	local perms
	perms=$(stat -c '%a' "${MOCK_CRON_DAILY}/myapp")
	[[ "$perms" = "755" ]]
}

@test "pkg_cron_install: auto-detects 755 for cron.hourly" {
	local hourly="${TEST_TMPDIR}/cron.hourly"
	mkdir -p "$hourly"

	local src="${TEST_TMPDIR}/mycron"
	echo "#!/bin/bash" > "$src"

	pkg_cron_install "$src" "${hourly}/myapp"
	local perms
	perms=$(stat -c '%a' "${hourly}/myapp")
	[[ "$perms" = "755" ]]
}

@test "pkg_cron_install: auto-detects 755 for cron.weekly" {
	local weekly="${TEST_TMPDIR}/cron.weekly"
	mkdir -p "$weekly"

	local src="${TEST_TMPDIR}/mycron"
	echo "#!/bin/bash" > "$src"

	pkg_cron_install "$src" "${weekly}/myapp"
	local perms
	perms=$(stat -c '%a' "${weekly}/myapp")
	[[ "$perms" = "755" ]]
}

@test "pkg_cron_install: auto-detects 755 for cron.monthly" {
	local monthly="${TEST_TMPDIR}/cron.monthly"
	mkdir -p "$monthly"

	local src="${TEST_TMPDIR}/mycron"
	echo "#!/bin/bash" > "$src"

	pkg_cron_install "$src" "${monthly}/myapp"
	local perms
	perms=$(stat -c '%a' "${monthly}/myapp")
	[[ "$perms" = "755" ]]
}

@test "pkg_cron_install: uses explicit mode override" {
	local src="${TEST_TMPDIR}/mycron"
	echo "*/5 * * * * root /usr/local/bin/myapp" > "$src"

	pkg_cron_install "$src" "${MOCK_CROND}/myapp" "600"
	local perms
	perms=$(stat -c '%a' "${MOCK_CROND}/myapp")
	[[ "$perms" = "600" ]]
}

@test "pkg_cron_install: preserves file content" {
	local src="${TEST_TMPDIR}/mycron"
	echo "*/5 * * * * root /usr/local/bin/myapp" > "$src"

	pkg_cron_install "$src" "${MOCK_CROND}/myapp"
	local content
	content=$(cat "${MOCK_CROND}/myapp")
	[[ "$content" = "*/5 * * * * root /usr/local/bin/myapp" ]]
}

@test "pkg_cron_install: creates destination directory if missing" {
	local src="${TEST_TMPDIR}/mycron"
	echo "*/5 * * * * root /usr/local/bin/myapp" > "$src"

	local deep_dest="${TEST_TMPDIR}/deep/nested/cron.d/myapp"
	run pkg_cron_install "$src" "$deep_dest"
	[[ "$status" -eq 0 ]]
	[[ -f "$deep_dest" ]]
}

@test "pkg_cron_install: fails with empty arguments" {
	run pkg_cron_install "" "/some/dest"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_cron_install: fails with missing source file" {
	run pkg_cron_install "${TEST_TMPDIR}/nonexistent" "${MOCK_CROND}/myapp"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_cron_install: overwrites existing file" {
	local src="${TEST_TMPDIR}/mycron"
	echo "old content" > "${MOCK_CROND}/myapp"
	echo "new content" > "$src"

	pkg_cron_install "$src" "${MOCK_CROND}/myapp"
	local content
	content=$(cat "${MOCK_CROND}/myapp")
	[[ "$content" = "new content" ]]
}

# ── pkg_cron_remove ───────────────────────────────────────────────

@test "pkg_cron_remove: removes existing cron file" {
	echo "*/5 * * * * root /usr/local/bin/myapp" > "${MOCK_CROND}/myapp"
	[[ -f "${MOCK_CROND}/myapp" ]]

	run pkg_cron_remove "${MOCK_CROND}/myapp"
	[[ "$status" -eq 0 ]]
	[[ ! -f "${MOCK_CROND}/myapp" ]]
}

@test "pkg_cron_remove: removes multiple files" {
	echo "cron1" > "${MOCK_CROND}/app1"
	echo "cron2" > "${MOCK_CROND}/app2"

	run pkg_cron_remove "${MOCK_CROND}/app1" "${MOCK_CROND}/app2"
	[[ "$status" -eq 0 ]]
	[[ ! -f "${MOCK_CROND}/app1" ]]
	[[ ! -f "${MOCK_CROND}/app2" ]]
}

@test "pkg_cron_remove: no-op for nonexistent file" {
	run pkg_cron_remove "${MOCK_CROND}/nonexistent"
	[[ "$status" -eq 0 ]]
}

@test "pkg_cron_remove: fails with no arguments" {
	run pkg_cron_remove
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_cron_cleanup_legacy ───────────────────────────────────────

@test "pkg_cron_cleanup_legacy: removes files matching pattern" {
	echo "old1" > "${MOCK_CROND}/old_app1"
	echo "old2" > "${MOCK_CROND}/old_app2"
	echo "keep" > "${MOCK_CROND}/keep_app"

	run pkg_cron_cleanup_legacy "${MOCK_CROND}/old_*"
	[[ "$status" -eq 0 ]]
	[[ ! -f "${MOCK_CROND}/old_app1" ]]
	[[ ! -f "${MOCK_CROND}/old_app2" ]]
	[[ -f "${MOCK_CROND}/keep_app" ]]
}

@test "pkg_cron_cleanup_legacy: handles multiple patterns" {
	echo "a" > "${MOCK_CROND}/legacy_a"
	echo "b" > "${MOCK_CROND}/deprecated_b"
	echo "keep" > "${MOCK_CROND}/keep_me"

	run pkg_cron_cleanup_legacy "${MOCK_CROND}/legacy_*" "${MOCK_CROND}/deprecated_*"
	[[ "$status" -eq 0 ]]
	[[ ! -f "${MOCK_CROND}/legacy_a" ]]
	[[ ! -f "${MOCK_CROND}/deprecated_b" ]]
	[[ -f "${MOCK_CROND}/keep_me" ]]
}

@test "pkg_cron_cleanup_legacy: no-op when pattern matches nothing" {
	run pkg_cron_cleanup_legacy "${MOCK_CROND}/nonexistent_*"
	[[ "$status" -eq 0 ]]
}

@test "pkg_cron_cleanup_legacy: fails with no arguments" {
	run pkg_cron_cleanup_legacy
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_cron_preserve_schedule ────────────────────────────────────

@test "pkg_cron_preserve_schedule: captures 5-field schedule" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	printf '# comment line\n*/10 * * * * root /usr/local/bin/myapp\n' > "$cron_file"

	run pkg_cron_preserve_schedule "$cron_file" "SAVED_SCHED"
	[[ "$status" -eq 0 ]]

	pkg_cron_preserve_schedule "$cron_file" "SAVED_SCHED"
	[[ "$SAVED_SCHED" = "*/10 * * * *" ]]
}

@test "pkg_cron_preserve_schedule: skips comments and empty lines" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	cat > "$cron_file" <<'EOF'
# This is a comment

# Another comment
0 3 * * * root /usr/local/bin/myapp
EOF

	pkg_cron_preserve_schedule "$cron_file" "SAVED_SCHED"
	[[ "$SAVED_SCHED" = "0 3 * * *" ]]
}

@test "pkg_cron_preserve_schedule: skips variable assignments" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	cat > "$cron_file" <<'EOF'
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
0 */2 * * * root /usr/local/bin/myapp
EOF

	pkg_cron_preserve_schedule "$cron_file" "SAVED_SCHED"
	[[ "$SAVED_SCHED" = "0 */2 * * *" ]]
}

@test "pkg_cron_preserve_schedule: returns 1 for missing file" {
	run pkg_cron_preserve_schedule "${TEST_TMPDIR}/nonexistent" "SAVED_SCHED"
	[[ "$status" -eq 1 ]]
}

@test "pkg_cron_preserve_schedule: returns 1 for empty file" {
	local cron_file="${TEST_TMPDIR}/empty.cron"
	touch "$cron_file"

	run pkg_cron_preserve_schedule "$cron_file" "SAVED_SCHED"
	[[ "$status" -eq 1 ]]
}

@test "pkg_cron_preserve_schedule: returns 1 for comment-only file" {
	local cron_file="${TEST_TMPDIR}/comments.cron"
	printf '# only comments\n# here\n' > "$cron_file"

	run pkg_cron_preserve_schedule "$cron_file" "SAVED_SCHED"
	[[ "$status" -eq 1 ]]
}

@test "pkg_cron_preserve_schedule: fails with empty arguments" {
	run pkg_cron_preserve_schedule "" "SAVED_SCHED"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_cron_restore_schedule ─────────────────────────────────────

@test "pkg_cron_restore_schedule: restores schedule in cron file" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	printf '# comment\n0 0 * * * root /usr/local/bin/myapp\n' > "$cron_file"

	run pkg_cron_restore_schedule "$cron_file" "*/10 * * * *"
	[[ "$status" -eq 0 ]]

	# Verify schedule was replaced
	local new_sched
	new_sched=$(grep -v '^#' "$cron_file" | head -1 | awk '{print $1, $2, $3, $4, $5}')
	[[ "$new_sched" = "*/10 * * * *" ]]
}

@test "pkg_cron_restore_schedule: no-op when schedules match" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	printf '*/10 * * * * root /usr/local/bin/myapp\n' > "$cron_file"

	run pkg_cron_restore_schedule "$cron_file" "*/10 * * * *"
	[[ "$status" -eq 0 ]]

	# Verify content unchanged
	grep -q '*/10 \* \* \* \* root /usr/local/bin/myapp' "$cron_file"
}

@test "pkg_cron_restore_schedule: handles asterisks in schedule" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	printf '0 0 * * * root /usr/local/bin/myapp\n' > "$cron_file"

	run pkg_cron_restore_schedule "$cron_file" "* * * * *"
	[[ "$status" -eq 0 ]]

	local new_sched
	new_sched=$(head -1 "$cron_file" | awk '{print $1, $2, $3, $4, $5}')
	[[ "$new_sched" = "* * * * *" ]]
}

@test "pkg_cron_restore_schedule: preserves command after schedule" {
	local cron_file="${TEST_TMPDIR}/test.cron"
	printf '0 0 * * * root /usr/local/bin/myapp --flag\n' > "$cron_file"

	pkg_cron_restore_schedule "$cron_file" "*/5 * * * *"

	# Command portion should still be there
	grep -q '/usr/local/bin/myapp --flag' "$cron_file"
}

@test "pkg_cron_restore_schedule: returns 1 for missing file" {
	run pkg_cron_restore_schedule "${TEST_TMPDIR}/nonexistent" "0 0 * * *"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_cron_restore_schedule: returns 1 for empty file" {
	local cron_file="${TEST_TMPDIR}/empty.cron"
	touch "$cron_file"

	run pkg_cron_restore_schedule "$cron_file" "0 0 * * *"
	[[ "$status" -eq 1 ]]
}

@test "pkg_cron_restore_schedule: fails with empty arguments" {
	run pkg_cron_restore_schedule "" "0 0 * * *"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── Round-trip: preserve + install + restore ──────────────────────

@test "cron round-trip: preserve schedule, overwrite, restore" {
	# Set up existing cron with custom schedule
	local cron_file="${TEST_TMPDIR}/test.cron"
	printf '*/15 * * * * root /usr/local/bin/myapp\n' > "$cron_file"

	# Preserve
	local saved_sched=""
	pkg_cron_preserve_schedule "$cron_file" "saved_sched"
	[[ "$saved_sched" = "*/15 * * * *" ]]

	# Simulate install overwriting with default schedule
	printf '0 * * * * root /usr/local/bin/myapp\n' > "$cron_file"

	# Restore
	pkg_cron_restore_schedule "$cron_file" "$saved_sched"

	# Verify
	local final_sched
	final_sched=$(head -1 "$cron_file" | awk '{print $1, $2, $3, $4, $5}')
	[[ "$final_sched" = "*/15 * * * *" ]]
}
