#!/usr/bin/env bats
# 05-fileops.bats — file operations function tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create a mock source tree for file operation tests
	MOCK_SRC="${TEST_TMPDIR}/src"
	MOCK_DEST="${TEST_TMPDIR}/dest"
	mkdir -p "${MOCK_SRC}/bin"
	mkdir -p "${MOCK_SRC}/conf"
	mkdir -p "${MOCK_SRC}/lib"
	echo "#!/bin/bash" > "${MOCK_SRC}/bin/myapp"
	echo "key=value" > "${MOCK_SRC}/conf/app.conf"
	echo "helper code" > "${MOCK_SRC}/lib/helper.sh"
	echo "readme" > "${MOCK_SRC}/README"
	export MOCK_SRC MOCK_DEST
}

teardown() {
	pkg_teardown
}

# ── pkg_copy_tree ────────────────────────────────────────────────

@test "pkg_copy_tree: copies entire directory tree" {
	run pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_DEST}/bin/myapp" ]]
	[[ -f "${MOCK_DEST}/conf/app.conf" ]]
	[[ -f "${MOCK_DEST}/lib/helper.sh" ]]
	[[ -f "${MOCK_DEST}/README" ]]
}

@test "pkg_copy_tree: preserves file content" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	local content
	content=$(cat "${MOCK_DEST}/conf/app.conf")
	[[ "$content" = "key=value" ]]
}

@test "pkg_copy_tree: preserves directory structure" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	[[ -d "${MOCK_DEST}/bin" ]]
	[[ -d "${MOCK_DEST}/conf" ]]
	[[ -d "${MOCK_DEST}/lib" ]]
}

@test "pkg_copy_tree: creates destination directory if needed" {
	local deep="${TEST_TMPDIR}/deep/nested/dest"
	run pkg_copy_tree "$MOCK_SRC" "$deep"
	[[ "$status" -eq 0 ]]
	[[ -f "${deep}/README" ]]
}

@test "pkg_copy_tree: fails with empty arguments" {
	run pkg_copy_tree "" "$MOCK_DEST"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_copy_tree: fails when source does not exist" {
	run pkg_copy_tree "${TEST_TMPDIR}/nonexistent" "$MOCK_DEST"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── pkg_set_perms ────────────────────────────────────────────────

@test "pkg_set_perms: sets directory permissions" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	run pkg_set_perms "$MOCK_DEST" "750" "640"
	[[ "$status" -eq 0 ]]
	# Check directory mode
	local mode
	mode=$(stat -c "%a" "${MOCK_DEST}/bin")
	[[ "$mode" = "750" ]]
}

@test "pkg_set_perms: sets file permissions" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	run pkg_set_perms "$MOCK_DEST" "750" "640"
	[[ "$status" -eq 0 ]]
	# Check file mode
	local mode
	mode=$(stat -c "%a" "${MOCK_DEST}/conf/app.conf")
	[[ "$mode" = "640" ]]
}

@test "pkg_set_perms: sets executable overrides" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	run pkg_set_perms "$MOCK_DEST" "750" "640" "bin/myapp"
	[[ "$status" -eq 0 ]]
	# Executable file should have dir_mode (750)
	local mode
	mode=$(stat -c "%a" "${MOCK_DEST}/bin/myapp")
	[[ "$mode" = "750" ]]
}

@test "pkg_set_perms: regular files not listed as exec stay at file_mode" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	pkg_set_perms "$MOCK_DEST" "750" "640" "bin/myapp"
	local mode
	mode=$(stat -c "%a" "${MOCK_DEST}/README")
	[[ "$mode" = "640" ]]
}

@test "pkg_set_perms: handles multiple executables" {
	pkg_copy_tree "$MOCK_SRC" "$MOCK_DEST"
	run pkg_set_perms "$MOCK_DEST" "750" "640" "bin/myapp" "lib/helper.sh"
	[[ "$status" -eq 0 ]]
	local mode1 mode2
	mode1=$(stat -c "%a" "${MOCK_DEST}/bin/myapp")
	mode2=$(stat -c "%a" "${MOCK_DEST}/lib/helper.sh")
	[[ "$mode1" = "750" ]]
	[[ "$mode2" = "750" ]]
}

@test "pkg_set_perms: fails with missing arguments" {
	run pkg_set_perms "" "750" "640"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_set_perms: fails when path does not exist" {
	run pkg_set_perms "${TEST_TMPDIR}/nonexistent" "750" "640"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"does not exist"* ]]
}

# ── pkg_create_dirs ──────────────────────────────────────────────

@test "pkg_create_dirs: creates directories with specified mode" {
	local dir1="${TEST_TMPDIR}/newdir1"
	local dir2="${TEST_TMPDIR}/newdir2"
	run pkg_create_dirs "750" "$dir1" "$dir2"
	[[ "$status" -eq 0 ]]
	[[ -d "$dir1" ]]
	[[ -d "$dir2" ]]
	local mode
	mode=$(stat -c "%a" "$dir1")
	[[ "$mode" = "750" ]]
	mode=$(stat -c "%a" "$dir2")
	[[ "$mode" = "750" ]]
}

@test "pkg_create_dirs: creates nested directories" {
	local deep="${TEST_TMPDIR}/a/b/c"
	run pkg_create_dirs "755" "$deep"
	[[ "$status" -eq 0 ]]
	[[ -d "$deep" ]]
	local mode
	mode=$(stat -c "%a" "$deep")
	[[ "$mode" = "755" ]]
}

@test "pkg_create_dirs: sets mode on existing directory" {
	local dir="${TEST_TMPDIR}/existing"
	mkdir -p "$dir"
	chmod 700 "$dir"
	run pkg_create_dirs "750" "$dir"
	[[ "$status" -eq 0 ]]
	local mode
	mode=$(stat -c "%a" "$dir")
	[[ "$mode" = "750" ]]
}

@test "pkg_create_dirs: fails with missing arguments" {
	run pkg_create_dirs "750"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_create_dirs: fails with empty mode" {
	run pkg_create_dirs "" "${TEST_TMPDIR}/somedir"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_symlink ──────────────────────────────────────────────────

@test "pkg_symlink: creates symlink" {
	local target="${TEST_TMPDIR}/target_file"
	local link="${TEST_TMPDIR}/my_link"
	echo "content" > "$target"
	run pkg_symlink "$target" "$link"
	[[ "$status" -eq 0 ]]
	[[ -L "$link" ]]
	local resolved
	resolved=$(readlink "$link")
	[[ "$resolved" = "$target" ]]
}

@test "pkg_symlink: replaces existing symlink" {
	local target1="${TEST_TMPDIR}/target1"
	local target2="${TEST_TMPDIR}/target2"
	local link="${TEST_TMPDIR}/my_link"
	echo "first" > "$target1"
	echo "second" > "$target2"

	pkg_symlink "$target1" "$link"
	[[ -L "$link" ]]

	run pkg_symlink "$target2" "$link"
	[[ "$status" -eq 0 ]]
	local resolved
	resolved=$(readlink "$link")
	[[ "$resolved" = "$target2" ]]
}

@test "pkg_symlink: replaces existing file with symlink" {
	local target="${TEST_TMPDIR}/target_file"
	local link="${TEST_TMPDIR}/existing_file"
	echo "target content" > "$target"
	echo "old content" > "$link"

	run pkg_symlink "$target" "$link"
	[[ "$status" -eq 0 ]]
	[[ -L "$link" ]]
}

@test "pkg_symlink: fails with empty arguments" {
	run pkg_symlink "" "${TEST_TMPDIR}/link"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_symlink_cleanup ─────────────────────────────────────────

@test "pkg_symlink_cleanup: removes symlinks" {
	local target="${TEST_TMPDIR}/target_file"
	local link="${TEST_TMPDIR}/my_link"
	echo "content" > "$target"
	ln -s "$target" "$link"

	run pkg_symlink_cleanup "$link"
	[[ "$status" -eq 0 ]]
	[[ ! -L "$link" ]]
}

@test "pkg_symlink_cleanup: removes multiple symlinks" {
	local target="${TEST_TMPDIR}/target"
	echo "content" > "$target"
	local link1="${TEST_TMPDIR}/link1"
	local link2="${TEST_TMPDIR}/link2"
	ln -s "$target" "$link1"
	ln -s "$target" "$link2"

	run pkg_symlink_cleanup "$link1" "$link2"
	[[ "$status" -eq 0 ]]
	[[ ! -L "$link1" ]]
	[[ ! -L "$link2" ]]
}

@test "pkg_symlink_cleanup: skips non-symlinks safely" {
	local regular="${TEST_TMPDIR}/regular_file"
	echo "data" > "$regular"

	run pkg_symlink_cleanup "$regular"
	[[ "$status" -eq 0 ]]
	# Regular file should still exist (not removed)
	[[ -f "$regular" ]]
	[[ "$output" == *"skipping non-symlink"* ]]
}

@test "pkg_symlink_cleanup: silently handles nonexistent paths" {
	run pkg_symlink_cleanup "${TEST_TMPDIR}/nonexistent"
	[[ "$status" -eq 0 ]]
}

@test "pkg_symlink_cleanup: fails with no arguments" {
	run pkg_symlink_cleanup
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_sed_replace ──────────────────────────────────────────────

@test "pkg_sed_replace: replaces paths in files" {
	local file="${TEST_TMPDIR}/test.conf"
	echo "path=/usr/local/myapp" > "$file"
	echo "bin=/usr/local/myapp/bin" >> "$file"

	run pkg_sed_replace "/usr/local/myapp" "/opt/myapp" "$file"
	[[ "$status" -eq 0 ]]

	local content
	content=$(cat "$file")
	[[ "$content" == *"/opt/myapp"* ]]
	[[ "$content" != *"/usr/local/myapp"* ]]
}

@test "pkg_sed_replace: handles multiple files" {
	local file1="${TEST_TMPDIR}/file1.conf"
	local file2="${TEST_TMPDIR}/file2.conf"
	echo "path=/old/path" > "$file1"
	echo "path=/old/path" > "$file2"

	run pkg_sed_replace "/old/path" "/new/path" "$file1" "$file2"
	[[ "$status" -eq 0 ]]
	[[ "$(cat "$file1")" == *"/new/path"* ]]
	[[ "$(cat "$file2")" == *"/new/path"* ]]
}

@test "pkg_sed_replace: replaces all occurrences in a file" {
	local file="${TEST_TMPDIR}/multi.conf"
	echo "a=/old/path b=/old/path" > "$file"

	pkg_sed_replace "/old/path" "/new/path" "$file"
	local content
	content=$(cat "$file")
	# Should not contain any /old/path
	[[ "$content" != *"/old/path"* ]]
	# Count occurrences of /new/path — should be 2
	local count
	count=$(grep -o "/new/path" "$file" | wc -l)
	[[ "$count" -eq 2 ]]
}

@test "pkg_sed_replace: warns on missing file and continues" {
	local good="${TEST_TMPDIR}/good.conf"
	echo "path=/old" > "$good"

	run pkg_sed_replace "/old" "/new" "${TEST_TMPDIR}/missing.conf" "$good"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"not found, skipping"* ]]
	# Good file should still be updated
	[[ "$(cat "$good")" == "path=/new" ]]
}

@test "pkg_sed_replace: fails with empty arguments" {
	run pkg_sed_replace "" "/new" "${TEST_TMPDIR}/file"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_sed_replace: fails with no files" {
	run pkg_sed_replace "/old" "/new"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_sed_replace: handles dots in paths (literal match)" {
	local file="${TEST_TMPDIR}/dotpath.conf"
	printf '%s\n' "path=/usr/local/maldetect" "other=/usr/local/maldetecX" > "$file"

	pkg_sed_replace "/usr/local/maldetect" "/opt/maldetect" "$file"

	# The dot in "maldetect" must be literal — "maldetecX" must NOT match
	grep -q "/opt/maldetect" "$file"
	grep -q "/usr/local/maldetecX" "$file"
}

# ── pkg_tmpfile ──────────────────────────────────────────────────

@test "pkg_tmpfile: creates temp file in PKG_TMPDIR" {
	run pkg_tmpfile
	[[ "$status" -eq 0 ]]
	[[ -n "$output" ]]
	[[ -f "$output" ]]
	# Should be under PKG_TMPDIR
	[[ "$output" == "${PKG_TMPDIR}/"* ]]
}

@test "pkg_tmpfile: uses custom template" {
	run pkg_tmpfile "myapp.XXXXXXXX"
	[[ "$status" -eq 0 ]]
	[[ -f "$output" ]]
	# File should start with the template prefix
	local basename_result
	basename_result=$(basename "$output")
	[[ "$basename_result" == myapp.* ]]
}

@test "pkg_tmpfile: uses default template when no argument" {
	run pkg_tmpfile
	[[ "$status" -eq 0 ]]
	local basename_result
	basename_result=$(basename "$output")
	[[ "$basename_result" == pkg_lib.* ]]
}

@test "pkg_tmpfile: creates unique files on repeated calls" {
	local file1 file2
	file1=$(pkg_tmpfile)
	file2=$(pkg_tmpfile)
	[[ "$file1" != "$file2" ]]
	[[ -f "$file1" ]]
	[[ -f "$file2" ]]
}

@test "pkg_tmpfile: respects PKG_TMPDIR setting" {
	local custom="${TEST_TMPDIR}/custom_tmp"
	mkdir -p "$custom"
	PKG_TMPDIR="$custom"
	run pkg_tmpfile
	[[ "$status" -eq 0 ]]
	[[ "$output" == "${custom}/"* ]]
}
