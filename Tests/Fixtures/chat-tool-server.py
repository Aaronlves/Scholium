#!/usr/bin/env python3
"""Offline MCP server for disposable runtime connection tests; no research operations."""
import json
import os
import sys

if '--require-fixture-environment' in sys.argv:
    if os.environ.get('SCHOLIUM_TOOL_FIXTURE_TOKEN') != 'synthetic-local-fixture':
        sys.exit(2)

for line in sys.stdin:
    request = json.loads(line)
    if 'id' not in request:
        continue
    method = request.get('method')
    result = {}
    if method == 'initialize':
        result = {'protocolVersion': request['params']['protocolVersion'],
            'capabilities': {'tools': {}}, 'serverInfo': {'name': 'scholium-fixture-server', 'version': '1'}}
    elif method == 'tools/list':
        result = {'tools': [{'name': 'fixture_echo', 'description': 'Return synthetic fixture text.',
            'inputSchema': {'type': 'object', 'properties': {}}}]}
    elif method == 'tools/call':
        result = {'content': [{'type': 'text', 'text': 'Synthetic fixture result.'}]}
    elif method == 'resources/list':
        result = {'resources': []}
    elif method == 'resources/templates/list':
        result = {'resourceTemplates': []}
    sys.stdout.write(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': result}) + '\n')
    sys.stdout.flush()
