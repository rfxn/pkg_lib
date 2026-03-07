#!/bin/bash
#
# pkg_gen.sh — Manifest-driven packaging artifact generator 1.0.0
###
# Copyright (C) 2002-2026 R-fx Networks <proj@rfxn.com>
#                         Ryan MacDonald <ryan@rfxn.com>
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
###
#
# Standalone build-time script (NOT sourced by pkg_lib.sh). Reads a project's
# pkg.manifest file and templates from pkg/templates/ to produce project-specific
# packaging artifacts in the project's pkg/ directory.
#
# Two-level substitution model:
#   Level 1 (this script): @@PKG_NAME@@, @@PKG_VERSION@@, and other manifest
#   variables are substituted from the sourced manifest into template output.
#   Level 2 (project-specific): Tokens like @@PKG_RPM_FILES_SECTION@@ and
#   @@PKG_POSTINST_EXTRA@@ are intentionally left as-is (or replaced with
#   empty defaults) for projects to fill in via post-processing or manual edit.
#   This allows the generator to produce a functional scaffold while leaving
#   project-specific content for the consumer to customize.
#
# Usage:
#   ./pkg_gen.sh --manifest ./pkg.manifest --templates /path/to/templates --output ./pkg
#   PKG_MANIFEST=./pkg.manifest PKG_TEMPLATES=./templates PKG_OUTPUT=./pkg ./pkg_gen.sh
#
set -euo pipefail

PKG_GEN_VERSION="1.0.0"

# ══════════════════════════════════════════════════════════════════
# Section: Output helpers
# ══════════════════════════════════════════════════════════════════

_gen_info() {
	echo "  [info] $1"
}

_gen_warn() {
	echo "  [warn] $1" >&2
}

_gen_error() {
	echo "  [error] $1" >&2
}

# ══════════════════════════════════════════════════════════════════
# Section: Argument parsing
# ══════════════════════════════════════════════════════════════════

_gen_usage() {
	cat <<'USAGE'
Usage: pkg_gen.sh [OPTIONS]

Generate project-specific packaging artifacts from templates and manifest.

Options:
  --manifest FILE     Path to pkg.manifest file (or set PKG_MANIFEST)
  --templates DIR     Path to templates directory (or set PKG_TEMPLATES)
  --output DIR        Output directory for generated files (or set PKG_OUTPUT)
  --dry-run           Show what would be generated without writing files
  --version           Show version and exit
  --help              Show this help and exit

Environment variables:
  PKG_MANIFEST        Manifest file path (overridden by --manifest)
  PKG_TEMPLATES       Templates directory (overridden by --templates)
  PKG_OUTPUT          Output directory (overridden by --output)
USAGE
}

_gen_parse_args() {
	local opt_manifest="${PKG_MANIFEST:-}"
	local opt_templates="${PKG_TEMPLATES:-}"
	local opt_output="${PKG_OUTPUT:-}"
	_GEN_DRY_RUN=0

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--manifest)
				[[ $# -ge 2 ]] || { _gen_error "--manifest requires a value"; return 1; }
				opt_manifest="$2"
				shift 2
				;;
			--templates)
				[[ $# -ge 2 ]] || { _gen_error "--templates requires a value"; return 1; }
				opt_templates="$2"
				shift 2
				;;
			--output)
				[[ $# -ge 2 ]] || { _gen_error "--output requires a value"; return 1; }
				opt_output="$2"
				shift 2
				;;
			--dry-run)
				_GEN_DRY_RUN=1
				shift
				;;
			--version)
				echo "pkg_gen.sh ${PKG_GEN_VERSION}"
				exit 0
				;;
			--help|-h)
				_gen_usage
				exit 0
				;;
			*)
				_gen_error "unknown option: $1"
				_gen_usage
				return 1
				;;
		esac
	done

	# Validate required parameters
	if [[ -z "$opt_manifest" ]]; then
		_gen_error "manifest file required (--manifest or PKG_MANIFEST)"
		return 1
	fi
	if [[ -z "$opt_templates" ]]; then
		_gen_error "templates directory required (--templates or PKG_TEMPLATES)"
		return 1
	fi
	if [[ -z "$opt_output" ]]; then
		_gen_error "output directory required (--output or PKG_OUTPUT)"
		return 1
	fi

	# Validate paths exist
	if [[ ! -f "$opt_manifest" ]]; then
		_gen_error "manifest file not found: ${opt_manifest}"
		return 1
	fi
	if [[ ! -d "$opt_templates" ]]; then
		_gen_error "templates directory not found: ${opt_templates}"
		return 1
	fi

	_GEN_MANIFEST="$opt_manifest"
	_GEN_TEMPLATES="$opt_templates"
	_GEN_OUTPUT="$opt_output"
}

# ══════════════════════════════════════════════════════════════════
# Section: Manifest loading
# ══════════════════════════════════════════════════════════════════

_gen_load_manifest() {
	# Source the manifest to get all PKG_* variables
	# shellcheck disable=SC1090
	source "$_GEN_MANIFEST" || {
		_gen_error "failed to source manifest: ${_GEN_MANIFEST}"
		return 1
	}

	# Validate required variables
	local rc=0
	local required_vars="PKG_NAME PKG_VERSION PKG_SUMMARY PKG_INSTALL_PATH"
	local var
	for var in $required_vars; do
		eval "local val=\"\${${var}:-}\""
		if [[ -z "$val" ]]; then
			_gen_error "required manifest variable not set: ${var}"
			rc=1
		fi
	done

	return "$rc"
}

# ══════════════════════════════════════════════════════════════════
# Section: Placeholder substitution
# ══════════════════════════════════════════════════════════════════

# _gen_build_sed_script — build a sed script from manifest PKG_* variables
# Collects all PKG_* scalar variables from the manifest and builds sed
# substitution commands for @@PKG_*@@ placeholders.
_gen_build_sed_script() {
	local sed_script=""
	local var val

	# Core manifest variables — always substituted
	# Using a fixed list ensures predictable ordering and avoids
	# compgen/declare -p which may not capture sourced variables in all bash versions
	local manifest_vars="
		PKG_NAME PKG_VERSION PKG_SUMMARY PKG_DESCRIPTION PKG_LICENSE
		PKG_URL PKG_MAINTAINER PKG_INSTALL_PATH PKG_BIN_NAME
		PKG_BIN_LEGACY PKG_SECTION PKG_COPYRIGHT_START PKG_VERSION_CMD
	"

	for var in $manifest_vars; do
		eval "val=\"\${${var}:-}\""
		if [[ -n "$val" ]]; then
			# Escape sed special characters in the value
			local escaped_val
			escaped_val=$(printf '%s' "$val" | sed -e 's/[&/\]/\\&/g')
			sed_script="${sed_script}s|@@${var}@@|${escaped_val}|g;"
		fi
	done

	# Add current year for copyright templates
	local current_year
	current_year=$(date +%Y)
	sed_script="${sed_script}s|@@PKG_COPYRIGHT_YEAR@@|${current_year}|g;"

	echo "$sed_script"
}

# _gen_process_conditionals — handle @@IF_*@@/@@ENDIF_*@@ conditional blocks
# Arguments:
#   $1 — input file path
#   $2 — output file path
# Reads the input file and processes conditional blocks based on PKG_HAS_* flags.
# If the flag is "1", the markers are removed but content is kept.
# If the flag is "0" or empty, the entire block (including markers) is removed.
_gen_process_conditionals() {
	local input_file="$1"
	local output_file="$2"

	# Find all @@IF_*@@ markers in the file
	local markers
	markers=$(grep -oE '@@IF_[A-Z_]+@@' "$input_file" 2>/dev/null | sort -u) || true

	if [[ -z "$markers" ]]; then
		# No conditionals — just copy
		cp "$input_file" "$output_file"
		return 0
	fi

	# Process each conditional marker
	cp "$input_file" "$output_file"

	local marker feature_name flag_var flag_val
	for marker in $markers; do
		# Extract feature name: @@IF_SYSTEMD@@ → SYSTEMD
		feature_name="${marker#@@IF_}"
		feature_name="${feature_name%@@}"

		# Map to PKG_HAS_* variable
		flag_var="PKG_HAS_${feature_name}"
		eval "flag_val=\"\${${flag_var}:-0}\""

		local end_marker="@@ENDIF_${feature_name}@@"

		if [[ "$flag_val" = "1" ]]; then
			# Feature enabled — remove markers but keep content
			sed -i "s|^${marker}$||; s|^${end_marker}$||" "$output_file"
			# Remove any blank lines left by marker removal (only if line is entirely empty)
			# Use a temporary approach: mark and delete consecutive empty lines at marker sites
		else
			# Feature disabled — remove the entire block including markers
			# Use sed range delete: /start_marker/,/end_marker/d
			sed -i "/^${marker}$/,/^${end_marker}$/d" "$output_file"
		fi
	done

	# Clean up empty lines left by marker removal (collapse triple+ blank lines to double)
	local tmpclean
	tmpclean=$(mktemp -t pkg_gen_clean.XXXXXX)
	awk 'NR==1{print; next} /^$/{empty++; next} {while(empty>0){print ""; empty--}; print}' \
		"$output_file" > "$tmpclean"
	mv "$tmpclean" "$output_file"

	return 0
}

# _gen_substitute_file — perform full substitution pipeline on a template file
# Arguments:
#   $1 — template source file
#   $2 — output destination file
#   $3 — sed substitution script (from _gen_build_sed_script)
_gen_substitute_file() {
	local src="$1"
	local dest="$2"
	local sed_script="$3"

	# Ensure output directory exists
	local dest_dir
	dest_dir=$(dirname "$dest")
	mkdir -p "$dest_dir"

	# Step 1: Apply placeholder substitution
	sed "$sed_script" "$src" > "$dest"

	# Step 2: Process conditional blocks
	local tmp_cond
	tmp_cond=$(mktemp -t pkg_gen_cond.XXXXXX)
	_gen_process_conditionals "$dest" "$tmp_cond"
	mv "$tmp_cond" "$dest"

	return 0
}

# ══════════════════════════════════════════════════════════════════
# Section: Output structure generation
# ══════════════════════════════════════════════════════════════════

# _gen_output_path — compute output path from template path
# Transforms template-relative path to output path:
#   - Strips .in suffix
#   - Renames project.spec.in → $PKG_NAME.spec
#   - github/ → .github/workflows/
# Arguments:
#   $1 — template file path relative to templates directory
_gen_output_path() {
	local rel_path="$1"

	# Strip .in suffix (except for static files like source/format)
	case "$rel_path" in
		*.in) rel_path="${rel_path%.in}" ;;
	esac

	# Rename project.spec → $PKG_NAME.spec
	rel_path="${rel_path//project.spec/${PKG_NAME}.spec}"

	# Map github/ → .github/workflows/
	case "$rel_path" in
		github/*)
			rel_path=".github/workflows/${rel_path#github/}"
			;;
	esac

	# Map top-level test template into test/ subdirectory
	case "$rel_path" in
		test-pkg-install.sh)
			rel_path="test/test-pkg-install.sh"
			;;
	esac

	echo "${_GEN_OUTPUT}/${rel_path}"
}

# _gen_process_templates — walk template directory and process all files
_gen_process_templates() {
	local sed_script
	sed_script=$(_gen_build_sed_script)

	local template_count=0
	local template_file rel_path output_path

	# Walk the templates directory
	while IFS= read -r template_file; do
		# Compute relative path from templates root
		rel_path="${template_file#"${_GEN_TEMPLATES}"/}"

		# Skip hidden files and directories
		case "$rel_path" in
			.*) continue ;;
		esac

		# Compute output path
		output_path=$(_gen_output_path "$rel_path")

		if [[ "$_GEN_DRY_RUN" = "1" ]]; then
			_gen_info "would generate: ${output_path}"
		else
			_gen_substitute_file "$template_file" "$output_path" "$sed_script"

			# Make shell scripts executable
			case "$output_path" in
				*.sh)
					chmod 755 "$output_path"
					;;
			esac

			_gen_info "generated: ${output_path}"
		fi

		template_count=$((template_count + 1))
	done < <(find "$_GEN_TEMPLATES" -type f | sort)

	# Copy static files that don't need substitution
	# source/format is already handled by the find loop since it has no .in suffix

	echo ""
	_gen_info "total: ${template_count} files processed"

	return 0
}

# ══════════════════════════════════════════════════════════════════
# Section: Summary report
# ══════════════════════════════════════════════════════════════════

_gen_report() {
	echo ""
	echo "=== pkg_gen.sh complete ==="
	# shellcheck disable=SC2154
	echo "  project:    ${PKG_NAME}"
	echo "  version:    ${PKG_VERSION}"
	echo "  manifest:   ${_GEN_MANIFEST}"
	echo "  templates:  ${_GEN_TEMPLATES}"
	echo "  output:     ${_GEN_OUTPUT}"

	# Check for remaining unsubstituted placeholders
	# grep returns 1 when no matches — safe to ignore in pipefail context
	local remaining_files=""
	remaining_files=$(grep -rlE '@@PKG_[A-Z_]+@@' "${_GEN_OUTPUT}/" 2>/dev/null) || true
	local remaining=0
	if [[ -n "$remaining_files" ]]; then
		remaining=$(echo "$remaining_files" | wc -l)
	fi
	if [[ "$remaining" -gt 0 ]]; then
		echo ""
		_gen_info "${remaining} file(s) contain unsubstituted @@PKG_*@@ tokens"
		_gen_info "These are two-level tokens for project-specific post-processing"
	fi
}

# ══════════════════════════════════════════════════════════════════
# Section: Main
# ══════════════════════════════════════════════════════════════════

main() {
	echo "=== pkg_gen.sh ${PKG_GEN_VERSION} — manifest-driven packaging generator ==="
	echo ""

	# Parse arguments
	_gen_parse_args "$@"

	# Load and validate manifest
	_gen_info "loading manifest: ${_GEN_MANIFEST}"
	_gen_load_manifest

	# Create output directory if not dry-run
	if [[ "$_GEN_DRY_RUN" != "1" ]]; then
		mkdir -p "$_GEN_OUTPUT"
	fi

	# Process templates
	echo ""
	_gen_info "processing templates from: ${_GEN_TEMPLATES}"
	echo ""
	_gen_process_templates

	# Report
	if [[ "$_GEN_DRY_RUN" != "1" ]]; then
		_gen_report
	fi

	return 0
}

main "$@"
