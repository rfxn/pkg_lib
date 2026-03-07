# pkg_lib -- Shared Packaging & Installer Library

Unified packaging, install, and uninstall primitives for rfxn projects (BFD, APF, LMD).
Provides consistent output formatting, OS detection, dependency checking, backup/restore,
file operations, service lifecycle management, cron/logrotate/man page installation,
config migration, FHS layout, symlink farms, and uninstall -- all driven by environment
variables with zero project-specific code.

**Version:** 1.0.0
**License:** GNU GPL v2
**Organization:** R-fx Networks

## Architecture

pkg_lib uses a split architecture with two independent components:

- **`files/pkg_lib.sh`** -- Runtime library (~3200 lines). Sourced by consuming
  projects at install/uninstall time. Contains all packaging primitives. Configured
  entirely via `PKG_*` environment variables.

- **`pkg/pkg_gen.sh`** -- Build-time generator (~450 lines). Standalone script
  that reads a project manifest and template files to produce project-specific
  RPM spec, DEB debian/, Docker, Makefile, and CI artifacts.

### Runtime Library (pkg_lib.sh)

Source the library after setting configuration variables:

```bash
# Set project-specific config via environment
export PKG_NAME="myproject"
export PKG_VERSION="1.0.0"
export PKG_INSTALL_PATH="/usr/local/myproject"

# Source the library
source /path/to/pkg_lib.sh

# Use library functions
pkg_header "$PKG_NAME" "$PKG_VERSION" "install"
pkg_detect_os
pkg_check_dep "curl" "curl" "curl" "required"
pkg_backup "$PKG_INSTALL_PATH"
pkg_copy_tree "./files" "$PKG_INSTALL_PATH"
pkg_service_install "$PKG_NAME" "./files/myproject.service"
pkg_service_enable "$PKG_NAME"
pkg_success "installation complete"
```

### Build-Time Generator (pkg_gen.sh)

Run the generator with a project manifest and template directory:

```bash
./pkg/pkg_gen.sh \
  --manifest ./pkg.manifest \
  --templates ./pkg/templates \
  --output ./pkg

# Or via environment variables:
PKG_MANIFEST=./pkg.manifest \
PKG_TEMPLATES=./pkg/templates \
PKG_OUTPUT=./pkg \
./pkg/pkg_gen.sh
```

## Quick Start for Consuming Projects

### 1. Create a project manifest

Create `pkg.manifest` in your project root:

```bash
PKG_NAME="myproject"
PKG_VERSION="2.0.1"
PKG_SUMMARY="My awesome project"
PKG_DESCRIPTION="Extended description of the project"
PKG_LICENSE="GPLv2+"
PKG_URL="https://github.com/rfxn/myproject"
PKG_MAINTAINER="R-fx Networks <proj@rfxn.com>"
PKG_INSTALL_PATH="/usr/local/myproject"
PKG_BIN_NAME="myproject"
PKG_BIN_LEGACY="/usr/local/sbin/myproject"
PKG_SECTION="1"
PKG_COPYRIGHT_START="2002"
PKG_VERSION_CMD="echo 2.0.1"

# Feature flags for conditional template blocks
PKG_HAS_SYSTEMD_SERVICE="1"
PKG_HAS_SYSV_INIT="1"
PKG_HAS_CRON_D="1"
PKG_HAS_LOGROTATE="1"
```

### 2. Generate packaging artifacts

```bash
./pkg/pkg_gen.sh --manifest ./pkg.manifest --templates /path/to/pkg_lib/pkg/templates --output ./pkg
```

This produces RPM spec, DEB debian/, Dockerfiles, Makefile, GHA workflow,
and install verification scripts -- all customized with your manifest values.

### 3. Use pkg_lib.sh in your install.sh

```bash
#!/bin/bash
source ./pkg_lib.sh

pkg_header "MyProject" "2.0.1" "install"

# Check dependencies
pkg_section "Checking dependencies"
pkg_check_dep "bash" "bash" "bash" "required"
pkg_check_dep "curl" "curl" "curl" "required"

# Backup existing install
if [[ -d "/usr/local/myproject" ]]; then
    pkg_section "Backing up existing installation"
    pkg_backup "/usr/local/myproject"
fi

# Install files
pkg_section "Installing files"
pkg_copy_tree "./files" "/usr/local/myproject"
pkg_set_perms "/usr/local/myproject" "750" "640" "bin/myproject"

# Install service
pkg_section "Configuring service"
pkg_service_install "myproject" "./files/myproject.service"
pkg_service_enable "myproject"

pkg_success "MyProject 2.0.1 installed successfully"
```

## Integration Guide

This section describes how to structure `install.sh` and `uninstall.sh` using
pkg_lib primitives. BFD, APF, and LMD all follow this pattern.

### Structuring install.sh

A typical installer sources pkg_lib.sh, then calls primitives in a fixed order.
The pattern handles both fresh installs and upgrades:

```bash
#!/bin/bash
set -eu
cd "$(dirname "$0")"

INSPATH="${INSTALL_PATH:-/usr/local/myproject}"
BINPATH="${BIN_PATH:-/usr/local/sbin/myproject}"
VER="2.0.1"

[ "$(id -u)" -ne 0 ] && { echo "error: must be root"; exit 1; }

# Optional: set PKG_BACKUP_SYMLINK before sourcing to customize
# shellcheck disable=SC1091
. ./files/internals/pkg_lib.sh

install_files() {
    rm -rf "$INSPATH"
    pkg_copy_tree "./files" "$INSPATH"
    pkg_set_perms "$INSPATH" "750" "640" "myproject"
    pkg_create_dirs "750" "$INSPATH/tmp"

    # CLI symlink
    mkdir -p "$(dirname "$BINPATH")"
    pkg_symlink "$INSPATH/myproject" "$BINPATH"

    # Cron, logrotate, man page, bash completion
    pkg_cron_install "cron" "/etc/cron.d/myproject"
    pkg_logrotate_install "logrotate.d.myproject" "myproject"
    pkg_man_install "myproject.1" "1" "myproject"
    pkg_bash_completion "myproject.bash-completion" "myproject"

    # Services: systemd units or SysV init fallback
    pkg_detect_init
    pkg_service_install_multi "myproject" "myproject.service" "myproject.timer"
}

if [ -d "$INSPATH" ]; then
    # Upgrade path
    pkg_header "MyProject" "$VER" "upgrade"
    pkg_section "Backing up existing installation"
    pkg_backup "$INSPATH"
    pkg_section "Installing files"
    install_files
    pkg_section "Importing configuration"
    BK_LAST=$(pkg_backup_path "$INSPATH") ./importconf
    pkg_success "MyProject ${VER} upgrade complete"
else
    # Fresh install
    pkg_header "MyProject" "$VER" "install"
    pkg_section "Installing files"
    install_files
    pkg_success "MyProject ${VER} installation complete"
fi
```

Key points:
- Call `pkg_detect_os` and `pkg_detect_init` before service/package operations
- Use `pkg_backup` before overwriting an existing install directory
- Call `pkg_copy_tree` or `pkg_fhs_install` for file placement
- Use `pkg_service_install_multi` for multi-unit service bundles
- Use `pkg_cron_install` for cron.d and cron.daily entries
- Call `pkg_success` at the end to print a styled success message

### Structuring uninstall.sh

The uninstaller sources pkg_lib from the installed location (with a fallback to
the source tree), confirms with the user, then removes all artifacts:

```bash
#!/bin/bash
INSPATH="${INSTALL_PATH:-/usr/local/myproject}"
BINPATH="${BIN_PATH:-/usr/local/sbin/myproject}"

[ "$(id -u)" -ne 0 ] && { echo "error: must be root"; exit 1; }

# Source from install path first, fall back to source tree
if [ -f "$INSPATH/internals/pkg_lib.sh" ]; then
    # shellcheck disable=SC1091
    . "$INSPATH/internals/pkg_lib.sh"
elif [ -f "files/internals/pkg_lib.sh" ]; then
    # shellcheck disable=SC1091
    . ./files/internals/pkg_lib.sh
fi

pkg_uninstall_confirm "MyProject" || exit 0

if [ -d "$INSPATH" ]; then
    # Remove services (systemd + SysV)
    pkg_service_uninstall_multi "myproject" "myproject-watch"

    # Remove man page, bash completion, logrotate
    pkg_uninstall_man "1" "myproject"
    pkg_uninstall_completion "myproject"
    pkg_uninstall_logrotate "myproject"

    # Remove cron files
    pkg_uninstall_cron /etc/cron.d/myproject /etc/cron.daily/myproject

    # Remove install dir, backups, CLI symlink, log files
    pkg_uninstall_files "$INSPATH".bk.* "$INSPATH" "$BINPATH" /var/log/myproject.log

    pkg_success "MyProject has been uninstalled."
else
    echo "MyProject does not appear to be installed."
fi
```

### Config Migration Pattern

On upgrade, use `pkg_config_merge` to preserve user settings while adding new
variables from the current template:

```bash
# In importconf (called after install_files during upgrade):
BK_LAST="${BK_LAST:-}"
[ -z "$BK_LAST" ] && { echo "No backup path provided"; exit 1; }

# Merge old config values into new template
pkg_config_merge "$BK_LAST/conf.myproject" "$INSPATH/conf.myproject" \
    "$INSPATH/conf.myproject"

# Rename deprecated variables
pkg_config_migrate_var "$INSPATH/conf.myproject" "OLD_VAR" "NEW_VAR"

# Clamp numeric values to safe maximums
pkg_config_clamp "$INSPATH/conf.myproject" "MAX_THREADS" 64
```

The AWK merge preserves all old values for matching keys and keeps new template
structure, comments, and any newly added variables.

## Use Cases

### Fresh Install

Detect the OS, check dependencies, copy files, install services, report success:

```bash
. ./files/internals/pkg_lib.sh
pkg_header "MyProject" "1.0.0" "install"
pkg_detect_os
pkg_detect_init
pkg_check_dep "curl" "curl" "curl" "required"
pkg_copy_tree "./files" "/usr/local/myproject"
pkg_set_perms "/usr/local/myproject" "750" "640" "bin/myproject"
pkg_service_install "myproject" "myproject.service"
pkg_service_enable "myproject"
pkg_success "MyProject 1.0.0 installed"
```

### Upgrade with Backup

Back up the old install, copy new files, restore user configuration, restart:

```bash
pkg_header "MyProject" "2.0.0" "upgrade"
pkg_backup "/usr/local/myproject"
rm -rf "/usr/local/myproject"
pkg_copy_tree "./files" "/usr/local/myproject"
BK_LAST=$(pkg_backup_path "/usr/local/myproject")
pkg_config_merge "$BK_LAST/conf.myproject" \
    "/usr/local/myproject/conf.myproject" \
    "/usr/local/myproject/conf.myproject"
pkg_service_restart "myproject"
pkg_success "MyProject 2.0.0 upgrade complete"
```

### Multi-Service Install

Install systemd units with SysV fallback, plus cron and logrotate:

```bash
pkg_detect_init
pkg_service_install_multi "myproject" \
    "myproject.service" "myproject.timer"
if [ -f "myproject-watch.init" ]; then
    pkg_service_install "myproject-watch" "myproject-watch.init"
fi
pkg_cron_install "cron" "/etc/cron.d/myproject"
pkg_cron_install "cron.daily" "/etc/cron.daily/myproject"
pkg_logrotate_install "logrotate.d.myproject" "myproject"
```

### FHS Layout with Symlink Farm

Register files for FHS-compliant paths, install them, then create backward-compat
symlinks at the legacy location:

```bash
# Register file mappings: source -> FHS destination
pkg_fhs_register "bin/myproject" "/usr/bin/myproject" "755" "bin"
pkg_fhs_register "conf.myproject" "/etc/myproject/conf.myproject" "640" "conf"
pkg_fhs_register "myproject.1" "/usr/share/man/man1/myproject.1.gz" "644" "doc"

# Install files to FHS destinations
pkg_fhs_install "./files"

# Create legacy symlinks: /usr/local/myproject/bin/myproject -> /usr/bin/myproject
pkg_fhs_symlink_farm "/usr/local/myproject"
```

### Package Generation

Write a manifest, then run `pkg_gen.sh` to produce RPM/DEB specs and build
infrastructure:

```bash
# pkg.manifest
PKG_NAME="myproject"
PKG_VERSION="2.0.1"
PKG_SUMMARY="My project"
PKG_INSTALL_PATH="/usr/local/myproject"
PKG_HAS_SYSTEMD_SERVICE="1"
PKG_HAS_CRON_D="1"
```

```bash
# Generate all packaging artifacts
./pkg/pkg_gen.sh \
    --manifest ./pkg.manifest \
    --templates ./pkg/templates \
    --output ./pkg

# Produces: pkg/rpm/myproject.spec, pkg/deb/debian/*, pkg/docker/*,
#           pkg/Makefile, pkg/.github/workflows/release.yml
```

## Configuration Variables

All behavior is controlled via `PKG_*` environment variables. Set these before
sourcing `pkg_lib.sh`:

### Core Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PKG_NO_COLOR` | `0` | Disable color output (`1` = no color) |
| `PKG_QUIET` | `0` | Suppress info messages (`1` = quiet) |
| `PKG_TMPDIR` | `$TMPDIR` or `/tmp` | Temporary file directory |

### Backup Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PKG_BACKUP_METHOD` | `move` | Backup method: `copy` or `move` |
| `PKG_BACKUP_SYMLINK` | `.bk.last` | Name of the latest-backup symlink |
| `PKG_BACKUP_PRUNE_DAYS` | `0` | Auto-prune backups older than N days (0 = disabled) |

### Service Lifecycle Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PKG_CHKCONFIG_LEVELS` | `345` | SysV runlevels for chkconfig |
| `PKG_UPDATERCD_START` | `95` | update-rc.d start priority |
| `PKG_UPDATERCD_STOP` | `05` | update-rc.d stop priority |
| `PKG_SYSTEMD_UNIT_DIR` | (auto-detect) | Override systemd unit directory |
| `PKG_SLACKWARE_RUNLEVELS` | `2 3 4 5` | Slackware runlevels |
| `PKG_SLACKWARE_PRIORITY` | `95` | Slackware S-link priority |

## Function Reference

### Output & Messaging

| Function | Description |
|----------|-------------|
| `pkg_header project version [action]` | Print styled install/uninstall header |
| `pkg_info message` | Print info message (suppressed by `PKG_QUIET=1`) |
| `pkg_warn message` | Print warning to stderr (yellow if terminal) |
| `pkg_error message` | Print error to stderr (red if terminal) |
| `pkg_success message` | Print success message (green if terminal) |
| `pkg_section title` | Print section separator with title |
| `pkg_item label value` | Print aligned key: value pair |

### OS & Platform Detection

| Function | Description |
|----------|-------------|
| `pkg_detect_os` | Detect OS family, ID, version, display name (cached) |
| `pkg_detect_init` | Detect init system: systemd, sysv, upstart, rc.local (cached) |
| `pkg_detect_pkgmgr` | Detect package manager: dnf, yum, apt, emerge, pkg, slackpkg (cached) |
| `pkg_is_systemd` | Return 0 if systemd is the init system |
| `pkg_os_family` | Echo OS family: rhel, debian, gentoo, slackware, freebsd, unknown |

### Dependency Checking

| Function | Description |
|----------|-------------|
| `pkg_check_dep binary rpm_pkg deb_pkg level` | Check single dependency (required/recommended/optional) |
| `pkg_check_deps prefix` | Batch check from parallel arrays (`${prefix}_DEP_BINS`, etc.) |
| `pkg_dep_hint rpm_pkg deb_pkg` | Print package-manager-specific install hint |

### Backup & Restore

| Function | Description |
|----------|-------------|
| `pkg_backup path [method]` | Create timestamped backup with collision safety |
| `pkg_backup_exists path` | Return 0 if `.bk.last` symlink exists |
| `pkg_backup_path path` | Echo resolved path of latest backup |
| `pkg_backup_prune path days` | Remove backups older than N days |
| `pkg_restore_files backup_path install_path patterns...` | Selective file restore by glob |
| `pkg_restore_dir backup_path install_path subdir` | Restore entire subdirectory |

### File Operations

| Function | Description |
|----------|-------------|
| `pkg_copy_tree src dest` | Recursive copy with attribute preservation |
| `pkg_set_perms path dir_mode file_mode [exec_files...]` | Set directory, file, and executable permissions |
| `pkg_create_dirs mode dirs...` | Create directories with specified mode |
| `pkg_symlink target link_path` | Create or update symbolic link |
| `pkg_symlink_cleanup link_paths...` | Remove symlinks only (safety: skip non-symlinks) |
| `pkg_sed_replace old_path new_path files...` | Sed-based path replacement across files |
| `pkg_tmpfile [prefix]` | Create temp file via mktemp in `PKG_TMPDIR` |

### Service Lifecycle

| Function | Description |
|----------|-------------|
| `pkg_service_install name source_file` | Install systemd unit or SysV init script |
| `pkg_service_uninstall name` | Remove service from all locations |
| `pkg_service_install_timer name source_file` | Install systemd timer unit |
| `pkg_service_install_multi services...` | Install multiple service units |
| `pkg_service_uninstall_multi services...` | Uninstall multiple service units |
| `pkg_service_start name` | Start service (systemd or SysV cascade) |
| `pkg_service_stop name` | Stop service |
| `pkg_service_restart name` | Restart service |
| `pkg_service_status name` | Check service status |
| `pkg_service_enable name` | Enable service at boot (OS-family cascade) |
| `pkg_service_disable name` | Disable service at boot |
| `pkg_service_exists name` | Return 0 if service unit/script exists |
| `pkg_service_is_enabled name` | Return 0 if service is enabled |
| `pkg_rclocal_add name command` | Add entry to rc.local (idempotent) |
| `pkg_rclocal_remove pattern` | Remove matching entries from rc.local |

### Cron Management

| Function | Description |
|----------|-------------|
| `pkg_cron_install source dest` | Install cron file with auto-detect mode |
| `pkg_cron_remove files...` | Remove cron files |
| `pkg_cron_cleanup_legacy patterns...` | Glob-based legacy cron cleanup |
| `pkg_cron_preserve_schedule cron_file var_name` | Capture 5-field schedule from existing cron file |
| `pkg_cron_restore_schedule cron_file var_name` | Restore captured schedule after install |

### Documentation Installation

| Function | Description |
|----------|-------------|
| `pkg_man_install src section [sed_pairs]` | Install man page with optional path substitution |
| `pkg_bash_completion name source_file` | Install bash completion file |
| `pkg_logrotate_install name source_file` | Install logrotate configuration |
| `pkg_doc_install install_path files...` | Install README/CHANGELOG/LICENSE to doc directory |

### Config Migration

| Function | Description |
|----------|-------------|
| `pkg_config_get file key` | Extract value from config file (AWK, quote-stripping) |
| `pkg_config_set file key value` | Set or update config variable in file |
| `pkg_config_merge old_config new_template output` | AWK merge preserving old values into new template |
| `pkg_config_migrate_var file old_name new_name [transform]` | Rename config variable with optional transform |
| `pkg_config_clamp file key max_value` | Clamp numeric config value to maximum |

### FHS Layout

| Function | Description |
|----------|-------------|
| `pkg_fhs_register src dest mode type` | Register file mapping in FHS registry |
| `pkg_fhs_install source_root` | Install registered files to FHS destinations |
| `pkg_fhs_symlink_farm legacy_root` | Create backward-compat symlinks from legacy to FHS paths |
| `pkg_fhs_symlink_farm_cleanup legacy_root` | Remove symlink farm and empty directories |
| `pkg_fhs_gen_rpm_files` | Generate RPM %files section from registry |
| `pkg_fhs_gen_deb_dirs` | Generate DEB dirs list from registry |
| `pkg_fhs_gen_deb_links legacy_root` | Generate DEB links list from registry |
| `pkg_fhs_gen_deb_conffiles` | Generate DEB conffiles list from registry |
| `pkg_fhs_gen_sed_pairs legacy_root` | Generate sed path-replacement expressions |

### Uninstall

| Function | Description |
|----------|-------------|
| `pkg_uninstall_confirm name` | Interactive y/N confirmation prompt |
| `pkg_uninstall_files paths...` | Remove files and directories (silent skip for missing) |
| `pkg_uninstall_man name sections...` | Remove man pages from all standard locations |
| `pkg_uninstall_cron files...` | Remove cron files |
| `pkg_uninstall_logrotate name` | Remove logrotate configuration |
| `pkg_uninstall_completion name` | Remove bash completion file |
| `pkg_uninstall_sysconfig name` | Remove sysconfig/default override file |

### Manifest Support

| Function | Description |
|----------|-------------|
| `pkg_manifest_load file` | Source a project manifest file |
| `pkg_manifest_validate` | Validate required manifest variables are set |

## pkg_gen.sh -- Manifest-Driven Generator

### Two-Level Substitution Model

The generator uses a two-level token substitution model:

- **Level 1 (generator):** `@@PKG_NAME@@`, `@@PKG_VERSION@@`, and other manifest
  variables are substituted from the sourced manifest into template output.

- **Level 2 (project-specific):** Tokens like `@@PKG_RPM_FILES_SECTION@@` and
  `@@PKG_POSTINST_EXTRA@@` are intentionally left as-is for projects to fill in
  via post-processing or manual edit. The generator produces a functional scaffold
  while leaving project-specific content for the consumer to customize.

### Conditional Blocks

Templates support feature-flag conditional blocks:

```
@@IF_SYSTEMD@@
systemd_enabled=true
@@ENDIF_SYSTEMD@@
```

Set `PKG_HAS_SYSTEMD="1"` in your manifest to keep the content (markers removed),
or `PKG_HAS_SYSTEMD="0"` (or omit) to remove the entire block.

### Manifest Format

The manifest is a plain bash variable assignment file. Required variables:

| Variable | Description |
|----------|-------------|
| `PKG_NAME` | Package name (used in filenames, specs, controls) |
| `PKG_VERSION` | Package version |
| `PKG_SUMMARY` | One-line package summary |
| `PKG_INSTALL_PATH` | FHS install path (e.g., `/usr/share/myproject`) |

Optional variables (substituted if present):

| Variable | Description |
|----------|-------------|
| `PKG_DESCRIPTION` | Extended package description |
| `PKG_LICENSE` | License identifier (e.g., `GPLv2+`) |
| `PKG_URL` | Project URL |
| `PKG_MAINTAINER` | Maintainer name and email |
| `PKG_BIN_NAME` | Binary/script name |
| `PKG_BIN_LEGACY` | Legacy binary path for backward compat |
| `PKG_SECTION` | Man page section number |
| `PKG_COPYRIGHT_START` | Copyright start year |
| `PKG_VERSION_CMD` | Command to extract version at runtime |

Feature flags (for conditional blocks):

| Variable | Description |
|----------|-------------|
| `PKG_HAS_SYSTEMD_SERVICE` | Include systemd service handling |
| `PKG_HAS_SYSV_INIT` | Include SysV init script handling |
| `PKG_HAS_CRON_D` | Include cron.d configuration |
| `PKG_HAS_LOGROTATE` | Include logrotate configuration |

### Template Inventory

| Template | Output | Description |
|----------|--------|-------------|
| `rpm/project.spec.in` | `rpm/$PKG_NAME.spec` | RPM spec file |
| `deb/debian/control.in` | `deb/debian/control` | DEB control file |
| `deb/debian/rules.in` | `deb/debian/rules` | DEB build rules |
| `deb/debian/conffiles.in` | `deb/debian/conffiles` | DEB conffiles list |
| `deb/debian/dirs.in` | `deb/debian/dirs` | DEB directory list |
| `deb/debian/links.in` | `deb/debian/links` | DEB symlinks |
| `deb/debian/preinst.in` | `deb/debian/preinst` | DEB pre-install script |
| `deb/debian/postinst.in` | `deb/debian/postinst` | DEB post-install script |
| `deb/debian/postrm.in` | `deb/debian/postrm` | DEB post-remove script |
| `deb/debian/changelog.in` | `deb/debian/changelog` | DEB changelog |
| `deb/debian/copyright.in` | `deb/debian/copyright` | DEB copyright |
| `deb/debian/source/format` | `deb/debian/source/format` | DEB source format |
| `docker/Dockerfile.rpm-el7.in` | `docker/Dockerfile.rpm-el7` | RPM build (CentOS 7) |
| `docker/Dockerfile.rpm-el9.in` | `docker/Dockerfile.rpm-el9` | RPM build (Rocky 9+) |
| `docker/Dockerfile.deb.in` | `docker/Dockerfile.deb` | DEB build (Debian 12) |
| `docker/Dockerfile.test-rpm.in` | `docker/Dockerfile.test-rpm` | RPM install test |
| `docker/Dockerfile.test-deb.in` | `docker/Dockerfile.test-deb` | DEB install test |
| `Makefile.in` | `Makefile` | Build system with tarball, RPM, DEB targets |
| `github/release.yml.in` | `.github/workflows/release.yml` | GHA release workflow |
| `test-pkg-install.sh.in` | `test/test-pkg-install.sh` | Package install verification |

## Testing

Tests use the [batsman](https://github.com/rfxn/batsman) test framework
(BATS-based) as a git submodule at `tests/infra/`.

### Commands

```bash
make -C tests test                 # Debian 12 (default)
make -C tests test-rocky9          # Rocky 9
make -C tests test-centos6         # CentOS 6 (bash 4.1 floor)
make -C tests test-all             # Full sequential matrix (9 OS targets)
make -C tests test-all-parallel    # Full parallel matrix
```

### Test Files

| File | Tests | Coverage |
|------|-------|----------|
| `00-scaffold.bats` | 2 | Source guard, version variable |
| `01-output.bats` | 21 | Header, color detection, message types, quiet mode |
| `02-os-detect.bats` | 17 | OS family, init system, package manager, mock /etc files |
| `03-deps.bats` | 23 | Binary checks, package hints, required/recommended/optional |
| `04-backup.bats` | 34 | Timestamp naming, collision safety, symlink, prune, abort |
| `05-fileops.bats` | 38 | Copy tree, permissions, symlinks, path sed, tmpfile |
| `06-service.bats` | 88 | Cascade detection, enable/disable, sysconfig, rc.local |
| `07-cron.bats` | 23 | Install, remove, legacy cleanup, schedule preserve/restore |
| `08-docs.bats` | 19 | Man page gzip, bash completion, logrotate, doc dir |
| `09-config.bats` | 30 | AWK merge, variable migration, clamp, set/get |
| `10-fhs.bats` | 30 | Registry, symlink farm, RPM/DEB artifact generation |
| `11-uninstall.bats` | 17 | Confirm prompt, file removal, service cleanup |
| `12-manifest.bats` | 12 | Load, validate, missing fields |
| `13-generator.bats` | 26 | Output structure, substitution, conditionals, dry-run |

### OS Test Matrix

Debian 12 (default), CentOS 6, CentOS 7, Rocky 8, Rocky 9, Rocky 10,
Ubuntu 12.04, Ubuntu 20.04, Ubuntu 24.04.

**Known issue:** CentOS 6 Docker image is missing `/usr/bin/cp`, causing
pre-existing test failures in backup, fileops, and service tests. This
is a test environment issue, not a library bug.

## Compatibility

- **Bash 4.1+** minimum (CentOS 6 floor)
- No bash 4.2+ features used
- No associative arrays for global state (parallel indexed arrays only)
- No project-specific code -- all context via environment variables
- Errors go to stderr -- no dependency on consuming project's logging

## Supported OS Families

CentOS 6+, Rocky 8/9/10, Ubuntu 12.04-24.04, Debian 12, Gentoo,
Slackware, FreeBSD (partial -- service management excluded).

## Troubleshooting

### Backup Collision

If two installs run within the same second, `pkg_backup` detects the collision
and appends a `-N` suffix (e.g., `myproject.07032026-1709834567-1`). If the
target directory still exists after backup, remove it before copying:
`rm -rf "$INSPATH"` after `pkg_backup` returns.

### Service Not Starting

Verify the init system was detected correctly: call `pkg_detect_init` then
inspect `$_PKG_INIT_SYSTEM` (values: `systemd`, `sysv`, `upstart`, `rc.local`).
On systemd hosts, ensure `systemctl daemon-reload` runs after any sed path
replacements in unit files. On SysV hosts, confirm the init script is in
`/etc/rc.d/init.d/` or `/etc/init.d/`.

### Detection Reports Wrong OS

`pkg_detect_os` reads `/etc/os-release` first, then falls back to legacy files
(`/etc/redhat-release`, `/etc/debian_version`, etc.). Inspect the cached
variables after detection: `$_PKG_OS_FAMILY`, `$_PKG_OS_ID`, `$_PKG_OS_VERSION`,
`$_PKG_OS_NAME`. On minimal Docker images that lack `/etc/os-release`, the
fallback chain determines the family. Override detection by setting these
variables before calling any pkg_lib function.

### Symlink Farm Broken

`pkg_fhs_symlink_farm` creates symlinks from `legacy_root/src` pointing to the
FHS `dest` path. If symlinks point to missing targets, verify that `pkg_fhs_install`
ran first to copy files to their FHS destinations. If paths look wrong, check
the `pkg_fhs_register` calls: `src` is relative to the source root, `dest` is
the absolute FHS path. Use `pkg_fhs_symlink_farm_cleanup` to remove a broken
farm before re-creating it.

### Config Merge Loses Values

`pkg_config_merge` uses AWK to merge old values into a new template. It matches
on the variable name before `=` and preserves the old value verbatim. Values
containing unbalanced quotes, literal `=` signs in the value portion, or lines
that do not follow `KEY=VALUE` format are skipped during merge. Comments and
blank lines from the new template are always preserved. If a variable is missing
after merge, verify its key name matches exactly between old and new configs.

### CentOS 6 Failures

The CentOS 6 Docker image is missing `/usr/bin/cp`, which causes failures in
`pkg_copy_tree`, `pkg_backup` (copy method), and service install operations.
This is a test environment limitation, not a library bug. On real CentOS 6
hosts, `/usr/bin/cp` is provided by coreutils. Legacy init fallback
(`sysv`/`chkconfig`) works correctly on CentOS 6 when binaries are present.
