#!/usr/bin/env bats
# 10-fhs.bats — FHS layout & symlink farm tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create mock source tree for FHS install tests
	MOCK_SRC="${TEST_TMPDIR}/src"
	MOCK_FHS="${TEST_TMPDIR}/fhs"
	MOCK_LEGACY="${TEST_TMPDIR}/legacy"
	mkdir -p "${MOCK_SRC}/files"
	mkdir -p "${MOCK_SRC}/files/internals"
	mkdir -p "${MOCK_SRC}/files/conf"
	echo '#!/bin/bash' > "${MOCK_SRC}/files/myapp"
	echo 'helper code' > "${MOCK_SRC}/files/internals/lib.sh"
	echo 'key=value' > "${MOCK_SRC}/files/conf/app.conf"
	echo 'readme content' > "${MOCK_SRC}/files/README"
	export MOCK_SRC MOCK_FHS MOCK_LEGACY
}

teardown() {
	pkg_teardown
}

# ── pkg_fhs_register ────────────────────────────────────────────

@test "pkg_fhs_register: registers a file mapping" {
	run pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	[[ "$status" -eq 0 ]]
	[[ "${#_PKG_FHS_SRCS[@]}" -eq 0 ]]  # run creates subshell — check in main
}

@test "pkg_fhs_register: populates parallel arrays" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	[[ "${_PKG_FHS_SRCS[0]}" = "files/myapp" ]]
	[[ "${_PKG_FHS_DESTS[0]}" = "/usr/sbin/myapp" ]]
	[[ "${_PKG_FHS_MODES[0]}" = "750" ]]
	[[ "${_PKG_FHS_TYPES[0]}" = "bin" ]]
}

@test "pkg_fhs_register: multiple registrations append correctly" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/conf/app.conf" "/etc/myapp/app.conf" "640" "conf"
	pkg_fhs_register "files/internals/lib.sh" "/usr/lib/myapp/lib.sh" "640" "lib"
	[[ "${#_PKG_FHS_SRCS[@]}" -eq 3 ]]
	[[ "${_PKG_FHS_TYPES[0]}" = "bin" ]]
	[[ "${_PKG_FHS_TYPES[1]}" = "conf" ]]
	[[ "${_PKG_FHS_TYPES[2]}" = "lib" ]]
}

@test "pkg_fhs_register: defaults type to data" {
	pkg_fhs_register "files/README" "/usr/share/myapp/README" "644"
	[[ "${_PKG_FHS_TYPES[0]}" = "data" ]]
}

@test "pkg_fhs_register: rejects invalid type" {
	run pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "invalid"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"invalid type"* ]]
}

@test "pkg_fhs_register: rejects invalid mode" {
	run pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "999" "bin"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"invalid mode"* ]]
}

@test "pkg_fhs_register: fails with empty src" {
	run pkg_fhs_register "" "/usr/sbin/myapp" "750" "bin"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_register: fails with empty fhs_dest" {
	run pkg_fhs_register "files/myapp" "" "750" "bin"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_register: fails with empty mode" {
	run pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "" "bin"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_register: accepts all valid types" {
	local types="bin lib conf data state doc"
	local t count=0
	for t in $types; do
		pkg_fhs_register "files/f${count}" "/dest/f${count}" "640" "$t"
		count=$((count + 1))
	done
	[[ "${#_PKG_FHS_SRCS[@]}" -eq 6 ]]
}

@test "pkg_fhs_register: accepts 4-digit octal mode" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "0750" "bin"
	[[ "${_PKG_FHS_MODES[0]}" = "0750" ]]
}

# ── pkg_fhs_install ─────────────────────────────────────────────

@test "pkg_fhs_install: installs registered files to FHS paths" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/conf/app.conf" "${MOCK_FHS}/etc/myapp/app.conf" "640" "conf"
	run pkg_fhs_install "$MOCK_SRC"
	[[ "$status" -eq 0 ]]
	[[ -f "${MOCK_FHS}/usr/sbin/myapp" ]]
	[[ -f "${MOCK_FHS}/etc/myapp/app.conf" ]]
}

@test "pkg_fhs_install: sets correct permissions" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_install "$MOCK_SRC"
	local mode
	mode=$(stat -c "%a" "${MOCK_FHS}/usr/sbin/myapp")
	[[ "$mode" = "750" ]]
}

@test "pkg_fhs_install: creates destination directories" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/deep/nested/dir/myapp" "750" "bin"
	run pkg_fhs_install "$MOCK_SRC"
	[[ "$status" -eq 0 ]]
	[[ -d "${MOCK_FHS}/deep/nested/dir" ]]
	[[ -f "${MOCK_FHS}/deep/nested/dir/myapp" ]]
}

@test "pkg_fhs_install: preserves file content" {
	pkg_fhs_register "files/conf/app.conf" "${MOCK_FHS}/etc/myapp/app.conf" "640" "conf"
	pkg_fhs_install "$MOCK_SRC"
	local content
	content=$(cat "${MOCK_FHS}/etc/myapp/app.conf")
	[[ "$content" = "key=value" ]]
}

@test "pkg_fhs_install: warns on empty registry" {
	run pkg_fhs_install "$MOCK_SRC"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"no files registered"* ]]
}

@test "pkg_fhs_install: fails with empty src_dir" {
	run pkg_fhs_install ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_install: fails when source directory missing" {
	run pkg_fhs_install "${TEST_TMPDIR}/nonexistent"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_fhs_install: warns on missing source file" {
	pkg_fhs_register "files/missing" "${MOCK_FHS}/dest/missing" "640" "data"
	run pkg_fhs_install "$MOCK_SRC"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_fhs_install: handles directory-type sources" {
	mkdir -p "${MOCK_SRC}/files/datadir/sub"
	echo "data" > "${MOCK_SRC}/files/datadir/sub/file.txt"
	pkg_fhs_register "files/datadir" "${MOCK_FHS}/share/myapp/datadir" "750" "data"
	run pkg_fhs_install "$MOCK_SRC"
	[[ "$status" -eq 0 ]]
	[[ -d "${MOCK_FHS}/share/myapp/datadir" ]]
}

@test "pkg_fhs_install: reports correct count when multiple files fail" {
	# Register 4 files: 2 exist, 2 missing — should report "installed 2"
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/missing1" "${MOCK_FHS}/dest/missing1" "640" "data"
	pkg_fhs_register "files/missing2" "${MOCK_FHS}/dest/missing2" "640" "data"
	pkg_fhs_register "files/conf/app.conf" "${MOCK_FHS}/etc/myapp/app.conf" "640" "conf"
	run pkg_fhs_install "$MOCK_SRC"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"installed 2 file(s)"* ]]
	[[ -f "${MOCK_FHS}/usr/sbin/myapp" ]]
	[[ -f "${MOCK_FHS}/etc/myapp/app.conf" ]]
}

# ── pkg_fhs_symlink_farm ───────────────────────────────────────

@test "pkg_fhs_symlink_farm: creates symlinks from legacy to FHS" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/conf/app.conf" "${MOCK_FHS}/etc/myapp/app.conf" "640" "conf"
	# Install files first so targets exist
	pkg_fhs_install "$MOCK_SRC"

	run pkg_fhs_symlink_farm "$MOCK_LEGACY"
	[[ "$status" -eq 0 ]]
	[[ -L "${MOCK_LEGACY}/files/myapp" ]]
	[[ -L "${MOCK_LEGACY}/files/conf/app.conf" ]]
}

@test "pkg_fhs_symlink_farm: symlinks point to correct FHS destinations" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_install "$MOCK_SRC"

	pkg_fhs_symlink_farm "$MOCK_LEGACY"
	local target
	target=$(readlink "${MOCK_LEGACY}/files/myapp")
	[[ "$target" = "${MOCK_FHS}/usr/sbin/myapp" ]]
}

@test "pkg_fhs_symlink_farm: creates parent directories" {
	pkg_fhs_register "files/internals/lib.sh" "${MOCK_FHS}/lib/myapp/lib.sh" "640" "lib"
	pkg_fhs_install "$MOCK_SRC"

	run pkg_fhs_symlink_farm "$MOCK_LEGACY"
	[[ "$status" -eq 0 ]]
	[[ -d "${MOCK_LEGACY}/files/internals" ]]
	[[ -L "${MOCK_LEGACY}/files/internals/lib.sh" ]]
}

@test "pkg_fhs_symlink_farm: warns on empty registry" {
	run pkg_fhs_symlink_farm "$MOCK_LEGACY"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"no files registered"* ]]
}

@test "pkg_fhs_symlink_farm: fails with empty legacy_root" {
	run pkg_fhs_symlink_farm ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_symlink_farm: reports correct count when multiple links fail" {
	# Register 3 files — all source paths under "files/", install them
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/conf/app.conf" "${MOCK_FHS}/etc/myapp/app.conf" "640" "conf"
	pkg_fhs_register "files/README" "${MOCK_FHS}/share/myapp/README" "644" "data"
	pkg_fhs_install "$MOCK_SRC"

	# Block symlink parent dir: place a file where "files/" directory needs to be
	mkdir -p "${MOCK_LEGACY}"
	echo "blocker" > "${MOCK_LEGACY}/files"

	run pkg_fhs_symlink_farm "$MOCK_LEGACY"
	[[ "$status" -eq 1 ]]
	# All 3 fail (parent dir "files" is a file, not a directory).
	# Old bug: rc=1 (boolean), reported "created 2" — wrong.
	# Fixed: failed=3, so installed=0, no "created" message.
	[[ "$output" != *"created 2"* ]]
	[[ "$output" != *"created 3"* ]]
}

# ── pkg_fhs_symlink_farm_cleanup ───────────────────────────────

@test "pkg_fhs_symlink_farm_cleanup: removes symlinks" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_install "$MOCK_SRC"
	pkg_fhs_symlink_farm "$MOCK_LEGACY"
	[[ -L "${MOCK_LEGACY}/files/myapp" ]]

	run pkg_fhs_symlink_farm_cleanup "$MOCK_LEGACY"
	[[ "$status" -eq 0 ]]
	[[ ! -L "${MOCK_LEGACY}/files/myapp" ]]
}

@test "pkg_fhs_symlink_farm_cleanup: removes empty directories" {
	pkg_fhs_register "files/internals/lib.sh" "${MOCK_FHS}/lib/myapp/lib.sh" "640" "lib"
	pkg_fhs_install "$MOCK_SRC"
	pkg_fhs_symlink_farm "$MOCK_LEGACY"
	[[ -d "${MOCK_LEGACY}/files/internals" ]]

	pkg_fhs_symlink_farm_cleanup "$MOCK_LEGACY"
	[[ ! -d "${MOCK_LEGACY}/files/internals" ]]
}

@test "pkg_fhs_symlink_farm_cleanup: leaves non-symlink files intact" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_install "$MOCK_SRC"
	pkg_fhs_symlink_farm "$MOCK_LEGACY"
	# Create a non-symlink file alongside
	echo "custom" > "${MOCK_LEGACY}/files/custom.conf"

	pkg_fhs_symlink_farm_cleanup "$MOCK_LEGACY"
	# Symlink removed but custom file preserved
	[[ ! -L "${MOCK_LEGACY}/files/myapp" ]]
	[[ -f "${MOCK_LEGACY}/files/custom.conf" ]]
}

@test "pkg_fhs_symlink_farm_cleanup: handles empty registry" {
	run pkg_fhs_symlink_farm_cleanup "$MOCK_LEGACY"
	[[ "$status" -eq 0 ]]
}

@test "pkg_fhs_symlink_farm_cleanup: fails with empty legacy_root" {
	run pkg_fhs_symlink_farm_cleanup ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

# ── pkg_fhs_gen_rpm_files ──────────────────────────────────────

@test "pkg_fhs_gen_rpm_files: generates %dir entries" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_rpm_files)
	[[ "$output" == *"%dir /usr/sbin"* ]]
}

@test "pkg_fhs_gen_rpm_files: config files get %config(noreplace)" {
	pkg_fhs_register "files/conf/app.conf" "/etc/myapp/app.conf" "640" "conf"
	local output
	output=$(pkg_fhs_gen_rpm_files)
	[[ "$output" == *"%config(noreplace) /etc/myapp/app.conf"* ]]
}

@test "pkg_fhs_gen_rpm_files: non-config files listed plainly" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_rpm_files)
	[[ "$output" == *"/usr/sbin/myapp"* ]]
	[[ "$output" != *"%config"*"/usr/sbin/myapp"* ]]
}

@test "pkg_fhs_gen_rpm_files: deduplicates %dir entries" {
	pkg_fhs_register "files/a" "/usr/lib/myapp/a" "640" "lib"
	pkg_fhs_register "files/b" "/usr/lib/myapp/b" "640" "lib"
	local output count
	output=$(pkg_fhs_gen_rpm_files)
	count=$(echo "$output" | grep -c "^%dir /usr/lib/myapp$")
	[[ "$count" -eq 1 ]]
}

@test "pkg_fhs_gen_rpm_files: empty registry produces no output" {
	local output
	output=$(pkg_fhs_gen_rpm_files)
	[[ -z "$output" ]]
}

# ── pkg_fhs_gen_deb_dirs ──────────────────────────────────────

@test "pkg_fhs_gen_deb_dirs: generates unique directory paths" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/conf/app.conf" "/etc/myapp/app.conf" "640" "conf"
	local output
	output=$(pkg_fhs_gen_deb_dirs)
	[[ "$output" == *"/usr/sbin"* ]]
	[[ "$output" == *"/etc/myapp"* ]]
}

@test "pkg_fhs_gen_deb_dirs: deduplicates directories" {
	pkg_fhs_register "files/a" "/usr/lib/myapp/a" "640" "lib"
	pkg_fhs_register "files/b" "/usr/lib/myapp/b" "640" "lib"
	local output count
	output=$(pkg_fhs_gen_deb_dirs)
	count=$(echo "$output" | grep -c "^/usr/lib/myapp$")
	[[ "$count" -eq 1 ]]
}

@test "pkg_fhs_gen_deb_dirs: empty registry produces no output" {
	local output
	output=$(pkg_fhs_gen_deb_dirs)
	[[ -z "$output" ]]
}

# ── pkg_fhs_gen_deb_links ──────────────────────────────────────

@test "pkg_fhs_gen_deb_links: generates dest-legacy pairs" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_deb_links "/usr/local/myapp")
	[[ "$output" == *"/usr/sbin/myapp /usr/local/myapp/files/myapp"* ]]
}

@test "pkg_fhs_gen_deb_links: handles multiple entries" {
	pkg_fhs_register "files/a" "/usr/sbin/a" "750" "bin"
	pkg_fhs_register "files/b" "/etc/myapp/b" "640" "conf"
	local output count
	output=$(pkg_fhs_gen_deb_links "/usr/local/myapp")
	count=$(echo "$output" | wc -l)
	[[ "$count" -eq 2 ]]
}

@test "pkg_fhs_gen_deb_links: fails with empty legacy_root" {
	run pkg_fhs_gen_deb_links ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_gen_deb_links: empty registry produces no output" {
	local output
	output=$(pkg_fhs_gen_deb_links "/usr/local/myapp")
	[[ -z "$output" ]]
}

# ── pkg_fhs_gen_deb_conffiles ──────────────────────────────────

@test "pkg_fhs_gen_deb_conffiles: lists only conf-type entries" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/conf/app.conf" "/etc/myapp/app.conf" "640" "conf"
	pkg_fhs_register "files/lib.sh" "/usr/lib/myapp/lib.sh" "640" "lib"
	local output
	output=$(pkg_fhs_gen_deb_conffiles)
	[[ "$output" = "/etc/myapp/app.conf" ]]
}

@test "pkg_fhs_gen_deb_conffiles: multiple conf entries" {
	pkg_fhs_register "files/a.conf" "/etc/myapp/a.conf" "640" "conf"
	pkg_fhs_register "files/b.conf" "/etc/myapp/b.conf" "640" "conf"
	local output count
	output=$(pkg_fhs_gen_deb_conffiles)
	count=$(echo "$output" | wc -l)
	[[ "$count" -eq 2 ]]
}

@test "pkg_fhs_gen_deb_conffiles: no conf entries produces no output" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_deb_conffiles)
	[[ -z "$output" ]]
}

@test "pkg_fhs_gen_deb_conffiles: empty registry produces no output" {
	local output
	output=$(pkg_fhs_gen_deb_conffiles)
	[[ -z "$output" ]]
}

# ── pkg_fhs_gen_sed_pairs ──────────────────────────────────────

@test "pkg_fhs_gen_sed_pairs: generates sed expressions" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_sed_pairs "INSTALL_PATH")
	[[ "$output" == *"-e"* ]]
	[[ "$output" == *"/usr/sbin"* ]]
	[[ "$output" == *'$INSTALL_PATH'* ]]
}

@test "pkg_fhs_gen_sed_pairs: deduplicates directory prefixes" {
	pkg_fhs_register "files/a" "/usr/lib/myapp/a" "640" "lib"
	pkg_fhs_register "files/b" "/usr/lib/myapp/b" "640" "lib"
	local output count
	output=$(pkg_fhs_gen_sed_pairs "INSTALL_PATH")
	count=$(echo "$output" | wc -l)
	[[ "$count" -eq 1 ]]
}

@test "pkg_fhs_gen_sed_pairs: fails with empty variable name" {
	run pkg_fhs_gen_sed_pairs ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_gen_sed_pairs: empty registry produces no output" {
	local output
	output=$(pkg_fhs_gen_sed_pairs "INSTALL_PATH")
	[[ -z "$output" ]]
}

# ── pkg_fhs_gen_manifest ──────────────────────────────────────

@test "pkg_fhs_gen_manifest: generates manifest header" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_manifest "/etc/myapp")
	local header
	header=$(echo "$output" | head -1)
	[[ "$header" = "# pkg_lib:symlink-manifest:1" ]]
}

@test "pkg_fhs_gen_manifest: generates tab-separated entries" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_manifest "/etc/myapp")
	# Second line should contain a tab between link path and target
	local entry
	entry=$(echo "$output" | sed -n '2p')
	local tab_count
	tab_count=$(printf '%s' "$entry" | tr -cd '\t' | wc -c)
	[[ "$tab_count" -eq 1 ]]
}

@test "pkg_fhs_gen_manifest: paths include legacy_root prefix" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	local output
	output=$(pkg_fhs_gen_manifest "/etc/myapp")
	[[ "$output" == *"/etc/myapp/files/myapp"* ]]
}

@test "pkg_fhs_gen_manifest: handles multiple entries" {
	pkg_fhs_register "files/myapp" "/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/internals/lib.sh" "/usr/lib/myapp/lib.sh" "640" "lib"
	pkg_fhs_register "files/conf/app.conf" "/etc/myapp/app.conf" "640" "conf"
	local output
	output=$(pkg_fhs_gen_manifest "/opt/myapp")
	# Header + 3 entries = 4 lines
	local line_count
	line_count=$(echo "$output" | wc -l)
	[[ "$line_count" -eq 4 ]]
}

@test "pkg_fhs_gen_manifest: warns on empty registry" {
	run pkg_fhs_gen_manifest "/etc/myapp"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"no files registered"* ]]
}

@test "pkg_fhs_gen_manifest: fails with empty legacy_root" {
	run pkg_fhs_gen_manifest ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_gen_manifest: entries match symlink_farm mapping" {
	pkg_fhs_register "files/myapp" "${MOCK_FHS}/usr/sbin/myapp" "750" "bin"
	pkg_fhs_register "files/internals/lib.sh" "${MOCK_FHS}/usr/lib/myapp/lib.sh" "640" "lib"
	pkg_fhs_install "$MOCK_SRC"
	pkg_fhs_symlink_farm "$MOCK_LEGACY"

	local manifest
	manifest=$(pkg_fhs_gen_manifest "$MOCK_LEGACY")

	# For each manifest entry (skip header), verify the symlink_farm created
	# the same mapping
	while IFS=$'\t' read -r link_path target; do
		[[ -L "$link_path" ]]
		local actual_target
		actual_target=$(readlink "$link_path")
		[[ "$actual_target" = "$target" ]]
	done < <(echo "$manifest" | tail -n +2)
}

@test "pkg_fhs_gen_manifest: empty registry produces no output" {
	local output
	output=$(pkg_fhs_gen_manifest "/etc/myapp" 2>/dev/null)  # suppress warning
	# With empty registry, no entries are produced — only the warning on stderr.
	# stdout should be empty since the function returns early before the header.
	# Actually per spec: warns and returns 0 — matching symlink_farm which
	# also returns 0 with warning. The function returns before writing header.
	[[ -z "$output" ]]
}

# ── pkg_fhs_verify_farm ───────────────────────────────────────

@test "pkg_fhs_verify_farm: returns 0 for intact symlinks" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Create target files
	echo "lib content" > "${target_dir}/lib.sh"
	echo "app content" > "${target_dir}/myapp"

	# Create correct symlinks
	mkdir -p "${farm_dir}/internals"
	ln -s "${target_dir}/lib.sh" "${farm_dir}/internals/lib.sh"
	ln -s "${target_dir}/myapp" "${farm_dir}/myapp"

	# Write manifest
	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"
	printf '%s\t%s\n' "${farm_dir}/myapp" "${target_dir}/myapp" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: returns 0 when manifest absent" {
	run pkg_fhs_verify_farm "/nonexistent/path/.symlink-manifest"
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "pkg_fhs_verify_farm: repairs broken symlink and warns" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Create target
	echo "lib content" > "${target_dir}/lib.sh"

	# Create a dangling symlink (points to nonexistent path)
	mkdir -p "${farm_dir}/internals"
	ln -s "${farm_dir}/gone/lib.sh" "${farm_dir}/internals/lib.sh"

	# Write manifest — the correct target is in target_dir
	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"repaired symlink"* ]]
	# Verify the symlink now points to the correct target
	local actual
	actual=$(readlink "${farm_dir}/internals/lib.sh")
	[[ "$actual" = "${target_dir}/lib.sh" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: repairs wrong-target symlink" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Create correct target and wrong target
	echo "correct" > "${target_dir}/lib.sh"
	echo "wrong" > "${target_dir}/wrong.sh"

	# Symlink points to wrong file
	mkdir -p "${farm_dir}/internals"
	ln -s "${target_dir}/wrong.sh" "${farm_dir}/internals/lib.sh"

	# Manifest says it should point to lib.sh
	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"wrong target"* ]]
	local actual
	actual=$(readlink "${farm_dir}/internals/lib.sh")
	[[ "$actual" = "${target_dir}/lib.sh" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: replaces regular file with symlink" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Create target
	echo "real content" > "${target_dir}/lib.sh"

	# Place a regular file where symlink should be (admin-copied scenario)
	mkdir -p "${farm_dir}/internals"
	echo "copied content" > "${farm_dir}/internals/lib.sh"

	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"replaced regular file with symlink"* ]]
	[[ -L "${farm_dir}/internals/lib.sh" ]]
	local actual
	actual=$(readlink "${farm_dir}/internals/lib.sh")
	[[ "$actual" = "${target_dir}/lib.sh" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: returns 1 when target missing" {
	local farm_dir
	farm_dir=$(mktemp -d)

	# No target files exist — create a dangling symlink
	mkdir -p "${farm_dir}/internals"
	ln -s "/nonexistent/target/lib.sh" "${farm_dir}/internals/lib.sh"

	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "/nonexistent/target/lib.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"symlink target missing"* ]]

	rm -rf "$farm_dir"
}

@test "pkg_fhs_verify_farm: repairs some, fails on missing targets" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Target exists for first entry, missing for second
	echo "lib content" > "${target_dir}/lib.sh"

	# First: dangling symlink with existing target (repairable)
	mkdir -p "${farm_dir}/internals"
	ln -s "/old/path/lib.sh" "${farm_dir}/internals/lib.sh"

	# Second: dangling symlink with missing target (not repairable)
	ln -s "/nonexistent/core.sh" "${farm_dir}/internals/core.sh"

	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/core.sh" "/nonexistent/target/core.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 1 ]]
	# First entry should be repaired
	[[ "$output" == *"repaired symlink"* ]]
	# Second entry has missing target
	[[ "$output" == *"symlink target missing"* ]]
	# First symlink was actually fixed
	local actual
	actual=$(readlink "${farm_dir}/internals/lib.sh")
	[[ "$actual" = "${target_dir}/lib.sh" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: skips comment and blank lines" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	echo "content" > "${target_dir}/lib.sh"
	mkdir -p "${farm_dir}/internals"
	ln -s "${target_dir}/lib.sh" "${farm_dir}/internals/lib.sh"

	# Manifest with comments and blank lines interspersed
	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '# This is a comment\n' >> "$manifest"
	printf '\n' >> "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"
	printf '\n' >> "$manifest"
	printf '# Another comment\n' >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: fails with empty manifest_path" {
	run pkg_fhs_verify_farm ""
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_fhs_verify_farm: repairs missing symlink (no entry at path)" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Create target
	echo "lib content" > "${target_dir}/lib.sh"

	# Do NOT create any symlink — the path simply does not exist
	mkdir -p "${farm_dir}/internals"

	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"repaired symlink"* ]]
	[[ -L "${farm_dir}/internals/lib.sh" ]]
	local actual
	actual=$(readlink "${farm_dir}/internals/lib.sh")
	[[ "$actual" = "${target_dir}/lib.sh" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: silent on all-valid farm" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	echo "content1" > "${target_dir}/a.sh"
	echo "content2" > "${target_dir}/b.sh"

	mkdir -p "${farm_dir}/internals"
	ln -s "${target_dir}/a.sh" "${farm_dir}/internals/a.sh"
	ln -s "${target_dir}/b.sh" "${farm_dir}/internals/b.sh"

	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/a.sh" "${target_dir}/a.sh" >> "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/b.sh" "${target_dir}/b.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]
	# No warnings or errors — completely silent
	[[ -z "$output" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: warns per repaired symlink" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	# Create 3 target files
	echo "content1" > "${target_dir}/a.sh"
	echo "content2" > "${target_dir}/b.sh"
	echo "content3" > "${target_dir}/c.sh"

	# Create parent dir but do NOT create any symlinks — all 3 are missing
	mkdir -p "${farm_dir}/internals"

	# Write manifest with 3 entries
	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/a.sh" "${target_dir}/a.sh" >> "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/b.sh" "${target_dir}/b.sh" >> "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/c.sh" "${target_dir}/c.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 0 ]]

	# Each missing symlink produces a separate "repaired" warning
	local repair_count
	repair_count=$(echo "$output" | grep -c "repaired")
	[[ "$repair_count" -eq 3 ]]

	# All 3 symlinks now exist and point to correct targets
	[[ -L "${farm_dir}/internals/a.sh" ]]
	[[ -L "${farm_dir}/internals/b.sh" ]]
	[[ -L "${farm_dir}/internals/c.sh" ]]

	rm -rf "$farm_dir" "$target_dir"
}

@test "pkg_fhs_verify_farm: errors on directory at link path" {
	local farm_dir
	farm_dir=$(mktemp -d)
	local target_dir
	target_dir=$(mktemp -d)

	echo "content" > "${target_dir}/lib.sh"

	# Place a directory where the symlink should be
	mkdir -p "${farm_dir}/internals/lib.sh"

	local manifest="${farm_dir}/.symlink-manifest"
	printf '# pkg_lib:symlink-manifest:1\n' > "$manifest"
	printf '%s\t%s\n' "${farm_dir}/internals/lib.sh" "${target_dir}/lib.sh" >> "$manifest"

	run pkg_fhs_verify_farm "$manifest"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"directory exists at symlink path"* ]]

	rm -rf "$farm_dir" "$target_dir"
}
