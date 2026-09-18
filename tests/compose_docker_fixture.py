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
    compose.write_text('services:\n  active:\n    image: alpine\n    command: ["sleep", "3600"]\n    environment: {FIXTURE_SECRET: diagnostic-secret-must-not-appear}\n    ports: ["127.0.0.1::8080"]\n    healthcheck: {test: ["CMD", "true"], interval: 1s, timeout: 1s, retries: 5}\n    mem_limit: 64m\n    cpus: 0.5\n    pids_limit: 64\n    volumes: ["data:/data"]\n  idle:\n    image: alpine\n    command: ["sleep", "3600"]\n    volumes: ["data:/data"]\nvolumes:\n  data: {}\n')
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
        # Reuse only this fixture's resources. Capture inventory; never print it.
        import time
        module = Path(__file__).resolve().parents[1] / 'src/modules/panels.sh'
        def diagnostic(*args):
            return subprocess.check_output(['bash', '-c', 'source "$1"; shift; panels_docker "$@"',
                                            'fixture', str(module), *args], text=True, stderr=subprocess.PIPE)
        active = next(c['Id'] for c in containers if c['State']['Running'])
        idle = next(c['Id'] for c in containers if not c['State']['Running'])
        for _ in range(30):
            detail = diagnostic('detail', active)
            if 'Health=healthy' in detail: break
            time.sleep(1)
        checks = 0
        def check(value):
            global checks
            assert value, 'isolated diagnostics assertion failed'
            checks += 1
        check('State=running' in detail)
        check('Health=healthy' in detail)
        check('diagnostic-secret-must-not-appear' not in detail and 'Environment=[redacted' in detail)
        check('8080/tcp' in detail and '127.0.0.1' in detail)
        check('Type=volume' in detail and project + '_data' in detail)
        check(project + '_default' in detail)
        check('MemoryBytes=67108864' in detail and 'NanoCPUs=500000000' in detail and 'PidsLimit=64' in detail)
        check('ImageID=sha256:' in detail and 'RestartPolicy=' in detail)
        check('RuntimeUsage: CPU=' in detail and 'Memory=' in detail)
        stopped = diagnostic('detail', idle)
        check('State=created' in stopped and 'RuntimeUsage=not sampled' in stopped)
        check('NanoCPUs=0' in stopped and 'no NanoCPU cap' in stopped)
        name = next(c['Name'].lstrip('/') for c in containers if c['Id'] == active)
        check('ID=' + active in diagnostic('detail', name))
        subprocess.check_call(['docker', 'pause', active], stdout=subprocess.DEVNULL)
        try:
            check('State=paused' in diagnostic('detail', active))
            summary = diagnostic('summary', '--all')
            check('Paused=' in summary and 'Disk usage' in summary and active in summary and 'Volumes (name/driver)' in summary)
        finally:
            subprocess.check_call(['docker', 'unpause', active], stdout=subprocess.DEVNULL)
        run('start', 'idle'); run('stop', 'idle')
        check('State=exited' in diagnostic('detail', idle))
        print(f'REAL DOCKER DIAGNOSTICS: {checks} checks passed (fixture-only detail; inventory suppressed)')
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
