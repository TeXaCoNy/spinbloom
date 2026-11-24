#!/usr/bin/env bash
# Every test Spinbloom has. Exit code 0 only if all pass.
set -uo pipefail
cd "$(dirname "$0")/.."

# ---------------------------------------------------------------- test isolation
# A test run once deleted the owner's LIVE Spinbloom data dir (the Chromium
# profile with the sign-in) because the suite inherited the real HOME/
# XDG_DATA_HOME and a bridge code path (the orphan-lease wipe) computed its
# delete target from those. Every test process below runs under a throwaway
# HOME/XDG_*/SPINBLOOM_* instead, plus SPINBLOOM_TEST=1 (the marker bin/spinbloom-engine's
# delete/rename helpers refuse to touch a real dir under, independent of any
# of this). XDG_RUNTIME_DIR/WAYLAND_DISPLAY are left alone: the QML scene
# tests need the real Wayland/Hyprland session.
REAL_HOME="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6)"
REAL_HOME="${REAL_HOME:-$HOME}"
BASE_TMP="${CLAUDE_SCRATCHPAD_DIR:-${TMPDIR:-/tmp}}"
SPINBLOOM_TEST_ENV_ROOT="$(mktemp -d "$BASE_TMP/spinbloom-testenv-XXXXXX")"
export SPINBLOOM_TEST_ENV_ROOT
export HOME="$SPINBLOOM_TEST_ENV_ROOT/home"
export XDG_DATA_HOME="$SPINBLOOM_TEST_ENV_ROOT/data"
export XDG_CACHE_HOME="$SPINBLOOM_TEST_ENV_ROOT/cache"
export XDG_CONFIG_HOME="$SPINBLOOM_TEST_ENV_ROOT/config"
export XDG_STATE_HOME="$SPINBLOOM_TEST_ENV_ROOT/state"
export SPINBLOOM_RUNTIME_DIR="$SPINBLOOM_TEST_ENV_ROOT/runtime/spinbloom"
export SPINBLOOM_PROFILE_DIR="$SPINBLOOM_TEST_ENV_ROOT/profile/engine"
# SPINBLOOM_CACHE_DIR is deliberately left unset here (not exported): several
# tests isolate it themselves via XDG_CACHE_HOME and expect SPINBLOOM_CACHE_DIR
# to fall through to that default, not be pinned ambiently for the whole
# suite. It is still part of the hard-verify check below, if anything sets it.
export SPINBLOOM_TEST=1
mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
         "$SPINBLOOM_RUNTIME_DIR" "$SPINBLOOM_PROFILE_DIR"

# Hard verify: refuse to run a single test if any of the above (or the real
# per-user dirs it must never touch) overlap - computed from the OS's real
# home (getent), never from $HOME itself, so this cannot be fooled by only
# $HOME being wrong.
path_overlaps() {  # $1 candidate, $2 forbidden
  [ "$1" = "$2" ] && return 0
  case "$1/" in "$2"/*) return 0;; esac
  case "$2/" in "$1"/*) return 0;; esac
  return 1
}
for id in spinbloom serallap.spinbloom; do
  for forbidden in "$REAL_HOME/.local/share/$id" "$REAL_HOME/.cache/$id" "$REAL_HOME/.local/state/$id" "/run/user/$(id -u)/$id" "$REAL_HOME/.config/omarchy"; do
    for candidate in "$HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" \
                      "$SPINBLOOM_RUNTIME_DIR" "$SPINBLOOM_PROFILE_DIR" "${SPINBLOOM_CACHE_DIR:-}"; do
      [ -z "$candidate" ] && continue
      if path_overlaps "$candidate" "$forbidden"; then
        echo "REFUSED: $candidate resolves against the real $forbidden - aborting before any test ran." >&2
        rm -rf "$SPINBLOOM_TEST_ENV_ROOT"
        exit 1
      fi
    done
  done
done
cleanup() { rm -rf "$SPINBLOOM_TEST_ENV_ROOT"; }
trap cleanup EXIT

failed=()
run() {
  local name="$1"; shift
  echo "== $name"
  if "$@"; then echo "== $name: ok"; else echo "== $name: FAILED"; failed+=("$name"); fi
}
run parse node --test tests/parse.test.cjs
run agent node --test tests/agent.test.cjs
run model node --test tests/model.test.cjs
run bridge python3 tests/test_bridge.py
run paths python3 tests/test_paths.py
run qml bash tests/lint-qml.sh
run render python3 tests/test_render.py
run hit-targets python3 tests/test_hit_targets.py
run bridge-socket python3 tests/test_bridge_socket.py
run closed python3 tests/test_closed.py
run settings python3 tests/test_settings.py
run account-state python3 tests/test_account_state.py
run signin-card python3 tests/test_signin_card.py
run panel-settings python3 tests/test_panel_settings.py
run widget-move python3 tests/test_widget_move.py
run signin-bridge-down python3 tests/test_signin_bridge_down.py
run queue-more python3 tests/test_queue_more.py
if command -v omarchy >/dev/null 2>&1; then run manifest omarchy plugin validate .; fi
echo "spinbloom in /run/user leftovers: $(ls "/run/user/$(id -u)" 2>/dev/null | grep -c spinbloom || true)"
if ((${#failed[@]})); then echo "FAILED: ${failed[*]}"; exit 1; fi
echo "ALL PASSED"
