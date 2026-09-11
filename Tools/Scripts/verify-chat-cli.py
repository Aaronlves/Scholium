#!/usr/bin/env python3
"""Exercise the installed-style stdio entry point without a model or a vault."""
import argparse
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import uuid

parser = argparse.ArgumentParser()
parser.add_argument('executable', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[2] / '.build' / ('chat-cli-' + str(uuid.uuid4()))
root.mkdir(mode=0o700, parents=True)
env = dict(os.environ, SCHOLIUM_HOME=str(root))
process = None
try:
    process = subprocess.Popen([str(args.executable.resolve()), 'mcp', 'serve', '--conversation-token', str(uuid.uuid4())], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    request = {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list', 'params': {}}
    process.stdin.write((json.dumps(request) + '\n').encode()); process.stdin.flush()
    selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
    assert selector.select(5), 'The live stdin connection did not answer tool discovery.'
    response = json.loads(process.stdout.readline())
    names = {tool['name'] for tool in response['result']['tools']}
    assert names == {
        'scholium_workspace_status', 'scholium_browse', 'scholium_search',
        'scholium_read_note', 'scholium_show_note', 'scholium_list_attachments',
        'scholium_read_attachment', 'scholium_list_links', 'scholium_create_note',
        'scholium_update_note', 'scholium_preview_move', 'scholium_move_note',
        'scholium_list_changes', 'scholium_read_change', 'scholium_undo_change',
        'scholium_trash_note', 'scholium_update_metadata', 'scholium_update_attachment',
        'scholium_capabilities', 'scholium_configure_skill', 'scholium_configure_tool',
        'scholium_configure_chat',
    }, names
    request = {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {'name': 'scholium_workspace_status', 'arguments': {}}}
    process.stdin.write((json.dumps(request) + '\n').encode()); process.stdin.flush()
    assert selector.select(5), 'The absent App was not reported.'
    response = json.loads(process.stdout.readline())
    assert response.get('error') or response.get('result', {}).get('isError'), response
    selector.close()
    process.stdin.close(); process.wait(timeout=5)
    assert process.returncode == 0, process.stderr.read().decode(errors='replace')
    rejected = subprocess.run([str(args.executable.resolve()), 'mcp', 'serve', '--conversation-token', 'invalid'], input=b'', capture_output=True, env=env, timeout=5)
    assert rejected.returncode != 0, 'An invalid conversation identity was accepted.'
    print('Chat CLI: live twenty-two-tool discovery, isolated absent-App refusal, and malformed-token rejection passed.')
    zotero_requests = [
        {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list', 'params': {}},
        {'jsonrpc': '2.0', 'id': 2, 'method': 'tools/call', 'params': {
            'name': 'zotero_read_original', 'arguments': {
                'library': 'user', 'attachment_key': 'ATTACH01', 'mode': 'text', 'path': '/not-authorized'}}},
        {'jsonrpc': '2.0', 'id': 3, 'method': 'tools/call', 'params': {
            'name': 'zotero_import_bibtex', 'arguments': {'dry_run': False, 'confirm': True}}},
    ]
    zotero = subprocess.run([str(args.executable.resolve()), 'zotero', 'mcp', 'serve', '--read-only'],
                            input=''.join(json.dumps(item) + '\n' for item in zotero_requests).encode(),
                            capture_output=True, env=env, timeout=5)
    assert zotero.returncode == 0, zotero.stderr.decode(errors='replace')
    replies = {item['id']: item for item in map(json.loads, zotero.stdout.splitlines())}
    names = {tool['name'] for tool in replies[1]['result']['tools']}
    assert names == {'zotero_status', 'zotero_search', 'zotero_item', 'zotero_selected_target',
                     'zotero_list_annotations', 'zotero_read_annotation', 'zotero_read_original'}, names
    assert replies[2]['result']['isError'] and replies[3]['result']['isError']
    print('Zotero CLI: seven read tools, arbitrary-path refusal and forged-import rejection passed without data access.')
finally:
    if process and process.poll() is None:
        process.terminate()
        try: process.wait(timeout=3)
        except subprocess.TimeoutExpired: process.kill(); process.wait()
    shutil.rmtree(root)
