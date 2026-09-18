#!/bin/bash
# Safe by default: no installation, system modification or external downloads.
set -e
cd "$(dirname "$0")/.."
bash tests/test_basic.sh
if command -v python >/dev/null 2>&1; then
  python tests/test_system_safety.py
  python tests/test_user_admin.py
  python tests/test_fail2ban_panel.py
  python tests/test_docker_diagnostics.py
  python tests/test_archive_transfer.py
  python tests/test_cluster_nodes.py
  python tests/test_market_domain.py
  python tests/test_market_apps.py
  python tests/test_compose_backup.py
  python tests/test_backup_jobs.py
  python tests/test_notifications.py
  python tests/test_reliability.py
  python tests/test_safety.py
  python tests/test_installer.py
  python tests/test_proxy_lifecycle.py
else
  python3 tests/test_system_safety.py
  python3 tests/test_user_admin.py
  python3 tests/test_fail2ban_panel.py
  python3 tests/test_docker_diagnostics.py
  python3 tests/test_archive_transfer.py
  python3 tests/test_cluster_nodes.py
  python3 tests/test_market_domain.py
  python3 tests/test_market_apps.py
  python3 tests/test_compose_backup.py
  python3 tests/test_backup_jobs.py
  python3 tests/test_notifications.py
  python3 tests/test_reliability.py
  python3 tests/test_safety.py
  python3 tests/test_installer.py
  python3 tests/test_proxy_lifecycle.py
fi
