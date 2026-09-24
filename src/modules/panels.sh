# FusionBox Panels & Docker Management Module
# Docker, server panels, and utility tools

# ---- Chinese help for raw Python passthrough subcommands ----
# Without these, running the subcommand with no arguments exposed an English
# argparse usage dump. Mirrors the existing ssh-candidate behaviour.

panels_compose_backup_help() {
  msg_title "$(L MSG_PANEL_0345)"
  msg ""
  msg "$(L MSG_PANEL_0346)"
  msg ""
  msg "$(L MSG_PANEL_0347)"
  msg "$(L MSG_PANEL_0348 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0349 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0350 "${F_GREEN}" "${F_RESET}")"
  msg ""
  msg "$(L MSG_PANEL_0351)"
  msg "$(L MSG_PANEL_0352)"
  msg ""
}

panels_docker_migration_help() {
  msg_title "$(L MSG_PANEL_0353)"
  msg ""
  msg "$(L MSG_PANEL_0354)"
  msg ""
  msg "$(L MSG_PANEL_0347)"
  msg "$(L MSG_PANEL_0355 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0356 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0357 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0358 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0359 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0360 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0361 "${F_GREEN}" "${F_RESET}")"
  msg "$(L MSG_PANEL_0362)"
  msg ""
  msg "$(L MSG_PANEL_0363)"
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
      _require_docker_compose "$(L MSG_PANEL_0364)" || return 1
      _require_python3 "$(L MSG_PANEL_0364)" || return 1
      python3 "$FUSION_SRC/lib/compose_backup.py" "$@"
      ;;
    docker-migration)
      _require_root
      [[ $# -ge 1 ]] || { panels_docker_migration_help; return 2; }
      if [[ "$1" == "remote" ]]; then
        _require_python3 "$(L MSG_PANEL_0365)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration_remote.py" "$@"
      else
        _require_docker "$(L MSG_PANEL_0366)" || return 1
        _require_python3 "$(L MSG_PANEL_0366)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration.py" "$@"
      fi
      ;;
    docker|dk)            panels_docker "$@" ;;
    mirror|mirrors)       panels_docker_mirror "${1:-}" ;;
    bt|baota)             panels_bt ;;
    1panel)              panels_1panel ;;
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
        _require_python3 "$(L MSG_PANEL_0365)" || return 1
        python3 "$FUSION_SRC/lib/docker_migration_remote.py" "$@"
      else
        _require_docker "$(L MSG_PANEL_0366)" || return 1
        _require_python3 "$(L MSG_PANEL_0366)" || return 1
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
    msg_info "$(L MSG_PANEL_0367 "$(docker --version)")"
    return
  fi

  msg_info "$(L MSG_PANEL_0368)"
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
    msg_ok "$(L MSG_PANEL_0369 "$(docker --version 2>/dev/null)")"
    docker compose version 2>/dev/null | xargs -I{} msg_ok "Docker Compose: {}"
    _log_write "$(L MSG_PANEL_0370)"
  fi
  progress_end
}

panels_docker_ps() {
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0371)"
    return
  fi
  msg_title "$(L MSG_PANEL_0372)"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_images() {
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0371)"
    return
  fi
  msg_title "$(L MSG_PANEL_0373)"
  msg ""
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_prune() {
  _require_root
  if ! confirm "$(L MSG_PANEL_0374)"; then
    return
  fi
  docker system prune -a -f --volumes 2>/dev/null
  msg_ok "$(L MSG_PANEL_0375)"
  _log_write "$(L MSG_PANEL_0376)"
  pause
}

panels_docker_compose() {
  _require_root
  local project="${2:-}"
  local compose_dir="/opt/docker"
  mkdir -p "$compose_dir"

  if [[ -z "$project" ]]; then
    msg_title "$(L MSG_PANEL_0377)"
    msg ""
    find "$compose_dir" -name "docker-compose.yml" -o -name "compose.yaml" 2>/dev/null | while read -r f; do
      msg "  $(dirname "$f" | xargs basename)"
    done

    msg ""
    msg "$(L MSG_PANEL_0378)"
    msg "$(L MSG_PANEL_0379)"
    read -p "$(L MSG_PANEL_0380)" comp_choice

    case "$comp_choice" in
      1)
        read -p "$(L MSG_PANEL_0381)" project
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
      - "80:80"  # fb-expose: 站点入口需公网 80
    volumes:
      - ./html:/usr/share/nginx/html
YEOF
          chmod 600 "$proj_dir/docker-compose.yml"
          mkdir -p "$proj_dir/html"
          echo "$(L MSG_PANEL_0382)" > "$proj_dir/html/index.html"
          msg_ok "$(L MSG_PANEL_0383 "$project" "$proj_dir")"
        fi
        ;;
      2)
        msg_info "$(L MSG_PANEL_0384)"
        for f in "$compose_dir"/*/docker-compose.yml; do
          [[ -f "$f" ]] && docker compose -f "$f" up -d 2>/dev/null && msg_info "$(L MSG_PANEL_0385 "$(basename "$(dirname "$f")")")"
        done
        ;;
    esac
  else
    local proj_file="$compose_dir/$project/docker-compose.yml"
    if [[ -f "$proj_file" ]]; then
      docker compose -f "$proj_file" up -d 2>/dev/null && msg_ok "$(L MSG_PANEL_0386 "$project")" || msg_err "$(L MSG_PANEL_0387)"
    else
      msg_err "$(L MSG_PANEL_0388 "$project")"
    fi
  fi
  pause
}

# ---- Docker 端口访问控制 ----
panels_docker_port_control() {
  msg_err "$(L MSG_PANEL_0389)"
  msg_warn "$(L MSG_PANEL_0390)"
  return 1
}

# ---- Docker IPv6 网络配置 ----
panels_docker_ipv6() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "$(L MSG_PANEL_0391)"
  msg ""

  msg "$(L MSG_PANEL_0392)"
  msg "$(L MSG_PANEL_0393)"
  msg "$(L MSG_PANEL_0394)"
  msg "$(L MSG_PANEL_0395)"
  read -p "$(L MSG_PANEL_0380)" ipv6_choice

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
      msg_ok "$(L MSG_PANEL_0396)"
      _log_write "$(L MSG_PANEL_0396)"
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
        msg_ok "$(L MSG_PANEL_0397)"
      fi
      ;;
    3)
      read -p "$(L MSG_PANEL_0398)" net_name
      read -p "$(L MSG_PANEL_0399)" ipv6_subnet
      if [[ -n "$net_name" && -n "$ipv6_subnet" ]]; then
        docker network create --ipv6 --subnet "$ipv6_subnet" "$net_name" 2>/dev/null && \
          msg_ok "$(L MSG_PANEL_0400 "$net_name")" || msg_err "$(L MSG_PANEL_0401)"
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
  [[ "$container" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$ ]] || { msg_err "$(L MSG_PANEL_0402 "$container")"; return 1; }
  [[ "$proto" == "tcp" || "$proto" == "udp" ]] || { msg_err "$(L MSG_PANEL_0403 "$proto")"; return 1; }
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { msg_err "$(L MSG_PANEL_0404 "$port")"; return 1; }
}

_panels_pb_chain_ok() {
  iptables -nL DOCKER-USER &>/dev/null || { msg_err "$(L MSG_PANEL_0405)"; return 1; }
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
        msg "$(L MSG_PANEL_0406 "${F_BOLD}" "${F_RESET}")"
        printf '  %s\n' "$rules"
      else
        msg "$(L MSG_PANEL_0407)"
      fi
      ;;
    add)
      shift
      local container="${1:-}" proto="${2:-tcp}" port="${3:-}" ip rc=0
      [[ $# -eq 3 ]] || { msg_err "$(L MSG_PANEL_0408)"; return 2; }
      _panels_pb_validate "$container" "$proto" "$port" || return 1
      command -v docker &>/dev/null || { msg_err "$(L MSG_PANEL_0371)"; return 1; }
      _panels_pb_chain_ok || return 1
      local ips; ips=$(_panels_pb_container_ips "$container")
      [[ -n "$ips" ]] || { msg_err "$(L MSG_PANEL_0409 "$container")"; return 1; }
      msg_info "$(L MSG_PANEL_0410 "$container" "$proto" "$port" "$(echo $ips | tr '\n' ' ')")"
      msg_warn "$(L MSG_PANEL_0411)"
      confirm "$(L MSG_PANEL_0412)" || { msg_info "$(L MSG_PANEL_0413)"; return 1; }
      local mark; mark=$(_panels_pb_mark "$container" "$proto" "$port")
      local -a rules_added=()
      for ip in $ips; do
        if iptables -I DOCKER-USER 1 -p "$proto" -d "$ip" --dport "$port" \
             -m comment --comment "$mark" -j DROP; then
          rules_added+=("$ip")
        else
          msg_err "$(L MSG_PANEL_0414 "$ip")"
          rc=1
          break
        fi
      done
      if [[ $rc -ne 0 ]]; then
        for ip in "${rules_added[@]}"; do
          iptables -D DOCKER-USER -p "$proto" -d "$ip" --dport "$port" \
            -m comment --comment "$mark" -j DROP 2>/dev/null || true
        done
        msg_err "$(L MSG_PANEL_0415)"
        return 1
      fi
      msg_ok "$(L MSG_PANEL_0416)"
      _log_write "$(L MSG_PANEL_0417 "$container" "$proto" "$port" "$ips")"
      ;;
    del)
      shift
      local container="${1:-}" proto="${2:-tcp}" port="${3:-}" mark spec removed=0
      [[ $# -eq 3 ]] || { msg_err "$(L MSG_PANEL_0418)"; return 2; }
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
        msg_err "$(L MSG_PANEL_0419)"
        return 1
      fi
      msg_ok "$(L MSG_PANEL_0420 "$removed")"
      _log_write "$(L MSG_PANEL_0421 "$container" "$proto" "$port")"
      ;;
    menu)
      panels_docker_port_block list
      msg ""
      msg "$(L MSG_PANEL_0422)"
      msg "$(L MSG_PANEL_0423)"
      msg "$(L MSG_PANEL_0395)"
      read -p "$(L MSG_PANEL_0380)" pb_choice || { msg ""; return; }
      case "$pb_choice" in
        1|2)
          local pb_c pb_pr pb_po
          read -r -p "$(L MSG_PANEL_0424)" pb_c
          read -r -p "$(L MSG_PANEL_0425)" pb_pr
          read -r -p "$(L MSG_PANEL_0426)" pb_po
          if [[ "$pb_choice" == 1 ]]; then
            panels_docker_port_block add "$pb_c" "$pb_pr" "$pb_po"
          else
            panels_docker_port_block del "$pb_c" "$pb_pr" "$pb_po"
          fi
          ;;
      esac
      ;;
    *)
      msg_err "$(L MSG_PANEL_0427 "$action")"; return 2 ;;
  esac
}

# ---- Docker 一键卸载 (G30)：全部容器/镜像/卷/网络 + 包 + 数据目录（YES 门禁） ----

_panels_docker_pkgs() {
  printf '%s\n' docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose-plugin2 \
    docker.io docker-doc docker-compose podman-docker containerd runc
}

panels_docker_uninstall() {
  _require_root
  command -v docker &>/dev/null || { msg_err "$(L MSG_PANEL_0428)"; return 1; }
  command -v systemctl &>/dev/null || { msg_err "$(L MSG_PANEL_0429)"; return 1; }

  msg_title "$(L MSG_PANEL_0430)"
  msg ""
  # 只读统计先行；失败不伪装为零
  local c i v n du_stat
  c=$(docker ps -aq 2>/dev/null | wc -l); i=$(docker images -aq 2>/dev/null | wc -l)
  v=$(docker volume ls -q 2>/dev/null | wc -l); n=$(docker network ls -q 2>/dev/null | wc -l)
  du_stat=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
  msg "$(L MSG_PANEL_0431)"
  msg "$(L MSG_PANEL_0432 "$c" "$i" "$v" "$n")"
  msg "$(L MSG_PANEL_0433 "${du_stat:-未知或不存在}")"
  [[ -f /etc/docker/daemon.json ]] && msg "$(L MSG_PANEL_0434)"
  msg ""
  msg_warn "$(L MSG_PANEL_0435)"
  msg_warn "$(L MSG_PANEL_0436)"
  msg_info "$(L MSG_PANEL_0437)"
  confirm "$(L MSG_PANEL_0438)" || { msg_info "$(L MSG_PANEL_0413)"; return 1; }
  local ans
  read -r -p "$(L MSG_PANEL_0439)" ans || { msg_info "$(L MSG_PANEL_0413)"; return 1; }
  [[ "$ans" == "YES" ]] || { msg_info "$(L MSG_PANEL_0413)"; return 1; }

  local wipe="yes"
  read -r -p "$(L MSG_PANEL_0440)" ans || ans="yes"
  [[ "$ans" == "keep" ]] && wipe="no"

  msg_info "$(L MSG_PANEL_0441)"
  local ids; ids=$(docker ps -aq 2>/dev/null)
  [[ -n "$ids" ]] && docker stop $ids >/dev/null 2>&1
  [[ -n "$ids" ]] && docker rm -f $ids >/dev/null 2>&1
  msg_info "$(L MSG_PANEL_0442)"
  docker network prune -f >/dev/null 2>&1
  docker volume prune -af >/dev/null 2>&1
  ids=$(docker images -aq 2>/dev/null)
  [[ -n "$ids" ]] && docker rmi -f $ids >/dev/null 2>&1
  docker system prune -af >/dev/null 2>&1

  msg_info "$(L MSG_PANEL_0443)"
  systemctl disable --now docker.service docker.socket >/dev/null 2>&1
  systemctl disable --now containerd.service >/dev/null 2>&1

  msg_info "$(L MSG_PANEL_0444)"
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
      apt)    apt-get purge -y "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0445)"; return 1; } ;;
      yum)    yum remove -y "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0445)"; return 1; } ;;
      apk)    apk del "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0445)"; return 1; } ;;
      zypper) zypper remove -y "${installed_pkgs[@]}" || { msg_err "$(L MSG_PANEL_0445)"; return 1; } ;;
      *)      msg_err "$(L MSG_PANEL_0446)"; return 1 ;;
    esac
  else
    msg_warn "$(L MSG_PANEL_0447)"
  fi

  if [[ "$wipe" == "yes" ]]; then
    msg_info "$(L MSG_PANEL_0448)"
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  else
    msg_warn "$(L MSG_PANEL_0449)"
  fi

  if command -v docker &>/dev/null; then
    msg_warn "$(L MSG_PANEL_0450)"
    return 1
  fi
  msg_ok "$(L MSG_PANEL_0451)"
  _log_write "$(L MSG_PANEL_0452 "$wipe")"
}

# ---- Docker daemon.json 编辑 ----
panels_docker_daemon() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "$(L MSG_PANEL_0453)"
  msg ""

  if [[ -f "$daemon_json" ]]; then
    msg "$(L MSG_PANEL_0454 "${F_BOLD}" "${F_RESET}")"
    cat "$daemon_json" 2>/dev/null
  else
    msg "$(L MSG_PANEL_0455)"
  fi

  msg ""
  msg "$(L MSG_PANEL_0456)"
  msg "$(L MSG_PANEL_0457)"
  msg "$(L MSG_PANEL_0458)"
  msg "$(L MSG_PANEL_0459)"
  msg "$(L MSG_PANEL_0460)"
  msg "$(L MSG_PANEL_0395)"
  read -p "$(L MSG_PANEL_0380)" dm_choice

  case "$dm_choice" in
    1)
      read -p "$(L MSG_PANEL_0461)" mirror_url
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
        msg_ok "$(L MSG_PANEL_0462)"
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
      msg_ok "$(L MSG_PANEL_0463)"
      ;;
    3)
      read -p "$(L MSG_PANEL_0464)" dns_server
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
        msg_ok "$(L MSG_PANEL_0465 "$dns_server")"
      fi
      ;;
    4)
      ${EDITOR:-vi} "$daemon_json"
      systemctl restart docker 2>/dev/null
      ;;
    5)
      if confirm "$(L MSG_PANEL_0466)"; then
        rm -f "$daemon_json"
        systemctl restart docker 2>/dev/null
        msg_ok "$(L MSG_PANEL_0467)"
      fi
      ;;
  esac
  pause
}

# ---- Docker 镜像加速 / 换源 ----
# 预设镜像源 数据表，字段: 名称|URL
# 特殊占位: __official__ = 清空 registry-mirrors 恢复官方, __aliyun__ = 需输入阿里云 ID, __custom__ = 手动输入
PANELS_DOCKER_MIRRORS=(
  "$(L MSG_PANEL_0468)"
  "$(L MSG_PANEL_0469)"
  "$(L MSG_PANEL_0470)"
  "$(L MSG_PANEL_0471)"
  "$(L MSG_PANEL_0472)"
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

  msg "$(L MSG_PANEL_0473 "${F_BOLD}" "${daemon_json}" "${F_RESET}")"
  if [[ ! -f "$daemon_json" ]]; then
    msg "$(L MSG_PANEL_0474 "${F_YELLOW}" "${F_RESET}")"
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
    msg "$(L MSG_PANEL_0475 "${F_YELLOW}" "${F_RESET}")"
  else
    echo "$mirrors" | while IFS= read -r m; do
      [[ -n "$m" ]] && msg "    ${F_GREEN}${m}${F_RESET}"
    done
  fi
}

# 列出可选镜像源
_panels_docker_mirror_list() {
  local item name url shown num i=0
  msg "$(L MSG_PANEL_0476 "${F_BOLD}" "${F_RESET}")"
  for item in "${PANELS_DOCKER_MIRRORS[@]}"; do
    IFS='|' read -r name url <<< "$item"
    i=$((i + 1))
    case "$url" in
      __official__) shown="$(L MSG_PANEL_0477)" ;;
      __aliyun__)   shown="$(L MSG_PANEL_0478)" ;;
      __custom__)   shown="$(L MSG_PANEL_0479)" ;;
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
    msg_info "$(L MSG_PANEL_0480 "$bak_file")"
  else
    rm -f "$daemon_json"
    msg_info "$(L MSG_PANEL_0481)"
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
    msg_err "$(L MSG_PANEL_0482)"
    msg_info "$(L MSG_PANEL_0483)"
    pause
    return 1
  fi

  # 1) 备份现有配置
  mkdir -p /etc/docker || { msg_err "$(L MSG_PANEL_0484)"; pause; return 1; }
  mkdir -p "$bak_dir" || { msg_err "$(L MSG_PANEL_0485 "$bak_dir")"; pause; return 1; }
  if [[ -f "$daemon_json" ]]; then
    cp -a "$daemon_json" "$bak_file" || { msg_err "$(L MSG_PANEL_0486 "$daemon_json")"; pause; return 1; }
    existed=1
    msg_info "$(L MSG_PANEL_0487 "$daemon_json" "$bak_file")"
  else
    msg_info "$(L MSG_PANEL_0488 "$bak_dir")"
  fi

  # 2) 合并 registry-mirrors
  local src; src=$(mktemp)
  local new_json; new_json=$(mktemp)
  if [[ "$existed" -eq 1 ]]; then cp "$daemon_json" "$src"; else echo '{}' > "$src"; fi
  if ! _panels_docker_json_valid "$src" "$tool"; then
    msg_err "$(L MSG_PANEL_0489)"
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
    msg_err "$(L MSG_PANEL_0490)"
    rm -f "$src" "$new_json"
    pause
    return 1
  fi
  cat "$new_json" > "$daemon_json"
  chmod 600 "$daemon_json"
  rm -f "$src" "$new_json"
  msg_info "$(L MSG_PANEL_0491 "$daemon_json")"

  # 4) 重启并验证
  if ! systemctl restart docker 2>/dev/null; then
    msg_err "$(L MSG_PANEL_0492)"
    _panels_docker_mirror_rollback "$bak_file" "$existed"
    pause
    return 1
  fi

  sleep 1
  local info_raw; info_raw=$(docker info 2>/dev/null)
  if [[ -z "$info_raw" ]]; then
    msg_err "$(L MSG_PANEL_0493)"
    _panels_docker_mirror_rollback "$bak_file" "$existed"
    pause
    return 1
  fi

  msg ""
  local mirrors; mirrors=$(echo "$info_raw" | grep -A5 "Registry Mirrors")
  if [[ -n "$mirrors" ]]; then
    msg_ok "$(L MSG_PANEL_0494)"
    echo "$mirrors" | while IFS= read -r l; do msg "  $l"; done
  else
    msg_ok "$(L MSG_PANEL_0495)"
  fi
  _log_write "$(L MSG_PANEL_0496 "${label}" "${url:-（清空）}")"
  pause
  return 0
}

# 清空镜像源（恢复官方）
panels_docker_mirror_clear() {
  if confirm "$(L MSG_PANEL_0497)"; then
    _panels_docker_mirror_apply clear "$(L MSG_PANEL_0498)"
  fi
}

# 测试拉取
panels_docker_mirror_test() {
  msg_info "$(L MSG_PANEL_0499)"
  local out; out=$(timeout 30 docker pull hello-world 2>&1)
  local rc=$?
  msg ""
  if [[ $rc -eq 0 ]]; then
    msg_ok "$(L MSG_PANEL_0500)"
    echo "$out" | tail -2 | while IFS= read -r l; do msg "  $l"; done
  elif [[ $rc -eq 124 ]]; then
    msg_warn "$(L MSG_PANEL_0501)"
    msg_info "$(L MSG_PANEL_0502)"
  else
    msg_err "$(L MSG_PANEL_0503 "$rc")"
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
        local aliyun_id; aliyun_id=$(read_input "$(L MSG_PANEL_0504)")
        if [[ ! "$aliyun_id" =~ ^[a-zA-Z0-9]+$ ]]; then
          msg_err "$(L MSG_PANEL_0505 "$aliyun_id")"
          pause
          return 1
        fi
        _panels_docker_mirror_apply set "$(L MSG_PANEL_0506)" "https://${aliyun_id}.mirror.aliyuncs.com"
        ;;
      __custom__)
        local custom_url; custom_url=$(read_input "$(L MSG_PANEL_0507)")
        if [[ "$custom_url" != https://* ]]; then
          msg_err "$(L MSG_PANEL_0508 "$custom_url")"
          pause
          return 1
        fi
        _panels_docker_mirror_apply set "$(L MSG_PANEL_0509)" "$custom_url"
        ;;
      *)
        _panels_docker_mirror_apply set "$name" "$url"
        ;;
    esac
    return $?
  done
  msg_err "$(L MSG_PANEL_0510 "$want")"
  pause
  return 1
}

panels_docker_mirror() {
  _require_root
  local action="${1:-}"

  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0511)"
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
    msg_title "$(L MSG_PANEL_0512)"
    msg ""
    _panels_docker_mirror_show_current
    msg ""
    _panels_docker_mirror_list
    msg "$(L MSG_PANEL_0513 "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}" "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_PANEL_0380)" m_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
  [[ -d "$directory" && ! -L "$directory" && ! -e "$target" && ! -L "$target" ]] || { msg_err "$(L MSG_PANEL_0514)"; return 1; }
  stage=$(mktemp -d "$directory/.fusionbox-export.XXXXXX") || return 1
  trap 'rm -rf -- "$stage"' EXIT
  if ! docker "$operation" "$@" > "$stage/archive.tar" || [[ ! -s "$stage/archive.tar" ]]; then
    msg_err "$(L MSG_PANEL_0515)"
    return 1
  fi
  tar -tf "$stage/archive.tar" >/dev/null 2>&1 || { msg_err "$(L MSG_PANEL_0516)"; return 1; }
  ln -- "$stage/archive.tar" "$target" || { msg_err "$(L MSG_PANEL_0517)"; return 1; }
)

panels_docker_backup() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0371)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0518)"
  msg ""
  msg "$(L MSG_PANEL_0519)"
  msg "$(L MSG_PANEL_0520)"
  msg "$(L MSG_PANEL_0521)"
  msg "$(L MSG_PANEL_0522)"
  msg "$(L MSG_PANEL_0523)"
  msg "$(L MSG_PANEL_0524)"
  msg "$(L MSG_PANEL_0525)"
  msg_warn "$(L MSG_PANEL_0526)"
  msg "$(L MSG_PANEL_0395)"
  read -p "$(L MSG_PANEL_0380)" dbk_choice

  local backup_dir="/root/docker_backups"
  (umask 077; mkdir -p "$backup_dir") || return 1
  local date_str=$(date '+%Y%m%d_%H%M%S')

  case "$dbk_choice" in
    1)
      msg_warn "$(L MSG_PANEL_0527)"
      msg_warn "$(L MSG_PANEL_0528)"
      python3 "$FUSION_SRC/lib/docker_migration.py" --help
      msg "CLI: fusionbox panels docker migration export BUNDLE (--container NAME ... | --compose-project PROJECT) --confirm-stop-writers [--bind ABS_SOURCE=LOGICAL --confirm-bind ABS_SOURCE]"
      msg "$(L MSG_PANEL_0529)"
      msg "$(L MSG_PANEL_0530)"
      msg "$(L MSG_PANEL_0531)"
      msg "$(L MSG_PANEL_0532)"
      ;;
    2)
      local containers container
      containers=$(docker ps -a --format '{{.Names}}') || { msg_err "$(L MSG_PANEL_0533)"; return 1; }
      for container in $containers; do
        [[ "$container" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
        _panels_docker_archive "$backup_dir/${container}_${date_str}.tar" export "$container" || return 1
      done
      msg_ok "$(L MSG_PANEL_0534 "$backup_dir")"
      ;;
    3)
      read -r -p "$(L MSG_PANEL_0535)" c
      [[ "$c" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
      _panels_docker_archive "$backup_dir/${c}_${date_str}.tar" export "$c" || return 1
      msg_ok "$(L MSG_PANEL_0536)"
      ;;
    4)
      local images
      images=$(docker images -q) || { msg_err "$(L MSG_PANEL_0537)"; return 1; }
      [[ -n "$images" ]] || { msg_err "$(L MSG_PANEL_0538)"; return 1; }
      local -a image_ids
      mapfile -t image_ids <<< "$images"
      _panels_docker_archive "$backup_dir/all_images_${date_str}.tar" save "${image_ids[@]}" || return 1
      msg_ok "$(L MSG_PANEL_0539)"
      ;;
    5)
      local action project source
      msg_warn "$(L MSG_PANEL_0540)"
      read -r -p "$(L MSG_PANEL_0541)" action
      read -r -p "$(L MSG_PANEL_0542)" project
      read -r -p "$(L MSG_PANEL_0543)" source
      case "$action" in
        register)
          confirm "$(L MSG_PANEL_0544)" || return 1
          python3 "$FUSION_SRC/lib/compose_backup.py" register "$project" "$source" --confirm-owned-import || return 1 ;;
        backup|restore)
          confirm "$(L MSG_PANEL_0545)" || return 1
          python3 "$FUSION_SRC/lib/compose_backup.py" "$action" "$project" "$source" --confirm-stop-writers || return 1 ;;
        *) return 1 ;;
      esac
      ;;
    6)
      ls -lh "$backup_dir"/*.tar "$backup_dir"/*.tar.gz 2>/dev/null
      read -p "$(L MSG_PANEL_0546)" backup_file
      if [[ -f "$backup_dir/$backup_file" ]]; then
        if [[ "$backup_file" == *images*.tar ]]; then
          docker load -i "$backup_dir/$backup_file" 2>/dev/null && msg_ok "$(L MSG_PANEL_0547)"
        elif [[ "$backup_file" == *.tar.gz ]]; then
          msg_err "$(L MSG_PANEL_0548)"
          return 1
        else
          read -p "$(L MSG_PANEL_0549)" new_name
          docker import "$backup_dir/$backup_file" "$new_name" 2>/dev/null && msg_ok "$(L MSG_PANEL_0550 "$new_name")"
        fi
      fi
      ;;
    7)
      read -p "$(L MSG_PANEL_0535)" c
      read -p "$(L MSG_PANEL_0551)" remote_host
      [[ "$c" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
      [[ "$remote_host" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || { msg_err "$(L MSG_PANEL_0552)"; return 1; }
      local img_file="$backup_dir/${c}_${date_str}.tar"
      _panels_docker_archive "$img_file" export "$c" || return 1
      # Strict host checking; no transfer is attempted after a failed export.
      scp -o StrictHostKeyChecking=yes -- "$img_file" "${remote_host}:/tmp/" || { msg_err "$(L MSG_PANEL_0553)"; return 1; }
      msg_ok "$(L MSG_PANEL_0554)"
      msg "$(L MSG_PANEL_0555 "$(basename "$img_file")" "$c")"
      ;;
  esac
  pause
}

# ---- Docker 容器管理 ----
panels_docker_container_mgmt() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0371)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0556)"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "$(L MSG_PANEL_0557)"
  msg "$(L MSG_PANEL_0558)"
  msg "$(L MSG_PANEL_0559)"
  msg "$(L MSG_PANEL_0560)"
  msg "$(L MSG_PANEL_0561)"
  msg "$(L MSG_PANEL_0562)"
  msg "$(L MSG_PANEL_0563)"
  msg "$(L MSG_PANEL_0564)"
  msg "$(L MSG_PANEL_0565)"
  msg "$(L MSG_PANEL_0395)"
  read -p "$(L MSG_PANEL_0380)" cm_choice

  case "$cm_choice" in
    1) read -p "$(L MSG_PANEL_0535)" c; docker start "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0566 "$c")" ;;
    2) read -p "$(L MSG_PANEL_0535)" c; docker stop "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0567 "$c")" ;;
    3) read -p "$(L MSG_PANEL_0535)" c; docker restart "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0568 "$c")" ;;
    4)
      read -p "$(L MSG_PANEL_0535)" c
      if confirm "$(L MSG_PANEL_0569 "$c")"; then
        docker stop "$c" 2>/dev/null; docker rm "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0570 "$c")"
      fi
      ;;
    5) read -p "$(L MSG_PANEL_0535)" c; read -p "$(L MSG_PANEL_0571)" n; docker logs --tail "${n:-50}" "$c" 2>/dev/null ;;
    6) read -p "$(L MSG_PANEL_0535)" c; docker exec -it "$c" /bin/bash 2>/dev/null || docker exec -it "$c" /bin/sh 2>/dev/null ;;
    7) docker stats --no-stream 2>/dev/null ;;
    9) read -r -p "$(L MSG_PANEL_0572)" c; panels_docker_detail "$c" || return $? ;;
    8)
      read -p "$(L MSG_PANEL_0535)" c
      msg "$(L MSG_PANEL_0573)"
      read -p "$(L MSG_PANEL_0574)" r
      case "$r" in
        no|on-failure|always|unless-stopped)
          docker update --restart="$r" "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0575 "$r")" || msg_err "$(L MSG_PANEL_0576)"
          ;;
        *)
          msg_err "$(L MSG_PANEL_0577 "$r")"
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
    msg_err "$(L MSG_PANEL_0371)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0578)"
  msg ""
  docker network ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "$(L MSG_PANEL_0579)"
  msg "$(L MSG_PANEL_0580)"
  msg "$(L MSG_PANEL_0581)"
  msg "$(L MSG_PANEL_0582)"
  msg "$(L MSG_PANEL_0395)"
  read -p "$(L MSG_PANEL_0380)" net_choice

  case "$net_choice" in
    1)
      read -p "$(L MSG_PANEL_0398)" net_name
      read -p "$(L MSG_PANEL_0583)" subnet
      if [[ -n "$net_name" ]]; then
        if [[ -n "$subnet" ]]; then
          docker network create --subnet "$subnet" "$net_name" 2>/dev/null
        else
          docker network create "$net_name" 2>/dev/null
        fi
        msg_ok "$(L MSG_PANEL_0584 "$net_name")"
      fi
      ;;
    2) read -p "$(L MSG_PANEL_0398)" n; docker network inspect "$n" 2>/dev/null ;;
    3)
      read -p "$(L MSG_PANEL_0398)" n; read -p "$(L MSG_PANEL_0535)" c
      docker network connect "$n" "$c" 2>/dev/null && msg_ok "$(L MSG_PANEL_0585)"
      ;;
    4) read -p "$(L MSG_PANEL_0398)" n; confirm "$(L MSG_PANEL_0586)" && docker network rm "$n" 2>/dev/null && msg_ok "$(L MSG_PANEL_0587)" ;;
  esac
  pause
}

# ---- Docker 卷管理 ----
panels_docker_volumes() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "$(L MSG_PANEL_0371)"; pause; return
  fi

  msg_title "$(L MSG_PANEL_0588)"
  msg ""
  docker volume ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "$(L MSG_PANEL_0589)"
  msg "$(L MSG_PANEL_0590)"
  msg "$(L MSG_PANEL_0591)"
  msg "$(L MSG_PANEL_0592)"
  msg "$(L MSG_PANEL_0395)"
  read -p "$(L MSG_PANEL_0380)" vol_choice

  case "$vol_choice" in
    1) read -p "$(L MSG_PANEL_0593)" v; docker volume create "$v" 2>/dev/null && msg_ok "$(L MSG_PANEL_0594 "$v")" ;;
    2) read -p "$(L MSG_PANEL_0593)" v; docker volume inspect "$v" 2>/dev/null ;;
    3) read -p "$(L MSG_PANEL_0593)" v; confirm "$(L MSG_PANEL_0586)" && docker volume rm "$v" 2>/dev/null && msg_ok "$(L MSG_PANEL_0587)" ;;
    4) confirm "$(L MSG_PANEL_0595)" && docker volume prune -f 2>/dev/null && msg_ok "$(L MSG_PANEL_0596)" ;;
  esac
  pause
}

panels_docker_menu() {
  while true; do
    clear
    msg_title "$(L MSG_PANEL_0597)"
    msg ""
    if command -v docker &>/dev/null; then
      msg "  Docker: $(docker --version 2>/dev/null)"
      local counts
      if counts=$(_panels_docker_read info --format 'Containers={{.Containers}} Running={{.ContainersRunning}} Paused={{.ContainersPaused}} Stopped={{.ContainersStopped}}'); then
        printf '  %s\n' "$counts"
      else
        msg "$(L MSG_PANEL_0598)"
      fi
    else
      msg "$(L MSG_PANEL_0599)"
    fi
    msg ""
    msg "$(L MSG_PANEL_0600 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0601 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0602 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0603 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0604 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0605 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0606 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0607 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0608 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0609 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0610 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0611 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0612 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0613 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0614 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0615 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0616 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0617 "${F_GREEN}" "${F_RESET}")"
    msg "$(L MSG_PANEL_0618 "${F_GREEN}" "${F_RESET}")"
    msg ""
    read -p "$(L MSG_PANEL_0619)" dk_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
      15) local target; read -r -p "$(L MSG_PANEL_0572)" target; panels_docker_detail "$target"; pause ;;
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
  msg_title "$(L MSG_PANEL_0620)"
  msg ""
  msg_warn "$(L MSG_PANEL_0621)"
  if [[ -d "/www/server/panel" ]] || command -v bt &>/dev/null; then
    msg_warn "$(L MSG_PANEL_0622)"
    pause; return
  fi
  if confirm "$(L MSG_PANEL_0623)"; then
    case "$F_PKG_MGR" in
      apt|yum)
        local bt_sh; bt_sh=$(mktemp)
        # 渠道码取自 config.yaml 的 panels.bt_install_code（官方脚本把它作为 o= 上报安装统计
        # 并写入 o.pl 做装机归属，不是凭据）；留空即不带码安装，行为与宝塔默认一致
        local bt_code="${CONFIG_panels_bt_install_code:-}"
        local bt_args=()
        [[ -n "$bt_code" ]] && bt_args+=("$bt_code")
        if _download "https://download.bt.cn/install/install_panel.sh" "$bt_sh"; then
          bash "$bt_sh" ${bt_args[@]+"${bt_args[@]}"} || msg_err "$(L MSG_PANEL_0624)"
        else
          msg_err "$(L MSG_PANEL_0625)"
        fi
        rm -f "$bt_sh"
        ;;
      *)
        msg_err "$(L MSG_PANEL_0626)"
        ;;
    esac
  fi
  pause
}

# ---- 1Panel ----
panels_1panel() {
  _require_root
  msg_title "$(L MSG_PANEL_0627)"
  if [[ -d "/opt/1panel" ]] || command -v 1panel &>/dev/null; then
    msg_warn "$(L MSG_PANEL_0628)"
    pause; return
  fi
  if confirm "$(L MSG_PANEL_0623)"; then
    local p1_sh; p1_sh=$(mktemp)
    if _download "https://resource.fit2cloud.com/1panel/package/v2/quick_start.sh" "$p1_sh"; then
      bash "$p1_sh" || msg_err "$(L MSG_PANEL_0629)"
    else
      msg_err "$(L MSG_PANEL_0630)"
    fi
    rm -f "$p1_sh"
  fi
  pause
}

# ---- X-UI ----
panels_xui() {
  _require_root
  msg_title "$(L MSG_PANEL_0631)"
  msg ""
  if confirm "$(L MSG_PANEL_0632)"; then
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
        msg_err "$(L MSG_PANEL_0633)"
      fi
    fi
    rm -f "$xui_sh"
    _log_write "$(L MSG_PANEL_0634)"
  fi
  pause
}

# ---- Aria2 ----
panels_aria2() {
  _require_root
  msg_title "$(L MSG_PANEL_0635)"
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
      msg_ok "$(L MSG_PANEL_0636 "${rpc_secret}")"
      msg_info "$(L MSG_PANEL_0637)"
      _log_write "$(L MSG_PANEL_0638)"
      ;;
    *)
      msg_err "$(L MSG_PANEL_0639)"
      ;;
  esac
  pause
}

# ---- Rclone ----
panels_rclone() {
  _require_root
  msg_title "$(L MSG_PANEL_0640)"
  msg ""
  if ! command -v rclone &>/dev/null; then
    msg_info "$(L MSG_PANEL_0641)"
    local rc_sh; rc_sh=$(mktemp)
    if _download "https://rclone.org/install.sh" "$rc_sh" && bash "$rc_sh"; then
      :
    else
      _install_pkg rclone
    fi
    rm -f "$rc_sh"
  fi

  if command -v rclone &>/dev/null; then
    msg_ok "$(L MSG_PANEL_0642 "$(rclone version --client 2>/dev/null | head -1)")"
    msg ""
    msg "$(L MSG_PANEL_0643)"
    msg "$(L MSG_PANEL_0644)"
    read -p "$(L MSG_PANEL_0380)" rc_choice
    case "$rc_choice" in
      1) rclone config ;;
      2) rclone listremotes 2>/dev/null | while read -r r; do msg "    $r"; done ;;
    esac
    _log_write "$(L MSG_PANEL_0645)"
  fi
  pause
}

# ---- FRP ----
panels_frp() {
  _require_root
  msg_title "$(L MSG_PANEL_0646)"
  msg ""
  msg "$(L MSG_PANEL_0647)"
  msg "$(L MSG_PANEL_0648)"
  read -p "$(L MSG_PANEL_0380)" frp_choice

  local frp_ver="0.58.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  local tmpdir=$(mktemp -d)
  local dl_url="https://github.com/fatedier/frp/releases/download/v${frp_ver}/frp_${frp_ver}_linux_${arch}.tar.gz"

  msg_info "$(L MSG_PANEL_0649 "${frp_ver}")"
  _download "$dl_url" "$tmpdir/frp.tar.gz" || {
    msg_err "$(L MSG_PANEL_0650)"
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
      msg_ok "$(L MSG_PANEL_0651)"
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
      msg_ok "$(L MSG_PANEL_0652)"
      ;;
  esac
  rm -rf "$tmpdir"
  _log_write "$(L MSG_PANEL_0653 "$frp_choice")"
  pause
}

# ---- Nezha Monitoring ----
panels_nezha() {
  _require_root
  msg_title "$(L MSG_PANEL_0654)"
  msg ""
  if ! command -v curl &>/dev/null; then
    _install_pkg curl
  fi

  msg_info "$(L MSG_PANEL_0655)"
  msg_info "$(L MSG_PANEL_0656)"
  msg ""
  read -p "$(L MSG_PANEL_0657)" nezha_server
  read -p "$(L MSG_PANEL_0658)" nezha_secret

  if [[ -n "$nezha_server" && -n "$nezha_secret" ]]; then
    local nz_sh; nz_sh=$(mktemp)
    if _download "https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh" "$nz_sh" && \
      bash "$nz_sh" -s "$nezha_server" -p "$nezha_secret" 2>/dev/null; then
      :
    else
      msg_err "$(L MSG_PANEL_0659)"
    fi
    rm -f "$nz_sh"
    _log_write "$(L MSG_PANEL_0660)"
  fi
  pause
}

# ---- Help ----
panels_help() {
  msg_title "$(L MSG_PANEL_0661)"
  msg ""
  msg "$(L MSG_PANEL_0662)"
  msg "$(L MSG_PANEL_0663)"
  msg "$(L MSG_PANEL_0664)"
  msg "$(L MSG_PANEL_0665)"
  msg "$(L MSG_PANEL_0666)"
  msg "$(L MSG_PANEL_0667)"
  msg "$(L MSG_PANEL_0668)"
  msg "$(L MSG_PANEL_0669)"
  msg "$(L MSG_PANEL_0670)"
  msg "$(L MSG_PANEL_0671)"
  msg "$(L MSG_PANEL_0672)"
  msg "$(L MSG_PANEL_0673)"
  msg "$(L MSG_PANEL_0674)"
  msg "$(L MSG_PANEL_0675)"
  msg "$(L MSG_PANEL_0676)"
  msg "$(L MSG_PANEL_0677)"
  msg ""
}

# ---- Interactive Menu ----
panels_menu() {
  while true; do
    clear
    _print_banner
    msg_title "$(L MSG_PANEL_0678)"
    msg ""
    msg "$(L MSG_PANEL_0679)"
    msg "$(L MSG_PANEL_0680)"
    msg "$(L MSG_PANEL_0681)"
    msg "$(L MSG_PANEL_0682)"
    msg "$(L MSG_PANEL_0683)"
    msg "$(L MSG_PANEL_0684)"
    msg "$(L MSG_PANEL_0685)"
    msg "$(L MSG_PANEL_0686)"
    msg "$(L MSG_PANEL_0687)"
    msg ""
    read -p "$(L MSG_PANEL_0688)" choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
    case "$choice" in
      1) panels_docker;;
      2) panels_bt ;;
      3) panels_1panel ;;
      4) panels_xui ;;
      5) panels_aria2 ;;
      6) panels_rclone ;;
      7) panels_frp ;;
      8) panels_nezha ;;
      0) break ;;
    esac
  done
}
