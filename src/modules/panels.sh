# FusionBox Panels & Docker Management Module
# Docker, server panels, and utility tools

# ---- Chinese help for raw Python passthrough subcommands ----
# Without these, running the subcommand with no arguments exposed an English
# argparse usage dump. Mirrors the existing ssh-candidate behaviour.

panels_compose_backup_help() {
  msg_title "$(L MSG_PANEL_0001)"
  msg ""
  msg "$(L MSG_PANEL_0002)"
  msg ""
  msg "$(L MSG_PANEL_0003)"
  msg "$(L MSG_PANEL_0004 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0005 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0006 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_PANEL_0007)"
  msg "$(L MSG_PANEL_0008)"
  msg ""
}

panels_docker_migration_help() {
  msg_title "$(L MSG_PANEL_0009)"
  msg ""
  msg "$(L MSG_PANEL_0010)"
  msg ""
  msg "$(L MSG_PANEL_0003)"
  msg "$(L MSG_PANEL_0011 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0012 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0013 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0014 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0015 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0016 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0017 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0018)"
  msg ""
  msg "$(L MSG_PANEL_0019)"
  msg "        fusionbox panels docker-migration remote node2 --bundle app.tar.gz \\"
  msg "               --name app.tar.gz --key ~/.ssh/migrate --known-hosts /etc/fusionbox/cluster/known_hosts"
  msg ""
}

panels_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    compose-backup)
      _require_root
      [[ $# -ge 1 ]] || { panels_compose_backup_help; return 2; }
      _require_docker_compose "$(L MSG_PANEL_0020)" || return 1
      _require_python3 "$(L MSG_PANEL_0020)" || return 1
      python3 "$FUSION_SRC/lib/compose_backup.py" "$@"
      ;;
    docker-migration)
      _require_root
      [[ $# -ge 1 ]] || { panels_docker_migration_help; return 2; }
      if [[ "$1" == "remote" ]]; then
        _require_python3 "$(L MSG_PANEL_0021)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration_remote.py" "$@"
      else
        _require_docker "$(L MSG_PANEL_0022)" || return 1
        _require_python3 "$(L MSG_PANEL_0022)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration.py" "$@"
      fi
      ;;
    docker|dk)            panels_docker "$@" ;;
    mirror|mirrors)       panels_docker_mirror "${1:-}" ;;
    bt|baota)             panels_bt ;;
    aa|aapanel)           panels_aa ;;
    xui|x-ui)             panels_xui ;;
    aria2)                panels_aria2 ;;
    rclone)               panels_rclone ;;
    frp)                  panels_frp ;;
    nezha|nezuta)         panels_nezha ;;
    menu|main)            panels_menu ;;
    help|h)               panels_help ;;
    *)                    _module_unknown_cmd "panels" "$cmd" ;;
  esac
}

# ---- Docker Management ----
panels_docker() {
  local action="${1:-menu}"

  case "$action" in
    summary)      shift; panels_docker_summary "$@" ;;
    detail)       shift; panels_docker_detail "$@" ;;
    install)      panels_docker_install ;;
    ps)           panels_docker_ps ;;
    images)       panels_docker_images ;;
    prune)        panels_docker_prune ;;
    compose|up)   panels_docker_compose "$@" ;;
    migrate|migration)
      shift
      _require_root
      [[ $# -ge 1 ]] || { panels_docker_migration_help; return 2; }
      if [[ "$1" == "remote" ]]; then
        _require_python3 "$(L MSG_PANEL_0021)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration_remote.py" "$@"
      else
        _require_docker "$(L MSG_PANEL_0022)" || return 1
        _require_python3 "$(L MSG_PANEL_0022)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration.py" "$@"
      fi
      ;;
    mirror|mirrors) panels_docker_mirror "${2:-}" ;;
    port-block|pb)  shift; panels_docker_port_block "$@" ;;
    uninstall)      panels_docker_uninstall ;;
    help|h)         panels_help ;;
    menu|"")      panels_docker_menu ;;
    *)            _module_unknown_cmd "panels docker" "$action" ;;
  esac
}

# Diagnostics never print Docker error bodies (which can contain endpoint credentials).
_panels_docker_read() {
  local output
  if ! command -v docker >/dev/null 2>&1; then
    printf '%s\n' 'Docker unavailable: CLI not installed' >&2; return 1
  fi
  if ! output=$(docker "$@" 2>/dev/null); then
    printf '%s\n' 'Docker query failed: check daemon connectivity, permissions, context and object existence; data unavailable' >&2
    return 1
  fi
  printf '%s\n' "$output"
}

panels_docker_summary() {
  local mode="${1:-}" info states networks volumes disk containers images line
  local total=0 running=0 paused=0 exited=0 created=0 restarting=0 dead=0 removing=0 stopped=0 nc=0 vc=0
  [[ $# -le 1 && ( -z "$mode" || "$mode" == --all ) ]] || {
    printf '%s\n' 'Usage: fusionbox panels docker summary [--all]' >&2; return 2;
  }
  # Collect everything before publishing; failed queries never become zero counts.
  info=$(_panels_docker_read info --format 'Engine={{.ServerVersion}} Images={{.Images}}') || return 1
  states=$(_panels_docker_read container ls -a --format '{{.State}}') || return 1
  networks=$(_panels_docker_read network ls --no-trunc --format '{{.ID}} {{json .Name}} {{.Driver}} {{.Scope}}') || return 1
  volumes=$(_panels_docker_read volume ls --format '{{json .Name}} {{.Driver}}') || return 1
  disk=$(_panels_docker_read system df) || return 1
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    total=$((total + 1))
    case "$line" in
      running) running=$((running + 1)) ;; paused) paused=$((paused + 1)) ;;
      exited) exited=$((exited + 1)); stopped=$((stopped + 1)) ;;
      created) created=$((created + 1)); stopped=$((stopped + 1)) ;;
      dead) dead=$((dead + 1)); stopped=$((stopped + 1)) ;;
      restarting) restarting=$((restarting + 1)) ;; removing) removing=$((removing + 1)) ;;
      *) printf '%s\n' 'Docker returned an unknown container state; summary unavailable' >&2; return 1 ;;
    esac
  done <<< "$states"
  while IFS= read -r line; do [[ -z "$line" ]] || nc=$((nc + 1)); done <<< "$networks"
  while IFS= read -r line; do [[ -z "$line" ]] || vc=$((vc + 1)); done <<< "$volumes"
  if [[ "$mode" == --all ]]; then
    containers=$(_panels_docker_read container ls -a --no-trunc --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.State}}\t{{.Ports}}') || return 1
    images=$(_panels_docker_read image ls -a --no-trunc --format 'table {{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}') || return 1
  fi
  printf '%s\n' "$info" "Containers=$total Running=$running Paused=$paused Stopped=$stopped Exited=$exited Created=$created Dead=$dead Restarting=$restarting Removing=$removing" "Networks=$nc Volumes=$vc" 'Stopped = created + exited + dead; paused/restarting/removing are separate.' 'Sequential engine observations, not an atomic snapshot. Images = engine image count, not tag rows.' 'Disk usage (Docker shared/reclaimable accounting, not host free space):' "$disk"
  if [[ "$mode" == --all ]]; then
    printf '\n%s\n' 'Containers:' "$containers" 'Images (multiple tags may share an ID):' "$images" 'Networks (ID/name/driver/scope):' "$networks" 'Volumes (name/driver):' "$volumes"
  fi
}

panels_docker_detail() {
  local target="${1:-}" detail stats state id
  [[ $# -eq 1 && ${#target} -le 255 && "$target" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || {
    printf '%s\n' 'Usage: fusionbox panels docker detail CONTAINER_ID_OR_NAME (simple name or ID only)' >&2; return 2;
  }
  # Whitelist fields; never expose Env, command arguments, labels, health output or raw inspect.
  detail=$(_panels_docker_read container inspect --format 'ID={{.Id}}
Name={{json .Name}}
ImageReference={{json .Config.Image}}
ImageID={{.Image}}
State={{.State.Status}}
Running={{.State.Running}} Paused={{.State.Paused}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}
Created={{.Created}} Started={{.State.StartedAt}} Finished={{.State.FinishedAt}}
Health={{if index .State "Health"}}{{.State.Health.Status}}{{else}}not-configured{{end}}
RestartPolicy={{.HostConfig.RestartPolicy.Name}} MaximumRetryCount={{.HostConfig.RestartPolicy.MaximumRetryCount}} RestartCount={{.RestartCount}}
PersistedLimits: MemoryBytes={{.HostConfig.Memory}} MemoryReservationBytes={{.HostConfig.MemoryReservation}} MemorySwapBytes={{.HostConfig.MemorySwap}} NanoCPUs={{.HostConfig.NanoCpus}} CpuQuota={{.HostConfig.CpuQuota}} CpuPeriod={{.HostConfig.CpuPeriod}} CpuShares={{.HostConfig.CpuShares}} CpusetCpus={{json .HostConfig.CpusetCpus}} PidsLimit={{.HostConfig.PidsLimit}}
ConfiguredPorts={{json .HostConfig.PortBindings}}
RuntimePorts={{json .NetworkSettings.Ports}}
Mounts:{{range .Mounts}}
  Type={{.Type}} Name={{json (index . "Name")}} Source={{json .Source}} Destination={{json .Destination}} RW={{.RW}}{{end}}
Networks:{{range $name, $net := .NetworkSettings.Networks}}
  Name={{json $name}} ID={{$net.NetworkID}} IP={{json $net.IPAddress}} IPv6={{json $net.GlobalIPv6Address}} Gateway={{json $net.Gateway}}{{end}}
Environment=[redacted: all values omitted]' -- "$target") || return 1
  [[ -n "$detail" ]] || return 1
  printf '%s\n' "$detail" 'Limit semantics: MemoryBytes=0 means no container memory cap; NanoCPUs=0 means no NanoCPU cap (quota/cpuset may still limit CPU); CpuQuota<=0 means no quota; CpuShares=0 means default weight; PidsLimit<=0/unset means no explicit PID cap. MemorySwap=0 is Docker default, -1 unlimited swap. Host/parent cgroups can impose further limits.'
  state=$(printf '%s\n' "$detail" | grep '^State=')
  id=${detail%%$'\n'*}; id=${id#ID=}
  if [[ "$state" == State=running ]]; then
    stats=$(_panels_docker_read container stats --no-stream --format 'RuntimeUsage: CPU={{.CPUPerc}} Memory={{.MemUsage}} MemoryPercent={{.MemPerc}} PIDs={{.PIDs}} NetworkIO={{.NetIO}} BlockIO={{.BlockIO}}' -- "$id") || {
      printf '%s\n' 'RuntimeUsage=unavailable (container may have changed state)' >&2; return 1;
    }
    [[ -n "$stats" ]] || { printf '%s\n' 'RuntimeUsage=unavailable' >&2; return 1; }
    printf '%s\n' "$stats" 'Runtime memory limit is engine-reported; CPU percent is usage, not a CPU limit.'
  else
    printf '%s\n' 'RuntimeUsage=not sampled (container not running or paused); persisted limits remain above.'
  fi
}

panels_docker_install() {
  _require_root
  if command -v docker &>/dev/null; then
    msg_info "$(L MSG_PANEL_0023 "$(docker --version)")"
    return
  fi

  msg_info "$(L MSG_PANEL_0024)"
  progress_begin 4
  case "$F_PKG_MGR" in
    apt)
      progress_step "$(_tr MSG_DOCKER_STAGES_1)"
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sh /tmp/get-docker.sh 2>/dev/null
      ;;
    yum)
      progress_step "$(_tr MSG_DOCKER_STAGES_1)"
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sh /tmp/get-docker.sh 2>/dev/null
      ;;
    apk)
      progress_step "$(_tr MSG_DOCKER_STAGES_1)"
      _install_pkg docker docker-compose
      progress_step "$(_tr MSG_DOCKER_STAGES_2)"
      rc-update add docker default 2>/dev/null
      rc-service docker start 2>/dev/null
      progress_end
      return
      ;;
  esac

  progress_step "$(_tr MSG_DOCKER_STAGES_2)"
  systemctl enable docker 2>/dev/null
  systemctl start docker 2>/dev/null

  progress_step "$(_tr MSG_DOCKER_STAGES_3)"
  if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
    local compose_ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/$compose_ver/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null && \
      chmod +x /usr/local/bin/docker-compose
  fi

  progress_step "$(_tr MSG_DOCKER_STAGES_4)"
  if command -v docker &>/dev/null; then
    msg_ok "$(L MSG_PANEL_0025 "$(docker --version 2>/dev/null)")"
    docker compose version 2>/dev/null | xargs -I{} msg_ok "Docker Compose: {}"
    _log_write "$(L MSG_PANEL_0026)"
  fi
  progress_end
}

panels_docker_ps() {
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0027)"
    return
  fi
  msg_title "$(L MSG_PANEL_0028)"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_images() {
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0027)"
    return
  fi
  msg_title "$(L MSG_PANEL_0029)"
  msg ""
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_prune() {
  _require_root
  if ! confirm "$(L MSG_PANEL_0030)"; then
    return
  fi
  docker system prune -a -f --volumes 2>/dev/null
  msg_ok "$(L MSG_PANEL_0031)"
  _log_write "$(L MSG_PANEL_0032)"
  pause
}

panels_docker_compose() {
  _require_root
  local project="${2:-}"
  local compose_dir="/opt/docker"
  mkdir -p "$compose_dir"

  if [[ -z "$project" ]]; then
    msg_title "$(L MSG_PANEL_0033)"
    msg ""
    find "$compose_dir" -name "docker-compose.yml" -o -name "compose.yaml" 2>/dev/null | while read -r f; do
      msg "  $(dirname "$f" | xargs basename)"
    done

    msg ""
    msg "$(L MSG_PANEL_0034)"
    msg "$(L MSG_PANEL_0035)"
    read -p "$(L MSG_PANEL_0036)" comp_choice

    case "$comp_choice" in
      1)
        read -p "$(L MSG_PANEL_0037)" project
        if [[ -n "$project" ]]; then
          local proj_dir="$compose_dir/$project"
          mkdir -p "$proj_dir"
          cat > "$proj_dir/docker-compose.yml" << YEOF
version: '3.8'
services:
  app:
    image: nginx:alpine
    container_name: ${project}_app
    restart: always
    ports:
      - "80:80"
    volumes:
      - ./html:/usr/share/nginx/html
YEOF
          chmod 600 "$proj_dir/docker-compose.yml"
          mkdir -p "$proj_dir/html"
          echo "$(L MSG_PANEL_0038)" > "$proj_dir/html/index.html"
          msg_ok "$(L MSG_PANEL_0039 "$project" "$proj_dir")"
        fi
        ;;
      2)
        msg_info "$(L MSG_PANEL_0040)"
        for f in "$compose_dir"/*/docker-compose.yml; do
          [[ -f "$f" ]] && docker compose -f "$f" up -d 2>/dev/null && msg_info "$(L MSG_PANEL_0041 "$(basename "$(dirname "$f")")")"
        done
        ;;
    esac
  else
    local proj_file="$compose_dir/$project/docker-compose.yml"
    if [[ -f "$proj_file" ]]; then
      docker compose -f "$proj_file" up -d 2>/dev/null && msg_ok "$(L MSG_PANEL_0042 "$project")" || msg_err "$(L MSG_PANEL_0043)"
    else
      msg_err "$(L MSG_PANEL_0044 "$project")"
    fi
  fi
  pause
}

# ---- Docker 端口访问控制 ----
panels_docker_port_control() {
  msg_err "$(L MSG_PANEL_0045)"
  msg_warn "$(L MSG_PANEL_0046)"
  return 1
}

# ---- Docker IPv6 网络配置 ----
panels_docker_ipv6() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "$(L MSG_PANEL_0047)"
  msg ""

  msg "$(L MSG_PANEL_0048)"
  msg "$(L MSG_PANEL_0049)"
  msg "$(L MSG_PANEL_0050)"
  msg "$(L MSG_PANEL_0051)"
  read -p "$(L MSG_PANEL_0036)" ipv6_choice

  case "$ipv6_choice" in
    1)
      mkdir -p /etc/docker
      if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg['ipv6'] = True
cfg['fixed-cidr-v6'] = 'fd00::/80'
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
      else
        echo '{"ipv6": true, "fixed-cidr-v6": "fd00::/80"}' > "$daemon_json"
      fi
      systemctl restart docker 2>/dev/null
      msg_ok "$(L MSG_PANEL_0052)"
      _log_write "$(L MSG_PANEL_0052)"
      ;;
    2)
      if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg.pop('ipv6', None)
cfg.pop('fixed-cidr-v6', None)
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
        systemctl restart docker 2>/dev/null
        msg_ok "$(L MSG_PANEL_0053)"
      fi
      ;;
    3)
      read -p "$(L MSG_PANEL_0054)" net_name
      read -p "$(L MSG_PANEL_0055)" ipv6_subnet
      if [[ -n "$net_name" && -n "$ipv6_subnet" ]]; then
        docker network create --ipv6 --subnet "$ipv6_subnet" "$net_name" 2>/dev/null && \
          msg_ok "$(L MSG_PANEL_0056 "$net_name")" || msg_err "$(L MSG_PANEL_0057)"
      fi
      ;;
  esac
  pause
}

# ---- 容器名级端口开关 (G27)：DOCKER-USER + 原始目标（容器 IP）规则 ----
# 规则带 fb-port-block comment 标记，只管理自有规则；不持久化（重启后失效），不支持 IPv6。

_panels_pb_mark() { printf 'fb-port-block:%s:%s:%s' "$1" "$2" "$3"; }

_panels_pb_validate() {
  local container="$1" proto="$2" port="$3"
  [[ "$container" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$ ]] || { msg_err "$(L MSG_PANEL_0058 "$container")"; return 1; }
  [[ "$proto" == "tcp" || "$proto" == "udp" ]] || { msg_err "$(L MSG_PANEL_0059 "$proto")"; return 1; }
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { msg_err "$(L MSG_PANEL_0060 "$port")"; return 1; }
}

_panels_pb_chain_ok() {
  iptables -nL DOCKER-USER &>/dev/null || { msg_err "$(L MSG_PANEL_0061)"; return 1; }
}

_panels_pb_container_ips() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}' "$1" 2>/dev/null \
    | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
}

_panels_pb_rules_from_save() {
  # 从 iptables-save 提取带指定标记的 DOCKER-USER 规则体（去掉 "-A DOCKER-USER " 与引号，
  # 使输出可直接传给 `iptables -D DOCKER-USER`）
  local mark="$1" line
  iptables-save -t filter 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      "-A DOCKER-USER "*--comment*"$mark"*)
        printf '%s\n' "${line#-A DOCKER-USER }" | tr -d '"' ;;
    esac
  done
}

panels_docker_port_block() {
  _require_root
  local action="${1:-list}"
  case "$action" in
    list)
      _panels_pb_chain_ok || return 1
      local rules
      rules=$(_panels_pb_rules_from_save "fb-port-block:")
      if [[ -n "$rules" ]]; then
        msg "$(L MSG_PANEL_0062 "${F_BOLD}" "${F_RESET}")"
        printf '  %s\n' "$rules"
      else
        msg "$(L MSG_PANEL_0063)"
      fi
      ;;
    add)
      shift
      local container="${1:-}" proto="${2:-tcp}" port="${3:-}" ip rc=0
      [[ $# -eq 3 ]] || { msg_err "$(L MSG_PANEL_0064)"; return 2; }
      _panels_pb_validate "$container" "$proto" "$port" || return 1
      command -v docker &>/dev/null || { msg_err "$(L MSG_PANEL_0027)"; return 1; }
      _panels_pb_chain_ok || return 1
      local ips; ips=$(_panels_pb_container_ips "$container")
      [[ -n "$ips" ]] || { msg_err "$(L MSG_PANEL_0065 "$container")"; return 1; }
      msg_info "$(L MSG_PANEL_0066 "$container" "$proto" "$port" "$(echo $ips | tr '\n' ' ')")"
      msg_warn "$(L MSG_PANEL_0067)"
      confirm "$(L MSG_PANEL_0068)" || { msg_info "$(L MSG_PANEL_0069)"; return 1; }
      local mark; mark=$(_panels_pb_mark "$container" "$proto" "$port")
      local -a rules_added=()
      for ip in $ips; do
        if iptables -I DOCKER-USER 1 -p "$proto" -d "$ip" --dport "$port" \
             -m comment --comment "$mark" -j DROP; then
          rules_added+=("$ip")
        else
          msg_err "$(L MSG_PANEL_0070 "$ip")"
          rc=1
          break
        fi
      done
      if [[ $rc -ne 0 ]]; then
        for ip in "${rules_added[@]}"; do
          iptables -D DOCKER-USER -p "$proto" -d "$ip" --dport "$port" \
            -m comment --comment "$mark" -j DROP 2>/dev/null || true
        done
        msg_err "$(L MSG_PANEL_0071)"
        return 1
      fi
      msg_ok "$(L MSG_PANEL_0072)"
      _log_write "$(L MSG_PANEL_0073 "$container" "$proto" "$port" "$ips")"
      ;;
    del)
      shift
      local container="${1:-}" proto="${2:-tcp}" port="${3:-}" mark spec removed=0
      [[ $# -eq 3 ]] || { msg_err "$(L MSG_PANEL_0074)"; return 2; }
      _panels_pb_validate "$container" "$proto" "$port" || return 1
      _panels_pb_chain_ok || return 1
      mark=$(_panels_pb_mark "$container" "$proto" "$port")
      while IFS= read -r spec; do
        [[ -n "$spec" ]] || continue
        if iptables -D DOCKER-USER $spec; then
          removed=$((removed + 1))
        fi
      done < <(_panels_pb_rules_from_save "$mark")
      if [[ $removed -eq 0 ]]; then
        msg_err "$(L MSG_PANEL_0075)"
        return 1
      fi
      msg_ok "$(L MSG_PANEL_0076 "$removed")"
      _log_write "$(L MSG_PANEL_0077 "$container" "$proto" "$port")"
      ;;
    menu)
      panels_docker_port_block list
      msg ""
      msg "$(L MSG_PANEL_0078)"
      msg "$(L MSG_PANEL_0079)"
      msg "$(L MSG_PANEL_0051)"
      read -p "$(L MSG_PANEL_0036)" pb_choice || { msg ""; return; }
      case "$pb_choice" in
        1|2)
          local pb_c pb_pr pb_po
          read -r -p "$(L MSG_PANEL_0080)" pb_c
          read -r -p "$(L MSG_PANEL_0081)" pb_pr
          read -r -p "$(L MSG_PANEL_0082)" pb_po
          if [[ "$pb_choice" == 1 ]]; then
            panels_docker_port_block add "$pb_c" "$pb_pr" "$pb_po"
          else
            panels_docker_port_block del "$pb_c" "$pb_pr" "$pb_po"
          fi
          ;;
      esac
      ;;
    *)
      msg_err "$(L MSG_PANEL_0083 "$action")"; return 2 ;;
  esac
}

# ---- Docker 一键卸载 (G30)：全部容器/镜像/卷/网络 + 包 + 数据目录（YES 门禁） ----

_panels_docker_pkgs() {
  printf '%s\n' docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose-plugin2 \
    docker.io docker-doc docker-compose podman-docker containerd runc
}

panels_docker_uninstall() {
  _require_root
  command -v docker &>/dev/null || { msg_err "$(L MSG_PANEL_0084)"; return 1; }
  command -v systemctl &>/dev/null || { msg_err "$(L MSG_PANEL_0085)"; return 1; }

  msg_title "$(L MSG_PANEL_0086)"
  msg ""
  # 只读统计先行；失败不伪装为零
  local c i v n du_stat
  c=$(docker ps -aq 2>/dev/null | wc -l); i=$(docker images -aq 2>/dev/null | wc -l)
  v=$(docker volume ls -q 2>/dev/null | wc -l); n=$(docker network ls -q 2>/dev/null | wc -l)
  du_stat=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
  msg "$(L MSG_PANEL_0087)"
  msg "$(L MSG_PANEL_0088 "$c" "$i" "$v" "$n")"
  msg "$(L MSG_PANEL_0089 "${du_stat:-未知或不存在}")"
  [[ -f /etc/docker/daemon.json ]] && msg "$(L MSG_PANEL_0090)"
  msg ""
  msg_warn "$(L MSG_PANEL_0091)"
  msg_warn "$(L MSG_PANEL_0092)"
  msg_info "$(L MSG_PANEL_0093)"
  confirm "$(L MSG_PANEL_0094)" || { msg_info "$(L MSG_PANEL_0069)"; return 1; }
  local ans
  read -r -p "$(L MSG_PANEL_0095)" ans || { msg_info "$(L MSG_PANEL_0069)"; return 1; }
  [[ "$ans" == "YES" ]] || { msg_info "$(L MSG_PANEL_0069)"; return 1; }

  local wipe="yes"
  read -r -p "$(L MSG_PANEL_0096)" ans || ans="yes"
  [[ "$ans" == "keep" ]] && wipe="no"

  msg_info "$(L MSG_PANEL_0097)"
  local ids; ids=$(docker ps -aq 2>/dev/null)
  [[ -n "$ids" ]] && docker stop $ids >/dev/null 2>&1
  [[ -n "$ids" ]] && docker rm -f $ids >/dev/null 2>&1
  msg_info "$(L MSG_PANEL_0098)"
  docker network prune -f >/dev/null 2>&1
  docker volume prune -af >/dev/null 2>&1
  ids=$(docker images -aq 2>/dev/null)
  [[ -n "$ids" ]] && docker rmi -f $ids >/dev/null 2>&1
  docker system prune -af >/dev/null 2>&1

  msg_info "$(L MSG_PANEL_0099)"
  systemctl disable --now docker.service docker.socket >/dev/null 2>&1
  systemctl disable --now containerd.service >/dev/null 2>&1

  msg_info "$(L MSG_PANEL_0100)"
  local p
  local -a installed_pkgs=()
  while IFS= read -r p; do
    case "$F_PKG_MGR" in
      apt)  dpkg -s "$p" >/dev/null 2>&1 && installed_pkgs+=("$p") ;;
      yum)  rpm -q "$p" >/dev/null 2>&1 && installed_pkgs+=("$p") ;;
      apk)  apk info -e "$p" >/dev/null 2>&1 && installed_pkgs+=("$p") ;;
      zypper) rpm -q "$p" >/dev/null 2>&1 && installed_pkgs+=("$p") ;;
    esac
  done < <(_panels_docker_pkgs)
  if [[ ${#installed_pkgs[@]} -gt 0 ]]; then
    case "$F_PKG_MGR" in
      apt)    apt-get purge -y "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0101)"; return 1; } ;;
      yum)    yum remove -y "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0101)"; return 1; } ;;
      apk)    apk del "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0101)"; return 1; } ;;
      zypper) zypper remove -y "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0101)"; return 1; } ;;
      *)      msg_err "$(L MSG_PANEL_0102)"; return 1 ;;
    esac
  else
    msg_warn "$(L MSG_PANEL_0103)"
  fi

  if [[ "$wipe" == "yes" ]]; then
    msg_info "$(L MSG_PANEL_0104)"
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  else
    msg_warn "$(L MSG_PANEL_0105)"
  fi

  if command -v docker &>/dev/null; then
    msg_warn "$(L MSG_PANEL_0106)"
    return 1
  fi
  msg_ok "$(L MSG_PANEL_0107)"
  _log_write "$(L MSG_PANEL_0108 "$wipe")"
}

# ---- Docker daemon.json 编辑 ----
panels_docker_daemon() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "$(L MSG_PANEL_0109)"
  msg ""

  if [[ -f "$daemon_json" ]]; then
    msg "$(L MSG_PANEL_0110 "${F_BOLD}" "${F_RESET}")"
    cat "$daemon_json" 2>/dev/null
  else
    msg "$(L MSG_PANEL_0111)"
  fi

  msg ""
  msg "$(L MSG_PANEL_0112)"
  msg "$(L MSG_PANEL_0113)"
  msg "$(L MSG_PANEL_0114)"
  msg "$(L MSG_PANEL_0115)"
  msg "$(L MSG_PANEL_0116)"
  msg "$(L MSG_PANEL_0051)"
  read -p "$(L MSG_PANEL_0036)" dm_choice

  case "$dm_choice" in
    1)
      read -p "$(L MSG_PANEL_0117)" mirror_url
      if [[ -n "$mirror_url" ]]; then
        mkdir -p /etc/docker
        if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
          FB_DOCKER_JSON="$daemon_json" FB_MIRROR="$mirror_url" python3 -c '
import json, os
path = os.environ["FB_DOCKER_JSON"]
url = os.environ["FB_MIRROR"]
with open(path) as f: cfg = json.load(f)
cfg["registry-mirrors"] = [url]
with open(path, "w") as f: json.dump(cfg, f, indent=2)
' 2>/dev/null
        else
          echo "{\"registry-mirrors\": [\"$mirror_url\"]}" > "$daemon_json"
        fi
        systemctl restart docker 2>/dev/null
        msg_ok "$(L MSG_PANEL_0118)"
      fi
      ;;
    2)
      if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$daemon_json') as f: cfg = json.load(f)
cfg['log-driver'] = 'json-file'
cfg['log-opts'] = {'max-size': '10m', 'max-file': '3'}
with open('$daemon_json','w') as f: json.dump(cfg, f, indent=2)
" 2>/dev/null
      else
        echo '{"log-driver": "json-file", "log-opts": {"max-size": "10m", "max-file": "3"}}' > "$daemon_json"
      fi
      systemctl restart docker 2>/dev/null
      msg_ok "$(L MSG_PANEL_0119)"
      ;;
    3)
      read -p "$(L MSG_PANEL_0120)" dns_server
      if [[ -n "$dns_server" ]]; then
        if [[ -f "$daemon_json" ]] && command -v python3 &>/dev/null; then
          FB_DOCKER_JSON="$daemon_json" FB_DNS="$dns_server" python3 -c '
import json, os
path = os.environ["FB_DOCKER_JSON"]
dns = os.environ["FB_DNS"]
with open(path) as f: cfg = json.load(f)
cfg["dns"] = [dns]
with open(path, "w") as f: json.dump(cfg, f, indent=2)
' 2>/dev/null
        fi
        systemctl restart docker 2>/dev/null
        msg_ok "$(L MSG_PANEL_0121 "$dns_server")"
      fi
      ;;
    4)
      ${EDITOR:-vi} "$daemon_json"
      systemctl restart docker 2>/dev/null
      ;;
    5)
      if confirm "$(L MSG_PANEL_0122)"; then
        rm -f "$daemon_json"
        systemctl restart docker 2>/dev/null
        msg_ok "$(L MSG_PANEL_0123)"
      fi
      ;;
  esac
  pause
}

# ---- Docker 镜像加速 / 换源 ----
# 预设镜像源 数据表，字段: 名称|URL
# 特殊占位: __official__ = 清空 registry-mirrors 恢复官方, __aliyun__ = 需输入阿里云 ID, __custom__ = 手动输入
PANELS_DOCKER_MIRRORS=(
  "$(L MSG_PANEL_0124)"
  "$(L MSG_PANEL_0125)"
  "$(L MSG_PANEL_0126)"
  "$(L MSG_PANEL_0127)"
  "$(L MSG_PANEL_0128)"
)

# 检测可用的 JSON 处理工具
_panels_docker_json_tool() {
  if command -v jq &>/dev/null; then
    echo "jq"
  elif command -v python3 &>/dev/null; then
    echo "python3"
  else
    echo ""
  fi
}

# JSON 合法性校验: $1=文件 $2=工具
_panels_docker_json_valid() {
  local file="$1" tool="$2"
  [[ -s "$file" ]] || return 1
  case "$tool" in
    jq)      jq -e . "$file" >/dev/null 2>&1 ;;
    python3) python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$file" >/dev/null 2>&1 ;;
    *)       return 1 ;;
  esac
}

# 显示当前 registry-mirrors 配置
_panels_docker_mirror_show_current() {
  local daemon_json="/etc/docker/daemon.json"
  local tool; tool=$(_panels_docker_json_tool)

  msg "$(L MSG_PANEL_0129 "${F_BOLD}" "${daemon_json}" "${F_RESET}")"
  if [[ ! -f "$daemon_json" ]]; then
    msg "$(L MSG_PANEL_0130 "${F_YELLOW}" "${F_RESET}")"
    return
  fi

  local mirrors=""
  if [[ "$tool" == "jq" ]]; then
    mirrors=$(jq -r '."registry-mirrors" // [] | .[]' "$daemon_json" 2>/dev/null)
  elif [[ "$tool" == "python3" ]]; then
    mirrors=$(python3 -c '
import json, sys
try:
    cfg = json.load(open(sys.argv[1]))
except Exception:
    cfg = {}
if not isinstance(cfg, dict):
    cfg = {}
for m in cfg.get("registry-mirrors") or []:
    print(m)
' "$daemon_json" 2>/dev/null)
  fi

  if [[ -z "$mirrors" ]]; then
    msg "$(L MSG_PANEL_0131 "${F_YELLOW}" "${F_RESET}")"
  else
    echo "$mirrors" | while IFS= read -r m; do
      [[ -n "$m" ]] && msg "    ${F_GREEN}${m}${F_RESET}"
    done
  fi
}

# 列出可选镜像源
_panels_docker_mirror_list() {
  local item name url shown num i=0
  msg "$(L MSG_PANEL_0132 "${F_BOLD}" "${F_RESET}")"
  for item in "${PANELS_DOCKER_MIRRORS[@]}"; do
    IFS='|' read -r name url <<< "$item"
    i=$((i + 1))
    case "$url" in
      __official__) shown="$(L MSG_PANEL_0133)" ;;
      __aliyun__)   shown="$(L MSG_PANEL_0134)" ;;
      __custom__)   shown="$(L MSG_PANEL_0135)" ;;
      *)            shown="$url" ;;
    esac
    printf -v num '%2d' "$i"
    msg "  ${F_GREEN}${num}${F_RESET}) ${F_BOLD}${name}${F_RESET} - ${shown}"
  done
  msg ""
}

# 回滚: $1=备份文件 $2=备份是否存在(0/1)
_panels_docker_mirror_rollback() {
  local bak_file="$1" existed="$2"
  local daemon_json="/etc/docker/daemon.json"
  if [[ "$existed" -eq 1 && -f "$bak_file" ]]; then
    cp -a "$bak_file" "$daemon_json"
    msg_info "$(L MSG_PANEL_0136 "$bak_file")"
  else
    rm -f "$daemon_json"
    msg_info "$(L MSG_PANEL_0137)"
  fi
  systemctl restart docker 2>/dev/null
}

# 合并 registry-mirrors: $1=模式(set|clear) $2=源JSON $3=目标JSON $4=工具 $5=URL
_panels_docker_mirror_merge() {
  local mode="$1" src="$2" dst="$3" tool="$4" url="${5:-}"
  if [[ "$tool" == "jq" ]]; then
    if [[ "$mode" == "clear" ]]; then
      jq 'del(."registry-mirrors")' "$src" > "$dst" 2>/dev/null
    else
      jq --arg u "$url" '."registry-mirrors" = [$u]' "$src" > "$dst" 2>/dev/null
    fi
  else
    FB_SRC="$src" FB_DST="$dst" FB_MODE="$mode" FB_URL="$url" python3 -c '
import json, os
src, dst = os.environ["FB_SRC"], os.environ["FB_DST"]
mode, url = os.environ["FB_MODE"], os.environ["FB_URL"]
try:
    with open(src) as f:
        cfg = json.load(f)
except Exception:
    cfg = {}
if not isinstance(cfg, dict):
    cfg = {}
if mode == "clear":
    cfg.pop("registry-mirrors", None)
else:
    cfg["registry-mirrors"] = [url]
with open(dst, "w") as f:
    json.dump(cfg, f, indent=2)
' 2>/dev/null
  fi
}

# 应用镜像源: $1=模式(set|clear) $2=名称 $3=URL(clear 时可省略)
_panels_docker_mirror_apply() {
  local mode="$1" label="$2" url="${3:-}"
  local daemon_json="/etc/docker/daemon.json"
  local ts; ts=$(date '+%Y%m%d_%H%M%S')
  local bak_dir="/etc/fusionbox/docker-bak-${ts}"
  local bak_file="$bak_dir/daemon.json"
  local existed=0

  local tool; tool=$(_panels_docker_json_tool)
  if [[ -z "$tool" ]]; then
    msg_err "$(L MSG_PANEL_0138)"
    msg_info "$(L MSG_PANEL_0139)"
    pause
    return 1
  fi

  # 1) 备份现有配置
  mkdir -p /etc/docker || { msg_err "$(L MSG_PANEL_0140)"; pause; return 1; }
  mkdir -p "$bak_dir" || { msg_err "$(L MSG_PANEL_0141 "$bak_dir")"; pause; return 1; }
  if [[ -f "$daemon_json" ]]; then
    cp -a "$daemon_json" "$bak_file" || { msg_err "$(L MSG_PANEL_0142 "$daemon_json")"; pause; return 1; }
    existed=1
    msg_info "$(L MSG_PANEL_0143 "$daemon_json" "$bak_file")"
  else
    msg_info "$(L MSG_PANEL_0144 "$bak_dir")"
  fi

  # 2) 合并 registry-mirrors
  local src; src=$(mktemp)
  local new_json; new_json=$(mktemp)
  if [[ "$existed" -eq 1 ]]; then cp "$daemon_json" "$src"; else echo '{}' > "$src"; fi
  if ! _panels_docker_json_valid "$src" "$tool"; then
    msg_err "$(L MSG_PANEL_0145)"
    rm -f "$src" "$new_json"
    return 1
  fi

  if [[ "$mode" == "clear" ]]; then
    _panels_docker_mirror_merge clear "$src" "$new_json" "$tool"
  else
    _panels_docker_mirror_merge set "$src" "$new_json" "$tool" "$url"
  fi

  # 3) JSON 校验通过后才落盘
  if ! _panels_docker_json_valid "$new_json" "$tool"; then
    msg_err "$(L MSG_PANEL_0146)"
    rm -f "$src" "$new_json"
    pause
    return 1
  fi
  cat "$new_json" > "$daemon_json"
  chmod 600 "$daemon_json"
  rm -f "$src" "$new_json"
  msg_info "$(L MSG_PANEL_0147 "$daemon_json")"

  # 4) 重启并验证
  if ! systemctl restart docker 2>/dev/null; then
    msg_err "$(L MSG_PANEL_0148)"
    _panels_docker_mirror_rollback "$bak_file" "$existed"
    pause
    return 1
  fi

  sleep 1
  local info_raw; info_raw=$(docker info 2>/dev/null)
  if [[ -z "$info_raw" ]]; then
    msg_err "$(L MSG_PANEL_0149)"
    _panels_docker_mirror_rollback "$bak_file" "$existed"
    pause
    return 1
  fi

  msg ""
  local mirrors; mirrors=$(echo "$info_raw" | grep -A5 "Registry Mirrors")
  if [[ -n "$mirrors" ]]; then
    msg_ok "$(L MSG_PANEL_0150)"
    echo "$mirrors" | while IFS= read -r l; do msg "  $l"; done
  else
    msg_ok "$(L MSG_PANEL_0151)"
  fi
  _log_write "$(L MSG_PANEL_0152 "${label}" "${url:-（清空）}")"
  pause
  return 0
}

# 清空镜像源（恢复官方）
panels_docker_mirror_clear() {
  if confirm "$(L MSG_PANEL_0153)"; then
    _panels_docker_mirror_apply clear "$(L MSG_PANEL_0154)"
  fi
}

# 测试拉取
panels_docker_mirror_test() {
  msg_info "$(L MSG_PANEL_0155)"
  local out; out=$(timeout 30 docker pull hello-world 2>&1)
  local rc=$?
  msg ""
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_PANEL_0156)"
    echo "$out" | tail -2 | while IFS= read -r l; do msg "  $l"; done
  elif [[ $rc -eq 124 ]]; then
    msg_warn "$(L MSG_PANEL_0157)"
    msg_info "$(L MSG_PANEL_0158)"
  else
    msg_err "$(L MSG_PANEL_0159 "$rc")"
    echo "$out" | tail -3 | while IFS= read -r l; do msg "  $l"; done
  fi
  pause
}

# 按序号或名称应用预设镜像源
_panels_docker_mirror_apply_preset() {
  local want="$1" item name url i=0
  for item in "${PANELS_DOCKER_MIRRORS[@]}"; do
    IFS='|' read -r name url <<< "$item"
    i=$((i + 1))
    [[ "$want" == "$i" || "${want,,}" == "${name,,}" ]] || continue
    case "$url" in
      __official__)
        panels_docker_mirror_clear
        ;;
      __aliyun__)
        local aliyun_id; aliyun_id=$(read_input "$(L MSG_PANEL_0160)")
        if [[ ! "$aliyun_id" =~ ^[a-zA-Z0-9]+$ ]]; then
          msg_err "$(L MSG_PANEL_0161 "$aliyun_id")"
          pause
          return 1
        fi
        _panels_docker_mirror_apply set "$(L MSG_PANEL_0162)" "https://${aliyun_id}.mirror.aliyuncs.com"
        ;;
      __custom__)
        local custom_url; custom_url=$(read_input "$(L MSG_PANEL_0163)")
        if [[ "$custom_url" != https://* ]]; then
          msg_err "$(L MSG_PANEL_0164 "$custom_url")"
          pause
          return 1
        fi
        _panels_docker_mirror_apply set "$(L MSG_PANEL_0165)" "$custom_url"
        ;;
      *)
        _panels_docker_mirror_apply set "$name" "$url"
        ;;
    esac
    return $?
  done
  msg_err "$(L MSG_PANEL_0166 "$want")"
  pause
  return 1
}

panels_docker_mirror() {
  _require_root
  local action="${1:-}"

  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0167)"
    pause
    return 1
  fi

  case "$action" in
    clear)  panels_docker_mirror_clear; return $? ;;
    test)   panels_docker_mirror_test; return $? ;;
    list)   _panels_docker_mirror_list; pause; return 0 ;;
    "")     ;;
    *)      _panels_docker_mirror_apply_preset "$action"; return $? ;;
  esac

  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_PANEL_0168)"
    msg ""
    _panels_docker_mirror_show_current
    msg ""
    _panels_docker_mirror_list
    msg "$(L MSG_PANEL_0169 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_PANEL_0036)" m_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$m_choice" in
      ""|0) break ;;
      t|T)  panels_docker_mirror_test ;;
      c|C)  panels_docker_mirror_clear ;;
      *)    _panels_docker_mirror_apply_preset "$m_choice" ;;
    esac
  done
}

# ---- Docker 备份/迁移/恢复 ----
# Publish complete private archives only; an existing destination is never replaced.
_panels_docker_archive() (
  umask 077
  local target="$1" operation="$2"; shift 2
  local directory stage
  directory=$(dirname "$target")
  [[ -d "$directory" && ! -L "$directory" && ! -e "$target" && ! -L "$target" ]] || { msg_err "$(L MSG_PANEL_0170)"; return 1; }
  stage=$(mktemp -d "$directory/.fusionbox-export.XXXXXX") || return 1
  trap 'rm -rf -- "$stage"' EXIT
  if ! docker "$operation" "$@" > "$stage/archive.tar" || [[ ! -s "$stage/archive.tar" ]]; then
    msg_err "$(L MSG_PANEL_0171)"
    return 1
  fi
  tar -tf "$stage/archive.tar" >/dev/null 2>&1 || { msg_err "$(L MSG_PANEL_0172)"; return 1; }
  ln -- "$stage/archive.tar" "$target" || { msg_err "$(L MSG_PANEL_0173)"; return 1; }
)

panels_docker_backup() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0027)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0174)"
  msg ""
  msg "$(L MSG_PANEL_0175)"
  msg "$(L MSG_PANEL_0176)"
  msg "$(L MSG_PANEL_0177)"
  msg "$(L MSG_PANEL_0178)"
  msg "$(L MSG_PANEL_0179)"
  msg "$(L MSG_PANEL_0180)"
  msg "$(L MSG_PANEL_0181)"
  msg_warn "$(L MSG_PANEL_0182)"
  msg "$(L MSG_PANEL_0051)"
  read -p "$(L MSG_PANEL_0036)" dbk_choice

  local backup_dir="/root/docker_backups"
  (umask 077; mkdir -p "$backup_dir") || return 1
  local date_str=$(date '+%Y%m%d_%H%M%S')

  case "$dbk_choice" in
    1)
      msg_warn "$(L MSG_PANEL_0183)"
      msg_warn "$(L MSG_PANEL_0184)"
      python3 "$FUSION_SRC/lib/docker_migration.py" --help
      msg "CLI: fusionbox panels docker migration export BUNDLE (--container NAME ... | --compose-project PROJECT) --confirm-stop-writers [--bind ABS_SOURCE=LOGICAL --confirm-bind ABS_SOURCE]"
      msg "$(L MSG_PANEL_0185)"
      msg "$(L MSG_PANEL_0186)"
      msg "$(L MSG_PANEL_0187)"
      msg "$(L MSG_PANEL_0188)"
      ;;
    2)
      local containers container
      containers=$(docker ps -a --format '{{.Names}}') || { msg_err "$(L MSG_PANEL_0189)"; return 1; }
      for container in $containers; do
        [[ "$container" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
        _panels_docker_archive "$backup_dir/${container}_${date_str}.tar" export "$container" || return 1
      done
      msg_ok "$(L MSG_PANEL_0190 "$backup_dir")"
      ;;
    3)
      read -r -p "$(L MSG_PANEL_0191)" c
      [[ "$c" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
      _panels_docker_archive "$backup_dir/${c}_${date_str}.tar" export "$c" || return 1
      msg_ok "$(L MSG_PANEL_0192)"
      ;;
    4)
      local images
      images=$(docker images -q) || { msg_err "$(L MSG_PANEL_0193)"; return 1; }
      [[ -n "$images" ]] || { msg_err "$(L MSG_PANEL_0194)"; return 1; }
      local -a image_ids
      mapfile -t image_ids <<< "$images"
      _panels_docker_archive "$backup_dir/all_images_${date_str}.tar" save "${image_ids[@]}" || return 1
      msg_ok "$(L MSG_PANEL_0195)"
      ;;
    5)
      local action project source
      msg_warn "$(L MSG_PANEL_0196)"
      read -r -p "$(L MSG_PANEL_0197)" action
      read -r -p "$(L MSG_PANEL_0198)" project
      read -r -p "$(L MSG_PANEL_0199)" source
      case "$action" in
        register)
          confirm "$(L MSG_PANEL_0200)" || return 1
          python3 "$FUSION_SRC/lib/compose_backup.py" register "$project" "$source" --confirm-owned-import || return 1 ;;
        backup|restore)
          confirm "$(L MSG_PANEL_0201)" || return 1
          python3 "$FUSION_SRC/lib/compose_backup.py" "$action" "$project" "$source" --confirm-stop-writers || return 1 ;;
        *) return 1 ;;
      esac
      ;;
    6)
      ls -lh "$backup_dir"/*.tar "$backup_dir"/*.tar.gz 2>/dev/null
      read -p "$(L MSG_PANEL_0202)" backup_file
      if [[ -f "$backup_dir/$backup_file" ]]; then
        if [[ "$backup_file" == *images*.tar ]]; then
          docker load -i "$backup_dir/$backup_file" 2>/dev/null && msg_ok "$(L MSG_PANEL_0203)"
        elif [[ "$backup_file" == *.tar.gz ]]; then
          msg_err "$(L MSG_PANEL_0204)"
          return 1
        else
          read -p "$(L MSG_PANEL_0205)" new_name
          docker import "$backup_dir/$backup_file" "$new_name" 2>/dev/null && msg_ok "$(L MSG_PANEL_0206 "$new_name")"
        fi
      fi
      ;;
    7)
      read -p "$(L MSG_PANEL_0191)" c
      read -p "$(L MSG_PANEL_0207)" remote_host
      [[ "$c" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
      [[ "$remote_host" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || { msg_err "$(L MSG_PANEL_0208)"; return 1; }
      local img_file="$backup_dir/${c}_${date_str}.tar"
      _panels_docker_archive "$img_file" export "$c" || return 1
      # Strict host checking; no transfer is attempted after a failed export.
      scp -o StrictHostKeyChecking=yes -- "$img_file" "${remote_host}:/tmp/" || { msg_err "$(L MSG_PANEL_0209)"; return 1; }
      msg_ok "$(L MSG_PANEL_0210)"
      msg "$(L MSG_PANEL_0211 "$(basename "$img_file")" "$c")"
      ;;
  esac
  pause
}

# ---- Docker 容器管理 ----
panels_docker_container_mgmt() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0027)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0212)"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "$(L MSG_PANEL_0213)"
  msg "$(L MSG_PANEL_0214)"
  msg "$(L MSG_PANEL_0215)"
  msg "$(L MSG_PANEL_0216)"
  msg "$(L MSG_PANEL_0217)"
  msg "$(L MSG_PANEL_0218)"
  msg "$(L MSG_PANEL_0219)"
  msg "$(L MSG_PANEL_0220)"
  msg "$(L MSG_PANEL_0221)"
  msg "$(L MSG_PANEL_0051)"
  read -p "$(L MSG_PANEL_0036)" cm_choice

  case "$cm_choice" in
    1) read -p "$(L MSG_PANEL_0191)" c; docker start "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0222 "$c")" ;;
    2) read -p "$(L MSG_PANEL_0191)" c; docker stop "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0223 "$c")" ;;
    3) read -p "$(L MSG_PANEL_0191)" c; docker restart "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0224 "$c")" ;;
    4)
      read -p "$(L MSG_PANEL_0191)" c
      if confirm "$(L MSG_PANEL_0225 "$c")"; then
        docker stop "$c" 2>/dev/null; docker rm "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0226 "$c")"
      fi
      ;;
    5) read -p "$(L MSG_PANEL_0191)" c; read -p "$(L MSG_PANEL_0227)" n; docker logs --tail "${n:-50}" "$c" 2>/dev/null ;;
    6) read -p "$(L MSG_PANEL_0191)" c; docker exec -it "$c" /bin/bash 2>/dev/null || docker exec -it "$c" /bin/sh 2>/dev/null ;;
    7) docker stats --no-stream 2>/dev/null ;;
    9) read -r -p "$(L MSG_PANEL_0228)" c; panels_docker_detail "$c" || return $? ;;
    8)
      read -p "$(L MSG_PANEL_0191)" c
      msg "$(L MSG_PANEL_0229)"
      read -p "$(L MSG_PANEL_0230)" r
      case "$r" in
        no|on-failure|always|unless-stopped)
          docker update --restart="$r" "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0231 "$r")" || msg_err "$(L MSG_PANEL_0232)"
          ;;
        *)
          msg_err "$(L MSG_PANEL_0233 "$r")"
          ;;
      esac
      ;;
  esac
  pause
}

# ---- Docker 网络管理 ----
panels_docker_network() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0027)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0234)"
  msg ""
  docker network ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "$(L MSG_PANEL_0235)"
  msg "$(L MSG_PANEL_0236)"
  msg "$(L MSG_PANEL_0237)"
  msg "$(L MSG_PANEL_0238)"
  msg "$(L MSG_PANEL_0051)"
  read -p "$(L MSG_PANEL_0036)" net_choice

  case "$net_choice" in
    1)
      read -p "$(L MSG_PANEL_0054)" net_name
      read -p "$(L MSG_PANEL_0239)" subnet
      if [[ -n "$net_name" ]]; then
        if [[ -n "$subnet" ]]; then
          docker network create --subnet "$subnet" "$net_name" 2>/dev/null
        else
          docker network create "$net_name" 2>/dev/null
        fi
        msg_ok "$(L MSG_PANEL_0240 "$net_name")"
      fi
      ;;
    2) read -p "$(L MSG_PANEL_0054)" n; docker network inspect "$n" 2>/dev/null ;;
    3)
      read -p "$(L MSG_PANEL_0054)" n; read -p "$(L MSG_PANEL_0191)" c
      docker network connect "$n" "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0241)"
      ;;
    4) read -p "$(L MSG_PANEL_0054)" n; confirm "$(L MSG_PANEL_0242)" && docker network rm "$n" 2>/dev/null && msg_ok "$(L MSG_PANEL_0243)" ;;
  esac
  pause
}

# ---- Docker 卷管理 ----
panels_docker_volumes() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0027)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0244)"
  msg ""
  docker volume ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "$(L MSG_PANEL_0245)"
  msg "$(L MSG_PANEL_0246)"
  msg "$(L MSG_PANEL_0247)"
  msg "$(L MSG_PANEL_0248)"
  msg "$(L MSG_PANEL_0051)"
  read -p "$(L MSG_PANEL_0036)" vol_choice

  case "$vol_choice" in
    1) read -p "$(L MSG_PANEL_0249)" v; docker volume create "$v" 2>/dev/null && msg_ok "$(L MSG_PANEL_0250 "$v")" ;;
    2) read -p "$(L MSG_PANEL_0249)" v; docker volume inspect "$v" 2>/dev/null ;;
    3) read -p "$(L MSG_PANEL_0249)" v; confirm "$(L MSG_PANEL_0242)" && docker volume rm "$v" 2>/dev/null && msg_ok "$(L MSG_PANEL_0243)" ;;
    4) confirm "$(L MSG_PANEL_0251)" && docker volume prune -f 2>/dev/null && msg_ok "$(L MSG_PANEL_0252)" ;;
  esac
  pause
}

panels_docker_menu() {
  while true; do
    clear
    msg_title "$(L MSG_PANEL_0253)"
    msg ""
    if command -v docker &>/dev/null; then
      msg "  Docker: $(docker --version 2>/dev/null)"
      local counts
      if counts=$(_panels_docker_read info --format 'Containers={{.Containers}} Running={{.ContainersRunning}} Paused={{.ContainersPaused}} Stopped={{.ContainersStopped}}'); then
        printf '  %s\n' "$counts"
      else
        msg "$(L MSG_PANEL_0254)"
      fi
    else
      msg "$(L MSG_PANEL_0255)"
    fi
    msg ""
    msg "$(L MSG_PANEL_0256 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0257 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0258 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0259 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0260 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0261 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0262 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0263 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0264 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0265 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0266 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0267 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0268 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0269 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0270 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0271 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0272 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0273 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0274 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_PANEL_0275)" dk_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$dk_choice" in
      1) panels_docker_install; pause ;;
      2) panels_docker_ps ;;
      3) panels_docker_images ;;
      4) panels_docker_compose ;;
      5) panels_docker_prune ;;
      6) panels_docker_port_control ;;
      7) panels_docker_ipv6 ;;
      8) panels_docker_daemon ;;
      9) panels_docker_backup ;;
      10) panels_docker_container_mgmt ;;
      11) panels_docker_network ;;
      12) panels_docker_volumes ;;
      13) panels_docker_mirror ;;
      14) panels_docker_summary --all; pause ;;
      15) local target; read -r -p "$(L MSG_PANEL_0228)" target; panels_docker_detail "$target"; pause ;;
      16) panels_docker_port_block menu ;;
      17) panels_docker_uninstall; pause ;;
      18) python3 "$FUSION_SRC/lib/docker_migration.py" --help; pause ;;
      0) break ;;
    esac
  done
}

# ---- Baota Panel ----
panels_bt() {
  _require_root
  msg_title "$(L MSG_PANEL_0276)"
  msg ""
  msg_warn "$(L MSG_PANEL_0277)"
  if [[ -d "/www/server/panel" ]] || command -v bt &>/dev/null; then
    msg_warn "$(L MSG_PANEL_0278)"
    pause; return
  fi
  if confirm "$(L MSG_PANEL_0279)"; then
    case "$F_PKG_MGR" in
      apt|yum)
        local bt_sh; bt_sh=$(mktemp)
        if _download "https://download.bt.cn/install/install_panel.sh" "$bt_sh"; then
          bash "$bt_sh" || msg_err "$(L MSG_PANEL_0280)"
        else
          msg_err "$(L MSG_PANEL_0281)"
        fi
        rm -f "$bt_sh"
        ;;
      *)
        msg_err "$(L MSG_PANEL_0282)"
        ;;
    esac
  fi
  pause
}

# ---- Aapanel ----
panels_aa() {
  _require_root
  msg_title "$(L MSG_PANEL_0283)"
  if [[ -d "/usr/local/aapanel" ]]; then
    msg_warn "$(L MSG_PANEL_0284)"
    pause; return
  fi
  if confirm "$(L MSG_PANEL_0279)"; then
    local aa_sh; aa_sh=$(mktemp)
    if _download "https://www.aapanel.com/script/install_7.0_en.sh" "$aa_sh"; then
      bash "$aa_sh" || msg_err "$(L MSG_PANEL_0285)"
    else
      msg_err "$(L MSG_PANEL_0286)"
    fi
    rm -f "$aa_sh"
  fi
  pause
}

# ---- X-UI ----
panels_xui() {
  _require_root
  msg_title "$(L MSG_PANEL_0287)"
  msg ""
  if confirm "$(L MSG_PANEL_0288)"; then
    local xui_sh; xui_sh=$(mktemp)
    if _download "https://raw.githubusercontent.com/vaxilu/x-ui/master/install.sh" "$xui_sh" && \
      bash "$xui_sh" 2>/dev/null; then
      :
    else
      rm -f "$xui_sh"
      xui_sh=$(mktemp)
      if _download "https://raw.githubusercontent.com/FranzKafkaYu/x-ui/master/install_en.sh" "$xui_sh" && \
        bash "$xui_sh" 2>/dev/null; then
        :
      else
        msg_err "$(L MSG_PANEL_0289)"
      fi
    fi
    rm -f "$xui_sh"
    _log_write "$(L MSG_PANEL_0290)"
  fi
  pause
}

# ---- Aria2 ----
panels_aria2() {
  _require_root
  msg_title "$(L MSG_PANEL_0291)"
  msg ""
  case "$F_PKG_MGR" in
    apt|yum|apk)
      _install_pkg aria2
      mkdir -p /etc/aria2
      local rpc_secret; rpc_secret=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
      cat > /etc/aria2/aria2.conf << AEOF
dir=/var/ftp
file-allocation=falloc
continue=true
daemon=true
max-connection-per-server=4
rpc-listen-all=true
rpc-allow-origin-all=true
rpc-secret=${rpc_secret}
AEOF
      chmod 600 /etc/aria2/aria2.conf
      mkdir -p /var/ftp
      msg_ok "$(L MSG_PANEL_0292 "${rpc_secret}")"
      msg_info "$(L MSG_PANEL_0293)"
      _log_write "$(L MSG_PANEL_0294)"
      ;;
    *)
      msg_err "$(L MSG_PANEL_0295)"
      ;;
  esac
  pause
}

# ---- Rclone ----
panels_rclone() {
  _require_root
  msg_title "$(L MSG_PANEL_0296)"
  msg ""
  if ! command -v rclone &>/dev/null; then
    msg_info "$(L MSG_PANEL_0297)"
    local rc_sh; rc_sh=$(mktemp)
    if _download "https://rclone.org/install.sh" "$rc_sh" && bash "$rc_sh"; then
      :
    else
      _install_pkg rclone
    fi
    rm -f "$rc_sh"
  fi

  if command -v rclone &>/dev/null; then
    msg_ok "$(L MSG_PANEL_0298 "$(rclone version --client 2>/dev/null | head -1)")"
    msg ""
    msg "$(L MSG_PANEL_0299)"
    msg "$(L MSG_PANEL_0300)"
    read -p "$(L MSG_PANEL_0036)" rc_choice
    case "$rc_choice" in
      1) rclone config ;;
      2) rclone listremotes 2>/dev/null | while read -r r; do msg "    $r"; done ;;
    esac
    _log_write "$(L MSG_PANEL_0301)"
  fi
  pause
}

# ---- FRP ----
panels_frp() {
  _require_root
  msg_title "$(L MSG_PANEL_0302)"
  msg ""
  msg "$(L MSG_PANEL_0303)"
  msg "$(L MSG_PANEL_0304)"
  read -p "$(L MSG_PANEL_0036)" frp_choice

  local frp_ver="0.58.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  local tmpdir=$(mktemp -d)
  local dl_url="https://github.com/fatedier/frp/releases/download/v${frp_ver}/frp_${frp_ver}_linux_${arch}.tar.gz"

  msg_info "$(L MSG_PANEL_0305 "${frp_ver}")"
  _download "$dl_url" "$tmpdir/frp.tar.gz" || {
    msg_err "$(L MSG_PANEL_0306)"
    rm -rf "$tmpdir"
    pause; return
  }

  tar xzf "$tmpdir/frp.tar.gz" -C "$tmpdir"
  local frp_dir="$tmpdir/frp_${frp_ver}_linux_${arch}"

  case "$frp_choice" in
    1)
      cp "$frp_dir/frps" /usr/local/bin/
      chmod +x /usr/local/bin/frps
      cp "$frp_dir/frps.toml" /etc/frps.toml 2>/dev/null || true
      cat > /lib/systemd/system/frps.service << FE1
[Unit]
Description=FRP Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frps.toml
Restart=on-failure
[Install]
WantedBy=multi-user.target
FE1
      systemctl daemon-reload 2>/dev/null
      systemctl enable --now frps 2>/dev/null
      msg_ok "$(L MSG_PANEL_0307)"
      ;;
    2)
      cp "$frp_dir/frpc" /usr/local/bin/
      chmod +x /usr/local/bin/frpc
      cp "$frp_dir/frpc.toml" /etc/frpc.toml 2>/dev/null || true
      cat > /lib/systemd/system/frpc.service << FE2
[Unit]
Description=FRP Client
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /etc/frpc.toml
Restart=on-failure
[Install]
WantedBy=multi-user.target
FE2
      systemctl daemon-reload 2>/dev/null
      systemctl enable --now frpc 2>/dev/null
      msg_ok "$(L MSG_PANEL_0308)"
      ;;
  esac
  rm -rf "$tmpdir"
  _log_write "$(L MSG_PANEL_0309 "$frp_choice")"
  pause
}

# ---- Nezha Monitoring ----
panels_nezha() {
  _require_root
  msg_title "$(L MSG_PANEL_0310)"
  msg ""
  if ! command -v curl &>/dev/null; then
    _install_pkg curl
  fi

  msg_info "$(L MSG_PANEL_0311)"
  msg_info "$(L MSG_PANEL_0312)"
  msg ""
  read -p "$(L MSG_PANEL_0313)" nezha_server
  read -p "$(L MSG_PANEL_0314)" nezha_secret

  if [[ -n "$nezha_server" && -n "$nezha_secret" ]]; then
    local nz_sh; nz_sh=$(mktemp)
    if _download "https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh" "$nz_sh" && \
      bash "$nz_sh" -s "$nezha_server" -p "$nezha_secret" 2>/dev/null; then
      :
    else
      msg_err "$(L MSG_PANEL_0315)"
    fi
    rm -f "$nz_sh"
    _log_write "$(L MSG_PANEL_0316)"
  fi
  pause
}

# ---- Help ----
panels_help() {
  msg_title "$(L MSG_PANEL_0317)"
  msg ""
  msg "$(L MSG_PANEL_0318)"
  msg "$(L MSG_PANEL_0319)"
  msg "$(L MSG_PANEL_0320)"
  msg "$(L MSG_PANEL_0321)"
  msg "$(L MSG_PANEL_0322)"
  msg "$(L MSG_PANEL_0323)"
  msg "$(L MSG_PANEL_0324)"
  msg "$(L MSG_PANEL_0325)"
  msg "$(L MSG_PANEL_0326)"
  msg "$(L MSG_PANEL_0327)"
  msg "$(L MSG_PANEL_0328)"
  msg "$(L MSG_PANEL_0329)"
  msg "$(L MSG_PANEL_0330)"
  msg "$(L MSG_PANEL_0331)"
  msg "$(L MSG_PANEL_0332)"
  msg "$(L MSG_PANEL_0333)"
  msg ""
}

# ---- Interactive Menu ----
panels_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_PANEL_0334)"
    msg ""
    msg "$(L MSG_PANEL_0335)"
    msg "$(L MSG_PANEL_0336)"
    msg "$(L MSG_PANEL_0337)"
    msg "$(L MSG_PANEL_0338)"
    msg "$(L MSG_PANEL_0339)"
    msg "$(L MSG_PANEL_0340)"
    msg "$(L MSG_PANEL_0341)"
    msg "$(L MSG_PANEL_0342)"
    msg "$(L MSG_PANEL_0343)"
    msg ""
    read -p "$(L MSG_PANEL_0344)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) panels_docker;;
      2) panels_bt ;;
      3) panels_aa ;;
      4) panels_xui ;;
      5) panels_aria2 ;;
      6) panels_rclone ;;
      7) panels_frp ;;
      8) panels_nezha ;;
      0) break ;;
    esac
  done
}
