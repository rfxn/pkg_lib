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
