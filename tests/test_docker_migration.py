"""Docker migration bundle and policy regressions; no Docker daemon required."""
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
import docker_migration as dm


class DockerMigration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.volume = self.root / 'volume'
        self.volume.mkdir()
        (self.volume / 'value').write_text('cold data')
        self.bind = self.root / 'bind'
        self.bind.mkdir()
        (self.bind / 'config').write_text('bind data')
        self.bundle = self.root / 'bundle.tar.gz'
        self.container = {
            'Id': 'c1', 'Name': '/fixture', 'Image': 'sha256:image', 'Created': 'now',
            'State': {'Running': True},
            'Config': {'Image': 'repo:tag', 'Env': ['SECRET=value'], 'Entrypoint': ['/entry'],
                       'Cmd': ['run'], 'User': '1000', 'WorkingDir': '/app', 'ExposedPorts': {'8080/tcp': {}},
                       'Healthcheck': {'Test': ['CMD', 'true']}, 'Labels': {'app': 'fixture'}},
            'HostConfig': {'RestartPolicy': {'Name': 'always'},
                           'PortBindings': {'8080/tcp': [{'HostIp': '127.0.0.1', 'HostPort': '18080'}]},
                           'Memory': 1024, 'NetworkMode': 'fixture-net'},
            'NetworkSettings': {'Networks': {'fixture-net': {'Aliases': ['app'], 'IPAddress': '172.20.0.2',
                                                               'GlobalIPv6Address': '', 'IPPrefixLen': 16,
                                                               'GlobalIPv6PrefixLen': 0}}},
            'Mounts': [],
        }
        self.declaration = {
            'format': dm.FORMAT, 'owner': dm.OWNER, 'selection': {'kind': 'containers', 'requested': ['fixture']},
            'engine': {}, 'containers': [dm.container_declaration(self.container)],
            'images': [{'id': 'sha256:image', 'repo_digests': ['repo@sha256:digest'],
                        'architecture': 'amd64', 'os': 'linux', 'variant': None}],
            'networks': [], 'data': {'volumes': {'fixture_data': 'data/volumes/0'},
                                     'binds': {str(self.bind): {'logical': 'app-config',
                                                                'path': 'data/binds/app-config'}}},
        }

    def image_save(self, *args, stdout=None):
        self.assertEqual(args[:2], ('image', 'save'))
        self.assertEqual(args[2:], ('sha256:image',))
        with tarfile.open(fileobj=stdout, mode='w') as archive:
            payload = b'{}'
            info = tarfile.TarInfo('manifest.json')
            info.size = len(payload)
            archive.addfile(info, io.BytesIO(payload))
        return b''

    def test_bundle_manifest_hash_size_and_declaration(self):
        fixture = json.loads((Path(__file__).parent / 'fixtures/docker_migration_declaration.json').read_text())
        self.assertEqual(fixture['owner'], dm.OWNER)
        self.assertEqual(fixture['expected']['ports'], self.declaration['containers'][0]['ports'])
        with patch.object(dm, 'docker', side_effect=self.image_save):
            dm.package(self.bundle, [self.container], {'fixture_data': self.volume},
                       {str(self.bind): 'app-config'}, self.declaration)
        declaration = dm.inspect_bundle(self.bundle)
        self.assertEqual(declaration['containers'][0]['ports']['8080/tcp'][0]['HostIp'], '127.0.0.1')
        self.assertEqual(declaration['containers'][0]['environment'], ['SECRET=value'])
        self.assertEqual(declaration['containers'][0]['networks']['fixture-net']['aliases'], ['app'])
        with tarfile.open(self.bundle, 'r:gz') as archive:
            manifest = json.load(archive.extractfile(dm.MANIFEST))
            files = [entry for entry in manifest['entries'] if entry['type'] == 'file']
            self.assertTrue(all(set(('size', 'sha256')).issubset(entry) for entry in files))
            self.assertEqual(archive.getmembers()[-1].name, dm.MANIFEST)

    def rewrite(self, transform):
        with tarfile.open(self.bundle, 'r:gz') as source:
            members = [(member, source.extractfile(member).read() if member.isfile() else None)
                       for member in source.getmembers()]
        bad = self.root / 'bad.tar.gz'
        with tarfile.open(bad, 'w:gz') as output:
            for member, payload in transform(members):
                output.addfile(member, io.BytesIO(payload) if payload is not None else None)
        return bad

    def test_payload_tamper_and_extra_member_rejected(self):
        with patch.object(dm, 'docker', side_effect=self.image_save):
            dm.package(self.bundle, [self.container], {'fixture_data': self.volume}, {},
                       dict(self.declaration, data={'volumes': {'fixture_data': 'data/volumes/0'}, 'binds': {}}))
        def tamper(members):
            for member, payload in members:
                if member.name == 'data/volumes/0/value':
                    payload = b'changed!'
                    member.size = len(payload)
                yield member, payload
        with self.assertRaises(ValueError):
            dm.verify(self.rewrite(tamper))
        def extra(members):
            yield from members[:-1]
            info = tarfile.TarInfo('../escape')
            info.size = 1
            yield info, b'x'
            yield members[-1]
        with self.assertRaises(ValueError):
            dm.verify(self.rewrite(extra))

    def test_bind_mapping_confirmation_and_protected_ranges(self):
        source = str(self.bind.resolve())
        self.assertEqual(dm.parse_binds([source + '=app-config'], [source]), {source: 'app-config'})
        with self.assertRaises(ValueError):
            dm.parse_binds([source + '=app-config'], [])
        with self.assertRaises(ValueError):
            dm.parse_binds([source + '=one', source + '=two'], [source])
        self.assertTrue(dm.overlap('/srv/app', '/srv/app/data'))
        self.assertTrue(dm.overlap('/proc', '/proc/1'))

    @unittest.skipIf(os.name == 'nt', 'POSIX links and special files')
    def test_symlink_and_special_file_rejected(self):
        (self.bind / 'link').symlink_to(self.bind / 'config')
        with self.assertRaises(ValueError):
            dm.audit_tree(self.bind)
        (self.bind / 'link').unlink()
        os.mkfifo(self.bind / 'pipe')
        with self.assertRaises(ValueError):
            dm.audit_tree(self.bind)

    def test_stop_failure_and_snapshot_failure_restore_original_state(self):
        calls = []
        def command(*args, **kwargs):
            calls.append(args)
            if args[0] == 'stop':
                raise RuntimeError('stop failed')
            return b''
        with patch.object(dm, 'docker', side_effect=command), \
                patch.object(dm, 'js', return_value=[{'State': {'Running': True}}]):
            with self.assertRaises(RuntimeError):
                with dm.stopped([self.container]):
                    self.fail('not reached')
        self.assertEqual(calls, [('stop', 'c1')])
        calls.clear()
        def successful(*args, **kwargs):
            calls.append(args)
            return b''
        with patch.object(dm, 'docker', side_effect=successful), \
                patch.object(dm, 'js', side_effect=[[{'State': {'Running': True}}],
                                                    [{'State': {'Running': False}}],
                                                    [{'State': {'Running': False}}]]):
            with self.assertRaisesRegex(RuntimeError, 'snapshot'):
                with dm.stopped([self.container]):
                    raise RuntimeError('snapshot')
        self.assertEqual(calls, [('stop', 'c1'), ('start', 'c1')])

    def test_unsupported_runtime_features_rejected(self):
        for key, value in [('Privileged', True), ('Devices', [{'PathOnHost': '/dev/x'}]),
                           ('Tmpfs', {'/tmp': ''}), ('PidMode', 'host'), ('IpcMode', 'host'),
                           ('CgroupnsMode', 'host'), ('UsernsMode', 'host'), ('NetworkMode', 'container:c2')]:
            container = json.loads(json.dumps(self.container))
            container['HostConfig'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                dm.reject_unsupported(container)

    def test_engine_managed_masked_paths_captured_not_rejected(self):
        """Real `docker run` containers always carry these engine defaults; the
        first real-machine acceptance run proved rejecting them made every real
        container unexportable. They are engine-managed (no CLI flag exists), so
        they are recorded for audit instead of refused."""
        container = json.loads(json.dumps(self.container))
        container['HostConfig']['MaskedPaths'] = ['/proc/kcore', '/sys/devices/virtual/block/dm-0']
        container['HostConfig']['ReadonlyPaths'] = ['/proc/bus', '/proc/sys']
        container['Config']['Healthcheck'] = {'Test': ['CMD-SHELL', 'true']}
        dm.reject_unsupported(container)  # must not raise
        declaration = dm.container_declaration(container)
        self.assertEqual(declaration['masked_paths'], ['/proc/kcore', '/sys/devices/virtual/block/dm-0'])
        self.assertEqual(declaration['readonly_paths'], ['/proc/bus', '/proc/sys'])
        clean = dm.container_declaration(self.container)
        self.assertEqual(clean['masked_paths'], [])
        self.assertEqual(clean['readonly_paths'], [])

    def test_image_declaration_deduplicates_for_prepare_pattern(self):
        images = {}
        image = {'id': 'sha256:image', 'repo_digests': [], 'architecture': 'amd64', 'os': 'linux', 'variant': None}
        with patch.object(dm, 'image_declaration', return_value=image):
            for container in (self.container, dict(self.container, Id='c2')):
                item = dm.image_declaration(container)
                images[item['id']] = item
        self.assertEqual(list(images), ['sha256:image'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
