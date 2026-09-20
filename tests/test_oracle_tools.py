import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import oracle_tools


class _FakeResponse:
    def __init__(self, body=b'{}', status=200, url=oracle_tools.OCI_METADATA_URL):
        self.body = body
        self.status = status
        self.url = url

    def __enter__(self):
        return self

    def __exit__(self, *unused):
        return False

    def geturl(self):
        return self.url

    def getcode(self):
        return self.status

    def read(self, amount=-1):
        return self.body if amount < 0 else self.body[:amount]


class _FakeOpener:
    def __init__(self, response=None, error=None):
        self.response = response
        self.error = error
        self.request = None
        self.timeout = None

    def open(self, request, timeout=None):
        self.request = request
        self.timeout = timeout
        if self.error is not None:
            raise self.error
        return self.response


class OracleToolsTests(unittest.TestCase):
    def test_unknown_environment_without_evidence(self):
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools, '_metadata_evidence') as metadata:
            result = oracle_tools.detect_environment()
        metadata.assert_not_called()
        self.assertEqual(result, {
            'verdict': 'unknown', 'evidence': [], 'metadata_checked': False, 'errors': [],
        })

    def test_oracle_linux_dmi_is_not_oci(self):
        def read(path, unused_limit):
            if path == oracle_tools.DMI_PRODUCT_PATH:
                return oracle_tools._PRESENT, 'Oracle Linux Server'
            if path == oracle_tools.DMI_VENDOR_PATH:
                return oracle_tools._PRESENT, 'Oracle Corporation'
            return oracle_tools._ABSENT, None

        with patch.object(oracle_tools, '_read_text_detail', side_effect=read):
            result = oracle_tools.detect_environment()
        self.assertEqual(result['verdict'], 'unknown')
        self.assertIn('dmi:oracle-generic', result['evidence'])

    def test_reliable_dmi_combination_identifies_oci(self):
        def read(path, unused_limit):
            if path == oracle_tools.DMI_PRODUCT_PATH:
                return oracle_tools._PRESENT, 'KVM'
            if path == oracle_tools.DMI_VENDOR_PATH:
                return oracle_tools._PRESENT, 'Oracle Corporation'
            return oracle_tools._ABSENT, None

        with patch.object(oracle_tools, '_read_text_detail', side_effect=read):
            result = oracle_tools.detect_environment()
        self.assertEqual(result['verdict'], 'oracle')
        self.assertEqual(result['evidence'], ['dmi:oci-combination'])

    def test_conflicting_cloud_init_markers_are_unknown(self):
        def read(path, unused_limit):
            if path.name == 'cloud-id':
                return oracle_tools._PRESENT, 'oci'
            if path.name == 'cloud-platform':
                return oracle_tools._PRESENT, 'aws'
            return oracle_tools._ABSENT, None

        with patch.object(oracle_tools, '_read_text_detail', side_effect=read):
            result = oracle_tools.detect_environment()
        self.assertEqual(result['verdict'], 'unknown')
        self.assertIn('cloud-init:oci-id', result['evidence'])
        self.assertIn('cloud-init:non-oci', result['evidence'])

    def test_metadata_validates_real_shape_and_does_not_expose_fields(self):
        body = json.dumps({
            'id': 'ocid1.instance.oc1.iad.aaaaaaaasecret',
            'region': 'us-ashburn-1',
            'shape': 'VM.Standard.E4.Flex',
            'displayName': 'private-instance-name',
            'metadata': {'api_key': 'private-value'},
        }).encode('utf-8')
        fake = _FakeOpener(_FakeResponse(body))
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools.urllib.request, 'build_opener', return_value=fake) as factory:
            result = oracle_tools.detect_environment(metadata=True)
        self.assertEqual(result['verdict'], 'oracle')
        self.assertEqual(result['evidence'], ['metadata:oci'])
        self.assertNotIn('private-instance-name', json.dumps(result))
        self.assertNotIn('private-value', json.dumps(result))
        request = fake.request
        self.assertEqual(request.full_url, oracle_tools.OCI_METADATA_URL)
        self.assertEqual(request.get_header('Authorization'), 'Bearer Oracle')
        self.assertEqual(request.get_header('Accept'), 'application/json')
        handlers = factory.call_args.args
        self.assertTrue(any(isinstance(item, oracle_tools._NoRedirect) for item in handlers))
        proxies = [item for item in handlers if isinstance(item, oracle_tools.urllib.request.ProxyHandler)]
        self.assertEqual(len(proxies), 1)
        self.assertEqual(proxies[0].proxies, {})

    def test_metadata_empty_object_is_invalid(self):
        fake = _FakeOpener(_FakeResponse(b'{}'))
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools.urllib.request, 'build_opener', return_value=fake):
            result = oracle_tools.detect_environment(metadata=True)
        self.assertEqual(result['verdict'], 'unknown')
        self.assertEqual(result['evidence'], ['metadata:invalid'])
        self.assertEqual(result['errors'], ['metadata:invalid'])

    def test_metadata_redirect_is_rejected(self):
        fake = _FakeOpener(_FakeResponse(
            b'{"id":"ocid1.instance.oc1.iad.a","region":"us-ashburn-1","shape":"VM.Standard.E4.Flex"}',
            url='http://proxy.invalid/metadata',
        ))
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools.urllib.request, 'build_opener', return_value=fake):
            result = oracle_tools.detect_environment(metadata=True)
        self.assertEqual(result['verdict'], 'unknown')
        self.assertEqual(result['evidence'], ['metadata:redirect'])

    def test_metadata_permission_and_size_errors_are_distinct(self):
        from urllib.error import HTTPError

        denied = _FakeOpener(error=HTTPError(
            oracle_tools.OCI_METADATA_URL, 403, 'forbidden', {}, io.BytesIO(),
        ))
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools.urllib.request, 'build_opener', return_value=denied):
            result = oracle_tools.detect_environment(metadata=True)
        self.assertEqual(result['evidence'], ['metadata:permission_denied'])
        self.assertEqual(result['errors'], ['metadata:permission_denied'])

        oversized = _FakeOpener(_FakeResponse(b'x' * (oracle_tools.MAX_METADATA_BYTES + 1)))
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools.urllib.request, 'build_opener', return_value=oversized):
            result = oracle_tools.detect_environment(metadata=True)
        self.assertEqual(result['evidence'], ['metadata:oversize'])

    def test_status_without_state_is_unmanaged_and_does_not_create_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / 'state.json'
            with patch.object(oracle_tools, 'STATE_FILE', state), \
                 patch.object(oracle_tools, '_legacy_status', return_value={
                     'script': oracle_tools._ABSENT,
                     'log': oracle_tools._ABSENT,
                     'cron': oracle_tools._UNAVAILABLE,
                     'legacy_present': oracle_tools._ABSENT,
                     'errors': [],
                 }), \
                 patch.object(oracle_tools.shutil, 'which', return_value=None):
                result = oracle_tools.status()
            self.assertFalse(state.exists())
            self.assertEqual(result['managed'], {
                'lifecycle': 'unavailable',
                'managed': 'unmanaged',
                'state_file': 'absent',
                'state': None,
                'error': None,
            })

    def test_existing_state_is_not_read_or_validated(self):
        with tempfile.TemporaryDirectory() as temporary:
            state = Path(temporary) / 'state.json'
            state.write_text(json.dumps({'secret': 'do-not-print'}), encoding='utf-8')
            with patch.object(oracle_tools, 'STATE_FILE', state), \
                 patch.object(Path, 'read_text', side_effect=AssertionError('status must not read state')):
                result = oracle_tools._managed_status()
            self.assertEqual(result['state_file'], 'present')
            self.assertEqual(result['managed'], 'unmanaged')
            self.assertEqual(result['lifecycle'], 'unavailable')
            self.assertIsNone(result['state'])
            self.assertNotIn('do-not-print', json.dumps(result))

    def test_state_symlink_is_unsafe_and_not_absent(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'target'
            target.write_text('{}', encoding='utf-8')
            link = Path(temporary) / 'state.json'
            try:
                link.symlink_to(target)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f'symlink unavailable: {error}')
            with patch.object(oracle_tools, 'STATE_FILE', link):
                result = oracle_tools._managed_status()
            self.assertEqual(result['state_file'], 'unsafe')
            self.assertEqual(result['managed'], 'unknown')
            self.assertNotEqual(result['state_file'], 'absent')

    def test_legacy_symlink_is_not_reported_absent(self):
        with tempfile.TemporaryDirectory() as temporary:
            target = Path(temporary) / 'target'
            target.write_text('legacy', encoding='utf-8')
            link = Path(temporary) / 'oracle-keepalive'
            try:
                link.symlink_to(target)
            except (OSError, NotImplementedError) as error:
                self.skipTest(f'symlink unavailable: {error}')
            with patch.object(oracle_tools, 'LEGACY_SCRIPT', link), \
                 patch.object(oracle_tools, 'LEGACY_LOG', Path(temporary) / 'missing'), \
                 patch.object(oracle_tools, '_cron_status', return_value=oracle_tools._ABSENT):
                result = oracle_tools._legacy_status()
            self.assertEqual(result['script'], 'unsafe')
            self.assertEqual(result['legacy_present'], 'unknown')
            self.assertIn('script:unsafe', result['errors'])

    def test_permission_is_not_reported_absent(self):
        class DeniedPath:
            parents = ()

            def lstat(self):
                raise PermissionError('denied')

        self.assertEqual(oracle_tools._path_status(DeniedPath()), 'permission_denied')
        with patch.object(oracle_tools.subprocess, 'run', side_effect=PermissionError('denied')):
            self.assertEqual(oracle_tools._cron_status(), 'permission_denied')

    def test_help_is_available_and_clean(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = oracle_tools.main(['help'])
        self.assertEqual(code, 0)
        self.assertIn('detect', output.getvalue())
        self.assertIn('status', output.getvalue())

    def test_detect_metadata_error_returns_nonzero(self):
        with patch.object(oracle_tools, '_local_evidence', return_value=[]), \
             patch.object(oracle_tools, '_metadata_evidence', return_value=['metadata:invalid']):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = oracle_tools.main(['detect', '--metadata'])
        self.assertEqual(code, 1)
        self.assertIn('metadata:invalid', output.getvalue())


if __name__ == '__main__':
    unittest.main()
