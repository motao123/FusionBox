"""Real isolated Compose fixture; only this unique project's resources are removed."""
import json, os, subprocess, sys, tempfile
from pathlib import Path
from unittest.mock import patch
if sys.argv[1:] != ['--run']:
    raise SystemExit('Explicit --run required; local Docker/root')
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src/lib'))
import compose_backup as cb
project = 'fb150fixture' + str(os.getpid())
with tempfile.TemporaryDirectory(prefix='fb150-fixture-') as directory:
    root = Path(directory)
    compose = root / 'compose.yaml'
    compose.write_text('services:\n  active:\n    image: alpine\n    command: ["sleep", "3600"]\n    volumes: ["data:/data"]\n  idle:\n    image: alpine\n    command: ["sleep", "3600"]\n    volumes: ["data:/data"]\nvolumes:\n  data: {}\n')
    command = ['docker', 'compose', '-p', project, '-f', str(compose)]
    def run(*args): return subprocess.check_output([*command, *args], stderr=subprocess.DEVNULL)
    cb.BASE = root / 'registry'
    try:
        run('create')
        run('start', 'active')
        cb.register(project, compose, True)
        record = cb.load(cb.BASE / (project + '.json'), project)
        data, containers, paths = cb.inspect(record)
        assert len(containers) == 2
        original = {c['Id']: c['State']['Running'] for c in containers}
        assert sorted(original.values()) == [False, True]
        volume = next(iter(paths.values()))
        (volume / 'value').write_text('original')
        def state():
            actual = {c['Id']: c['State']['Running'] for c in cb.inspect(record)[1]}
            assert actual == original
        backup = root / 'snapshot.tar.gz'
        cb.operate(project, 'backup', backup, True); state()
        (volume / 'value').write_text('changed')
        cb.operate(project, 'restore', backup, True); state()
        assert (volume / 'value').read_text() == 'original'
        with patch.object(cb, 'package', side_effect=OSError('injected snapshot failure')):
            try: cb.operate(project, 'backup', root / 'failed.tar.gz', True)
            except OSError: pass
            else: raise AssertionError('expected backup failure')
        state()
        (volume / 'value').write_text('live')
        original_apply = cb.apply
        attempts = []
        def fail_once(source, paths):
            attempts.append(source)
            if len(attempts) == 1:
                (volume / 'value').write_text('partial')
                raise OSError('injected activation failure')
            original_apply(source, paths)
        with patch.object(cb, 'apply', side_effect=fail_once):
            try: cb.operate(project, 'restore', backup, True)
            except RuntimeError as error: assert 'rolled back' in str(error)
            else: raise AssertionError('expected restore failure')
        state()
        assert (volume / 'value').read_text() == 'live'
        assert len(list(cb.BASE.glob('*safety*'))) == 2
        with patch.object(cb, 'apply', side_effect=OSError('injected double failure')):
            try: cb.operate(project, 'restore', backup, True)
            except RuntimeError as error: assert 'project left stopped' in str(error)
            else: raise AssertionError('expected double failure')
        assert all(not c['State']['Running'] for c in cb.inspect(record)[1])
        assert len(list(cb.BASE.glob('*safety*'))) == 3
        print('REAL COMPOSE: 13 assertions passed including double failure leaves all stopped and retains safety artifact')
    finally:
        run('down', '--volumes')
        assert not cb.docker('ps', '-aq', '--filter', 'label=com.docker.compose.project=' + project).strip()
        assert not cb.docker('volume', 'ls', '-q', '--filter', 'label=com.docker.compose.project=' + project).strip()
        assert not cb.docker('network', 'ls', '-q', '--filter', 'label=com.docker.compose.project=' + project).strip()
        print('CLEANUP: fixture containers, volume and network absent')
