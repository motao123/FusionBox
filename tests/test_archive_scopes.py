"""Scoped system archive regressions; isolated local files only."""
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import archive


class ArchiveScopes(unittest.TestCase):
    # 用户可见报错的措辞已在不同分支本地化（英文原文 vs 中文 + 下一步指引）。
    # 断言「拒绝了哪个条件」，而不是「用了哪句文案」——否则测试会随着文案本地化
    # 变成与被测行为无关的假失败。
    def refused(self, *wordings):
        return self.assertRaisesRegex(ValueError, '|'.join(wordings))

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        fixtures = {
            'etc/fusionbox/config': 'fusion',
            'etc/ssh/sshd_config': 'ssh',
            'etc/cron.d/job': 'cron',
            'var/www/index.html': 'web',
            'opt/docker/compose.yml': 'docker',
            'usr/local/bin/tool': 'tool',
            'home/alice/profile': 'home',
        }
        for name, text in fixtures.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.backup = self.root / 'backup.tar.gz'

    def test_manifest_audits_scope_owner_mode_and_hash(self):
        scopes = ['fusion', 'web', 'docker', 'ssh', 'cron', 'usr-local', 'home']
        archive.create(self.backup, scopes, self.root)
        data = archive.inspect(self.backup, scopes)
        self.assertEqual(data['owner'], archive.OWNER)
        self.assertEqual(data['scopes'], scopes)
        records = {entry['path']: entry for entry in data['entries']}
        record = records['etc/ssh/sshd_config']
        source_info = (self.root / record['path']).stat()
        self.assertEqual(record['owner'], {'uid': source_info.st_uid, 'gid': source_info.st_gid})
        self.assertEqual(record['mode'], (self.root / record['path']).stat().st_mode & 0o7777)
        self.assertEqual(record['sha256'], hashlib.sha256(b'ssh').hexdigest())
        self.assertEqual(data['database_consistency'].split(';')[0], 'excluded')

    @unittest.skipIf(os.name == 'nt', 'POSIX symlinks and FIFOs')
    def test_links_and_special_files_refused(self):
        (self.root / 'etc/ssh/link').symlink_to('/tmp')
        with self.refused('symlink', '符号链接'):
            archive.create(self.backup, 'ssh', self.root)
        (self.root / 'etc/ssh/link').unlink()
        os.mkfifo(self.root / 'etc/ssh/pipe')
        with self.refused('special', '特殊文件'):
            archive.create(self.backup, 'ssh', self.root)

    def test_scope_mismatch_and_tampered_hash_refused(self):
        archive.create(self.backup, 'ssh', self.root)
        with self.refused('not present', '不在该备份中'):
            archive.verify(self.backup, 'cron')
        damaged = self.root / 'damaged.tar.gz'
        with tarfile.open(self.backup, 'r:gz') as source, tarfile.open(damaged, 'w:gz') as target:
            for member in source.getmembers():
                payload = source.extractfile(member).read() if member.isfile() else None
                if member.name == 'etc/ssh/sshd_config':
                    payload = b'bad'
                    member.size = len(payload)
                target.addfile(member, io.BytesIO(payload) if payload is not None else None)
        with self.refused('checksum', '校验失败'):
            archive.verify(damaged, 'ssh')

    def test_preview_conflict_policies_and_selective_scope(self):
        archive.create(self.backup, ['ssh', 'cron'], self.root)
        with self.refused('conflicts', '目标已存在'):
            archive.preview(self.backup, ['ssh', 'cron'], self.root)
        replace = archive.preview(self.backup, ['ssh', 'cron'], self.root, 'replace')
        self.assertTrue(all(item['action'] == 'replace' for item in replace))
        skipped = archive.preview(self.backup, ['ssh', 'cron'], self.root, 'skip')
        self.assertTrue(all(item['action'] == 'skip' for item in skipped))
        subset = archive.preview(self.backup, ['ssh'], self.root, 'replace')
        self.assertEqual([item['root'] for item in subset], ['etc/ssh'])

    def test_replace_retains_previous_and_skip_preserves_current(self):
        archive.create(self.backup, ['ssh', 'cron'], self.root)
        (self.root / 'etc/ssh/sshd_config').write_text('current')
        (self.root / 'etc/cron.d/job').write_text('current cron')
        archive.restore(self.backup, ['ssh', 'cron'], self.root, 'replace')
        self.assertEqual((self.root / 'etc/ssh/sshd_config').read_text(), 'ssh')
        self.assertEqual((self.root / 'etc/cron.d/job').read_text(), 'cron')
        self.assertEqual(next((self.root / 'etc').glob('.fusionbox-restore-*/previous/sshd_config')).read_text(), 'current')
        second = self.root / 'second.tar.gz'
        archive.create(second, ['ssh'], self.root)
        (self.root / 'etc/ssh/sshd_config').write_text('keep')
        archive.restore(second, ['ssh'], self.root, 'skip')
        self.assertEqual((self.root / 'etc/ssh/sshd_config').read_text(), 'keep')

    def test_activation_failure_rolls_back_all_activated_roots(self):
        archive.create(self.backup, ['ssh', 'cron'], self.root)
        ssh = self.root / 'etc/ssh/sshd_config'
        cron = self.root / 'etc/cron.d/job'
        ssh.write_text('live ssh')
        cron.write_text('live cron')
        rename = Path.rename
        activations = 0

        def fail_second(path, destination):
            nonlocal activations
            if path.name == 'new':
                activations += 1
                if activations == 2:
                    raise OSError('injected')
            return rename(path, destination)

        with patch.object(Path, 'rename', fail_second):
            with self.assertRaises(OSError):
                archive.restore(self.backup, ['ssh', 'cron'], self.root, 'replace')
        self.assertEqual(ssh.read_text(), 'live ssh')
        self.assertEqual(cron.read_text(), 'live cron')

    def test_manifest_path_escape_rejected(self):
        unsafe = self.root / 'unsafe.tar.gz'
        manifest = {'format': archive.FORMAT, 'owner': archive.OWNER, 'scopes': ['ssh'],
                    'scope_roots': {'ssh': ['etc/ssh']}, 'roots': ['etc/ssh'],
                    'database_consistency': 'excluded', 'entries': []}
        with tarfile.open(unsafe, 'w:gz') as output:
            payload = json.dumps(manifest).encode()
            item = tarfile.TarInfo(archive.MANIFEST); item.size = len(payload)
            output.addfile(item, io.BytesIO(payload))
            item = tarfile.TarInfo('../escape'); item.size = 1
            output.addfile(item, io.BytesIO(b'x'))
        with self.assertRaisesRegex(ValueError, 'Unsafe'):
            archive.verify(unsafe, 'ssh')


if __name__ == '__main__':
    unittest.main(verbosity=2)
