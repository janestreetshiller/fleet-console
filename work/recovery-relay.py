import json
import os
from pathlib import Path
import socket
import threading
import time

upstream = str(Path.home() / 'Library/Application Support/FleetConsole/fleetd.sock')
owned_socket = '/private/tmp/fleet-recovery-owner-20261013.sock'
evidence = Path('/Users/main/Documents/Codex/2026-10-11/pl/outputs/fleet-apple-ui-e2e-2026-10-13/recovery-relay.jsonl')
lock = threading.Lock()
fail_once = True

def record(event, **details):
    with lock:
        with evidence.open('a') as output:
            output.write(json.dumps({'time': time.time(), 'event': event, **details}) + '\n')

def handle(client):
    global fail_once
    try:
        reader = client.makefile('rb')
        line = reader.readline(65537)
        if len(line) > 65536:
            raise ValueError('Request exceeds the bound')
        request = json.loads(line)
        operation = request.get('op')
        if operation not in ('subscribe', 'snapshot'):
            raise ValueError('Only observational subscription and snapshot requests are allowed')
        with lock:
            should_fail = operation == 'snapshot' and fail_once
            if should_fail:
                fail_once = False
        if should_fail:
            record('injected-refresh-failure', operation=operation)
            client.sendall(b'{"ok":false,"error":"Controlled refresh failure for recovery verification"}\n')
            return
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as source:
            source.connect(upstream)
            source.sendall(line)
            with source.makefile('rb') as stream:
                for response in stream:
                    value = json.loads(response)
                    snapshot = value.get('snapshot')
                    if snapshot:
                        record('forwarded-real-snapshot', operation=operation,
                               generatedAt=snapshot.get('generatedAt'),
                               daemonPID=snapshot.get('daemon', {}).get('pid'))
                    client.sendall(response)
                    if operation != 'subscribe':
                        break
    except (BrokenPipeError, ConnectionResetError):
        pass
    except Exception as error:
        record('relay-error', message=str(error))
    finally:
        client.close()

if os.path.lexists(owned_socket):
    raise SystemExit('Refusing to replace an existing socket')
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
    server.bind(owned_socket)
    os.chmod(owned_socket, 0o600)
    server.listen(8)
    record('started', upstream=upstream, socket=owned_socket)
    print('Owned observational recovery relay ready', flush=True)
    try:
        while True:
            client, _ = server.accept()
            threading.Thread(target=handle, args=(client,), daemon=True).start()
    finally:
        os.unlink(owned_socket)
