#!/usr/bin/env bats
# 09-config.bats — config migration function tests

load helpers/pkg-common

setup() {
	pkg_common_setup

	# Create a sample config file for testing
	MOCK_CONF="${TEST_TMPDIR}/app.conf"
	cat > "$MOCK_CONF" <<'EOF'
# Sample configuration file
# Comment lines are preserved

# Database settings
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="myapp"

# Application settings
LOG_LEVEL="info"
MAX_RETRIES="5"
TIMEOUT="30"
EMPTY_VAR=""
MULTI_WORD="hello world"
UNQUOTED_VAL=simplevalue
EOF
	export MOCK_CONF
}

teardown() {
	pkg_teardown
}

# ── pkg_config_get ────────────────────────────────────────────────

@test "pkg_config_get: reads quoted value" {
	run pkg_config_get "$MOCK_CONF" "DB_HOST"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "localhost" ]]
}

@test "pkg_config_get: reads numeric value" {
	run pkg_config_get "$MOCK_CONF" "DB_PORT"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "5432" ]]
}

@test "pkg_config_get: reads multi-word value" {
	run pkg_config_get "$MOCK_CONF" "MULTI_WORD"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "hello world" ]]
}

@test "pkg_config_get: reads unquoted value" {
	run pkg_config_get "$MOCK_CONF" "UNQUOTED_VAL"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "simplevalue" ]]
}

@test "pkg_config_get: returns empty for empty variable" {
	run pkg_config_get "$MOCK_CONF" "EMPTY_VAR"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "" ]]
}

@test "pkg_config_get: returns 1 for nonexistent variable" {
	run pkg_config_get "$MOCK_CONF" "NONEXISTENT"
	[[ "$status" -eq 1 ]]
}

@test "pkg_config_get: skips commented-out lines" {
	local conf="${TEST_TMPDIR}/skip.conf"
	cat > "$conf" <<'EOF'
# DB_HOST="old_host"
DB_HOST="new_host"
EOF
	run pkg_config_get "$conf" "DB_HOST"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "new_host" ]]
}

@test "pkg_config_get: fails with empty arguments" {
	run pkg_config_get "" "DB_HOST"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_config_get: fails with missing file" {
	run pkg_config_get "${TEST_TMPDIR}/nonexistent" "DB_HOST"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── pkg_config_set ────────────────────────────────────────────────

@test "pkg_config_set: updates existing variable" {
	pkg_config_set "$MOCK_CONF" "DB_HOST" "newhost.example.com"

	run pkg_config_get "$MOCK_CONF" "DB_HOST"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "newhost.example.com" ]]
}

@test "pkg_config_set: appends new variable" {
	pkg_config_set "$MOCK_CONF" "NEW_VAR" "new_value"

	run pkg_config_get "$MOCK_CONF" "NEW_VAR"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "new_value" ]]
}

@test "pkg_config_set: sets empty value" {
	pkg_config_set "$MOCK_CONF" "DB_HOST" ""

	# Variable should exist with empty value
	grep -q '^DB_HOST=""' "$MOCK_CONF"
}

@test "pkg_config_set: sets numeric value" {
	pkg_config_set "$MOCK_CONF" "DB_PORT" "3306"

	run pkg_config_get "$MOCK_CONF" "DB_PORT"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "3306" ]]
}

@test "pkg_config_set: preserves other variables" {
	pkg_config_set "$MOCK_CONF" "DB_HOST" "newhost"

	# DB_PORT should be unchanged
	run pkg_config_get "$MOCK_CONF" "DB_PORT"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "5432" ]]
}

@test "pkg_config_set: preserves comments" {
	pkg_config_set "$MOCK_CONF" "DB_HOST" "newhost"

	# Comments should still be there
	grep -q "^# Sample configuration file" "$MOCK_CONF"
	grep -q "^# Database settings" "$MOCK_CONF"
}

@test "pkg_config_set: fails with empty conf_file" {
	run pkg_config_set "" "DB_HOST" "value"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_config_set: fails with missing file" {
	run pkg_config_set "${TEST_TMPDIR}/nonexistent" "DB_HOST" "value"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_config_set: handles pipe character in value" {
	pkg_config_set "$MOCK_CONF" "DB_HOST" "foo|bar|baz"

	run pkg_config_get "$MOCK_CONF" "DB_HOST"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "foo|bar|baz" ]]
}

# ── pkg_config_merge ──────────────────────────────────────────────

@test "pkg_config_merge: preserves old values for matching variables" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	cat > "$old" <<'EOF'
DB_HOST="myserver.example.com"
DB_PORT="3306"
EOF

	cat > "$new" <<'EOF'
# New config template
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="default"
EOF

	run pkg_config_merge "$old" "$new" "$out"
	[[ "$status" -eq 0 ]]
	[[ -f "$out" ]]

	# Old values should be preserved
	grep -q 'DB_HOST="myserver.example.com"' "$out"
	grep -q 'DB_PORT="3306"' "$out"
	# New variable should have default value
	grep -q 'DB_NAME="default"' "$out"
}

@test "pkg_config_merge: preserves comments from new template" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	echo 'VAR1="oldval"' > "$old"
	cat > "$new" <<'EOF'
# Important comment
VAR1="default"
# Another comment
VAR2="newdefault"
EOF

	pkg_config_merge "$old" "$new" "$out"

	# Comments should be preserved from new template
	grep -q "^# Important comment" "$out"
	grep -q "^# Another comment" "$out"
}

@test "pkg_config_merge: keeps new template ordering" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	cat > "$old" <<'EOF'
ZZVAR="zz"
AAVAR="aa"
EOF

	cat > "$new" <<'EOF'
AAVAR="default_a"
BBVAR="default_b"
ZZVAR="default_z"
EOF

	pkg_config_merge "$old" "$new" "$out"

	# Verify ordering follows new template
	local line_aa line_zz
	line_aa=$(grep -n 'AAVAR=' "$out" | head -1 | cut -d: -f1)
	line_zz=$(grep -n 'ZZVAR=' "$out" | head -1 | cut -d: -f1)
	[[ "$line_aa" -lt "$line_zz" ]]
}

@test "pkg_config_merge: handles empty old config" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	touch "$old"
	cat > "$new" <<'EOF'
VAR1="default1"
VAR2="default2"
EOF

	run pkg_config_merge "$old" "$new" "$out"
	[[ "$status" -eq 0 ]]

	# Should keep all new defaults
	grep -q 'VAR1="default1"' "$out"
	grep -q 'VAR2="default2"' "$out"
}

@test "pkg_config_merge: handles quoted multi-word values" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	echo 'LABEL="my custom label with spaces"' > "$old"
	echo 'LABEL="default"' > "$new"

	pkg_config_merge "$old" "$new" "$out"
	grep -q '"my custom label with spaces"' "$out"
}

@test "pkg_config_merge: creates output directory if missing" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/deep/nested/merged.conf"

	echo 'VAR1="val"' > "$old"
	echo 'VAR1="default"' > "$new"

	run pkg_config_merge "$old" "$new" "$out"
	[[ "$status" -eq 0 ]]
	[[ -f "$out" ]]
}

@test "pkg_config_merge: fails with empty arguments" {
	run pkg_config_merge "" "${TEST_TMPDIR}/new" "${TEST_TMPDIR}/out"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_config_merge: fails with missing old config" {
	local new="${TEST_TMPDIR}/new.conf"
	echo 'VAR="val"' > "$new"

	run pkg_config_merge "${TEST_TMPDIR}/nonexistent" "$new" "${TEST_TMPDIR}/out"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_config_merge: fails with missing new config" {
	local old="${TEST_TMPDIR}/old.conf"
	echo 'VAR="val"' > "$old"

	run pkg_config_merge "$old" "${TEST_TMPDIR}/nonexistent" "${TEST_TMPDIR}/out"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

@test "pkg_config_merge: preserves permissions of template file" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	echo 'VAR1="oldval"' > "$old"
	echo 'VAR1="default"' > "$new"
	chmod 640 "$new"

	pkg_config_merge "$old" "$new" "$out"

	local mode
	mode=$(stat -c '%a' "$out")
	[[ "$mode" = "640" ]]
}

@test "pkg_config_merge: creates output without error when template has default permissions" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged_default.conf"

	echo 'VAR1="oldval"' > "$old"
	echo 'VAR1="default"' > "$new"

	run pkg_config_merge "$old" "$new" "$out"
	[[ "$status" -eq 0 ]]
	[[ -f "$out" ]]
}

@test "pkg_config_merge: preserves empty lines from new template" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	echo 'VAR1="old"' > "$old"
	printf 'VAR1="default"\n\nVAR2="default2"\n' > "$new"

	pkg_config_merge "$old" "$new" "$out"

	# Empty line should be preserved
	local empty_count
	empty_count=$(grep -c '^$' "$out")
	[[ "$empty_count" -ge 1 ]]
}

# ── pkg_config_migrate_var ────────────────────────────────────────

@test "pkg_config_migrate_var: renames variable" {
	pkg_config_migrate_var "$MOCK_CONF" "DB_HOST" "DATABASE_HOST"

	# New variable should exist
	grep -q '^DATABASE_HOST="localhost"' "$MOCK_CONF"
	# Old variable should be commented
	grep -q "^# migrated:" "$MOCK_CONF"
}

@test "pkg_config_migrate_var: no-op when old_var does not exist" {
	local before
	before=$(cat "$MOCK_CONF")

	run pkg_config_migrate_var "$MOCK_CONF" "NONEXISTENT" "NEW_VAR"
	[[ "$status" -eq 0 ]]

	local after
	after=$(cat "$MOCK_CONF")
	[[ "$before" = "$after" ]]
}

@test "pkg_config_migrate_var: comments out old when new already exists" {
	# Add new_var first
	echo 'DATABASE_HOST="already_set"' >> "$MOCK_CONF"

	run pkg_config_migrate_var "$MOCK_CONF" "DB_HOST" "DATABASE_HOST"
	[[ "$status" -eq 0 ]]

	# Old should be commented
	grep -q "migrated to DATABASE_HOST" "$MOCK_CONF"
	# New should be unchanged
	grep -q '^DATABASE_HOST="already_set"' "$MOCK_CONF"
}

@test "pkg_config_migrate_var: applies upper transform" {
	local conf="${TEST_TMPDIR}/transform.conf"
	echo 'OLD_VAR="hello"' > "$conf"

	pkg_config_migrate_var "$conf" "OLD_VAR" "NEW_VAR" "upper"
	grep -q 'NEW_VAR="HELLO"' "$conf"
}

@test "pkg_config_migrate_var: applies lower transform" {
	local conf="${TEST_TMPDIR}/transform.conf"
	echo 'OLD_VAR="HELLO"' > "$conf"

	pkg_config_migrate_var "$conf" "OLD_VAR" "NEW_VAR" "lower"
	grep -q 'NEW_VAR="hello"' "$conf"
}

@test "pkg_config_migrate_var: handles unknown transform gracefully" {
	local conf="${TEST_TMPDIR}/transform.conf"
	echo 'OLD_VAR="hello"' > "$conf"

	run pkg_config_migrate_var "$conf" "OLD_VAR" "NEW_VAR" "bogus"
	[[ "$status" -eq 0 ]]
	# Should use original value (no transform applied)
	grep -q 'NEW_VAR="hello"' "$conf"
}

@test "pkg_config_migrate_var: fails with empty arguments" {
	run pkg_config_migrate_var "" "OLD" "NEW"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_config_migrate_var: fails with missing file" {
	run pkg_config_migrate_var "${TEST_TMPDIR}/nonexistent" "OLD" "NEW"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── pkg_config_clamp ─────────────────────────────────────────────

@test "pkg_config_clamp: clamps value exceeding max" {
	pkg_config_clamp "$MOCK_CONF" "TIMEOUT" "10"

	run pkg_config_get "$MOCK_CONF" "TIMEOUT"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "10" ]]
}

@test "pkg_config_clamp: no-op when value within range" {
	pkg_config_clamp "$MOCK_CONF" "TIMEOUT" "100"

	run pkg_config_get "$MOCK_CONF" "TIMEOUT"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "30" ]]
}

@test "pkg_config_clamp: no-op when value equals max" {
	pkg_config_clamp "$MOCK_CONF" "TIMEOUT" "30"

	run pkg_config_get "$MOCK_CONF" "TIMEOUT"
	[[ "$status" -eq 0 ]]
	[[ "$output" = "30" ]]
}

@test "pkg_config_clamp: no-op for nonexistent variable" {
	run pkg_config_clamp "$MOCK_CONF" "NONEXISTENT" "10"
	[[ "$status" -eq 0 ]]
}

@test "pkg_config_clamp: no-op for non-numeric value" {
	run pkg_config_clamp "$MOCK_CONF" "LOG_LEVEL" "10"
	[[ "$status" -eq 0 ]]

	# LOG_LEVEL should be unchanged
	run pkg_config_get "$MOCK_CONF" "LOG_LEVEL"
	[[ "$output" = "info" ]]
}

@test "pkg_config_clamp: uses custom warning message" {
	run pkg_config_clamp "$MOCK_CONF" "TIMEOUT" "10" "TIMEOUT too high, clamping"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"TIMEOUT too high"* ]]
}

@test "pkg_config_clamp: uses default warning when no message" {
	run pkg_config_clamp "$MOCK_CONF" "TIMEOUT" "10"
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"clamped from 30 to 10"* ]]
}

@test "pkg_config_clamp: fails with non-integer max_val" {
	run pkg_config_clamp "$MOCK_CONF" "TIMEOUT" "abc"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"positive integer"* ]]
}

@test "pkg_config_clamp: fails with empty arguments" {
	run pkg_config_clamp "" "TIMEOUT" "10"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"required"* ]]
}

@test "pkg_config_clamp: fails with missing file" {
	run pkg_config_clamp "${TEST_TMPDIR}/nonexistent" "TIMEOUT" "10"
	[[ "$status" -eq 1 ]]
	[[ "$output" == *"not found"* ]]
}

# ── Integration: merge + migrate + clamp ──────────────────────────

@test "config integration: merge then migrate variable" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	cat > "$old" <<'EOF'
OLD_PORT="8080"
DB_NAME="mydb"
EOF

	cat > "$new" <<'EOF'
# New config
DB_NAME="default"
LISTEN_ADDR="0.0.0.0"
EOF

	# Merge: OLD_PORT not in new template, DB_NAME carried from old
	pkg_config_merge "$old" "$new" "$out"

	# Consumer appends OLD_PORT from old config (not in new template)
	echo 'OLD_PORT="8080"' >> "$out"

	# Migrate OLD_PORT -> NEW_PORT (NEW_PORT not yet in merged output)
	pkg_config_migrate_var "$out" "OLD_PORT" "NEW_PORT"

	# Verify migration happened — NEW_PORT should have old value
	grep -q 'NEW_PORT="8080"' "$out"
	# Old var should be commented out
	grep -q "^# migrated:" "$out"
}

@test "config integration: merge then clamp value" {
	local old="${TEST_TMPDIR}/old.conf"
	local new="${TEST_TMPDIR}/new.conf"
	local out="${TEST_TMPDIR}/merged.conf"

	cat > "$old" <<'EOF'
TIMEOUT="999"
EOF

	cat > "$new" <<'EOF'
TIMEOUT="30"
MAX_SIZE="100"
EOF

	pkg_config_merge "$old" "$new" "$out"
	# Old value (999) should be preserved
	grep -q 'TIMEOUT="999"' "$out" || grep -q 'TIMEOUT=999' "$out"

	# Clamp it
	pkg_config_clamp "$out" "TIMEOUT" "60"

	run pkg_config_get "$out" "TIMEOUT"
	[[ "$output" = "60" ]]
}
