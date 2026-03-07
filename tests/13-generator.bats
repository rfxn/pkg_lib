#!/usr/bin/env bats
# 13-generator.bats — pkg_gen.sh generator tests

load helpers/pkg-common

setup() {
	pkg_common_setup
	# Path to the generator script
	GEN_SCRIPT="${PROJECT_ROOT}/pkg/pkg_gen.sh"
	# Path to the real templates
	TEMPLATES_DIR="${PROJECT_ROOT}/pkg/templates"
	# Output directory for this test
	GEN_OUTPUT="${TEST_TMPDIR}/gen-output"
	# Create a standard test manifest
	_create_test_manifest
}

teardown() {
	pkg_teardown
}

# Helper: create a complete test manifest with all required variables
_create_test_manifest() {
	MANIFEST_FILE="${TEST_TMPDIR}/pkg.manifest"
	cat > "$MANIFEST_FILE" <<'MANIFEST'
PKG_NAME="testpkg"
PKG_VERSION="2.0.1"
PKG_SUMMARY="Test Package for generator validation"
PKG_DESCRIPTION="A test package used to validate the pkg_gen.sh generator script"
PKG_LICENSE="GPLv2+"
PKG_URL="https://github.com/rfxn/testpkg"
PKG_MAINTAINER="R-fx Networks <proj@rfxn.com>"
PKG_INSTALL_PATH="/usr/local/testpkg"
PKG_BIN_NAME="testpkg"
PKG_BIN_LEGACY="/usr/local/sbin/testpkg"
PKG_SECTION="1"
PKG_COPYRIGHT_START="2002"
PKG_VERSION_CMD="echo 2.0.1"

PKG_HAS_SYSTEMD_SERVICE="1"
PKG_HAS_SYSV_INIT="1"
PKG_HAS_CRON_D="1"
PKG_HAS_LOGROTATE="1"
MANIFEST
}

# ── Basic invocation ──────────────────────────────────────────

@test "pkg_gen.sh: --version shows version" {
	run "$GEN_SCRIPT" --version
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"pkg_gen.sh"* ]]
	[[ "$output" == *"1.0.0"* ]]
}

@test "pkg_gen.sh: --help shows usage" {
	run "$GEN_SCRIPT" --help
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"Usage"* ]]
	[[ "$output" == *"--manifest"* ]]
	[[ "$output" == *"--templates"* ]]
	[[ "$output" == *"--output"* ]]
}

@test "pkg_gen.sh: fails without required arguments" {
	run "$GEN_SCRIPT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_gen.sh: fails with missing manifest file" {
	run "$GEN_SCRIPT" --manifest /nonexistent --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_gen.sh: fails with missing templates directory" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates /nonexistent --output "$GEN_OUTPUT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *"not found"* ]]
}

# ── Output structure ──────────────────────────────────────────

@test "pkg_gen.sh: generates all expected output files" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	# RPM
	[[ -f "$GEN_OUTPUT/rpm/testpkg.spec" ]]

	# DEB
	[[ -f "$GEN_OUTPUT/deb/debian/control" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/rules" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/conffiles" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/dirs" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/links" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/preinst" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/postinst" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/postrm" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/changelog" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/copyright" ]]
	[[ -f "$GEN_OUTPUT/deb/debian/source/format" ]]

	# Docker
	[[ -f "$GEN_OUTPUT/docker/Dockerfile.rpm-el7" ]]
	[[ -f "$GEN_OUTPUT/docker/Dockerfile.rpm-el9" ]]
	[[ -f "$GEN_OUTPUT/docker/Dockerfile.deb" ]]
	[[ -f "$GEN_OUTPUT/docker/Dockerfile.test-rpm" ]]
	[[ -f "$GEN_OUTPUT/docker/Dockerfile.test-deb" ]]

	# GHA
	[[ -f "$GEN_OUTPUT/.github/workflows/release.yml" ]]

	# Makefile + test
	[[ -f "$GEN_OUTPUT/Makefile" ]]
	[[ -f "$GEN_OUTPUT/test/test-pkg-install.sh" ]]
}

@test "pkg_gen.sh: RPM spec renamed from project.spec.in to PKG_NAME.spec" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]
	[[ -f "$GEN_OUTPUT/rpm/testpkg.spec" ]]
	# project.spec should NOT exist
	[[ ! -f "$GEN_OUTPUT/rpm/project.spec" ]]
	[[ ! -f "$GEN_OUTPUT/rpm/project.spec.in" ]]
}

@test "pkg_gen.sh: github/ maps to .github/workflows/" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]
	[[ -f "$GEN_OUTPUT/.github/workflows/release.yml" ]]
	# github/ dir should NOT exist in output
	[[ ! -d "$GEN_OUTPUT/github" ]]
}

# ── Placeholder substitution ─────────────────────────────────

@test "pkg_gen.sh: RPM spec contains correct Name and Version" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	local spec="$GEN_OUTPUT/rpm/testpkg.spec"
	grep -q '^%define name.*testpkg' "$spec"
	grep -q '^%define version.*2.0.1' "$spec"
	grep -q '^Summary:.*Test Package for generator validation' "$spec"
	grep -q '^License:.*GPLv2+' "$spec"
	grep -q '^URL:.*https://github.com/rfxn/testpkg' "$spec"
}

@test "pkg_gen.sh: DEB control contains correct Package and Maintainer" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	local control="$GEN_OUTPUT/deb/debian/control"
	grep -q '^Source: testpkg' "$control"
	grep -q '^Package: testpkg' "$control"
	grep -q '^Maintainer: R-fx Networks' "$control"
	grep -q '^Homepage: https://github.com/rfxn/testpkg' "$control"
	grep -q '^Description: Test Package for generator validation' "$control"
}

@test "pkg_gen.sh: DEB copyright contains correct copyright range" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	local copyright="$GEN_OUTPUT/deb/debian/copyright"
	grep -q 'Upstream-Name: testpkg' "$copyright"
	# Copyright line should have start year and current year
	grep -q 'Copyright: 2002-' "$copyright"
	grep -q 'R-fx Networks' "$copyright"
}

@test "pkg_gen.sh: Docker templates contain correct package name" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	grep -q 'COPY.*testpkg' "$GEN_OUTPUT/docker/Dockerfile.rpm-el7"
	grep -q '/src/testpkg' "$GEN_OUTPUT/docker/Dockerfile.rpm-el9"
	grep -q '/src/testpkg' "$GEN_OUTPUT/docker/Dockerfile.deb"
}

@test "pkg_gen.sh: Makefile contains correct NAME and VERSION_CMD" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	grep -q 'NAME.*:=.*testpkg' "$GEN_OUTPUT/Makefile"
	grep -q 'echo 2.0.1' "$GEN_OUTPUT/Makefile"
}

@test "pkg_gen.sh: preinst has correct LEGACY_PATH" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	grep -q 'LEGACY_PATH="/usr/local/testpkg"' "$GEN_OUTPUT/deb/debian/preinst"
}

@test "pkg_gen.sh: release.yml contains correct package name in docker commands" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	grep -q 'testpkg-rpm-el7' "$GEN_OUTPUT/.github/workflows/release.yml"
	grep -q 'testpkg-rpm-el9' "$GEN_OUTPUT/.github/workflows/release.yml"
	grep -q 'testpkg-deb' "$GEN_OUTPUT/.github/workflows/release.yml"
}

# ── Two-level substitution ────────────────────────────────────

@test "pkg_gen.sh: two-level tokens preserved for project-specific post-processing" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	# These tokens are intentionally NOT in the manifest — they are level-2
	# tokens that projects fill in via post-processing or manual edit
	local spec="$GEN_OUTPUT/rpm/testpkg.spec"
	grep -q '@@PKG_RPM_FILES_SECTION@@' "$spec"
	grep -q '@@PKG_RPM_INSTALL_SECTION@@' "$spec"

	local control="$GEN_OUTPUT/deb/debian/control"
	grep -q '@@PKG_DEB_DEPENDS@@' "$control"
}

# ── Manifest variable handling ────────────────────────────────

@test "pkg_gen.sh: manifest with missing required variable fails" {
	# Create a manifest missing PKG_NAME
	local bad_manifest="${TEST_TMPDIR}/bad.manifest"
	cat > "$bad_manifest" <<'MANIFEST'
PKG_VERSION="1.0.0"
PKG_SUMMARY="Test"
PKG_INSTALL_PATH="/opt/test"
MANIFEST

	run "$GEN_SCRIPT" --manifest "$bad_manifest" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -ne 0 ]]
	[[ "$output" == *"PKG_NAME"* ]]
}

# ── Sed escape edge cases ─────────────────────────────────────

@test "pkg_gen.sh: manifest value containing pipe char substituted correctly" {
	# QA-004: pipe char | is the sed delimiter — must be escaped in values
	local pipe_manifest="${TEST_TMPDIR}/pipe.manifest"
	cat > "$pipe_manifest" <<'MANIFEST'
PKG_NAME="pipepkg"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Summary with | pipe char"
PKG_INSTALL_PATH="/opt/pipepkg"
MANIFEST

	local tpl_dir="${TEST_TMPDIR}/templates"
	mkdir -p "$tpl_dir"
	cat > "$tpl_dir/test.conf.in" <<'TEMPLATE'
name=@@PKG_NAME@@
summary=@@PKG_SUMMARY@@
TEMPLATE

	local out_dir="${TEST_TMPDIR}/pipe-output"
	run "$GEN_SCRIPT" --manifest "$pipe_manifest" --templates "$tpl_dir" --output "$out_dir"
	[[ "$status" -eq 0 ]]

	local outfile="$out_dir/test.conf"
	[[ -f "$outfile" ]]
	grep -q 'name=pipepkg' "$outfile"
	grep -q 'Summary with | pipe char' "$outfile"
}

# ── Conditional blocks ────────────────────────────────────────

@test "pkg_gen.sh: conditional blocks removed when feature flag is 0" {
	# Create template with conditional
	local tpl_dir="${TEST_TMPDIR}/templates"
	mkdir -p "$tpl_dir"
	cat > "$tpl_dir/test.conf.in" <<'TEMPLATE'
# Config file
option_a=1
@@IF_CRON_D@@
cron_schedule="* * * * *"
@@ENDIF_CRON_D@@
option_b=2
TEMPLATE

	# Manifest with PKG_HAS_CRON_D=0
	local manifest="${TEST_TMPDIR}/cond.manifest"
	cat > "$manifest" <<'MANIFEST'
PKG_NAME="condtest"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Conditional test"
PKG_INSTALL_PATH="/opt/condtest"
PKG_HAS_CRON_D="0"
MANIFEST

	local out_dir="${TEST_TMPDIR}/cond-output"
	run "$GEN_SCRIPT" --manifest "$manifest" --templates "$tpl_dir" --output "$out_dir"
	[[ "$status" -eq 0 ]]

	local outfile="$out_dir/test.conf"
	[[ -f "$outfile" ]]
	# The conditional block should be removed
	run grep -q 'cron_schedule' "$outfile"
	[[ "$status" -ne 0 ]]
	run grep -q '@@IF_CRON_D@@' "$outfile"
	[[ "$status" -ne 0 ]]
	run grep -q '@@ENDIF_CRON_D@@' "$outfile"
	[[ "$status" -ne 0 ]]
	# Non-conditional content should remain
	grep -q 'option_a=1' "$outfile"
	grep -q 'option_b=2' "$outfile"
}

@test "pkg_gen.sh: conditional blocks kept when feature flag is 1" {
	# Create template with conditional
	local tpl_dir="${TEST_TMPDIR}/templates"
	mkdir -p "$tpl_dir"
	cat > "$tpl_dir/test.conf.in" <<'TEMPLATE'
# Config file
option_a=1
@@IF_LOGROTATE@@
logrotate_enabled=true
@@ENDIF_LOGROTATE@@
option_b=2
TEMPLATE

	# Manifest with PKG_HAS_LOGROTATE=1
	local manifest="${TEST_TMPDIR}/cond.manifest"
	cat > "$manifest" <<'MANIFEST'
PKG_NAME="condtest"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Conditional test"
PKG_INSTALL_PATH="/opt/condtest"
PKG_HAS_LOGROTATE="1"
MANIFEST

	local out_dir="${TEST_TMPDIR}/cond-output"
	run "$GEN_SCRIPT" --manifest "$manifest" --templates "$tpl_dir" --output "$out_dir"
	[[ "$status" -eq 0 ]]

	local outfile="$out_dir/test.conf"
	[[ -f "$outfile" ]]
	# The content should be kept, markers removed
	grep -q 'logrotate_enabled=true' "$outfile"
	run grep -q '@@IF_LOGROTATE@@' "$outfile"
	[[ "$status" -ne 0 ]]
	run grep -q '@@ENDIF_LOGROTATE@@' "$outfile"
	[[ "$status" -ne 0 ]]
	grep -q 'option_a=1' "$outfile"
	grep -q 'option_b=2' "$outfile"
}

@test "pkg_gen.sh: multiple conditional blocks handled independently" {
	local tpl_dir="${TEST_TMPDIR}/templates"
	mkdir -p "$tpl_dir"
	cat > "$tpl_dir/multi.conf.in" <<'TEMPLATE'
# Config
base=true
@@IF_SYSTEMD@@
systemd_enabled=true
@@ENDIF_SYSTEMD@@
middle=true
@@IF_CRON_D@@
cron_enabled=true
@@ENDIF_CRON_D@@
end=true
TEMPLATE

	local manifest="${TEST_TMPDIR}/multi.manifest"
	cat > "$manifest" <<'MANIFEST'
PKG_NAME="multitest"
PKG_VERSION="1.0.0"
PKG_SUMMARY="Multi-conditional test"
PKG_INSTALL_PATH="/opt/multitest"
PKG_HAS_SYSTEMD="1"
PKG_HAS_CRON_D="0"
MANIFEST

	local out_dir="${TEST_TMPDIR}/multi-output"
	run "$GEN_SCRIPT" --manifest "$manifest" --templates "$tpl_dir" --output "$out_dir"
	[[ "$status" -eq 0 ]]

	local outfile="$out_dir/multi.conf"
	# Systemd block kept (flag=1)
	grep -q 'systemd_enabled=true' "$outfile"
	# Cron block removed (flag=0)
	run grep -q 'cron_enabled=true' "$outfile"
	[[ "$status" -ne 0 ]]
	# Surrounding content intact
	grep -q 'base=true' "$outfile"
	grep -q 'middle=true' "$outfile"
	grep -q 'end=true' "$outfile"
}

# ── Dry-run mode ──────────────────────────────────────────────

@test "pkg_gen.sh: --dry-run does not write files" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" \
		--output "$GEN_OUTPUT" --dry-run
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"would generate"* ]]
	# Output directory should not have the expected files
	[[ ! -f "$GEN_OUTPUT/rpm/testpkg.spec" ]]
}

# ── Environment variable mode ────────────────────────────────

@test "pkg_gen.sh: accepts config via environment variables" {
	PKG_MANIFEST="$MANIFEST_FILE" PKG_TEMPLATES="$TEMPLATES_DIR" PKG_OUTPUT="$GEN_OUTPUT" \
		run "$GEN_SCRIPT"
	[[ "$status" -eq 0 ]]
	[[ -f "$GEN_OUTPUT/rpm/testpkg.spec" ]]
}

# ── Shell script executability ────────────────────────────────

@test "pkg_gen.sh: generated shell scripts are executable" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]

	[[ -x "$GEN_OUTPUT/test/test-pkg-install.sh" ]]
}

# ── Completion report ─────────────────────────────────────────

@test "pkg_gen.sh: prints completion report with file count" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"total:"* ]]
	[[ "$output" == *"files processed"* ]]
	[[ "$output" == *"pkg_gen.sh complete"* ]]
	[[ "$output" == *"project:    testpkg"* ]]
}

@test "pkg_gen.sh: report notes remaining two-level tokens" {
	run "$GEN_SCRIPT" --manifest "$MANIFEST_FILE" --templates "$TEMPLATES_DIR" --output "$GEN_OUTPUT"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"unsubstituted"* ]]
	[[ "$output" == *"two-level"* ]]
}
