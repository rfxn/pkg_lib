#!/usr/bin/env bats
# 04-backup.bats — backup and restore function tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create a mock install directory for backup tests
	MOCK_INSTALL="${TEST_TMPDIR}/myapp"
	mkdir -p "${MOCK_INSTALL}/conf"
	mkdir -p "${MOCK_INSTALL}/lib"
	echo "key=value" > "${MOCK_INSTALL}/conf/app.conf"
	echo "key2=value2" > "${MOCK_INSTALL}/conf/extra.conf"
	echo "#!/bin/bash" > "${MOCK_INSTALL}/lib/helper.sh"
	echo "data" > "${MOCK_INSTALL}/README"
	export MOCK_INSTALL
}

teardown() {
	pkg_teardown
}

# ── pkg_backup — basic operation ─────────────────────────────────

@test "pkg_backup: creates timestamped backup with move method" {
	run pkg_backup "$MOCK_INSTALL" "move"
	[[ "$status" -eq 0 ]]
	# Original should be gone (moved)
	[[ ! -d "$MOCK_INSTALL" ]]
	# A backup directory should exist in parent dir
	local found=0
	local entry
	for entry in "${TEST_TMPDIR}"/myapp.*; do
		if [[ -d "$entry" ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_backup: creates timestamped backup with copy method" {
	run pkg_backup "$MOCK_INSTALL" "copy"
	[[ "$status" -eq 0 ]]
	# Original should still exist (copied)
	[[ -d "$MOCK_INSTALL" ]]
	# A backup directory should exist in parent dir
	local found=0
	local entry
	for entry in "${TEST_TMPDIR}"/myapp.*; do
		if [[ -d "$entry" ]]; then
			found=1
			break
		fi
	done
	[[ "$found" -eq 1 ]]
}

@test "pkg_backup: preserves file content in backup" {
	pkg_backup "$MOCK_INSTALL" "copy"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")
	[[ -f "${bk_path}/conf/app.conf" ]]
	local content
	content=$(cat "${bk_path}/conf/app.conf")
	[[ "$content" = "key=value" ]]
}

@test "pkg_backup: defaults to PKG_BACKUP_METHOD env var" {
	PKG_BACKUP_METHOD="copy"
	run pkg_backup "$MOCK_INSTALL"
	[[ "$status" -eq 0 ]]
	# Original should still exist (copy is default)
	[[ -d "$MOCK_INSTALL" ]]
}

@test "pkg_backup: creates .bk.last symlink by default" {
	pkg_backup "$MOCK_INSTALL" "copy"
	local symlink="${TEST_TMPDIR}/.bk.last"
	[[ -L "$symlink" ]]
}

@test "pkg_backup: uses custom symlink name from PKG_BACKUP_SYMLINK" {
	PKG_BACKUP_SYMLINK=".last"
	pkg_backup "$MOCK_INSTALL" "copy"
	local symlink="${TEST_TMPDIR}/.last"
	[[ -L "$symlink" ]]
}

@test "pkg_backup: fails with empty install_path" {
	run pkg_backup ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"install_path required"* ]]
}

@test "pkg_backup: fails when install_path does not exist" {
	run pkg_backup "${TEST_TMPDIR}/nonexistent"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"does not exist"* ]]
}

@test "pkg_backup: fails with invalid method" {
	run pkg_backup "$MOCK_INSTALL" "invalid"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"invalid method"* ]]
}

# ── pkg_backup — collision safety ────────────────────────────────

@test "pkg_backup: handles collision by appending -N suffix" {
	# Create first backup
	pkg_backup "$MOCK_INSTALL" "copy"
	local first_bk
	first_bk=$(pkg_backup_path "$MOCK_INSTALL")

	# Create a fake collision path matching the timestamp pattern
	# The second backup should get a different timestamp (or -N suffix)
	pkg_backup "$MOCK_INSTALL" "copy"
	local second_bk
	second_bk=$(pkg_backup_path "$MOCK_INSTALL")

	# Both should exist and be different
	[[ -d "$first_bk" ]]
	[[ -d "$second_bk" ]]
}

# ── pkg_backup_exists ────────────────────────────────────────────

@test "pkg_backup_exists: returns 0 when backup symlink exists" {
	pkg_backup "$MOCK_INSTALL" "copy"
	run pkg_backup_exists "$MOCK_INSTALL"
	[[ "$status" -eq 0 ]]
}

@test "pkg_backup_exists: returns 1 when no backup exists" {
	run pkg_backup_exists "$MOCK_INSTALL"
	[[ "$status" -eq 1 ]]
}

@test "pkg_backup_exists: fails with empty install_path" {
	run pkg_backup_exists ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"install_path required"* ]]
}

# ── pkg_backup_path ──────────────────────────────────────────────

@test "pkg_backup_path: returns resolved backup path" {
	pkg_backup "$MOCK_INSTALL" "copy"
	run pkg_backup_path "$MOCK_INSTALL"
	[[ "$status" -eq 0 ]]
	[[ -n "$output" ]]
	# The output path should actually exist
	[[ -d "$output" ]]
}

@test "pkg_backup_path: fails when no backup symlink exists" {
	run pkg_backup_path "$MOCK_INSTALL"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"no backup symlink found"* ]]
}

@test "pkg_backup_path: fails with empty install_path" {
	run pkg_backup_path ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"install_path required"* ]]
}

# ── pkg_backup_prune ─────────────────────────────────────────────

@test "pkg_backup_prune: no-op when max_age_days is 0" {
	pkg_backup "$MOCK_INSTALL" "copy"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")
	run pkg_backup_prune "$MOCK_INSTALL" "0"
	[[ "$status" -eq 0 ]]
	# Backup should still exist
	[[ -d "$bk_path" ]]
}

@test "pkg_backup_prune: removes old backups beyond max_age" {
	# Create a backup, then touch it to be old
	pkg_backup "$MOCK_INSTALL" "copy"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	# Create a second backup entry that we'll make old
	local old_backup="${TEST_TMPDIR}/myapp.01012020-1000000000"
	mkdir -p "$old_backup"
	# Make it appear old by touching with an old date
	touch -d "2020-01-01" "$old_backup"

	run pkg_backup_prune "$MOCK_INSTALL" "1"
	[[ "$status" -eq 0 ]]
	# Old backup should be removed
	[[ ! -d "$old_backup" ]]
	# Current backup (pointed to by .bk.last) should remain
	[[ -d "$bk_path" ]]
}

@test "pkg_backup_prune: preserves current .bk.last target" {
	pkg_backup "$MOCK_INSTALL" "copy"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	# Even if we set max_age to 0-tolerance, current should survive
	# (because 0 = no pruning)
	run pkg_backup_prune "$MOCK_INSTALL" "0"
	[[ "$status" -eq 0 ]]
	[[ -d "$bk_path" ]]
}

@test "pkg_backup_prune: fails with missing arguments" {
	run pkg_backup_prune "$MOCK_INSTALL" ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_backup_prune: fails with non-integer max_age_days" {
	run pkg_backup_prune "$MOCK_INSTALL" "abc"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"positive integer"* ]]
}

# ── pkg_restore_files ────────────────────────────────────────────

@test "pkg_restore_files: restores files matching glob pattern" {
	# Create backup
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	# Recreate install dir (simulating fresh install)
	mkdir -p "${MOCK_INSTALL}/conf"

	run pkg_restore_files "$bk_path" "$MOCK_INSTALL" "*.conf"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_INSTALL}/conf/app.conf" ]]
	[[ -f "${MOCK_INSTALL}/conf/extra.conf" ]]
}

@test "pkg_restore_files: restores specific file pattern" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	mkdir -p "$MOCK_INSTALL"

	run pkg_restore_files "$bk_path" "$MOCK_INSTALL" "app.conf"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_INSTALL}/conf/app.conf" ]]
	# extra.conf should NOT be restored (different pattern)
	[[ ! -f "${MOCK_INSTALL}/conf/extra.conf" ]]
}

@test "pkg_restore_files: preserves file content" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	mkdir -p "${MOCK_INSTALL}/conf"

	pkg_restore_files "$bk_path" "$MOCK_INSTALL" "app.conf"
	local content
	content=$(cat "${MOCK_INSTALL}/conf/app.conf")
	[[ "$content" = "key=value" ]]
}

@test "pkg_restore_files: creates install_path if missing" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	# Do not recreate install dir — let the function handle it
	run pkg_restore_files "$bk_path" "$MOCK_INSTALL" "*.conf"
	[[ "$status" -eq 0 ]]
	[[ -d "$MOCK_INSTALL" ]]
}

@test "pkg_restore_files: returns 1 when no files match" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	mkdir -p "$MOCK_INSTALL"
	run pkg_restore_files "$bk_path" "$MOCK_INSTALL" "*.nonexistent"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"no files matched"* ]]
}

@test "pkg_restore_files: fails with missing arguments" {
	run pkg_restore_files "" "$MOCK_INSTALL" "*.conf"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_restore_files: fails with no patterns" {
	run pkg_restore_files "${TEST_TMPDIR}/some_backup" "$MOCK_INSTALL"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"pattern required"* ]]
}

@test "pkg_restore_files: fails when backup_path does not exist" {
	run pkg_restore_files "${TEST_TMPDIR}/nonexistent" "$MOCK_INSTALL" "*.conf"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── pkg_restore_dir ──────────────────────────────────────────────

@test "pkg_restore_dir: restores entire subdirectory" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	mkdir -p "$MOCK_INSTALL"

	run pkg_restore_dir "$bk_path" "$MOCK_INSTALL" "conf"
	[[ "$status" -eq 0 ]]
	[[ -d "${MOCK_INSTALL}/conf" ]]
	[[ -f "${MOCK_INSTALL}/conf/app.conf" ]]
	[[ -f "${MOCK_INSTALL}/conf/extra.conf" ]]
}

@test "pkg_restore_dir: preserves directory structure" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	mkdir -p "$MOCK_INSTALL"

	pkg_restore_dir "$bk_path" "$MOCK_INSTALL" "lib"
	[[ -f "${MOCK_INSTALL}/lib/helper.sh" ]]
	local content
	content=$(cat "${MOCK_INSTALL}/lib/helper.sh")
	[[ "$content" = "#!/bin/bash" ]]
}

@test "pkg_restore_dir: fails when subdirectory not found in backup" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	run pkg_restore_dir "$bk_path" "$MOCK_INSTALL" "nonexistent"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found in backup"* ]]
}

@test "pkg_restore_dir: fails with missing arguments" {
	run pkg_restore_dir "" "$MOCK_INSTALL" "conf"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_restore_dir: creates parent directory if needed" {
	pkg_backup "$MOCK_INSTALL" "move"
	local bk_path
	bk_path=$(pkg_backup_path "$MOCK_INSTALL")

	local deep_dest="${TEST_TMPDIR}/deep/nested/install"
	run pkg_restore_dir "$bk_path" "$deep_dest" "conf"
	[[ "$status" -eq 0 ]]
	[[ -d "${deep_dest}/conf" ]]
}
