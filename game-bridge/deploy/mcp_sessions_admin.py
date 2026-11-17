"""Fixed SSH maintenance command; no dependency on an available MCP session."""
import argparse,json,os,pathlib,subprocess,time,urllib.request

STATE=pathlib.Path('/home/ubuntu/.local/state/oracle-vm-work/https-sessions-status.json')

def status():
    pid=int(subprocess.check_output(['systemctl','show','oracle-vm-mcp','-p','MainPID','--value'],text=True).strip())
    if pid <= 0 or STATE.is_symlink() or not STATE.is_file():
        raise RuntimeError('MCP_STATUS_UNAVAILABLE')
    data=json.loads(STATE.read_text())
    fields=('pid','current','created_since_reset','active_calls','limit')
    if any(type(data.get(k)) is not int or data[k] < 0 for k in fields):
        raise RuntimeError('MCP_STATUS_INVALID')
    if data['pid'] != pid or data['current'] > data['limit']:
        raise RuntimeError('MCP_STATUS_STALE')
    return {k:data[k] for k in fields}

def operate(operation):
    if operation == 'status':
        return dict(ok=True,operation=operation,**status())
    if operation != 'reset':
        raise ValueError('UNKNOWN_OPERATION')
    # Avoid interrupting a command currently executing through cloud MCP.
    for _ in range(20):
        before=status()
        if before['active_calls'] == 0:
            break
        time.sleep(.5)
    else:
        raise RuntimeError('MCP_BUSY_RETRY_AFTER_CURRENT_COMMAND')
    subprocess.run(['systemctl','restart','oracle-vm-mcp'],check=True,timeout=15,capture_output=True)
    for _ in range(25):
        try:
            after=status()
            with urllib.request.urlopen('http://127.0.0.1:7320/healthz',timeout=1) as response:
                ready=json.load(response).get('ready')
            if ready and after['pid'] != before['pid']:
                return dict(ok=True,operation=operation,previous_current=before['current'],**after)
        except (OSError,ValueError,RuntimeError):
            pass
        time.sleep(.2)
    raise RuntimeError('MCP_RESTART_HEALTH_FAILED')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('operation',choices=('status','reset'))
    operation=parser.parse_args().operation
    try:
        print(json.dumps(operate(operation)))
    except Exception as error:
        allowed={'MCP_STATUS_UNAVAILABLE','MCP_STATUS_INVALID','MCP_STATUS_STALE',
                 'MCP_BUSY_RETRY_AFTER_CURRENT_COMMAND','MCP_RESTART_HEALTH_FAILED'}
        message=str(error) if str(error) in allowed else 'MCP_MAINTENANCE_FAILED'
        print(json.dumps({'ok':False,'operation':operation,'error':message}))
        raise SystemExit(1)

if __name__ == '__main__':
    main()
