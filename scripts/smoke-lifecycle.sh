#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
stage=$(mktemp -d /private/tmp/headroom-lifecycle.XXXXXX)
trap 'rm -rf "$stage"' EXIT
cat > "$stage/slow-cli" <<'PY'
#!/usr/bin/python3
import os,signal,time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
Path(os.environ['HEADROOM_TEST_PID_FILE']).write_text(str(os.getpid()))
time.sleep(60)
PY
chmod +x "$stage/slow-cli"
HEADROOM_TEST_PID_FILE="$stage/pid" python3 - "$PWD/dist/Headroom.app/Contents/MacOS/Headroom" "$stage/slow-cli" "$stage/pid" <<'PY'
import os,signal,subprocess,sys,time
from pathlib import Path
app,fixture,pidfile=sys.argv[1:]
pid=None
try:
    start=time.monotonic()
    r=subprocess.run([app,'--preview-window','--smoke-test','--quit-during-refresh','--codex-cli',fixture],capture_output=True,text=True,timeout=12)
    print(r.stdout.strip())
    assert r.returncode==0, r.stderr
    assert 'storage=true, codex=false' in r.stdout, 'Failure isolation was not observed'
    pid=int(Path(pidfile).read_text())
    try:
        os.kill(pid,0)
    except ProcessLookupError:
        print(f'PASS quit during stuck read: app and helper exited in {time.monotonic()-start:.2f}s')
    else:
        raise AssertionError('Owned test helper remains running')
finally:
    if Path(pidfile).exists():
        pid=int(Path(pidfile).read_text())
        observed=subprocess.run(['ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
        if fixture in observed:
            os.kill(pid,signal.SIGKILL)
PY
