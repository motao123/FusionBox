#!/bin/bash
# FusionBox 完整回归套件
#
# 安全前提：不安装软件包、不修改系统配置、不发起外部下载。
# 需要真实 Docker / 真实 SSH 的用例在各自测试内 mock 或跳过。
#
# ！新增测试必须登记到下面的 BASH_TESTS / PY_TESTS，否则不会被执行。
#   文件末尾的自检会在存在“未登记测试文件”时直接失败——这正是为了修掉
#   v1.33.0 之前 5 个 python 测试 + 1 个 bash 测试被静默漏跑的问题。
set -e
cd "$(dirname "$0")/.."

PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1; then
    PY="$candidate"
    break
  fi
done
if [[ -z "$PY" ]]; then
  echo "错误: 需要 python3（Python 3 是 FusionBox 的明确依赖）" >&2
  exit 1
fi

BASH_TESTS=(
  test_basic.sh
  test_help_dispatch.sh
  test_privacy_telemetry.sh
)

PY_TESTS=(
  test_config_keys.py
  test_system_safety.py
  test_user_admin.py
  test_fail2ban_panel.py
  test_env_nic.py
  test_docker_uninstall.py
  test_web_lifecycle.py
  test_misc_batch.py
  test_web_tune.py
  test_system_tools.py
  test_docker_diagnostics.py
  test_docker_migration.py
  test_docker_migration_restore.py
  test_archive_transfer.py
  test_archive_scopes.py
  test_acme_transaction.py
  test_cluster_nodes.py
  test_cluster_session.py
  test_oracle_tools.py
  test_ssh_preflight.py
  test_market_domain.py
  test_market_apps.py
  test_market_catalog.py
  test_compose_backup.py
  test_backup_jobs.py
  test_notifications.py
  test_reliability.py
  test_safety.py
  test_installer.py
  test_proxy_lifecycle.py
  test_release_downloads.py
)

# ---- 自检：不允许存在未登记的测试文件 ----
_registered=" ${BASH_TESTS[*]} ${PY_TESTS[*]} "
_unregistered=0
for f in tests/test_*.sh tests/test_*.py; do
  base="$(basename "$f")"
  if [[ "$_registered" != *" $base "* ]]; then
    echo "错误: 测试文件未登记到 comprehensive_test.sh: $base" >&2
    _unregistered=1
  fi
done
if [[ $_unregistered -ne 0 ]]; then
  echo "请在 BASH_TESTS / PY_TESTS 中登记上述文件后重试。" >&2
  exit 1
fi

echo "=========================================="
echo "FusionBox 完整回归套件"
echo "=========================================="

echo ""
echo "########## bash 测试 ##########"
for t in "${BASH_TESTS[@]}"; do
  echo ""
  echo ">>>>> $t"
  bash "tests/$t"
done

echo ""
echo "########## python 测试 ##########"
for t in "${PY_TESTS[@]}"; do
  echo ""
  echo ">>>>> $t"
  PYTHONDONTWRITEBYTECODE=1 "$PY" -B "tests/$t"
done

echo ""
echo "=========================================="
echo "全部回归通过（bash ${#BASH_TESTS[@]} 个 + python ${#PY_TESTS[@]} 个）"
echo "=========================================="
