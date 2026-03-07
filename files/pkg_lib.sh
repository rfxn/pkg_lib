#!/bin/bash
#
# pkg_lib.sh — Shared Packaging & Installer Library 1.0.0
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
# Shared packaging, install, and uninstall library for rfxn projects.
# Source this file after setting PKG_* configuration variables.
# No project-specific code — all behavior controlled via variables and arguments.

# Source guard — safe for repeated sourcing
# shellcheck disable=SC2154
[[ -n "${_PKG_LIB_LOADED:-}" ]] && return 0 2>/dev/null
_PKG_LIB_LOADED=1
# shellcheck disable=SC2034 # version checked by consumers
PKG_LIB_VERSION="1.0.0"

# Configurable defaults — consuming projects override via environment
PKG_NO_COLOR="${PKG_NO_COLOR:-0}"
PKG_QUIET="${PKG_QUIET:-0}"
PKG_TMPDIR="${PKG_TMPDIR:-${TMPDIR:-/tmp}}"

# Internal state — populated by detection functions, cached after first call
_PKG_C_RED=""
_PKG_C_GREEN=""
_PKG_C_YELLOW=""
_PKG_C_BOLD=""
_PKG_C_RESET=""
_PKG_COLOR_INIT_DONE=""

_PKG_OS_FAMILY=""
_PKG_OS_ID=""
_PKG_OS_VERSION=""
_PKG_OS_NAME=""
_PKG_OS_DETECT_DONE=""

_PKG_INIT_SYSTEM=""
_PKG_INIT_DETECT_DONE=""

_PKG_PKGMGR=""
_PKG_PKGMGR_DETECT_DONE=""

_PKG_DEPS_MISSING=0

# ══════════════════════════════════════════════════════════════════
# Section: Output & Messaging
# ══════════════════════════════════════════════════════════════════

# _pkg_color_init — detect terminal color support and set color variables
# Sets _PKG_C_RED, _PKG_C_GREEN, _PKG_C_YELLOW, _PKG_C_BOLD, _PKG_C_RESET.
# Non-terminal or PKG_NO_COLOR=1 → all empty strings.
# Cached: only runs once (idempotent on repeated calls).
_pkg_color_init() {
	# Already initialized — skip
	[[ -n "$_PKG_COLOR_INIT_DONE" ]] && return 0

	_PKG_COLOR_INIT_DONE=1
	_PKG_C_RED=""
	_PKG_C_GREEN=""
	_PKG_C_YELLOW=""
	_PKG_C_BOLD=""
	_PKG_C_RESET=""

	# Respect PKG_NO_COLOR override
	if [[ "${PKG_NO_COLOR:-0}" = "1" ]]; then
		return 0
	fi

	# Check if stdout is a terminal
	if [[ ! -t 1 ]]; then
		return 0
	fi

	# Check tput color support — graceful fallback if tput unavailable
	local colors
	colors=$(tput colors 2>/dev/null) || return 0
	if [[ "$colors" -ge 8 ]] 2>/dev/null; then
		_PKG_C_RED=$(tput setaf 1 2>/dev/null) || _PKG_C_RED=""
		_PKG_C_GREEN=$(tput setaf 2 2>/dev/null) || _PKG_C_GREEN=""
		_PKG_C_YELLOW=$(tput setaf 3 2>/dev/null) || _PKG_C_YELLOW=""
		_PKG_C_BOLD=$(tput bold 2>/dev/null) || _PKG_C_BOLD=""
		_PKG_C_RESET=$(tput sgr0 2>/dev/null) || _PKG_C_RESET=""
	fi

	return 0
}

# pkg_header project_name version action — print styled install/uninstall header
# Arguments:
#   $1 — project name (e.g., "BFD", "APF")
#   $2 — version string (e.g., "2.0.1")
#   $3 — action (e.g., "install", "uninstall", "upgrade")
pkg_header() {
	local project="$1" version="$2" action="$3"
	if [[ -z "$project" ]] || [[ -z "$version" ]]; then
		echo "pkg_lib: pkg_header requires project_name and version" >&2
		return 1
	fi
	local header_text="${project} ${version}"
	if [[ -n "$action" ]]; then
		header_text="${header_text} — ${action}"
	fi
	_pkg_color_init
	echo ""
	echo "${_PKG_C_BOLD}:: ${header_text}${_PKG_C_RESET}"
	echo "---------------------------------------------------------------"
	return 0
}

# pkg_info message — print info message with consistent prefix
# Suppressed when PKG_QUIET=1.
pkg_info() {
	local msg="$1"
	if [[ "${PKG_QUIET:-0}" = "1" ]]; then
		return 0
	fi
	_pkg_color_init
	echo "  ${msg}"
	return 0
}

# pkg_warn message — print warning to stderr (yellow if terminal)
pkg_warn() {
	local msg="$1"
	_pkg_color_init
	echo "${_PKG_C_YELLOW}  warning: ${msg}${_PKG_C_RESET}" >&2
	return 0
}

# pkg_error message — print error to stderr (red if terminal)
pkg_error() {
	local msg="$1"
	_pkg_color_init
	echo "${_PKG_C_RED}  error: ${msg}${_PKG_C_RESET}" >&2
	return 0
}

# pkg_success message — print success message (green if terminal)
pkg_success() {
	local msg="$1"
	_pkg_color_init
	echo "${_PKG_C_GREEN}  ${msg}${_PKG_C_RESET}"
	return 0
}

# pkg_section title — print section separator with title
pkg_section() {
	local title="$1"
	if [[ -z "$title" ]]; then
		echo "pkg_lib: pkg_section requires a title" >&2
		return 1
	fi
	_pkg_color_init
	echo ""
	echo "${_PKG_C_BOLD}  [ ${title} ]${_PKG_C_RESET}"
	return 0
}

# pkg_item label value — print aligned key: value pair
# Arguments:
#   $1 — label (left side)
#   $2 — value (right side)
pkg_item() {
	local label="$1" value="$2"
	printf "  %-20s %s\n" "${label}:" "$value"
	return 0
}

# ══════════════════════════════════════════════════════════════════
# Section: OS & Platform Detection
# ══════════════════════════════════════════════════════════════════

# pkg_detect_os — detect operating system family, ID, version, and display name
# Sets: _PKG_OS_FAMILY, _PKG_OS_ID, _PKG_OS_VERSION, _PKG_OS_NAME
# Detection chain: /etc/os-release → /etc/redhat-release → /etc/debian_version →
#   /etc/gentoo-release → /etc/slackware-version → uname -s (FreeBSD)
# Cached: only runs once.
pkg_detect_os() {
	# Already detected — skip
	[[ -n "$_PKG_OS_DETECT_DONE" ]] && return 0
	_PKG_OS_DETECT_DONE=1

	_PKG_OS_FAMILY="unknown"
	_PKG_OS_ID="unknown"
	_PKG_OS_VERSION=""
	_PKG_OS_NAME="unknown"

	# Primary: /etc/os-release (modern distros)
	if [[ -f /etc/os-release ]]; then
		local line key val
		while IFS= read -r line; do
			# Skip comments and blank lines
			[[ "$line" =~ ^[[:space:]]*# ]] && continue
			[[ -z "$line" ]] && continue
			# Parse KEY=VALUE (strip quotes)
			key="${line%%=*}"
			val="${line#*=}"
			val="${val#\"}"
			val="${val%\"}"
			val="${val#\'}"
			val="${val%\'}"
			case "$key" in
				ID)         _PKG_OS_ID="$val" ;;
				VERSION_ID) _PKG_OS_VERSION="$val" ;;
				ID_LIKE)
					# Map ID_LIKE to family
					case "$val" in
						*rhel*|*centos*|*fedora*) _PKG_OS_FAMILY="rhel" ;;
						*debian*)                 _PKG_OS_FAMILY="debian" ;;
					esac
					;;
				PRETTY_NAME) _PKG_OS_NAME="$val" ;;
			esac
		done < /etc/os-release

		# Derive family from ID if ID_LIKE did not set it
		if [[ "$_PKG_OS_FAMILY" = "unknown" ]]; then
			case "$_PKG_OS_ID" in
				centos|rhel|rocky|alma|fedora|ol|amzn) _PKG_OS_FAMILY="rhel" ;;
				debian|ubuntu|linuxmint|raspbian)      _PKG_OS_FAMILY="debian" ;;
				gentoo)                                 _PKG_OS_FAMILY="gentoo" ;;
				slackware)                              _PKG_OS_FAMILY="slackware" ;;
			esac
		fi

		# Fallback name
		if [[ "$_PKG_OS_NAME" = "unknown" ]]; then
			_PKG_OS_NAME="${_PKG_OS_ID} ${_PKG_OS_VERSION}"
		fi
		return 0
	fi

	# Fallback: /etc/redhat-release
	if [[ -f /etc/redhat-release ]]; then
		_PKG_OS_FAMILY="rhel"
		_PKG_OS_NAME=$(cat /etc/redhat-release 2>/dev/null) || _PKG_OS_NAME="RHEL-family"
		# Extract version number (first numeric sequence with optional dots)
		local ver_pat='[0-9]+(\.[0-9]+)*'
		if [[ "$_PKG_OS_NAME" =~ $ver_pat ]]; then
			_PKG_OS_VERSION="${BASH_REMATCH[0]}"
		fi
		# Extract distro ID
		local id_lower
		id_lower=$(echo "$_PKG_OS_NAME" | tr '[:upper:]' '[:lower:]')
		case "$id_lower" in
			centos*)  _PKG_OS_ID="centos" ;;
			red*)     _PKG_OS_ID="rhel" ;;
			rocky*)   _PKG_OS_ID="rocky" ;;
			alma*)    _PKG_OS_ID="alma" ;;
			fedora*)  _PKG_OS_ID="fedora" ;;
			*)        _PKG_OS_ID="rhel" ;;
		esac
		return 0
	fi

	# Fallback: /etc/debian_version
	if [[ -f /etc/debian_version ]]; then
		_PKG_OS_FAMILY="debian"
		_PKG_OS_ID="debian"
		_PKG_OS_VERSION=$(cat /etc/debian_version 2>/dev/null) || _PKG_OS_VERSION=""
		_PKG_OS_NAME="Debian ${_PKG_OS_VERSION}"
		return 0
	fi

	# Fallback: /etc/gentoo-release
	if [[ -f /etc/gentoo-release ]]; then
		_PKG_OS_FAMILY="gentoo"
		_PKG_OS_ID="gentoo"
		_PKG_OS_NAME=$(cat /etc/gentoo-release 2>/dev/null) || _PKG_OS_NAME="Gentoo"
		return 0
	fi

	# Fallback: /etc/slackware-version
	if [[ -f /etc/slackware-version ]]; then
		_PKG_OS_FAMILY="slackware"
		_PKG_OS_ID="slackware"
		_PKG_OS_NAME=$(cat /etc/slackware-version 2>/dev/null) || _PKG_OS_NAME="Slackware"
		local ver_pat='[0-9]+(\.[0-9]+)*'
		if [[ "$_PKG_OS_NAME" =~ $ver_pat ]]; then
			_PKG_OS_VERSION="${BASH_REMATCH[0]}"
		fi
		return 0
	fi

	# Fallback: uname -s (FreeBSD)
	local uname_s
	uname_s=$(uname -s 2>/dev/null) || uname_s=""
	case "$uname_s" in
		FreeBSD)
			_PKG_OS_FAMILY="freebsd"
			_PKG_OS_ID="freebsd"
			_PKG_OS_VERSION=$(uname -r 2>/dev/null) || _PKG_OS_VERSION=""
			_PKG_OS_NAME="FreeBSD ${_PKG_OS_VERSION}"
			;;
	esac

	return 0
}

# pkg_detect_init — detect init system
# Sets: _PKG_INIT_SYSTEM (systemd|sysv|upstart|rc.local|unknown)
# Detection chain: /run/systemd/system dir → /proc/1/comm → rc.local
# Cached: only runs once.
pkg_detect_init() {
	# Already detected — skip
	[[ -n "$_PKG_INIT_DETECT_DONE" ]] && return 0
	_PKG_INIT_DETECT_DONE=1

	_PKG_INIT_SYSTEM="unknown"

	# systemd: check for /run/systemd/system directory
	if [[ -d /run/systemd/system ]]; then
		_PKG_INIT_SYSTEM="systemd"
		return 0
	fi

	# Check /proc/1/comm if it exists (may not on CentOS 6)
	if [[ -f /proc/1/comm ]]; then
		local pid1_comm
		pid1_comm=$(cat /proc/1/comm 2>/dev/null) || pid1_comm=""
		case "$pid1_comm" in
			systemd)  _PKG_INIT_SYSTEM="systemd" ;;
			init)     _PKG_INIT_SYSTEM="sysv" ;;
			upstart)  _PKG_INIT_SYSTEM="upstart" ;;
		esac
		if [[ "$_PKG_INIT_SYSTEM" != "unknown" ]]; then
			return 0
		fi
	fi

	# Fallback: if /etc/init.d exists, likely SysV
	if [[ -d /etc/init.d ]] || [[ -d /etc/rc.d/init.d ]]; then
		_PKG_INIT_SYSTEM="sysv"
		return 0
	fi

	# Last resort: rc.local
	if [[ -f /etc/rc.local ]] || [[ -f /etc/rc.d/rc.local ]]; then
		_PKG_INIT_SYSTEM="rc.local"
		return 0
	fi

	return 0
}

# pkg_detect_pkgmgr — detect package manager
# Sets: _PKG_PKGMGR (dnf|yum|apt|emerge|pkg|slackpkg|unknown)
# Uses command -v cascade. Cached: only runs once.
pkg_detect_pkgmgr() {
	# Already detected — skip
	[[ -n "$_PKG_PKGMGR_DETECT_DONE" ]] && return 0
	_PKG_PKGMGR_DETECT_DONE=1

	_PKG_PKGMGR="unknown"

	if command -v dnf >/dev/null 2>&1; then
		_PKG_PKGMGR="dnf"
	elif command -v yum >/dev/null 2>&1; then
		_PKG_PKGMGR="yum"
	elif command -v apt-get >/dev/null 2>&1; then
		_PKG_PKGMGR="apt"
	elif command -v emerge >/dev/null 2>&1; then
		_PKG_PKGMGR="emerge"
	elif command -v pkg >/dev/null 2>&1; then
		_PKG_PKGMGR="pkg"
	elif command -v slackpkg >/dev/null 2>&1; then
		_PKG_PKGMGR="slackpkg"
	fi

	return 0
}

# pkg_is_systemd — return 0 if systemd is the init system
# Calls pkg_detect_init if not already done.
pkg_is_systemd() {
	pkg_detect_init
	[[ "$_PKG_INIT_SYSTEM" = "systemd" ]]
}

# pkg_os_family — echo OS family and return 0
# Calls pkg_detect_os if not already done.
# Outputs: rhel|debian|gentoo|slackware|freebsd|unknown
pkg_os_family() {
	pkg_detect_os
	echo "$_PKG_OS_FAMILY"
	return 0
}

# ══════════════════════════════════════════════════════════════════
# Section: Dependency Checking
# ══════════════════════════════════════════════════════════════════

# pkg_dep_hint pkg_rpm pkg_deb — print package-manager-specific install command
# Arguments:
#   $1 — RPM package name
#   $2 — DEB package name
# Uses _PKG_PKGMGR to select the right hint. Calls pkg_detect_pkgmgr if needed.
pkg_dep_hint() {
	local pkg_rpm="$1" pkg_deb="$2"
	pkg_detect_pkgmgr

	local hint=""
	case "$_PKG_PKGMGR" in
		dnf)      hint="dnf install ${pkg_rpm}" ;;
		yum)      hint="yum install ${pkg_rpm}" ;;
		apt)      hint="apt-get install ${pkg_deb}" ;;
		emerge)   hint="emerge ${pkg_rpm}" ;;
		pkg)      hint="pkg install ${pkg_rpm}" ;;
		slackpkg) hint="slackpkg install ${pkg_rpm}" ;;
		*)        hint="install package providing this binary" ;;
	esac
	echo "$hint"
	return 0
}

# pkg_check_dep binary pkg_rpm pkg_deb level — check a single dependency
# Arguments:
#   $1 — binary name to check (via command -v)
#   $2 — RPM package name (for install hint)
#   $3 — DEB package name (for install hint)
#   $4 — level: required|recommended|optional
# Returns 0 if found, 1 if missing.
# Side effects: sets _PKG_DEPS_MISSING=1 for required deps.
pkg_check_dep() {
	local binary="$1" pkg_rpm="$2" pkg_deb="$3" level="${4:-required}"

	if [[ -z "$binary" ]]; then
		echo "pkg_lib: pkg_check_dep requires binary name" >&2
		return 1
	fi

	# Binary found — pass
	if command -v "$binary" >/dev/null 2>&1; then
		return 0
	fi

	# Binary missing — report based on level
	local hint
	hint=$(pkg_dep_hint "$pkg_rpm" "$pkg_deb")

	case "$level" in
		required)
			_PKG_DEPS_MISSING=1
			pkg_error "missing required dependency: ${binary}"
			pkg_info "  install: ${hint}"
			;;
		recommended)
			pkg_warn "missing recommended dependency: ${binary}"
			pkg_info "  install: ${hint}"
			;;
		optional)
			pkg_info "optional dependency not found: ${binary} (${hint})"
			;;
		*)
			pkg_warn "unknown dependency level '${level}' for ${binary}"
			;;
	esac

	return 1
}

# pkg_check_deps prefix — batch check dependencies from parallel arrays
# Arguments:
#   $1 — variable name prefix for arrays (e.g., "MY_APP" looks for
#         ${MY_APP_DEP_BINS[@]}, ${MY_APP_DEP_RPMS[@]},
#         ${MY_APP_DEP_DEBS[@]}, ${MY_APP_DEP_LEVELS[@]})
# Returns 0 if all found, 1 if any missing required deps.
# Uses indirect expansion compatible with bash 4.1.
pkg_check_deps() {
	local prefix="$1"

	if [[ -z "$prefix" ]]; then
		echo "pkg_lib: pkg_check_deps requires a variable prefix" >&2
		return 1
	fi

	# Build indirect references for bash 4.1 compat (no declare -n)
	local bins_ref="${prefix}_DEP_BINS[@]"
	local rpms_ref="${prefix}_DEP_RPMS[@]"
	local debs_ref="${prefix}_DEP_DEBS[@]"
	local levels_ref="${prefix}_DEP_LEVELS[@]"

	# Copy into local indexed arrays
	local bins=("${!bins_ref}")
	local rpms=("${!rpms_ref}")
	local debs=("${!debs_ref}")
	local levels=("${!levels_ref}")

	if [[ ${#bins[@]} -eq 0 ]]; then
		return 0
	fi

	local i
	local any_missing=0
	for i in "${!bins[@]}"; do
		pkg_check_dep "${bins[$i]}" "${rpms[$i]:-}" "${debs[$i]:-}" "${levels[$i]:-required}" || any_missing=1
	done

	return "$any_missing"
}

# ══════════════════════════════════════════════════════════════════
# Section: Backup & Restore
# ══════════════════════════════════════════════════════════════════

# Configurable defaults — consuming projects override via environment
PKG_BACKUP_METHOD="${PKG_BACKUP_METHOD:-move}"
PKG_BACKUP_SYMLINK="${PKG_BACKUP_SYMLINK:-.bk.last}"
PKG_BACKUP_PRUNE_DAYS="${PKG_BACKUP_PRUNE_DAYS:-0}"

# pkg_backup install_path [method] — create timestamped backup of install_path
# Arguments:
#   $1 — install path to back up (must exist)
#   $2 — method: "copy" (cp -R, original stays) or "move" (mv, original removed)
#         Defaults to PKG_BACKUP_METHOD env var (default: move)
# Backup naming: <install_path>.<DDMMYYYY-EPOCH>
# Collision safety: appends -N suffix if target already exists.
# Creates PKG_BACKUP_SYMLINK (default .bk.last) pointing to latest backup.
# Returns 1 on failure.
pkg_backup() {
	local install_path="$1"
	local method="${2:-${PKG_BACKUP_METHOD}}"

	if [[ -z "$install_path" ]]; then
		pkg_error "pkg_backup: install_path required"
		return 1
	fi

	if [[ ! -e "$install_path" ]]; then
		pkg_error "pkg_backup: install path does not exist: ${install_path}"
		return 1
	fi

	# Validate method
	case "$method" in
		copy|move) ;;
		*)
			pkg_error "pkg_backup: invalid method '${method}' (must be copy or move)"
			return 1
			;;
	esac

	# Build timestamp: DDMMYYYY-EPOCH
	local timestamp
	timestamp="$(date +%d%m%Y)-$(date +%s)"

	local backup_path="${install_path}.${timestamp}"

	# Collision safety — append -N if target exists
	if [[ -e "$backup_path" ]]; then
		local suffix=1
		while [[ -e "${backup_path}-${suffix}" ]]; do
			suffix=$((suffix + 1))
		done
		backup_path="${backup_path}-${suffix}"
	fi

	# Perform backup
	local rc=0
	case "$method" in
		copy)
			/usr/bin/cp -pR "$install_path" "$backup_path" || rc=$?
			;;
		move)
			mv "$install_path" "$backup_path" || rc=$?
			;;
	esac

	if [[ "$rc" -ne 0 ]]; then
		pkg_error "pkg_backup: failed to ${method} ${install_path} to ${backup_path}"
		return 1
	fi

	# Update .bk.last symlink (or configured name)
	local symlink_path
	symlink_path="$(dirname "$install_path")/${PKG_BACKUP_SYMLINK}"
	rm -f "$symlink_path"
	ln -s "$backup_path" "$symlink_path" || {
		pkg_warn "pkg_backup: failed to create symlink ${symlink_path}"
	}

	pkg_info "backup created: ${backup_path}"
	return 0
}

# pkg_backup_exists install_path — return 0 if .bk.last symlink exists
# Arguments:
#   $1 — install path (symlink is looked up in its parent directory)
pkg_backup_exists() {
	local install_path="$1"

	if [[ -z "$install_path" ]]; then
		pkg_error "pkg_backup_exists: install_path required"
		return 1
	fi

	local symlink_path
	symlink_path="$(dirname "$install_path")/${PKG_BACKUP_SYMLINK}"
	[[ -L "$symlink_path" ]]
}

# pkg_backup_path install_path — echo resolved path of .bk.last symlink
# Arguments:
#   $1 — install path (symlink is looked up in its parent directory)
# Returns 1 if symlink does not exist.
pkg_backup_path() {
	local install_path="$1"

	if [[ -z "$install_path" ]]; then
		pkg_error "pkg_backup_path: install_path required"
		return 1
	fi

	local symlink_path
	symlink_path="$(dirname "$install_path")/${PKG_BACKUP_SYMLINK}"

	if [[ ! -L "$symlink_path" ]]; then
		pkg_error "pkg_backup_path: no backup symlink found: ${symlink_path}"
		return 1
	fi

	# Resolve symlink target
	local target
	target=$(readlink "$symlink_path") || {
		pkg_error "pkg_backup_path: failed to read symlink: ${symlink_path}"
		return 1
	}
	echo "$target"
	return 0
}

# pkg_backup_prune install_path max_age_days — remove backups older than N days
# Arguments:
#   $1 — install path (backups are <install_path>.<timestamp> in parent dir)
#   $2 — max age in days (0 = no pruning)
# Removes matching backup directories/files older than max_age_days.
# Does not remove the .bk.last symlink target.
# Returns 0 on success, 1 on invalid arguments.
pkg_backup_prune() {
	local install_path="$1"
	local max_age_days="$2"

	if [[ -z "$install_path" ]] || [[ -z "$max_age_days" ]]; then
		pkg_error "pkg_backup_prune: install_path and max_age_days required"
		return 1
	fi

	# Validate max_age_days is a non-negative integer
	local int_pat='^[0-9]+$'
	if ! [[ "$max_age_days" =~ $int_pat ]]; then
		pkg_error "pkg_backup_prune: max_age_days must be a positive integer"
		return 1
	fi

	# 0 = no pruning
	if [[ "$max_age_days" -eq 0 ]]; then
		return 0
	fi

	local parent_dir
	parent_dir="$(dirname "$install_path")"
	local base_name
	base_name="$(basename "$install_path")"

	# Resolve current .bk.last target so we never prune it
	local current_backup=""
	local symlink_path="${parent_dir}/${PKG_BACKUP_SYMLINK}"
	if [[ -L "$symlink_path" ]]; then
		current_backup=$(readlink "$symlink_path" 2>/dev/null) || current_backup=""
	fi

	# Find backup entries matching the pattern: <base_name>.<digits>-<digits>*
	local bk_pat="^${base_name}\.[0-9]{8}-[0-9]+"
	local pruned=0
	local entry entry_path
	while IFS= read -r entry; do
		[[ -z "$entry" ]] && continue
		if ! [[ "$entry" =~ $bk_pat ]]; then
			continue
		fi
		entry_path="${parent_dir}/${entry}"

		# Skip if this is the current backup target
		if [[ -n "$current_backup" ]] && [[ "$entry_path" = "$current_backup" ]]; then
			continue
		fi

		# Check age using find -maxdepth 0 -mtime
		if find "$entry_path" -maxdepth 0 -mtime +"$max_age_days" -print 2>/dev/null | read -r _; then
			rm -rf "$entry_path"
			pruned=$((pruned + 1))
		fi
	done < <(ls -1 "$parent_dir" 2>/dev/null)

	if [[ "$pruned" -gt 0 ]]; then
		pkg_info "pruned ${pruned} old backup(s)"
	fi

	return 0
}

# pkg_restore_files backup_path install_path patterns... — selective file restore
# Arguments:
#   $1 — backup path (source directory)
#   $2 — install path (destination directory)
#   $3+ — glob patterns to restore (e.g., "conf.*" "*.rules")
# Copies matching files from backup to install path, preserving attributes.
# Returns 1 on failure.
pkg_restore_files() {
	local backup_path="$1"
	local install_path="$2"
	shift 2

	if [[ -z "$backup_path" ]] || [[ -z "$install_path" ]]; then
		pkg_error "pkg_restore_files: backup_path and install_path required"
		return 1
	fi

	if [[ $# -eq 0 ]]; then
		pkg_error "pkg_restore_files: at least one glob pattern required"
		return 1
	fi

	if [[ ! -d "$backup_path" ]]; then
		pkg_error "pkg_restore_files: backup path not found: ${backup_path}"
		return 1
	fi

	# Create install path if it does not exist
	if [[ ! -d "$install_path" ]]; then
		mkdir -p "$install_path" || {
			pkg_error "pkg_restore_files: failed to create ${install_path}"
			return 1
		}
	fi

	local pattern restored=0 rc
	for pattern in "$@"; do
		# Use find with -name for each pattern (avoids glob expansion issues)
		while IFS= read -r match; do
			[[ -z "$match" ]] && continue
			# Compute relative path from backup_path
			local relpath="${match#"${backup_path}"/}"
			local dest="${install_path}/${relpath}"
			local dest_dir
			dest_dir="$(dirname "$dest")"

			# Ensure destination directory exists
			if [[ ! -d "$dest_dir" ]]; then
				mkdir -p "$dest_dir" || continue
			fi

			rc=0
			/usr/bin/cp -p "$match" "$dest" || rc=$?
			if [[ "$rc" -eq 0 ]]; then
				restored=$((restored + 1))
			else
				pkg_warn "pkg_restore_files: failed to restore ${relpath}"
			fi
		done < <(find "$backup_path" -name "$pattern" -not -type d 2>/dev/null)
	done

	if [[ "$restored" -eq 0 ]]; then
		pkg_warn "pkg_restore_files: no files matched the given patterns"
		return 1
	fi

	pkg_info "restored ${restored} file(s)"
	return 0
}

# pkg_restore_dir backup_path install_path subdir — restore entire subdirectory
# Arguments:
#   $1 — backup path (source root)
#   $2 — install path (destination root)
#   $3 — subdirectory name to restore (relative to backup/install)
# Copies the entire subdirectory from backup to install path.
# Returns 1 on failure.
pkg_restore_dir() {
	local backup_path="$1"
	local install_path="$2"
	local subdir="$3"

	if [[ -z "$backup_path" ]] || [[ -z "$install_path" ]] || [[ -z "$subdir" ]]; then
		pkg_error "pkg_restore_dir: backup_path, install_path, and subdir required"
		return 1
	fi

	local src="${backup_path}/${subdir}"

	if [[ ! -d "$src" ]]; then
		pkg_error "pkg_restore_dir: subdirectory not found in backup: ${subdir}"
		return 1
	fi

	local dest="${install_path}/${subdir}"
	local dest_parent
	dest_parent="$(dirname "$dest")"

	# Ensure destination parent directory exists
	if [[ ! -d "$dest_parent" ]]; then
		mkdir -p "$dest_parent" || {
			pkg_error "pkg_restore_dir: failed to create ${dest_parent}"
			return 1
		}
	fi

	/usr/bin/cp -pR "$src" "$dest" || {
		pkg_error "pkg_restore_dir: failed to restore ${subdir}"
		return 1
	}

	pkg_info "restored directory: ${subdir}"
	return 0
}

# ══════════════════════════════════════════════════════════════════
# Section: File Operations
# ══════════════════════════════════════════════════════════════════

# pkg_copy_tree src_dir dest_dir — recursive copy with attribute preservation
# Arguments:
#   $1 — source directory
#   $2 — destination directory
# Uses cp -pR to preserve ownership, permissions, timestamps.
# Returns 1 on failure.
pkg_copy_tree() {
	local src_dir="$1"
	local dest_dir="$2"

	if [[ -z "$src_dir" ]] || [[ -z "$dest_dir" ]]; then
		pkg_error "pkg_copy_tree: src_dir and dest_dir required"
		return 1
	fi

	if [[ ! -d "$src_dir" ]]; then
		pkg_error "pkg_copy_tree: source directory not found: ${src_dir}"
		return 1
	fi

	# Create destination if it does not exist
	if [[ ! -d "$dest_dir" ]]; then
		mkdir -p "$dest_dir" || {
			pkg_error "pkg_copy_tree: failed to create ${dest_dir}"
			return 1
		}
	fi

	/usr/bin/cp -pR "${src_dir}/." "$dest_dir/" || {
		pkg_error "pkg_copy_tree: failed to copy ${src_dir} to ${dest_dir}"
		return 1
	}

	return 0
}

# pkg_set_perms path dir_mode file_mode [exec_files...] — set permissions
# Arguments:
#   $1 — base path to set permissions on
#   $2 — mode for directories (e.g., "750")
#   $3 — mode for regular files (e.g., "640")
#   $4+ — executable files (relative to path) to set to exec_mode (same as dir_mode)
# Sets directory permissions, then file permissions, then executable overrides.
# Returns 1 on failure.
pkg_set_perms() {
	local base_path="$1"
	local dir_mode="$2"
	local file_mode="$3"
	shift 3

	if [[ -z "$base_path" ]] || [[ -z "$dir_mode" ]] || [[ -z "$file_mode" ]]; then
		pkg_error "pkg_set_perms: base_path, dir_mode, and file_mode required"
		return 1
	fi

	if [[ ! -e "$base_path" ]]; then
		pkg_error "pkg_set_perms: path does not exist: ${base_path}"
		return 1
	fi

	# Set directory permissions
	find "$base_path" -type d -exec chmod "$dir_mode" {} + 2>/dev/null

	# Set regular file permissions
	find "$base_path" -type f -exec chmod "$file_mode" {} + 2>/dev/null

	# Override executable files (use dir_mode as executable mode)
	local exec_file
	for exec_file in "$@"; do
		local full_path="${base_path}/${exec_file}"
		if [[ -f "$full_path" ]]; then
			chmod "$dir_mode" "$full_path" || {
				pkg_warn "pkg_set_perms: failed to set exec mode on ${exec_file}"
			}
		fi
	done

	return 0
}

# pkg_create_dirs mode dirs... — create directories with specified mode
# Arguments:
#   $1 — mode (e.g., "750")
#   $2+ — directory paths to create
# Returns 1 if any creation fails.
pkg_create_dirs() {
	local mode="$1"
	shift

	if [[ -z "$mode" ]] || [[ $# -eq 0 ]]; then
		pkg_error "pkg_create_dirs: mode and at least one directory required"
		return 1
	fi

	local dir rc=0
	for dir in "$@"; do
		if [[ ! -d "$dir" ]]; then
			mkdir -p "$dir" || {
				pkg_error "pkg_create_dirs: failed to create ${dir}"
				rc=1
				continue
			}
		fi
		chmod "$mode" "$dir" || {
			pkg_warn "pkg_create_dirs: failed to set mode ${mode} on ${dir}"
		}
	done

	return "$rc"
}

# pkg_symlink target link_path — create or update a symbolic link
# Arguments:
#   $1 — target (what the link points to)
#   $2 — link path (the symlink to create)
# Removes existing link/file at link_path before creating.
# Returns 1 on failure.
pkg_symlink() {
	local target="$1"
	local link_path="$2"

	if [[ -z "$target" ]] || [[ -z "$link_path" ]]; then
		pkg_error "pkg_symlink: target and link_path required"
		return 1
	fi

	# Remove existing link or file at link_path
	rm -f "$link_path" 2>/dev/null  # safe: only removes file/symlink, not dir

	ln -s "$target" "$link_path" || {
		pkg_error "pkg_symlink: failed to create symlink ${link_path} -> ${target}"
		return 1
	}

	return 0
}

# pkg_symlink_cleanup link_paths... — remove symlinks only (safety: skip non-symlinks)
# Arguments:
#   $1+ — symlink paths to remove
# Silently skips paths that are not symlinks (safety measure).
# Returns 0 always.
pkg_symlink_cleanup() {
	if [[ $# -eq 0 ]]; then
		pkg_error "pkg_symlink_cleanup: at least one link path required"
		return 1
	fi

	local link_path
	for link_path in "$@"; do
		if [[ -L "$link_path" ]]; then
			rm -f "$link_path"
		elif [[ -e "$link_path" ]]; then
			pkg_warn "pkg_symlink_cleanup: skipping non-symlink: ${link_path}"
		fi
	done

	return 0
}

# pkg_sed_replace old_path new_path files... — sed -i path replacement across files
# Arguments:
#   $1 — old path string to replace
#   $2 — new path string to substitute
#   $3+ — files to perform replacement on
# Uses '|' as sed delimiter to avoid conflicts with path separators.
# Returns 1 if no files provided.
pkg_sed_replace() {
	local old_path="$1"
	local new_path="$2"
	shift 2

	if [[ -z "$old_path" ]] || [[ -z "$new_path" ]]; then
		pkg_error "pkg_sed_replace: old_path and new_path required"
		return 1
	fi

	if [[ $# -eq 0 ]]; then
		pkg_error "pkg_sed_replace: at least one file required"
		return 1
	fi

	local file
	for file in "$@"; do
		if [[ ! -f "$file" ]]; then
			pkg_warn "pkg_sed_replace: file not found, skipping: ${file}"
			continue
		fi
		sed -i "s|${old_path}|${new_path}|g" "$file" || {
			pkg_warn "pkg_sed_replace: sed failed on ${file}"
		}
	done

	return 0
}

# pkg_tmpfile [template] — mktemp wrapper with default template
# Arguments:
#   $1 — optional mktemp template (default: pkg_lib.XXXXXXXXXX)
# Creates temp file in PKG_TMPDIR. Echoes path to stdout.
# Returns 1 on failure.
pkg_tmpfile() {
	local template="${1:-pkg_lib.XXXXXXXXXX}"

	local tmpfile
	tmpfile=$(mktemp "${PKG_TMPDIR}/${template}") || {
		pkg_error "pkg_tmpfile: mktemp failed"
		return 1
	}

	echo "$tmpfile"
	return 0
}
