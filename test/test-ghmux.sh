#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
bin_path="$repo_root/bin/ghmux"
credential_bin_path="$repo_root/bin/git-credential-ghmux"

fail() {
  printf 'not ok - %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$message"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$message"
  fi
}

make_stub_gh() {
  local path="$1"

  mkdir -p -- "$(dirname -- "$path")"
  printf '%s\n' '#!/usr/bin/env bash' > "$path"
  printf '%s\n' 'set -euo pipefail' >> "$path"
  printf '%s\n' 'if [[ "${1:-}" == "auth" && "${2:-}" == "token" ]]; then' >> "$path"
  printf '%s\n' '  shift 2' >> "$path"
  printf '%s\n' '  host=""' >> "$path"
  printf '%s\n' '  user=""' >> "$path"
  printf '%s\n' '  while (($#)); do' >> "$path"
  printf '%s\n' '    case "$1" in' >> "$path"
  printf '%s\n' '      --hostname)' >> "$path"
  printf '%s\n' '        host="$2"' >> "$path"
  printf '%s\n' '        shift 2' >> "$path"
  printf '%s\n' '        ;;' >> "$path"
  printf '%s\n' '      --user)' >> "$path"
  printf '%s\n' '        user="$2"' >> "$path"
  printf '%s\n' '        shift 2' >> "$path"
  printf '%s\n' '        ;;' >> "$path"
  printf '%s\n' '      *)' >> "$path"
  printf '%s\n' '        shift' >> "$path"
  printf '%s\n' '        ;;' >> "$path"
  printf '%s\n' '    esac' >> "$path"
  printf '%s\n' '  done' >> "$path"
  printf '%s\n' '  printf "TOKEN:%s:%s\n" "$host" "$user"' >> "$path"
  printf '%s\n' '  exit 0' >> "$path"
  printf '%s\n' 'fi' >> "$path"
  printf '%s\n' 'env | sort' >> "$path"
  chmod +x "$path"
}

make_stub_real_gh() {
  local path="$1"
  local active_user="${2:-default-user}"

  mkdir -p -- "$(dirname -- "$path")"
  printf '%s\n' '#!/usr/bin/env bash' > "$path"
  printf '%s\n' 'set -euo pipefail' >> "$path"
  printf '%s\n' "active_user='$active_user'" >> "$path"
  printf '%s\n' 'if [[ "${1:-}" == "auth" && "${2:-}" == "token" ]]; then' >> "$path"
  printf '%s\n' '  shift 2' >> "$path"
  printf '%s\n' '  host=""' >> "$path"
  printf '%s\n' '  user=""' >> "$path"
  printf '%s\n' '  while (($#)); do' >> "$path"
  printf '%s\n' '    case "$1" in' >> "$path"
  printf '%s\n' '      --hostname)' >> "$path"
  printf '%s\n' '        host="$2"' >> "$path"
  printf '%s\n' '        shift 2' >> "$path"
  printf '%s\n' '        ;;' >> "$path"
  printf '%s\n' '      --user)' >> "$path"
  printf '%s\n' '        user="$2"' >> "$path"
  printf '%s\n' '        shift 2' >> "$path"
  printf '%s\n' '        ;;' >> "$path"
  printf '%s\n' '      *)' >> "$path"
  printf '%s\n' '        shift' >> "$path"
  printf '%s\n' '        ;;' >> "$path"
  printf '%s\n' '    esac' >> "$path"
  printf '%s\n' '  done' >> "$path"
  printf '%s\n' '  printf "TOKEN:%s:%s\n" "$host" "$user"' >> "$path"
  printf '%s\n' '  exit 0' >> "$path"
  printf '%s\n' 'fi' >> "$path"
  printf '%s\n' 'if [[ "${1:-}" == "auth" && "${2:-}" == "git-credential" ]]; then' >> "$path"
  printf '%s\n' '  while IFS= read -r line; do' >> "$path"
  printf '%s\n' '    [[ -z "$line" ]] && break' >> "$path"
  printf '%s\n' '  done' >> "$path"
  printf '%s\n' '  printf "username=%s\n" "$active_user"' >> "$path"
  printf '%s\n' '  printf "password=DEFAULT:%s\n" "$active_user"' >> "$path"
  printf '%s\n' '  exit 0' >> "$path"
  printf '%s\n' 'fi' >> "$path"
  printf '%s\n' 'env | sort' >> "$path"
  chmod +x "$path"
}

write_config() {
  local config_path="$1"
  shift

  mkdir -p -- "$(dirname -- "$config_path")"
  : > "$config_path"
  printf '%s\n' '#!/usr/bin/env bash' >> "$config_path"
  printf '%s\n' 'GHMUX_DEFAULT_HOST=github.com' >> "$config_path"
  printf '%s\n' 'GHMUX_DEFAULT_USER=' >> "$config_path"
  printf '%s\n' 'GHMUX_RULES=(' >> "$config_path"
  while (($#)); do
    printf "  '%s'\n" "$1" >> "$config_path"
    shift
  done
  printf '%s\n' ')' >> "$config_path"
}

test_passthrough_without_matching_rule() {
  local tmp
  local stub
  local output

  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  stub="$tmp/stub-gh"
  make_stub_gh "$stub"

  mkdir -p "$tmp/outside"
  output=$(cd "$tmp/outside" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" GHMUX_REAL_GH="$stub" "$bin_path")

  assert_contains "$output" "GHMUX_ACTIVE_USER=" "expected empty active user for passthrough"
  assert_contains "$output" "GHMUX_ACTIVE_HOST=" "expected empty active host for passthrough"
  assert_not_contains "$output" "GH_TOKEN=" "did not expect token injection in passthrough mode"
  pass "passthrough without matching rule"
}

test_matching_rule_injects_token() {
  local tmp
  local stub
  local config
  local worktree
  local output

  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  stub="$tmp/stub-gh"
  config="$tmp/xdg/ghmux/config.sh"
  worktree="$tmp/work/project"

  make_stub_gh "$stub"
  write_config "$config" "$tmp/work|github.com|alice"
  mkdir -p "$worktree"

  output=$(cd "$worktree" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" GHMUX_REAL_GH="$stub" "$bin_path")

  assert_contains "$output" "GHMUX_ACTIVE_USER=alice" "expected routed user"
  assert_contains "$output" "GHMUX_ACTIVE_HOST=github.com" "expected routed host"
  assert_contains "$output" "GH_TOKEN=TOKEN:github.com:alice" "expected injected gh token"
  assert_contains "$output" "GITHUB_TOKEN=TOKEN:github.com:alice" "expected injected github token"
  pass "matching rule injects token"
}

test_longest_prefix_wins() {
  local tmp
  local stub
  local config
  local worktree
  local output

  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  stub="$tmp/stub-gh"
  config="$tmp/xdg/ghmux/config.sh"
  worktree="$tmp/work/client/nested/repo"

  make_stub_gh "$stub"
  write_config "$config" \
    "$tmp/work|github.com|alice" \
    "$tmp/work/client|github.com|bob"
  mkdir -p "$worktree"

  output=$(cd "$worktree" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" GHMUX_REAL_GH="$stub" "$bin_path")

  assert_contains "$output" "GHMUX_ACTIVE_PREFIX=$tmp/work/client" "expected longest matching prefix"
  assert_contains "$output" "GHMUX_ACTIVE_USER=bob" "expected longest-prefix user"
  assert_contains "$output" "GH_TOKEN=TOKEN:github.com:bob" "expected longest-prefix token"
  pass "longest prefix wins"
}

test_auth_login_blocked_in_routed_context() {
  local tmp
  local stub
  local config
  local worktree
  local output

  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  stub="$tmp/stub-gh"
  config="$tmp/xdg/ghmux/config.sh"
  worktree="$tmp/work/repo"

  make_stub_gh "$stub"
  write_config "$config" "$tmp/work|github.com|alice"
  mkdir -p "$worktree"

  if output=$(cd "$worktree" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" GHMUX_REAL_GH="$stub" "$bin_path" auth login 2>&1); then
    fail "expected gh auth login to be blocked in routed context"
  fi

  assert_contains "$output" "refusing 'gh auth login' inside a routed context" "expected guardrail error"
  pass "auth login blocked in routed context"
}

test_git_credential_helper_passthrough_without_matching_rule() {
  local tmp
  local stub
  local output

  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  stub="$tmp/stub-gh"

  make_stub_real_gh "$stub" "default-user"
  mkdir -p "$tmp/outside"

  output=$(cd "$tmp/outside" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" GHMUX_REAL_GH="$stub" \
    bash -lc "printf 'protocol=https\nhost=github.com\n\n' | '$credential_bin_path' get")

  if [[ -n "$output" ]]; then
    fail "expected no credentials when no ghmux rule matches"
  fi
  pass "git credential helper passthrough without matching rule"
}

test_git_credential_helper_returns_routed_credentials() {
  local tmp
  local stub
  local config
  local worktree
  local output

  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  stub="$tmp/stub-gh"
  config="$tmp/xdg/ghmux/config.sh"
  worktree="$tmp/work/project"

  make_stub_real_gh "$stub" "default-user"
  write_config "$config" "$tmp/work|github.com|alice"
  mkdir -p "$worktree"

  output=$(cd "$worktree" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/xdg" GHMUX_REAL_GH="$stub" \
    bash -lc "printf 'protocol=https\nhost=github.com\n\n' | '$credential_bin_path' get")

  assert_contains "$output" "username=x-access-token" "expected access token username in credential helper response"
  assert_contains "$output" "password=TOKEN:github.com:alice" "expected routed token in credential helper response"
  pass "git credential helper returns routed credentials"
}

bash -n "$bin_path" "$credential_bin_path" "$repo_root/lib/ghmux.sh"
test_passthrough_without_matching_rule
test_matching_rule_injects_token
test_longest_prefix_wins
test_auth_login_blocked_in_routed_context
test_git_credential_helper_passthrough_without_matching_rule
test_git_credential_helper_returns_routed_credentials
