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
