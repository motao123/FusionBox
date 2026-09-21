"""Orchestrate a docker-v1 bundle onto a trusted cluster node over key-only SSH.

This module adds no new SSH, transfer or restore mechanics. It only sequences
capabilities that already exist and are individually tested:

* `archive_transfer.py --kind docker-v1` performs the verified transfer
  (SHA-256 checked in flight, atomic no-clobber publication, no extraction).
* `docker_migration.py preflight|restore|rollback` runs *on the target*, from the
  target's own installation, and owns the journal-backed transaction.

The point of the orchestration is the failure matrix: a target-side conflict, a
transfer interruption or a failed apply must never leave a half-migrated target.
Every failure after the restore has started triggers a target-side rollback; if
that rollback also fails the transaction ID is reported so a human can use
`docker-migration rollback` / `resume` directly.
"""
import argparse
import contextlib
import io
import json
import os
import re
import shlex
import subprocess
import sys

import archive_transfer
import cluster_nodes
import cluster_session
import docker_migration

REMOTE_SRC_DEFAULT = '/etc/fusionbox/src'
STORE_DEFAULT = '/var/lib/fusionbox/docker-migration-store'
DOCKER_MIGRATION = 'lib/docker_migration.py'
SAFE_PATH = re.compile(r'/[A-Za-z0-9_./-]+')
# Matches both "Restore complete. Transaction: <id>" (stdout, success) and the
# failure hint "use rollback or resume with transaction <id>" (stderr, no colon).
TRANSACTION = re.compile(r'transaction[:\s]+([a-f0-9]{32})', re.IGNORECASE)
HELP_TEXT = """Docker 跨主机迁移编排

用法: fusionbox panels docker-migration remote <节点> --bundle <离线包> --name <远端名> \\
         --key <私钥> --known-hosts <文件> [选项]

前置（缺一项即拒绝继续）:
  * 目标机已安装 FusionBox（默认 <远端源码>/lib/docker_migration.py）
  * 目标机 Docker 可用且守护进程应答；OS/架构一致由目标机 preflight 判定
  * 目标机传输落地目录已由运维预先创建为 0700 且属 SSH 用户（本工具不创建）

步骤（顺序执行，任一步失败即中止）:
  1. 本机：离线包校验 + 容器清单与摘要
  2. 目标机：环境门禁（python3 / docker / 守护进程 / FusionBox 安装 / 落地目录权限）
  3. 传输：archive_transfer --kind docker-v1（含摘要校验，源包保留）
  4. 目标机：只读 preflight（磁盘、inode、端口、同名容器/卷/网络冲突）
  5. 目标机：restore（事务化，--confirm-clean-target）
  6. 目标机：健康校验（声明的每个容器必须在运行）
  7. 失败且已进入 restore：目标机 rollback；rollback 也失败则报告事务 ID

选项:
  --remote-src <路径>      目标机 FusionBox 源码目录（默认 /etc/fusionbox/src）
  --remote-store <路径>    目标机落地目录（默认 /var/lib/fusionbox/docker-migration-store）
  --directory <路径>       本机节点清单目录（默认 /etc/fusionbox/cluster）
  --health-timeout <秒>    目标机健康等待上限（默认 120）
  --transfer-timeout <秒>  单次传输与目标机命令上限（默认 300）
  --dry-run                只做第 1、2 步；**不向目标机写入任何文件**
  --json                   额外输出一行机器可读摘要

注意: --dry-run 不传输，因此也不会执行第 4 步的目标机冲突预检——目标机侧
      预检需要离线包已经落地。需要完整预检请执行一次正式迁移。
"""


class Plan(object):
    """Attribute bag matching the shape archive_transfer.run() expects."""

    def __init__(self, **fields):
        self.__dict__.update(fields)


def _ssh(node, known_hosts, key, command, timeout=120):
    """Run one command on the target with the cluster session's strict options.

    Reuses cluster_session.key_options() so host-key pinning, agent bypass and
    password refusal are identical to `cluster session exec`; only output capture
    differs, because the orchestration has to read the target's stdout.
    """
    argv = (['ssh'] + cluster_session.key_options(node, known_hosts)
            + ['-o', 'IdentityFile=' + str(key), '-o', 'IdentitiesOnly=yes']
            + [cluster_session.target(node), command])
    try:
        return subprocess.run(argv, stdin=subprocess.DEVNULL, capture_output=True,
                              text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        raise RuntimeError('目标机命令超时（%d 秒）' % timeout)


def _remote_facts(node, known_hosts, key, remote_src, remote_store, timeout=60):
    """Read-only target gate: never installs, never writes."""
    migration = remote_src.rstrip('/') + '/' + DOCKER_MIGRATION
    store = shlex.quote(remote_store)
    script = (
        'set -u; '
        'echo "python3=$(python3 -c \'import sys;print("%d.%d" % sys.version_info[:2])\' 2>/dev/null)"; '
        'echo "docker=$(docker version --format \'{{.Server.Version}}\' 2>/dev/null)"; '
        'echo "ostype=$(docker info --format \'{{.OSType}}\' 2>/dev/null)"; '
        'echo "arch=$(docker info --format \'{{.Architecture}}\' 2>/dev/null)"; '
        'echo "migration=$(test -f ' + shlex.quote(migration) + ' && echo yes || echo no)"; '
        'echo "store=$(test -d ' + store + ' && stat -c %a ' + store + ' || echo missing)"'
    )
    result = _ssh(node, known_hosts, key, script, timeout=timeout)
    facts = {}
    for line in result.stdout.splitlines():
        if '=' in line:
            name, value = line.split('=', 1)
            facts[name.strip()] = value.strip()
    missing = [key_name for key_name in ('python3', 'docker', 'ostype', 'arch')
               if not facts.get(key_name)]
    if missing:
        detail = (result.stderr or result.stdout or '').strip().splitlines()
        raise RuntimeError('目标机环境门禁失败，缺少 %s（python3 或 Docker 守护进程不可用）: %s'
                           % (','.join(missing), detail[-1] if detail else 'no output'))
    return facts


def _remote_python(node, known_hosts, key, remote_src, arguments, timeout=600):
    script = 'exec python3 -B %s %s' % (
        shlex.quote(remote_src.rstrip('/') + '/' + DOCKER_MIGRATION),
        ' '.join(shlex.quote(str(item)) for item in arguments))
    return _ssh(node, known_hosts, key, script, timeout=timeout)


def _local_bundle(bundle):
    """Validate the bundle locally before anything touches the target."""
    path = cluster_nodes.safe(bundle)
    declaration = docker_migration.inspect_bundle(path)
    names = [item['name'] for item in declaration['containers']]
    with path.open('rb') as stream:
        sha256 = archive_transfer.digest(stream)
    return path, sha256, declaration, names


def _transfer(node_id, bundle, name, sha256, args):
    # archive_transfer prints its own confirmation line; the orchestration owns
    # the single machine-readable summary, so that line is swallowed here.
    with contextlib.redirect_stdout(io.StringIO()):
        archive_transfer.run(Plan(
            action='push', node=node_id, name=name, file=str(bundle), kind='docker-v1',
            scope=None, sha256=sha256, remote_root=args.remote_store, key=str(args.key),
            known_hosts=str(args.known_hosts), directory=str(args.directory),
            timeout=args.transfer_timeout, confirm_owned_store=True))


def _container_states(node, known_hosts, key, names, timeout=60):
    """Read-only target health probe; returns {name: 'running'|'stopped'|'absent'}."""
    # Go templates render booleans lowercase ("true"), not "True".
    script = ('for n in %s; do '
              'if docker inspect -f "{{.State.Running}}" "$n" >/dev/null 2>&1; then '
              'r=$(docker inspect -f "{{.State.Running}}" "$n"); '
              'if [ "$r" = true ]; then echo "$n=running"; else echo "$n=stopped"; fi; '
              'else echo "$n=absent"; fi; done'
              % ' '.join(shlex.quote(name) for name in names))
    result = _ssh(node, known_hosts, key, script, timeout=timeout)
    states = {}
    for line in result.stdout.splitlines():
        if '=' in line:
            name, value = line.split('=', 1)
            states[name.strip()] = value.strip()
    return states


def _journal_error(node, known_hosts, key, transaction, timeout=60):
    """Read the failure reason the target recorded in its journal."""
    script = ('python3 -c %s' % shlex.quote(
        "import json;print(json.load(open('/var/lib/fusionbox/docker-migration/%s/journal.json')).get('error',''))"
        % transaction))
    result = _ssh(node, known_hosts, key, script, timeout=timeout)
    return (result.stdout or '').strip()


def _rollback(node, known_hosts, key, args, transaction, summary, reason):
    """Best-effort target-side rollback; never hides the transaction identifier."""
    summary['rollback_reason'] = reason
    if not transaction:
        summary['rollback'] = 'skipped-no-transaction'
        summary['action_required'] = ('目标机可能已有残留资源，请在目标机用 '
                                      'fusionbox panels docker-migration 检查后手工处理')
        return
    result = _remote_python(node, known_hosts, key, args.remote_src,
                            ['rollback', transaction], timeout=args.transfer_timeout)
    if result.returncode:
        summary['rollback'] = 'failed'
        summary['recovery_required'] = True
        summary['action_required'] = ('在目标机执行 fusionbox panels docker-migration rollback %s '
                                      '或 resume %s' % (transaction, transaction))
    else:
        summary['rollback'] = 'rolled-back'
        summary['target_clean'] = True


def _report(summary, as_json):
    if as_json:
        print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
        return
    # Every field is optional: the summary may be reported for a failure that
    # happened before the target was even resolved.
    print('跨主机迁移摘要')
    print('  节点: %s (%s)' % (summary.get('node', '?'), summary.get('target', '?')))
    print('  离线包: %s' % summary.get('bundle', '?'))
    print('  摘要: %s' % summary.get('sha256', '?'))
    print('  步骤: %s' % (' -> '.join(summary.get('steps') or []) or '无'))
    print('  结果: %s' % summary.get('result', 'failed'))
    if summary.get('error'):
        print('  错误: %s' % summary['error'])
    if summary.get('transaction'):
        print('  事务: %s' % summary['transaction'])
    if summary.get('containers_state'):
        print('  容器: %s' % json.dumps(summary['containers_state'], ensure_ascii=False, sort_keys=True))
    if summary.get('rollback'):
        print('  回滚: %s' % summary['rollback'])
    if summary.get('note'):
        print('  说明: %s' % summary['note'])
    if summary.get('detail'):
        print('  详情: %s' % ' | '.join(str(item) for item in summary['detail']))
    if summary.get('action_required'):
        print('  需要处理: %s' % summary['action_required'])


def run(args):
    """Validate, orchestrate and report exactly once (success or failure)."""
    summary = {'node': getattr(args, 'node', ''), 'steps': [],
               'dry_run': bool(getattr(args, 'dry_run', False))}
    try:
        _run(args, summary)
    except Exception as error:
        summary['result'] = summary.get('result', 'failed')
        summary.setdefault('error', str(error))
        _report(summary, bool(getattr(args, 'json_output', False)))
        raise
    _report(summary, bool(getattr(args, 'json_output', False)))
    return summary


def _run(args, summary):
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_-]{0,63}', args.node):
        raise ValueError('节点标识非法')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,127}\.tar\.gz', args.name):
        raise ValueError('远端名必须以 .tar.gz 结尾且只含安全字符')
    for label, value in (('--remote-src', args.remote_src),
                         ('--remote-store', args.remote_store),
                         ('--known-hosts', str(args.known_hosts))):
        if not SAFE_PATH.fullmatch(value):
            raise ValueError(label + ' 必须是绝对路径且不含空白或选项引用')
    if not 1 <= args.health_timeout <= 3600:
        raise ValueError('--health-timeout 必须在 1..3600 秒')
    if not 1 <= args.transfer_timeout <= 3600:
        raise ValueError('--transfer-timeout 必须在 1..3600 秒')
    key = cluster_nodes.safe(args.key)
    known_hosts = cluster_nodes.safe(args.known_hosts)

    bundle, sha256, _declaration, names = _local_bundle(args.bundle)
    with cluster_nodes.locked(args.directory) as inventory:
        nodes = [n for n in cluster_nodes.legacy(inventory) if n['id'] == args.node]
    if len(nodes) != 1:
        raise ValueError('未知节点: ' + args.node)
    node = nodes[0]

    summary.update({'target': cluster_session.target(node), 'bundle': str(bundle),
                    'sha256': sha256, 'archive': args.name, 'containers': names})

    facts = _remote_facts(node, known_hosts, key, args.remote_src, args.remote_store)
    summary['remote'] = facts
    summary['steps'].append('gate')
    if facts.get('migration') != 'yes':
        raise RuntimeError('目标机未安装 FusionBox 迁移模块: '
                           + args.remote_src.rstrip('/') + '/' + DOCKER_MIGRATION)
    if facts.get('store') != '700':
        raise RuntimeError('目标机落地目录必须由运维预先创建为 0700，实测 mode=%s: %s'
                           % (facts.get('store'), args.remote_store))

    if args.dry_run:
        summary['result'] = 'dry-run'
        summary['note'] = ('未向目标机写入任何文件；目标机侧冲突预检需要离线包落地，'
                           '故未执行（正式迁移会执行）')
        return

    _transfer(node['id'], bundle, args.name, sha256, args)
    summary['steps'].append('transfer')

    remote_bundle = args.remote_store.rstrip('/') + '/' + args.name
    preflight = _remote_python(node, known_hosts, key, args.remote_src,
                               ['preflight', remote_bundle, '--external-volume-policy', 'reject'],
                               timeout=args.transfer_timeout)
    if preflight.returncode:
        detail = (preflight.stderr or preflight.stdout or '').strip().splitlines()
        summary['result'] = 'preflight-rejected'
        summary['detail'] = detail[-3:]
        summary['target_clean'] = True
        raise RuntimeError('目标机 preflight 拒绝；未创建任何资源。原文: '
                           + (detail[-1] if detail else 'no output'))
    summary['steps'].append('preflight')

    restore = _remote_python(node, known_hosts, key, args.remote_src,
                             ['restore', remote_bundle, '--confirm-clean-target',
                              '--health-timeout', str(args.health_timeout)],
                             timeout=args.health_timeout + args.transfer_timeout + 120)
    # The transaction id appears on stdout for success and inside the stderr
    # failure hint ("use rollback or resume with transaction <id>"); search both.
    match = TRANSACTION.search((restore.stdout or '') + '\n' + (restore.stderr or ''))
    transaction = match.group(1) if match else None
    summary['transaction'] = transaction
    if restore.returncode:
        detail = (restore.stderr or restore.stdout or '').strip().splitlines()
        summary['detail'] = detail[-3:]
        if transaction:
            reason = _journal_error(node, known_hosts, key, transaction)
            if reason:
                summary['detail'] = ['目标机 journal: ' + reason] + detail[-2:]
        _rollback(node, known_hosts, key, args, transaction, summary, '目标机 restore 失败')
        raise RuntimeError('目标机 restore 失败' + ('（事务 %s）' % transaction if transaction else '')
                           + '；已尝试回滚，结果见摘要。原文: '
                           + (detail[-1] if detail else 'no output'))
    summary['steps'].append('restore')

    if not transaction:
        # A restore reporting success must name its transaction; without it there is
        # no rollback path, so this is treated as a failure rather than reporting a
        # migration that cannot be undone.
        _rollback(node, known_hosts, key, args, None, summary, '目标机未返回事务 ID')
        raise RuntimeError('目标机 restore 未返回事务 ID；已按失败处理')

    states = _container_states(node, known_hosts, key, names)
    summary['containers_state'] = states
    unhealthy = {name: state for name, state in states.items() if state != 'running'}
    if unhealthy:
        detail = json.dumps(unhealthy, ensure_ascii=False, sort_keys=True)
        summary['detail'] = ['健康校验未通过: ' + detail]
        _rollback(node, known_hosts, key, args, transaction, summary, '目标机健康校验未通过')
        raise RuntimeError('目标机健康校验未通过: ' + detail + '；已尝试回滚')

    summary['steps'].append('health')
    summary['result'] = 'migrated'


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        print('参数有误: ' + message, file=sys.stderr)
        print(HELP_TEXT, file=sys.stderr)
        raise SystemExit(2)


def main(argv=None):
    os.umask(0o077)
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] in ('help', '--help', '-h'):
        print(HELP_TEXT)
        return
    parser = _Parser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    remote = sub.add_parser('remote')
    remote.add_argument('node')
    remote.add_argument('--bundle', required=True)
    remote.add_argument('--name', required=True, help='目标机上的离线包文件名，需以 .tar.gz 结尾')
    remote.add_argument('--key', required=True)
    remote.add_argument('--known-hosts', required=True)
    remote.add_argument('--remote-src', default=REMOTE_SRC_DEFAULT)
    remote.add_argument('--remote-store', default=STORE_DEFAULT)
    remote.add_argument('--directory', default='/etc/fusionbox/cluster')
    remote.add_argument('--health-timeout', type=int, default=120)
    remote.add_argument('--transfer-timeout', type=int, default=300)
    remote.add_argument('--dry-run', action='store_true')
    remote.add_argument('--json', dest='json_output', action='store_true')
    args = parser.parse_args(argv)
    if args.action == 'remote':
        try:
            run(args)
        except SystemExit:
            raise
        except Exception as error:
            # run() already reported the summary (including the error) exactly once.
            print('跨主机迁移失败: ' + str(error), file=sys.stderr)
            raise SystemExit(1)


if __name__ == '__main__':
    main()
