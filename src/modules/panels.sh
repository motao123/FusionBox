# FusionBox Panels & Docker Management Module
# Docker, server panels, and utility tools

# ---- Chinese help for raw Python passthrough subcommands ----
# Without these, running the subcommand with no arguments exposed an English
# argparse usage dump. Mirrors the existing ssh-candidate behaviour.

panels_compose_backup_help() {
  msg_title "受管 Compose 备份 帮助"
  msg ""
  msg "  用法: fusionbox panels compose-backup <操作> <项目名> <路径> [选项]"
  msg ""
  msg "  操作:"
  msg "  ${F_GREEN}register${F_RESET} <项目名> <compose 文件>   注册受管项目（需 --confirm-owned-import）"
  msg "  ${F_GREEN}backup${F_RESET}   <项目名> <归档路径>        备份（需 --confirm-stop-writers）"
  msg "  ${F_GREEN}restore${F_RESET}  <项目名> <归档路径>        恢复（需 --confirm-stop-writers）"
  msg ""
  msg "  说明: 私有元数据可能包含密钥，错误输出不会打印 Docker 原始内容。"
  msg "  示例: fusionbox panels compose-backup register myapp /opt/myapp/compose.yml --confirm-owned-import"
  msg ""
}

panels_docker_migration_help() {
  msg_title "Docker 离线迁移 帮助"
  msg ""
  msg "  用法: fusionbox panels docker-migration <操作> [参数] [选项]"
  msg ""
  msg "  操作:"
  msg "  ${F_GREEN}export${F_RESET} <bundle>       导出（-容器/--compose-project 二选一）"
  msg "  ${F_GREEN}verify${F_RESET} <bundle>       校验离线包完整性"
  msg "  ${F_GREEN}preflight${F_RESET} <bundle>    只读目标兼容性与冲突预检"
  msg "  ${F_GREEN}restore${F_RESET} <bundle>      恢复（--confirm-clean-target 清空目标）"
  msg "  ${F_GREEN}rollback${F_RESET} <事务ID>     回滚"
  msg "  ${F_GREEN}resume${F_RESET} <事务ID>       续跑中断的恢复"
  msg ""
  msg "  示例: fusionbox panels docker-migration preflight ./mybundle"
  msg ""
}

panels_main() {
  local cmd="${1:-menu}"; shift || true

  case "$cmd" in
    compose-backup)
      _require_root
      [[ $# -ge 1 ]] || { panels_compose_backup_help; return 2; }
      _require_docker_compose "Compose 备份/恢复" || return 1
      _require_python3 "Compose 备份/恢复" || return 1
      python3 "$FUSION_SRC/lib/compose_backup.py" "$@"
      ;;
    docker-migration)
      _require_root
      [[ $# -ge 1 ]] || { panels_docker_migration_help; return 2; }
      _require_docker "Docker 离线迁移" || return 1
      _require_python3 "Docker 离线迁移" || return 1
      python3 "$FUSION_SRC/lib/docker_migration.py" "$@"
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
    *)                    panels_menu ;;
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
      _require_docker "Docker 离线迁移" || return 1
      _require_python3 "Docker 离线迁移" || return 1
      python3 "$FUSION_SRC/lib/docker_migration.py" "$@"
      ;;
    mirror|mirrors) panels_docker_mirror "${2:-}" ;;
    port-block|pb)  shift; panels_docker_port_block "$@" ;;
    uninstall)      panels_docker_uninstall ;;
    menu|"")      panels_docker_menu ;;
    *)            panels_docker_menu ;;
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
    msg_info "Docker 已安装: $(docker --version)"
    return
  fi

  msg_info "正在安装 Docker..."
  case "$F_PKG_MGR" in
    apt)
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sh /tmp/get-docker.sh 2>/dev/null
      ;;
    yum)
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sh /tmp/get-docker.sh 2>/dev/null
      ;;
    apk)
      _install_pkg docker docker-compose
      rc-update add docker default 2>/dev/null
      rc-service docker start 2>/dev/null
      return
      ;;
  esac

  systemctl enable docker 2>/dev/null
  systemctl start docker 2>/dev/null

  if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
    local compose_ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d'"' -f4)
    curl -L "https://github.com/docker/compose/releases/download/$compose_ver/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose 2>/dev/null && \
      chmod +x /usr/local/bin/docker-compose
  fi

  if command -v docker &>/dev/null; then
    msg_ok "Docker 安装完成: $(docker --version 2>/dev/null)"
    docker compose version 2>/dev/null | xargs -I{} msg_ok "Docker Compose: {}"
    _log_write "Docker 已安装"
  fi
}

panels_docker_ps() {
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"
    return
  fi
  msg_title "Docker 容器"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_images() {
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"
    return
  fi
  msg_title "Docker 镜像"
  msg ""
  docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done
  pause
}

panels_docker_prune() {
  _require_root
  if ! confirm "是否清理未使用的 Docker 资源？"; then
    return
  fi
  docker system prune -a -f --volumes 2>/dev/null
  msg_ok "Docker 清理完成"
  _log_write "Docker 已清理"
  pause
}

panels_docker_compose() {
  _require_root
  local project="${2:-}"
  local compose_dir="/opt/docker"
  mkdir -p "$compose_dir"

  if [[ -z "$project" ]]; then
    msg_title "Docker Compose 项目"
    msg ""
    find "$compose_dir" -name "docker-compose.yml" -o -name "compose.yaml" 2>/dev/null | while read -r f; do
      msg "  $(dirname "$f" | xargs basename)"
    done

    msg ""
    msg "  1) 创建新项目"
    msg "  2) 部署现有项目"
    read -p "请选择: " comp_choice

    case "$comp_choice" in
      1)
        read -p "请输入项目名: " project
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
          echo "由 FusionBox 部署" > "$proj_dir/html/index.html"
          msg_ok "项目 '$project' 已创建于 $proj_dir"
        fi
        ;;
      2)
        msg_info "正在自动部署所有项目..."
        for f in "$compose_dir"/*/docker-compose.yml; do
          [[ -f "$f" ]] && docker compose -f "$f" up -d 2>/dev/null && msg_info "  已部署: $(basename "$(dirname "$f")")"
        done
        ;;
    esac
  else
    local proj_file="$compose_dir/$project/docker-compose.yml"
    if [[ -f "$proj_file" ]]; then
      docker compose -f "$proj_file" up -d 2>/dev/null && msg_ok "$project 已部署" || msg_err "部署失败"
    else
      msg_err "未找到项目: $project"
    fi
  fi
  pause
}

# ---- Docker 端口访问控制 ----
panels_docker_port_control() {
  msg_err "旧端口开关已禁用：DOCKER-USER 的目标端口已经过 DNAT，不能按宿主端口安全匹配。"
  msg_warn "请在 Compose ports 中明确绑定宿主 IP（本机使用 127.0.0.1），重新部署并验证；现有规则需人工审查。容器+原始目标地址规则尚未实现。"
  return 1
}

# ---- Docker IPv6 网络配置 ----
panels_docker_ipv6() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "Docker IPv6 网络配置"
  msg ""

  msg "  1) 启用 Docker IPv6"
  msg "  2) 禁用 Docker IPv6"
  msg "  3) 创建 IPv6 网络"
  msg "  0) 返回"
  read -p "请选择: " ipv6_choice

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
      msg_ok "Docker IPv6 已启用"
      _log_write "Docker IPv6 已启用"
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
        msg_ok "Docker IPv6 已禁用"
      fi
      ;;
    3)
      read -p "网络名称: " net_name
      read -p "IPv6 子网 (如 fd00:1::/64): " ipv6_subnet
      if [[ -n "$net_name" && -n "$ipv6_subnet" ]]; then
        docker network create --ipv6 --subnet "$ipv6_subnet" "$net_name" 2>/dev/null && \
          msg_ok "IPv6 网络 '$net_name' 已创建" || msg_err "创建失败"
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
  [[ "$container" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,62}$ ]] || { msg_err "容器名无效: $container"; return 1; }
  [[ "$proto" == "tcp" || "$proto" == "udp" ]] || { msg_err "协议仅支持 tcp/udp: $proto"; return 1; }
  [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || { msg_err "端口必须是 1-65535: $port"; return 1; }
}

_panels_pb_chain_ok() {
  iptables -nL DOCKER-USER &>/dev/null || { msg_err "iptables DOCKER-USER 链不可用（Docker 未安装或过旧，或当前 nftables 环境不支持）；不做任何更改"; return 1; }
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
        msg "  ${F_BOLD}FusionBox 受管 DOCKER-USER 规则:${F_RESET}"
        printf '  %s\n' "$rules"
      else
        msg "  当前无 FusionBox 受管的容器端口封禁规则"
      fi
      ;;
    add)
      shift
      local container="${1:-}" proto="${2:-tcp}" port="${3:-}" ip rc=0
      [[ $# -eq 3 ]] || { msg_err "用法: fusionbox panels docker port-block add <容器名> <tcp|udp> <端口>"; return 2; }
      _panels_pb_validate "$container" "$proto" "$port" || return 1
      command -v docker &>/dev/null || { msg_err "Docker 未安装"; return 1; }
      _panels_pb_chain_ok || return 1
      local ips; ips=$(_panels_pb_container_ips "$container")
      [[ -n "$ips" ]] || { msg_err "容器不存在或没有 IPv4 地址: $container"; return 1; }
      msg_info "将封禁 容器=$container 协议=$proto 容器端口=$port 目标 IP: $(echo $ips | tr '\n' ' ')"
      msg_warn "规则不持久（重启后失效）；不支持 IPv6；容器重建后 IP 变化需先 del 旧规则"
      confirm "确认在 DOCKER-USER 插入 DROP 规则？" || { msg_info "已取消"; return 1; }
      local mark; mark=$(_panels_pb_mark "$container" "$proto" "$port")
      local -a rules_added=()
      for ip in $ips; do
        if iptables -I DOCKER-USER 1 -p "$proto" -d "$ip" --dport "$port" \
             -m comment --comment "$mark" -j DROP; then
          rules_added+=("$ip")
        else
          msg_err "iptables 插入失败（IP: $ip）"
          rc=1
          break
        fi
      done
      if [[ $rc -ne 0 ]]; then
        for ip in "${rules_added[@]}"; do
          iptables -D DOCKER-USER -p "$proto" -d "$ip" --dport "$port" \
            -m comment --comment "$mark" -j DROP 2>/dev/null || true
        done
        msg_err "已回滚本次已插入的规则"
        return 1
      fi
      msg_ok "封禁规则已插入 DOCKER-USER 顶部"
      _log_write "Docker 端口封禁: $container $proto $port ($ips)"
      ;;
    del)
      shift
      local container="${1:-}" proto="${2:-tcp}" port="${3:-}" mark spec removed=0
      [[ $# -eq 3 ]] || { msg_err "用法: fusionbox panels docker port-block del <容器名> <tcp|udp> <端口>"; return 2; }
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
        msg_err "未找到匹配的受管规则（容器 IP 可能已变化；用 port-block list 查看现存规则）"
        return 1
      fi
      msg_ok "已删除 $removed 条规则"
      _log_write "Docker 端口解封: $container $proto $port"
      ;;
    menu)
      panels_docker_port_block list
      msg ""
      msg "  1) 封禁容器端口"
      msg "  2) 解封容器端口"
      msg "  0) 返回"
      read -p "请选择: " pb_choice || { msg ""; return; }
      case "$pb_choice" in
        1|2)
          local pb_c pb_pr pb_po
          read -r -p "容器名: " pb_c
          read -r -p "协议 tcp/udp: " pb_pr
          read -r -p "端口: " pb_po
          if [[ "$pb_choice" == 1 ]]; then
            panels_docker_port_block add "$pb_c" "$pb_pr" "$pb_po"
          else
            panels_docker_port_block del "$pb_c" "$pb_pr" "$pb_po"
          fi
          ;;
      esac
      ;;
    *)
      msg_err "未知子命令: $action（可用: list/menu/add/del）"; return 2 ;;
  esac
}

# ---- Docker 一键卸载 (G30)：全部容器/镜像/卷/网络 + 包 + 数据目录（YES 门禁） ----

_panels_docker_pkgs() {
  printf '%s\n' docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose-plugin2 \
    docker.io docker-doc docker-compose podman-docker containerd runc
}

panels_docker_uninstall() {
  _require_root
  command -v docker &>/dev/null || { msg_err "未安装 Docker"; return 1; }
  command -v systemctl &>/dev/null || { msg_err "仅支持 systemd 环境"; return 1; }

  msg_title "Docker 一键卸载"
  msg ""
  # 只读统计先行；失败不伪装为零
  local c i v n du_stat
  c=$(docker ps -aq 2>/dev/null | wc -l); i=$(docker images -aq 2>/dev/null | wc -l)
  v=$(docker volume ls -q 2>/dev/null | wc -l); n=$(docker network ls -q 2>/dev/null | wc -l)
  du_stat=$(du -sh /var/lib/docker 2>/dev/null | awk '{print $1}')
  msg "  将删除的资源统计（当前）："
  msg "    容器: $c    镜像: $i    卷: $v    自定义网络: $n"
  msg "    数据目录 /var/lib/docker: ${du_stat:-未知或不存在}"
  [[ -f /etc/docker/daemon.json ]] && msg "    /etc/docker/daemon.json 存在（将随卸载删除）"
  msg ""
  msg_warn "无论容器/镜像/卷由谁创建（包括 FusionBox 市场、Compose 项目、手工部署），全部删除且数据不可恢复"
  msg_warn "依赖 Docker 的业务将立即中断；containerd 同时停用会影响本机其他容器运行时（如 Kubernetes）"
  msg_info "如需保留数据，请先备份：fusionbox panels docker backup / compose-backup / market managed"
  confirm "确认继续卸载 Docker？" || { msg_info "已取消"; return 1; }
  local ans
  read -r -p "请输入 YES 确认（其他输入取消）: " ans || { msg_info "已取消"; return 1; }
  [[ "$ans" == "YES" ]] || { msg_info "已取消"; return 1; }

  local wipe="yes"
  read -r -p "是否删除数据目录 /var/lib/docker /var/lib/containerd /etc/docker？[yes/keep，默认 yes]: " ans || ans="yes"
  [[ "$ans" == "keep" ]] && wipe="no"

  msg_info "停止并删除全部容器..."
  local ids; ids=$(docker ps -aq 2>/dev/null)
  [[ -n "$ids" ]] && docker stop $ids >/dev/null 2>&1
  [[ -n "$ids" ]] && docker rm -f $ids >/dev/null 2>&1
  msg_info "清理网络/卷/镜像..."
  docker network prune -f >/dev/null 2>&1
  docker volume prune -af >/dev/null 2>&1
  ids=$(docker images -aq 2>/dev/null)
  [[ -n "$ids" ]] && docker rmi -f $ids >/dev/null 2>&1
  docker system prune -af >/dev/null 2>&1

  msg_info "停用 docker / docker.socket 服务..."
  systemctl disable --now docker.service docker.socket >/dev/null 2>&1
  systemctl disable --now containerd.service >/dev/null 2>&1

  msg_info "按包管理器卸载软件包..."
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
      apt)    apt-get purge -y "${installed_pkgs[@]}" || { msg_err "软件包卸载失败"; return 1; } ;;
      yum)    yum remove -y "${installed_pkgs[@]}" || { msg_err "软件包卸载失败"; return 1; } ;;
      apk)    apk del "${installed_pkgs[@]}" || { msg_err "软件包卸载失败"; return 1; } ;;
      zypper) zypper remove -y "${installed_pkgs[@]}" || { msg_err "软件包卸载失败"; return 1; } ;;
      *)      msg_err "未知包管理器，请手动卸载软件包"; return 1 ;;
    esac
  else
    msg_warn "未检测到已安装的 Docker 相关软件包"
  fi

  if [[ "$wipe" == "yes" ]]; then
    msg_info "删除数据目录..."
    rm -rf /var/lib/docker /var/lib/containerd /etc/docker
  else
    msg_warn "数据目录已保留：/var/lib/docker /var/lib/containerd /etc/docker（重装后可能恢复）"
  fi

  if command -v docker &>/dev/null; then
    msg_warn "docker 命令仍存在，卸载可能不完整"
    return 1
  fi
  msg_ok "Docker 已卸载"
  _log_write "Docker 已卸载 (wipe=$wipe)"
}

# ---- Docker daemon.json 编辑 ----
panels_docker_daemon() {
  _require_root
  local daemon_json="/etc/docker/daemon.json"
  msg_title "Docker daemon.json 配置"
  msg ""

  if [[ -f "$daemon_json" ]]; then
    msg "  ${F_BOLD}当前配置:${F_RESET}"
    cat "$daemon_json" 2>/dev/null
  else
    msg "  当前使用默认配置"
  fi

  msg ""
  msg "  1) 配置镜像加速"
  msg "  2) 配置日志限制"
  msg "  3) 配置 DNS"
  msg "  4) 手动编辑 daemon.json"
  msg "  5) 重置为默认"
  msg "  0) 返回"
  read -p "请选择: " dm_choice

  case "$dm_choice" in
    1)
      read -p "请输入镜像加速地址: " mirror_url
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
        msg_ok "镜像加速已配置"
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
      msg_ok "日志限制已配置 (10MB x 3)"
      ;;
    3)
      read -p "DNS 服务器 (如 8.8.8.8): " dns_server
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
        msg_ok "DNS 已设为 $dns_server"
      fi
      ;;
    4)
      ${EDITOR:-vi} "$daemon_json"
      systemctl restart docker 2>/dev/null
      ;;
    5)
      if confirm "确认重置 daemon.json？"; then
        rm -f "$daemon_json"
        systemctl restart docker 2>/dev/null
        msg_ok "已重置为默认配置"
      fi
      ;;
  esac
  pause
}

# ---- Docker 镜像加速 / 换源 ----
# 预设镜像源 数据表，字段: 名称|URL
# 特殊占位: __official__ = 清空 registry-mirrors 恢复官方, __aliyun__ = 需输入阿里云 ID, __custom__ = 手动输入
PANELS_DOCKER_MIRRORS=(
  "官方(清空)|__official__"
  "DaoCloud(需自行验证)|https://docker.m.daocloud.io"
  "1ms(需自行验证)|https://docker.1ms.run"
  "阿里云(需输入ID)|__aliyun__"
  "自定义 URL|__custom__"
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

  msg "  ${F_BOLD}当前配置 (${daemon_json}):${F_RESET}"
  if [[ ! -f "$daemon_json" ]]; then
    msg "    ${F_YELLOW}未配置${F_RESET} - daemon.json 不存在，使用 Docker 官方仓库"
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
    msg "    ${F_YELLOW}未配置${F_RESET} - 使用 Docker 官方仓库"
  else
    echo "$mirrors" | while IFS= read -r m; do
      [[ -n "$m" ]] && msg "    ${F_GREEN}${m}${F_RESET}"
    done
  fi
}

# 列出可选镜像源
_panels_docker_mirror_list() {
  local item name url shown num i=0
  msg "  ${F_BOLD}可选镜像源:${F_RESET}"
  for item in "${PANELS_DOCKER_MIRRORS[@]}"; do
    IFS='|' read -r name url <<< "$item"
    i=$((i + 1))
    case "$url" in
      __official__) shown="清空 registry-mirrors，恢复 Docker 官方仓库" ;;
      __aliyun__)   shown="需输入你的阿里云 ID，生成专属加速地址" ;;
      __custom__)   shown="手动输入镜像源 URL" ;;
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
    msg_info "已回滚到备份: $bak_file"
  else
    rm -f "$daemon_json"
    msg_info "已删除新建的 daemon.json，恢复到未配置状态"
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
    msg_err "未找到 jq 或 python3，无法安全修改 JSON 配置"
    msg_info "请先安装: fusionbox market install jq"
    pause
    return 1
  fi

  # 1) 备份现有配置
  mkdir -p /etc/docker || { msg_err "无法创建 /etc/docker"; pause; return 1; }
  mkdir -p "$bak_dir" || { msg_err "无法创建备份目录: $bak_dir"; pause; return 1; }
  if [[ -f "$daemon_json" ]]; then
    cp -a "$daemon_json" "$bak_file" || { msg_err "备份失败: $daemon_json"; pause; return 1; }
    existed=1
    msg_info "已备份: $daemon_json -> $bak_file"
  else
    msg_info "未发现 daemon.json，将新建（备份目录: $bak_dir）"
  fi

  # 2) 合并 registry-mirrors
  local src; src=$(mktemp)
  local new_json; new_json=$(mktemp)
  if [[ "$existed" -eq 1 ]]; then cp "$daemon_json" "$src"; else echo '{}' > "$src"; fi
  if ! _panels_docker_json_valid "$src" "$tool"; then
    msg_err "现有 daemon.json 非法，拒绝覆盖"
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
    msg_err "生成的配置不是合法 JSON，已放弃写入（原配置未改动）"
    rm -f "$src" "$new_json"
    pause
    return 1
  fi
  cat "$new_json" > "$daemon_json"
  chmod 600 "$daemon_json"
  rm -f "$src" "$new_json"
  msg_info "已写入 $daemon_json（权限 600）"

  # 4) 重启并验证
  if ! systemctl restart docker 2>/dev/null; then
    msg_err "systemctl restart docker 失败，正在回滚配置"
    _panels_docker_mirror_rollback "$bak_file" "$existed"
    pause
    return 1
  fi

  sleep 1
  local info_raw; info_raw=$(docker info 2>/dev/null)
  if [[ -z "$info_raw" ]]; then
    msg_err "docker info 无输出（守护进程可能未正常启动），正在回滚配置"
    _panels_docker_mirror_rollback "$bak_file" "$existed"
    pause
    return 1
  fi

  msg ""
  local mirrors; mirrors=$(echo "$info_raw" | grep -A5 "Registry Mirrors")
  if [[ -n "$mirrors" ]]; then
    msg_ok "镜像源已生效:"
    echo "$mirrors" | while IFS= read -r l; do msg "  $l"; done
  else
    msg_ok "镜像源已清空，Docker 将使用官方仓库"
  fi
  _log_write "Docker 镜像源已更新: ${label} ${url:-（清空）}"
  pause
  return 0
}

# 清空镜像源（恢复官方）
panels_docker_mirror_clear() {
  if confirm "确认清空镜像源（恢复 Docker 官方仓库）？"; then
    _panels_docker_mirror_apply clear "官方(清空)"
  fi
}

# 测试拉取
panels_docker_mirror_test() {
  msg_info "正在通过当前镜像源拉取 hello-world 镜像（最长等待 30 秒）..."
  local out; out=$(timeout 30 docker pull hello-world 2>&1)
  local rc=$?
  msg ""
  if [[ $rc -eq 0 ]]; then
    msg_ok "拉取成功，当前镜像源工作正常"
    echo "$out" | tail -2 | while IFS= read -r l; do msg "  $l"; done
  elif [[ $rc -eq 124 ]]; then
    msg_warn "拉取超时（30 秒），当前镜像源较慢或不可用"
    msg_info "可返回上一级切换其他镜像源"
  else
    msg_err "拉取失败（退出码 $rc），当前镜像源可能不可用"
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
        local aliyun_id; aliyun_id=$(read_input "请输入阿里云加速器 ID (形如 abcd1234)")
        if [[ ! "$aliyun_id" =~ ^[a-zA-Z0-9]+$ ]]; then
          msg_err "无效的阿里云 ID（仅允许字母与数字）: $aliyun_id"
          pause
          return 1
        fi
        _panels_docker_mirror_apply set "阿里云" "https://${aliyun_id}.mirror.aliyuncs.com"
        ;;
      __custom__)
        local custom_url; custom_url=$(read_input "请输入镜像源 URL (https:// 开头)")
        if [[ "$custom_url" != https://* ]]; then
          msg_err "仅支持 https:// 开头的地址: $custom_url"
          pause
          return 1
        fi
        _panels_docker_mirror_apply set "自定义" "$custom_url"
        ;;
      *)
        _panels_docker_mirror_apply set "$name" "$url"
        ;;
    esac
    return $?
  done
  msg_err "未找到镜像源: $want（可用序号或名称）"
  pause
  return 1
}

panels_docker_mirror() {
  _require_root
  local action="${1:-}"

  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装，请先执行: fusionbox panels docker install"
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
    msg_title "Docker 镜像加速 / 换源"
    msg ""
    _panels_docker_mirror_show_current
    msg ""
    _panels_docker_mirror_list
    msg "  ${F_GREEN} t${F_RESET}) 测试拉取 hello-world  ${F_GREEN}c${F_RESET}) 清空镜像源（恢复官方）  ${F_GREEN}0${F_RESET}) 返回"
    msg ""
    read -p "请选择: " m_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
  [[ -d "$directory" && ! -L "$directory" && ! -e "$target" && ! -L "$target" ]] || { msg_err "归档目标冲突或目录无效"; return 1; }
  stage=$(mktemp -d "$directory/.fusionbox-export.XXXXXX") || return 1
  trap 'rm -rf -- "$stage"' EXIT
  if ! docker "$operation" "$@" > "$stage/archive.tar" || [[ ! -s "$stage/archive.tar" ]]; then
    msg_err "Docker 导出失败；未发布归档"
    return 1
  fi
  tar -tf "$stage/archive.tar" >/dev/null 2>&1 || { msg_err "归档校验失败"; return 1; }
  ln -- "$stage/archive.tar" "$target" || { msg_err "归档发布失败；旧目标保留"; return 1; }
)

panels_docker_backup() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "Docker 备份/迁移/恢复"
  msg ""
  msg "  1) 完整迁移 bundle 导出/verify（inspect + 镜像 + 本地卷/bind 冷备，不恢复）"
  msg "  2) 导出所有容器文件系统（旧 export；不含卷/运行配置）"
  msg "  3) 导出指定容器文件系统（旧 export；不含卷/运行配置）"
  msg "  4) 备份所有镜像"
  msg "  5) 受管 Compose 登记/具名卷备份/原项目恢复"
  msg "  6) 导入文件系统镜像/加载镜像"
  msg "  7) 传输容器文件系统（旧 export，不是完整迁移）"
  msg_warn "docker export 不包含卷、挂载数据、网络或运行配置，不能用于完整应用恢复。"
  msg "  0) 返回"
  read -p "请选择: " dbk_choice

  local backup_dir="/root/docker_backups"
  (umask 077; mkdir -p "$backup_dir") || return 1
  local date_str=$(date '+%Y%m%d_%H%M%S')

  case "$dbk_choice" in
    1)
      msg_warn "迁移导出会停止选中的 Docker 容器；宿主进程、其他运行时或网络存储写入者必须由你在外部冻结。"
      msg_warn "文件级导出不提供跨文件事务快照；数据库必须先做原生 dump/一致性停写。bundle 含环境变量等秘密。"
      python3 "$FUSION_SRC/lib/docker_migration.py" --help
      msg "CLI: fusionbox panels docker migration export BUNDLE (--container NAME ... | --compose-project PROJECT) --confirm-stop-writers [--bind ABS_SOURCE=LOGICAL --confirm-bind ABS_SOURCE]"
      msg "只读预检: fusionbox panels docker migration preflight BUNDLE [--bind-target LOGICAL=ABS_TARGET]"
      msg "干净目标恢复: fusionbox panels docker migration restore BUNDLE --confirm-clean-target [--bind-target LOGICAL=ABS_TARGET]"
      msg "事务恢复: fusionbox panels docker migration rollback|resume TRANSACTION_ID"
      msg "校验: fusionbox panels docker migration verify BUNDLE"
      ;;
    2)
      local containers container
      containers=$(docker ps -a --format '{{.Names}}') || { msg_err "容器列表读取失败"; return 1; }
      for container in $containers; do
        [[ "$container" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
        _panels_docker_archive "$backup_dir/${container}_${date_str}.tar" export "$container" || return 1
      done
      msg_ok "列出的容器文件系统已导出到 $backup_dir（不含卷/运行配置）"
      ;;
    3)
      read -r -p "容器名称: " c
      [[ "$c" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
      _panels_docker_archive "$backup_dir/${c}_${date_str}.tar" export "$c" || return 1
      msg_ok "容器文件系统已导出（不含卷/运行配置）"
      ;;
    4)
      local images
      images=$(docker images -q) || { msg_err "镜像列表读取失败"; return 1; }
      [[ -n "$images" ]] || { msg_err "没有镜像可导出"; return 1; }
      local -a image_ids
      mapfile -t image_ids <<< "$images"
      _panels_docker_archive "$backup_dir/all_images_${date_str}.tar" save "${image_ids[@]}" || return 1
      msg_ok "镜像归档已发布"
      ;;
    5)
      local action project source
      msg_warn "仅本机已创建的单 Compose 文件项目、本地具名卷；拒绝 bind/external/匿名卷。归档含私密元数据，请妥善保管。"
      read -r -p "操作 register / backup / restore: " action
      read -r -p "Compose 项目名: " project
      read -r -p "Compose 文件（登记）或归档绝对路径: " source
      case "$action" in
        register)
          confirm "确认拥有该项目并授权导入管理？" || return 1
          python3 "$FUSION_SRC/lib/compose_backup.py" register "$project" "$source" --confirm-owned-import || return 1 ;;
        backup|restore)
          confirm "确认允许停机且所有外部写入者已停止？仅停止本项目原运行容器；恢复与回滚双重失败保持停止并需人工恢复" || return 1
          python3 "$FUSION_SRC/lib/compose_backup.py" "$action" "$project" "$source" --confirm-stop-writers || return 1 ;;
        *) return 1 ;;
      esac
      ;;
    6)
      ls -lh "$backup_dir"/*.tar "$backup_dir"/*.tar.gz 2>/dev/null
      read -p "输入备份文件名: " backup_file
      if [[ -f "$backup_dir/$backup_file" ]]; then
        if [[ "$backup_file" == *images*.tar ]]; then
          docker load -i "$backup_dir/$backup_file" 2>/dev/null && msg_ok "镜像已恢复"
        elif [[ "$backup_file" == *.tar.gz ]]; then
          msg_err "旧 Compose 归档没有安全清单/卷元数据；拒绝向 / 解压，请在隔离目录人工审查。"
          return 1
        else
          read -p "新容器名称: " new_name
          docker import "$backup_dir/$backup_file" "$new_name" 2>/dev/null && msg_ok "已导入: $new_name"
        fi
      fi
      ;;
    7)
      read -p "容器名称: " c
      read -p "远程主机 (user@host): " remote_host
      [[ "$c" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || return 1
      [[ "$remote_host" =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*@[a-zA-Z0-9][a-zA-Z0-9.-]*$ ]] || { msg_err "远程地址必须为 user@host"; return 1; }
      local img_file="$backup_dir/${c}_${date_str}.tar"
      _panels_docker_archive "$img_file" export "$c" || return 1
      # Strict host checking; no transfer is attempted after a failed export.
      scp -o StrictHostKeyChecking=yes -- "$img_file" "${remote_host}:/tmp/" || { msg_err "传输失败；本地归档保留"; return 1; }
      msg_ok "文件系统归档已传输（不是完整备份/迁移）"
      msg "在远程审查后运行: docker import /tmp/$(basename "$img_file") $c"
      ;;
  esac
  pause
}

# ---- Docker 容器管理 ----
panels_docker_container_mgmt() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "容器管理"
  msg ""
  docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 启动容器"
  msg "  2) 停止容器"
  msg "  3) 重启容器"
  msg "  4) 删除容器"
  msg "  5) 查看容器日志"
  msg "  6) 进入容器终端"
  msg "  7) 查看资源占用"
  msg "  8) 设置自动重启"
  msg "  9) 只读容器详情（环境变量隐藏）"
  msg "  0) 返回"
  read -p "请选择: " cm_choice

  case "$cm_choice" in
    1) read -p "容器名称: " c; docker start "$c" 2>/dev/null && msg_ok "已启动: $c" ;;
    2) read -p "容器名称: " c; docker stop "$c" 2>/dev/null && msg_ok "已停止: $c" ;;
    3) read -p "容器名称: " c; docker restart "$c" 2>/dev/null && msg_ok "已重启: $c" ;;
    4)
      read -p "容器名称: " c
      if confirm "确认删除容器 $c？"; then
        docker stop "$c" 2>/dev/null; docker rm "$c" 2>/dev/null && msg_ok "已删除: $c"
      fi
      ;;
    5) read -p "容器名称: " c; read -p "行数 (默认50): " n; docker logs --tail "${n:-50}" "$c" 2>/dev/null ;;
    6) read -p "容器名称: " c; docker exec -it "$c" /bin/bash 2>/dev/null || docker exec -it "$c" /bin/sh 2>/dev/null ;;
    7) docker stats --no-stream 2>/dev/null ;;
    9) read -r -p "容器名称或 ID: " c; panels_docker_detail "$c" || return $? ;;
    8)
      read -p "容器名称: " c
      msg "  可选重启策略: no / on-failure / always / unless-stopped"
      read -p "请输入重启策略: " r
      case "$r" in
        no|on-failure|always|unless-stopped)
          docker update --restart="$r" "$c" 2>/dev/null && msg_ok "重启策略已设为 $r" || msg_err "设置失败"
          ;;
        *)
          msg_err "无效的重启策略: $r"
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
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "Docker 网络管理"
  msg ""
  docker network ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 创建网络"
  msg "  2) 查看网络详情"
  msg "  3) 连接容器到网络"
  msg "  4) 删除网络"
  msg "  0) 返回"
  read -p "请选择: " net_choice

  case "$net_choice" in
    1)
      read -p "网络名称: " net_name
      read -p "子网 (如 172.20.0.0/16，可留空): " subnet
      if [[ -n "$net_name" ]]; then
        if [[ -n "$subnet" ]]; then
          docker network create --subnet "$subnet" "$net_name" 2>/dev/null
        else
          docker network create "$net_name" 2>/dev/null
        fi
        msg_ok "网络 '$net_name' 已创建"
      fi
      ;;
    2) read -p "网络名称: " n; docker network inspect "$n" 2>/dev/null ;;
    3)
      read -p "网络名称: " n; read -p "容器名称: " c
      docker network connect "$n" "$c" 2>/dev/null && msg_ok "已连接"
      ;;
    4) read -p "网络名称: " n; confirm "确认删除？" && docker network rm "$n" 2>/dev/null && msg_ok "已删除" ;;
  esac
  pause
}

# ---- Docker 卷管理 ----
panels_docker_volumes() {
  _require_root
  if ! command -v docker &>/dev/null; then
    msg_err "Docker 未安装"; pause; return
  fi

  msg_title "Docker 卷管理"
  msg ""
  docker volume ls 2>/dev/null | while read -r line; do
    msg "  $line"
  done

  msg ""
  msg "  1) 创建卷"
  msg "  2) 查看卷详情"
  msg "  3) 删除卷"
  msg "  4) 清理未使用卷"
  msg "  0) 返回"
  read -p "请选择: " vol_choice

  case "$vol_choice" in
    1) read -p "卷名称: " v; docker volume create "$v" 2>/dev/null && msg_ok "卷 '$v' 已创建" ;;
    2) read -p "卷名称: " v; docker volume inspect "$v" 2>/dev/null ;;
    3) read -p "卷名称: " v; confirm "确认删除？" && docker volume rm "$v" 2>/dev/null && msg_ok "已删除" ;;
    4) confirm "清理所有未使用的卷？" && docker volume prune -f 2>/dev/null && msg_ok "已清理" ;;
  esac
  pause
}

panels_docker_menu() {
  while true; do
    clear
    msg_title "Docker 管理"
    msg ""
    if command -v docker &>/dev/null; then
      msg "  Docker: $(docker --version 2>/dev/null)"
      local counts
      if counts=$(_panels_docker_read info --format 'Containers={{.Containers}} Running={{.ContainersRunning}} Paused={{.ContainersPaused}} Stopped={{.ContainersStopped}}'); then
        printf '  %s\n' "$counts"
      else
        msg "  容器计数不可用（不是零）"
      fi
    else
      msg "  Docker 未安装"
    fi
    msg ""
    msg "  ${F_GREEN} 1${F_RESET}) 安装 Docker"
    msg "  ${F_GREEN} 2${F_RESET}) 列出容器"
    msg "  ${F_GREEN} 3${F_RESET}) 列出镜像"
    msg "  ${F_GREEN} 4${F_RESET}) Docker Compose / 项目"
    msg "  ${F_GREEN} 5${F_RESET}) 清理 (prune)"
    msg "  ${F_GREEN} 6${F_RESET}) 容器端口访问控制"
    msg "  ${F_GREEN} 7${F_RESET}) Docker IPv6 网络配置"
    msg "  ${F_GREEN} 8${F_RESET}) 编辑 daemon.json"
    msg "  ${F_GREEN} 9${F_RESET}) Docker 备份/迁移/恢复"
    msg "  ${F_GREEN}10${F_RESET}) 容器管理 (启动/停止/重启/删除)"
    msg "  ${F_GREEN}11${F_RESET}) 网络管理"
    msg "  ${F_GREEN}12${F_RESET}) 卷管理"
    msg "  ${F_GREEN}13${F_RESET}) 镜像加速 / 换源"
    msg "  ${F_GREEN}14${F_RESET}) 只读全局总览（含完整资源列表）"
    msg "  ${F_GREEN}15${F_RESET}) 只读容器详情（环境变量隐藏）"
    msg "  ${F_GREEN}16${F_RESET}) 容器端口封禁（DOCKER-USER 按容器）"
    msg "  ${F_GREEN}17${F_RESET}) Docker 一键卸载（YES 门禁）"
    msg "  ${F_GREEN}18${F_RESET}) 完整迁移 bundle 导出/预检/恢复/回滚帮助"
    msg "  ${F_GREEN} 0${F_RESET}) 返回"
    msg ""
    read -p "请选择 [0-18]: " dk_choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
      15) local target; read -r -p "容器名称或 ID: " target; panels_docker_detail "$target"; pause ;;
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
  msg_title "安装宝塔面板"
  msg ""
  msg_warn "宝塔面板是第三方服务器管理面板。"
  if [[ -d "/www/server/panel" ]] || command -v bt &>/dev/null; then
    msg_warn "检测到宝塔面板已安装，跳过重复安装"
    pause; return
  fi
  if confirm "确认继续安装？"; then
    case "$F_PKG_MGR" in
      apt|yum)
        local bt_sh; bt_sh=$(mktemp)
        if _download "https://download.bt.cn/install/install_panel.sh" "$bt_sh"; then
          bash "$bt_sh" || msg_err "宝塔面板安装失败"
        else
          msg_err "宝塔安装脚本下载失败"
        fi
        rm -f "$bt_sh"
        ;;
      *)
        msg_err "宝塔面板仅支持 apt/yum 系统"
        ;;
    esac
  fi
  pause
}

# ---- Aapanel ----
panels_aa() {
  _require_root
  msg_title "安装 Aapanel"
  if [[ -d "/usr/local/aapanel" ]]; then
    msg_warn "检测到 Aapanel 已安装，跳过重复安装"
    pause; return
  fi
  if confirm "确认继续安装？"; then
    local aa_sh; aa_sh=$(mktemp)
    if _download "https://www.aapanel.com/script/install_7.0_en.sh" "$aa_sh"; then
      bash "$aa_sh" || msg_err "Aapanel 安装失败"
    else
      msg_err "Aapanel 安装脚本下载失败"
    fi
    rm -f "$aa_sh"
  fi
  pause
}

# ---- X-UI ----
panels_xui() {
  _require_root
  msg_title "安装 X-UI 面板"
  msg ""
  if confirm "将执行第三方安装脚本安装 X-UI (xray 面板)，确认继续？"; then
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
        msg_err "X-UI 安装失败"
      fi
    fi
    rm -f "$xui_sh"
    _log_write "X-UI 已安装"
  fi
  pause
}

# ---- Aria2 ----
panels_aria2() {
  _require_root
  msg_title "安装 Aria2"
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
      msg_ok "Aria2 安装完成。RPC 密钥: ${rpc_secret}（请妥善保存）"
      msg_info "配置文件: /etc/aria2/aria2.conf"
      _log_write "Aria2 已安装"
      ;;
    *)
      msg_err "不支持的包管理器"
      ;;
  esac
  pause
}

# ---- Rclone ----
panels_rclone() {
  _require_root
  msg_title "配置 Rclone"
  msg ""
  if ! command -v rclone &>/dev/null; then
    msg_info "正在安装 rclone..."
    local rc_sh; rc_sh=$(mktemp)
    if _download "https://rclone.org/install.sh" "$rc_sh" && bash "$rc_sh"; then
      :
    else
      _install_pkg rclone
    fi
    rm -f "$rc_sh"
  fi

  if command -v rclone &>/dev/null; then
    msg_ok "rclone 已安装: $(rclone version --client 2>/dev/null | head -1)"
    msg ""
    msg "  1) 配置新远程存储（交互式）"
    msg "  2) 列出已配置的远程存储"
    read -p "请选择: " rc_choice
    case "$rc_choice" in
      1) rclone config ;;
      2) rclone listremotes 2>/dev/null | while read -r r; do msg "    $r"; done ;;
    esac
    _log_write "Rclone 已配置"
  fi
  pause
}

# ---- FRP ----
panels_frp() {
  _require_root
  msg_title "安装 FRP (内网穿透)"
  msg ""
  msg "  1) 安装 FRP 服务端"
  msg "  2) 安装 FRP 客户端"
  read -p "请选择: " frp_choice

  local frp_ver="0.58.0"
  local arch="amd64"
  [[ "$F_ARCH" == "arm64" ]] && arch="arm64"

  local tmpdir=$(mktemp -d)
  local dl_url="https://github.com/fatedier/frp/releases/download/v${frp_ver}/frp_${frp_ver}_linux_${arch}.tar.gz"

  msg_info "正在下载 FRP v${frp_ver}..."
  _download "$dl_url" "$tmpdir/frp.tar.gz" || {
    msg_err "下载失败"
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
      msg_ok "FRP 服务端已安装"
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
      msg_ok "FRP 客户端已安装"
      ;;
  esac
  rm -rf "$tmpdir"
  _log_write "FRP 已安装 (类型: $frp_choice)"
  pause
}

# ---- Nezha Monitoring ----
panels_nezha() {
  _require_root
  msg_title "安装哪吒监控 Agent"
  msg ""
  if ! command -v curl &>/dev/null; then
    _install_pkg curl
  fi

  msg_info "正在安装哪吒监控 Agent..."
  msg_info "需要先运行哪吒监控服务端。"
  msg ""
  read -p "服务端地址（如 example.com:8008）: " nezha_server
  read -p "客户端密钥: " nezha_secret

  if [[ -n "$nezha_server" && -n "$nezha_secret" ]]; then
    local nz_sh; nz_sh=$(mktemp)
    if _download "https://raw.githubusercontent.com/nezhahq/scripts/main/install.sh" "$nz_sh" && \
      bash "$nz_sh" -s "$nezha_server" -p "$nezha_secret" 2>/dev/null; then
      :
    else
      msg_err "安装失败"
    fi
    rm -f "$nz_sh"
    _log_write "哪吒监控 Agent 已配置"
  fi
  pause
}

# ---- Help ----
panels_help() {
  msg_title "面板与工具 帮助"
  msg ""
  msg "  fusionbox panels compose-backup   受管 Compose register/backup/restore（--help）"
  msg "  fusionbox panels docker-migration --help  Docker 离线迁移导出/校验/只读预检/恢复/回滚/续跑"
  msg "  fusionbox panels docker           Docker 管理"
  msg "  fusionbox panels docker summary [--all]  只读计数/磁盘用量；--all 完整列表"
  msg "  fusionbox panels docker detail NAME_OR_ID  只读详情/限额/占用；环境变量隐藏"
  msg "  fusionbox panels docker mirror    Docker 镜像加速 / 换源"
  msg "  fusionbox panels mirror           Docker 镜像加速 / 换源"
  msg "  fusionbox panels mirror test      测试拉取 hello-world"
  msg "  fusionbox panels mirror clear     清空镜像源（恢复官方）"
  msg "  fusionbox panels bt               安装宝塔面板"
  msg "  fusionbox panels aa               安装 Aapanel"
  msg "  fusionbox panels xui              安装 X-UI"
  msg "  fusionbox panels aria2            安装 Aria2"
  msg "  fusionbox panels rclone           配置 Rclone"
  msg "  fusionbox panels frp              安装 FRP"
  msg "  fusionbox panels nezha            安装哪吒监控 Agent"
  msg ""
}

# ---- Interactive Menu ----
panels_menu() {
  while true; do
    clear
    _print_banner
    msg_title "面板与工具"
    msg ""
    msg "  1) Docker 管理"
    msg "  2) 安装宝塔面板"
    msg "  3) 安装 Aapanel"
    msg "  4) 安装 X-UI"
    msg "  5) 安装 Aria2"
    msg "  6) 配置 Rclone"
    msg "  7) 安装 FRP"
    msg "  8) 安装哪吒监控 Agent"
    msg "  0) 返回主菜单"
    msg ""
    read -p "请选择 [0-8]: " choice || { msg ""; break; }   # stdin 关闭时退出，防死循环
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
