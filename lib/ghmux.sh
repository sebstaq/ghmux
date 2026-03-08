#!/usr/bin/env bash

ghmux_die() {
  printf 'ghmux: %s\n' "$*" >&2
  exit 1
}

ghmux_debug_enabled() {
  case "${GHMUX_DEBUG:-0}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ghmux_log() {
  if ghmux_debug_enabled; then
    printf 'ghmux: %s\n' "$*" >&2
  fi
}

ghmux_normalize_path() {
  realpath -m -- "$1"
}

ghmux_current_cwd() {
  pwd -P
}

ghmux_path_has_prefix() {
  local path="$1"
  local prefix="$2"

  case "$path" in
    "$prefix"|"$prefix"/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ghmux_default_config_file() {
  if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
    printf '%s/ghmux/config.sh\n' "$XDG_CONFIG_HOME"
    return 0
  fi

  printf '%s/.config/ghmux/config.sh\n' "$HOME"
}

ghmux_config_file() {
  printf '%s\n' "${GHMUX_CONFIG:-$(ghmux_default_config_file)}"
}

ghmux_reset_config() {
  GHMUX_DEFAULT_HOST=github.com
  GHMUX_DEFAULT_USER=
  GHMUX_RULES=()
}

ghmux_load_config() {
  if [[ "${GHMUX_CONFIG_LOADED:-0}" == "1" ]]; then
    return 0
  fi

  ghmux_reset_config

  local config_file
  config_file=$(ghmux_config_file)
  if [[ -f "$config_file" ]]; then
    # shellcheck source=/dev/null
    source "$config_file"
  fi

  GHMUX_CONFIG_LOADED=1
}

ghmux_real_gh_path() {
  printf '%s\n' "${GHMUX_REAL_GH:-}"
}

ghmux_resolve_real_gh() {
  local configured_path
  configured_path=$(ghmux_real_gh_path)

  if [[ -n "$configured_path" ]]; then
    printf '%s\n' "$configured_path"
    return 0
  fi

  local self_real=""
  local candidate=""
  local candidate_real=""

  if [[ -n "${GHMUX_SELF_PATH:-}" ]]; then
    self_real=$(realpath -m -- "$GHMUX_SELF_PATH")
  fi

  while IFS= read -r candidate; do
    [[ -z "$candidate" ]] && continue
    candidate_real=$(realpath -m -- "$candidate")

    if [[ -n "$self_real" && "$candidate_real" == "$self_real" ]]; then
      continue
    fi

    printf '%s\n' "$candidate"
    return 0
  done < <(type -aP gh 2>/dev/null || true)

  if [[ -x /usr/bin/gh ]]; then
    printf '%s\n' /usr/bin/gh
    return 0
  fi

  ghmux_die "unable to locate the real gh binary"
}

ghmux_default_route() {
  ghmux_load_config

  if [[ -n "$GHMUX_DEFAULT_USER" ]]; then
    printf '|%s|%s\n' "$GHMUX_DEFAULT_HOST" "$GHMUX_DEFAULT_USER"
    return 0
  fi

  printf '||\n'
}

ghmux_select_route() {
  local cwd="$1"
  ghmux_load_config

  local best_prefix=""
  local best_host=""
  local best_user=""
  local rule=""
  local prefix=""
  local host=""
  local user=""
  local normalized_prefix=""

  for rule in "${GHMUX_RULES[@]}"; do
    IFS='|' read -r prefix host user <<< "$rule"
    [[ -z "$prefix" ]] && continue

    normalized_prefix=$(ghmux_normalize_path "$prefix")
    if ! ghmux_path_has_prefix "$cwd" "$normalized_prefix"; then
      continue
    fi

    if (( ${#normalized_prefix} > ${#best_prefix} )); then
      best_prefix="$normalized_prefix"
      best_host="${host:-github.com}"
      best_user="$user"
    fi
  done

  if [[ -n "$best_prefix" ]]; then
    printf '%s|%s|%s\n' "$best_prefix" "$best_host" "$best_user"
    return 0
  fi

  ghmux_default_route
}

ghmux_current_route() {
  local cwd
  cwd=$(ghmux_current_cwd)
  ghmux_select_route "$cwd"
}

ghmux_fetch_token() {
  local real_gh="$1"
  local host="$2"
  local user="$3"

  env -u GH_TOKEN -u GITHUB_TOKEN -u GH_CONFIG_DIR -u GH_HOST \
    "$real_gh" auth token --hostname "$host" --user "$user" 2>/dev/null
}

ghmux_apply_route_env() {
  local real_gh="$1"
  local host="$2"
  local user="$3"

  if [[ -z "$user" ]]; then
    unset GH_TOKEN
    unset GITHUB_TOKEN
    unset GH_CONFIG_DIR
    return 0
  fi

  local token
  token=$(ghmux_fetch_token "$real_gh" "$host" "$user")

  if [[ -z "$token" ]]; then
    ghmux_die "unable to resolve token for user '$user' on host '$host'"
  fi

  export GH_TOKEN="$token"
  export GITHUB_TOKEN="$token"
  unset GH_CONFIG_DIR
}

ghmux_route_credentials() {
  local real_gh="$1"
  local route="$2"
  local route_prefix=""
  local route_host=""
  local route_user=""
  local token=""

  IFS='|' read -r route_prefix route_host route_user <<< "$route"

  if [[ -z "$route_user" ]]; then
    return 0
  fi

  token=$(ghmux_fetch_token "$real_gh" "$route_host" "$route_user")
  if [[ -z "$token" ]]; then
    ghmux_die "unable to resolve token for user '$route_user' on host '$route_host'"
  fi

  printf 'username=x-access-token\n'
  printf 'password=%s\n' "$token"
}

ghmux_guard_auth_command() {
  local routed_user="$1"
  shift

  if [[ -z "$routed_user" || $# -lt 2 ]]; then
    return 0
  fi

  if [[ "$1" != "auth" ]]; then
    return 0
  fi

  case "$2" in
    login|logout|switch)
      ghmux_die "refusing 'gh auth $2' inside a routed context; use GHMUX_BYPASS=1 gh auth $2 or run the real gh binary directly"
      ;;
  esac
}

ghmux_main() {
  local cwd
  local route
  local route_prefix
  local route_host
  local route_user
  local real_gh

  if [[ "${GHMUX_BYPASS:-0}" == "1" ]]; then
    real_gh=$(ghmux_resolve_real_gh)
    exec "$real_gh" "$@"
  fi

  cwd=$(ghmux_current_cwd)
  route=$(ghmux_select_route "$cwd")
  IFS='|' read -r route_prefix route_host route_user <<< "$route"
  real_gh=$(ghmux_resolve_real_gh)

  ghmux_guard_auth_command "$route_user" "$@"
  ghmux_apply_route_env "$real_gh" "$route_host" "$route_user"

  export GHMUX_ACTIVE_CWD="$cwd"
  export GHMUX_ACTIVE_PREFIX="$route_prefix"
  export GHMUX_ACTIVE_HOST="$route_host"
  export GHMUX_ACTIVE_USER="$route_user"

  ghmux_log "cwd=$cwd"
  ghmux_log "prefix=$route_prefix"
  ghmux_log "host=$route_host"
  ghmux_log "user=$route_user"
  ghmux_log "real_gh=$real_gh"

  exec "$real_gh" "$@"
}

ghmux_read_credential_request() {
  local line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && break
  done
  return 0
}

ghmux_git_credential_main() {
  local operation="${1:-get}"
  local route
  local real_gh
  local route_prefix=""
  local route_host=""
  local route_user=""

  ghmux_read_credential_request

  case "$operation" in
    get|fill)
      route=$(ghmux_current_route)
      IFS='|' read -r route_prefix route_host route_user <<< "$route"
      real_gh=$(ghmux_resolve_real_gh)

      ghmux_log "credential prefix=$route_prefix"
      ghmux_log "credential host=$route_host"
      ghmux_log "credential user=$route_user"
      ghmux_log "credential real_gh=$real_gh"

      ghmux_route_credentials "$real_gh" "$route"
      ;;
    store|approve|erase|reject)
      return 0
      ;;
    *)
      ghmux_die "unsupported git credential operation '$operation'"
      ;;
  esac
}
