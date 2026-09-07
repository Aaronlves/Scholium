#!/usr/bin/env python3
# coding: utf-8
"""Deterministic stdio fixture; never calls a model, network, or research vault."""
import json
import os
import sys
import uuid
from pathlib import Path

home = Path(os.environ['CODEX_HOME'])
archive = home / 'fixture-threads.json'
threads = json.loads(archive.read_text()) if archive.exists() else {}

def write(value):
    data = (json.dumps(value, ensure_ascii=False) + '\n').encode()
    # Deliberately split Unicode and frame boundaries.
    for offset in range(0, len(data), 7):
        sys.stdout.buffer.write(data[offset:offset + 7])
        sys.stdout.buffer.flush()

def event(method, params):
    write({'method': method, 'params': params})

def save():
    archive.write_text(json.dumps(threads))

for line in sys.stdin:
    request = json.loads(line)
    method = request.get('method')
    params = request.get('params', {})
    if 'id' not in request:
        continue
    if method is None:
        (home / 'approval-response.json').write_text(json.dumps(request))
        continue
    result = {}
    if method == 'account/read':
        result = {'account': {'type': 'chatgpt'}}
    elif method == 'model/list':
        result = {'data': [{'id': 'fixture-model'}]}
    elif method == 'thread/start':
        tid = str(uuid.uuid4())
        threads[tid] = {'id': tid, 'turns': []}
        result = {'thread': threads[tid]}
        (home / 'configuration.json').write_text(json.dumps(params))
        save()
    elif method in ('thread/read', 'thread/resume'):
        result = {'thread': threads[params['threadId']]}
        if method == 'thread/resume':
            (home / 'configuration.json').write_text(json.dumps(params))
    elif method in ('turn/start', 'turn/steer'):
        tid = params['threadId']
        text = params['input'][0]['text']
        turn_id = str(uuid.uuid4())
        user = {'id': str(uuid.uuid4()), 'type': 'userMessage', 'clientId': params['clientUserMessageId'], 'content': params['input']}
        if method == 'turn/steer':
            turn = threads[tid]['turns'][-1]
            turn['items'].append(user)
        else:
            turn = {'id': turn_id, 'status': 'inProgress', 'items': [user]}
            threads[tid]['turns'].append(turn)
        event('turn/started', {'threadId': tid, 'turn': turn})
        if 'activity' in text:
            activity = {'id': 'command-' + turn_id, 'type': 'commandExecution', 'command': 'Inspect research materials', 'status': 'inProgress', 'commandActions': [], 'cwd': str(home)}
            turn['items'].append(activity)
            event('item/started', {'threadId': tid, 'turnId': turn['id'], 'item': activity})
            event('item/commandExecution/outputDelta', {'threadId': tid, 'turnId': turn['id'], 'itemId': activity['id'], 'delta': 'Reading public fixture data.'})
            if 'hold' not in text:
                activity['status'] = 'completed'
                event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': activity})
        if 'hold' not in text:
            mid = str(uuid.uuid4())
            reply = '中文 😀 fixture reply'
            if 'rich' in text:
                reply = """这是一段用于检查完整讨论排版的合成回答。我们可以沿着一个问题继续追问，让解释有足够的篇幅展开，也让每段文字各自表达一个清楚的意思。

第二段保留了**强调**与自然的段落分隔。较长的回答应当能够连续阅读；你仍然可以选中文字、复制一段话，或引用整个回答继续讨论。

### 一个具体区分

> 这段引文只是排版测试材料，并不来自任何文献。

1. 先说明正在讨论的问题。
2. 再展开理由与尚未解决的疑问。

| 讨论内容 | 后续工作 |
|---|---|
| 已经说明的区别 | 回到相关笔记核对 |
| 仍不清楚的问题 | 继续追问并保留分歧 |

最后一段测试正常的长回复。研究材料仍在正文区域；聊天负责让交流顺畅地持续下去。"""
            event('item/agentMessage/delta', {'threadId': tid, 'itemId': mid, 'delta': reply})
            item = {'type': 'agentMessage', 'id': mid, 'text': reply}
            turn['items'].append(item)
            event('item/completed', {'threadId': tid, 'item': item})
            turn['status'] = 'completed'
            event('turn/completed', {'threadId': tid, 'turn': turn})
        if 'approval' in text:
            write({'id': 'approval-fixture', 'method': 'item/commandExecution/requestApproval', 'params': {'threadId': tid, 'itemId': 'command-1', 'command': 'echo fixture', 'cwd': str(home)}})
        save()
        if 'disconnect' in text:
            sys.exit(0)
        result = {'turn': turn}
    elif method == 'turn/interrupt':
        tid = params['threadId']
        turn = threads[tid]['turns'][-1]
        turn['status'] = 'interrupted'
        event('turn/completed', {'threadId': tid, 'turn': turn})
        save()
    elif method == 'test/echo':
        result = params
    elif method == 'test/hang':
        continue
    elif method == 'test/malformed':
        sys.stdout.write('invalid-json\n'); sys.stdout.flush()
        continue
    write({'id': request['id'], 'result': result})
