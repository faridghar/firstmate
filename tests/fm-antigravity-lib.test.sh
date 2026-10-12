#!/usr/bin/env bash
# tests/fm-antigravity-lib.test.sh - unit tests for Antigravity executable
# resolution and process identity library (bin/fm-antigravity-lib.sh).
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-antigravity-lib)
LIB="$ROOT/bin/fm-antigravity-lib.sh"

test_resolve_binary_from_path() {
  local fakebin dir got
  dir="$TMP_ROOT/path-resolve"
  fakebin=$(fm_fakebin "$dir/bin")
  touch "$fakebin/agy"
  chmod +x "$fakebin/agy"

  got=$(PATH="$fakebin:$PATH" bash -c ". '$LIB'; fm_antigravity_resolve_binary")
  [ "$got" = "$fakebin/agy" ] || fail "expected '$fakebin/agy', got '$got'"
  pass "fm_antigravity_resolve_binary: resolves agy from PATH"
}

test_resolve_binary_fallback() {
  local fakehome got
  fakehome="$TMP_ROOT/fakehome"
  mkdir -p "$fakehome/.local/bin"
  touch "$fakehome/.local/bin/agy"
  chmod +x "$fakehome/.local/bin/agy"

  got=$(PATH="/bin:/usr/bin" HOME="$fakehome" bash -c ". '$LIB'; fm_antigravity_resolve_binary")
  [ "$got" = "$fakehome/.local/bin/agy" ] || fail "expected '$fakehome/.local/bin/agy', got '$got'"
  pass "fm_antigravity_resolve_binary: resolves agy from ~/.local/bin fallback"
}

test_resolve_binary_fails_cleanly_when_missing() {
  local got status
  got=$(PATH="/dev/null" HOME="$TMP_ROOT/empty" bash -c ". '$LIB'; fm_antigravity_resolve_binary" 2>&1) && status=0 || status=$?
  [ "$status" -ne 0 ] || fail "expected non-zero exit when no agy exists, got $status with output '$got'"
  pass "fm_antigravity_resolve_binary: returns 1 when no executable is found"
}

test_process_matches_exact_and_prefixed() {
  local comm
  for comm in agy agy.exe antigravity antigravity.exe; do
    bash -c ". '$LIB'; fm_antigravity_process_matches '$comm'" \
      || fail "process name '$comm' should match"
    bash -c ". '$LIB'; fm_antigravity_process_matches '' '' '/opt/bin/$comm'" \
      || fail "argv0 '/opt/bin/$comm' should match"
  done

  # Unrelated commands containing fragments must never match
  for comm in agy_helper non_antigravity bagy my_agy_tool; do
    if bash -c ". '$LIB'; fm_antigravity_process_matches '$comm'" 2>/dev/null; then
      fail "unrelated process name '$comm' must not match"
    fi
  done
  pass "fm_antigravity_process_matches: matches agy variants and rejects unrelated names"
}

test_is_active_env_markers() {
  # ANTIGRAVITY_AGENT=1 and AGY_AGENT=1 activate
  env -u FM_TEST_SEAM ANTIGRAVITY_AGENT=1 bash -c ". '$LIB'; fm_antigravity_is_active" \
    || fail "ANTIGRAVITY_AGENT=1 must be active"
  env -u FM_TEST_SEAM AGY_AGENT=1 bash -c ". '$LIB'; fm_antigravity_is_active" \
    || fail "AGY_AGENT=1 must be active"

  # GEMINI_AGENT=1 must NOT activate agy (conflation fix)
  if env -u FM_TEST_SEAM -u ANTIGRAVITY_AGENT -u AGY_AGENT GEMINI_AGENT=1 bash -c ". '$LIB'; fm_antigravity_is_active" 2>/dev/null; then
    fail "GEMINI_AGENT=1 must NOT activate antigravity"
  fi

  # Inactive when unset
  if env -u FM_TEST_SEAM -u ANTIGRAVITY_AGENT -u AGY_AGENT -u GEMINI_AGENT bash -c ". '$LIB'; fm_antigravity_is_active" 2>/dev/null; then
    fail "unconfigured env without markers must be inactive"
  fi

  # FM_TEST_SEAM=1 isolates and returns 1 even when markers exist
  if FM_TEST_SEAM=1 ANTIGRAVITY_AGENT=1 bash -c ". '$LIB'; fm_antigravity_is_active" 2>/dev/null; then
    fail "FM_TEST_SEAM=1 must cause fm_antigravity_is_active to return 1"
  fi
  pass "fm_antigravity_is_active: activated by ANTIGRAVITY_AGENT/AGY_AGENT and rejects GEMINI_AGENT"
}

test_is_active_config_harness() {
  local dir
  dir="$TMP_ROOT/cfg-active"
  mkdir -p "$dir/config"
  printf 'agy\n' > "$dir/config/harness"

  FM_HOME="$dir" CONFIG_AGY="$dir/config" env -u FM_TEST_SEAM -u ANTIGRAVITY_AGENT -u AGY_AGENT \
    bash -c ". '$LIB'; fm_antigravity_is_active" \
    || fail "config/harness naming agy must be active"

  printf 'claude\n' > "$dir/config/harness"
  if FM_HOME="$dir" CONFIG_AGY="$dir/config" env -u FM_TEST_SEAM -u ANTIGRAVITY_AGENT -u AGY_AGENT \
    bash -c ". '$LIB'; fm_antigravity_is_active" 2>/dev/null; then
    fail "config/harness naming claude must not be active"
  fi
  pass "fm_antigravity_is_active: honors config/harness agy setting"
}

test_session_pid_respects_isolation_seams() {
  # TMP_ROOT and FM_TEST_SEAM isolate session PID detection from host processes
  if FM_TEST_SEAM=1 bash -c ". '$LIB'; fm_antigravity_session_pid" 2>/dev/null; then
    fail "FM_TEST_SEAM=1 must cause session_pid to return 1"
  fi
  if TMP_ROOT="$TMP_ROOT" bash -c ". '$LIB'; fm_antigravity_session_pid" 2>/dev/null; then
    fail "TMP_ROOT set must cause session_pid to return 1"
  fi
  pass "fm_antigravity_session_pid: respects test isolation seams"
}

test_session_pid_env_overrides() {
  local got
  got=$(env -u TMP_ROOT -u FM_TEST_SEAM AGY_AGENT=1 ANTIGRAVITY_PID=$$ bash -c ". '$LIB'; fm_antigravity_session_pid")
  [ "$got" = "$$" ] || fail "expected '$$', got '$got'"

  got=$(env -u TMP_ROOT -u FM_TEST_SEAM -u ANTIGRAVITY_PID AGY_AGENT=1 AGY_PID=$$ bash -c ". '$LIB'; fm_antigravity_session_pid")
  [ "$got" = "$$" ] || fail "expected '$$', got '$got'"
  pass "fm_antigravity_session_pid: respects ANTIGRAVITY_PID and AGY_PID overrides"
}

test_session_pid_finds_process_via_pgrep() {
  local dir fakebin got dummy_pid
  dir="$TMP_ROOT/session-pgrep"
  fakebin=$(fm_fakebin "$dir/bin")

  # Start a dummy process so kill -0 succeeds on the mock PID
  sleep 30 &
  dummy_pid=$!

  cat << EOF > "$fakebin/pgrep"
#!/bin/sh
echo "$dummy_pid"
EOF
  chmod +x "$fakebin/pgrep"

  got=$(PATH="$fakebin:$PATH" env -u TMP_ROOT -u FM_TEST_SEAM -u ANTIGRAVITY_PID -u AGY_PID AGY_AGENT=1 \
    bash -c ". '$LIB'; fm_antigravity_session_pid")
  kill "$dummy_pid" 2>/dev/null || true
  wait "$dummy_pid" 2>/dev/null || true

  [ "$got" = "$dummy_pid" ] || fail "expected '$dummy_pid' from mock pgrep, got '$got'"

  # When pgrep finds no process, returns 1
  cat << 'EOF' > "$fakebin/pgrep"
#!/bin/sh
exit 1
EOF
  if PATH="$fakebin:$PATH" env -u TMP_ROOT -u FM_TEST_SEAM -u ANTIGRAVITY_PID -u AGY_PID AGY_AGENT=1 \
    bash -c ". '$LIB'; fm_antigravity_session_pid" 2>/dev/null; then
    fail "empty pgrep must cause fm_antigravity_session_pid to return 1"
  fi
  pass "fm_antigravity_session_pid: correctly finds and returns PID via pgrep"
}

test_resolve_binary_from_path
test_resolve_binary_fallback
test_resolve_binary_fails_cleanly_when_missing
test_process_matches_exact_and_prefixed
test_is_active_env_markers
test_is_active_config_harness
test_session_pid_respects_isolation_seams
test_session_pid_env_overrides
test_session_pid_finds_process_via_pgrep

