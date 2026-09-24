#!/bin/bash
# Release-owned paths only; never traverse or replace business state.
fusion_validate_release() {
  local dir="$1" file version
  for file in fusion.sh install.sh version.txt src/init.sh src/lib/common.sh src/lib/deploy.sh configs/config.yaml; do
    [[ -s "$dir/$file" && ! -L "$dir/$file" ]] || return 1
  done
  for file in proxy system network web panels market warp workspace cluster; do
    [[ -s "$dir/src/modules/$file.sh" ]] || return 1
  done
  for file in src templates configs; do
    [[ -d "$dir/$file" && ! -L "$dir/$file" ]] || return 1
    [[ -z "$(find "$dir/$file" ! -type d ! -type f -print)" ]] || return 1
  done
  version=$(tr -d '[:space:]' < "$dir/version.txt") || return 1
  [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  IFS= read -r file < "$dir/fusion.sh"
  [[ "$file" == '#!/bin/bash' ]] || return 1
  while IFS= read -r -d '' file; do
    bash -n "$file" || return 1
  done < <(find "$dir/src" "$dir/fusion.sh" "$dir/install.sh" -name '*.sh' -type f -print0)
}

# Ownership is established by link identity, never by executing the command.
fusion_owned_command() {
  [[ -L "$1" && "$(readlink -m -- "$1")" == "$2/fusion.sh" ]]
}

# Subshell traps are private to this transaction. Every operation is checked:
# callers may invoke this function in an if/&& context where errexit is disabled.
fusion_deploy() (
  local source="$1" base="$2" bin="${3:-}" txn='' lock='' committed=0
  local item i failed=0 bin_active=0 bin_stage='' config_new=0 config_stage='' bin_owned=0
  local -a paths=(src templates fusion.sh install.sh version.txt) saved=() active=()
  fusion_validate_release "$source" || { printf '%s\n' 'Invalid release' >&2; exit 1; }
  mkdir -p -- "$base" || exit 1
  base=$(cd "$base" && pwd -P) || exit 1
  umask 077
  lock="$base/.fusionbox-install.lock"
  mkdir -- "$lock" || { printf '%s\n' 'Deployment locked; inspect prior transaction before retrying' >&2; exit 1; }
  cleanup() {
    local rc=$?
    trap - EXIT HUP INT TERM
    if [[ $committed == 0 && -n "$txn" ]]; then
      if [[ $bin_active == 1 ]]; then mv -T -- "$bin" "$bin_stage/new" || failed=1; fi
      if [[ $config_new == 1 ]]; then rm -f -- "$HOME/.config/fusionbox/config.yaml" || failed=1; fi
      for ((i=${#active[@]}-1; i>=0; i--)); do
        item=${active[i]}
        mv -T -- "$base/$item" "$txn/new/$item" || failed=1
      done
      for ((i=${#saved[@]}-1; i>=0; i--)); do
        item=${saved[i]}
        mv -T -- "$txn/old/$item" "$base/$item" || failed=1
      done
    fi
    if [[ $failed == 1 ]]; then
      printf 'Rollback incomplete; recovery: %s %s (lock retained)\n' "$txn" "$bin_stage" >&2
      exit 1
    fi
    [[ -z "$bin_stage" ]] || rm -rf -- "$bin_stage"
    [[ -z "$config_stage" ]] || rm -rf -- "$config_stage"
    # Keep previous code as a recovery backup, never blanket-delete the base.
    if [[ $committed == 1 && ${#saved[@]} -gt 0 ]]; then
      printf 'Previous code retained: %s\n' "$txn"
    elif [[ -n "$txn" ]]; then
      rm -rf -- "$txn"
    fi
    rmdir -- "$lock"
    exit "$rc"
  }
  trap cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  txn=$(mktemp -d "$base/.fusionbox-backup.XXXXXXXX") || exit 1
  mkdir "$txn/new" "$txn/old" || exit 1
  # Existing config, including symlinks, is user-owned.
  if [[ ! -e "$base/configs" && ! -L "$base/configs" ]]; then paths+=(configs); fi
  for item in "${paths[@]}"; do
    [[ ! -L "$base/$item" ]] || { printf 'Refusing managed symlink: %s\n' "$base/$item" >&2; exit 1; }
    cp -a -- "$source/$item" "$txn/new/$item" || exit 1
  done
  if [[ ! -d "$txn/new/configs" ]]; then cp -a -- "$source/configs" "$txn/new/configs" || exit 1; fi
  fusion_validate_release "$txn/new" || exit 1
  find "$txn/new/src" "$txn/new/templates" -type d -exec chmod 755 {} + || exit 1
  find "$txn/new/src" "$txn/new/templates" -type f -exec chmod 644 {} + || exit 1
  chmod 755 "$txn/new/fusion.sh" "$txn/new/install.sh" || exit 1
  if [[ -n "$bin" ]]; then
    if [[ -e "$bin" || -L "$bin" ]]; then
      fusion_owned_command "$bin" "$base" || {
        printf 'Refusing unrelated command: %s\n' "$bin" >&2
        exit 1
      }
      # An owned link already targets the activation path; keep it verbatim.
      bin_owned=1
    fi
    mkdir -p -- "$(dirname "$bin")" || exit 1
    bin_stage=$(mktemp -d "$(dirname "$bin")/.fusionbox-bin.XXXXXXXX") || exit 1
    ln -s -- "$base/fusion.sh" "$bin_stage/new" || exit 1
  fi
  # Only the installer seeds defaults. Existing user files/links are untouched.
  if [[ -n "$bin" && ! -e "$HOME/.config/fusionbox/config.yaml" && ! -L "$HOME/.config/fusionbox/config.yaml" ]]; then
    mkdir -p -- "$HOME/.config/fusionbox" || exit 1
    config_stage=$(mktemp -d "$HOME/.config/fusionbox/.install.XXXXXXXX") || exit 1
    cp -- "$source/configs/config.yaml" "$config_stage/default" || exit 1
    # Hard-link creation fails rather than replacing a concurrently created file.
    chmod 600 "$config_stage/default" || exit 1
    command ln -- "$config_stage/default" "$HOME/.config/fusionbox/config.yaml" || exit 1
    config_new=1
  fi
  for item in "${paths[@]}"; do
    if [[ -e "$base/$item" ]]; then
      mv -T -- "$base/$item" "$txn/old/$item" || exit 1
      saved+=("$item")
    fi
    mv -T -- "$txn/new/$item" "$base/$item" || exit 1
    active+=("$item")
  done
  if [[ -n "$bin" && $bin_owned == 0 ]]; then
    [[ ! -e "$bin" && ! -L "$bin" ]] || exit 1
    mv -T -- "$bin_stage/new" "$bin" || exit 1
    bin_active=1
  elif [[ -n "$bin" ]]; then
    fusion_owned_command "$bin" "$base" || exit 1
  fi
  committed=1

  # 快捷命令：fb / FB 与 fusionbox 一样是指向 fusion.sh 的软链接，装完即可直接敲。
  # 已存在但不是本脚本建的链接一律不动；这一步在提交之后执行，失败也不影响部署结果。
  local alias_bin alias_dir alias_link alias_target
  alias_bin="${bin:-/usr/local/bin/fusionbox}"
  alias_dir="$(dirname "$alias_bin")"
  for alias_link in fb FB; do
    alias_target="$alias_dir/$alias_link"
    if [[ -e "$alias_target" || -L "$alias_target" ]]; then
      if [[ -L "$alias_target" && "$(readlink -m -- "$alias_target")" == "$base/fusion.sh" ]]; then
        continue
      fi
      printf 'Shortcut left untouched (not created by FusionBox): %s
' "$alias_target" >&2
      continue
    fi
    ln -s -- "$base/fusion.sh" "$alias_target" || true
  done
)
