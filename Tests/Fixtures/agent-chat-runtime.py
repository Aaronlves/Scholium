#!/usr/bin/env python3
# coding: utf-8
"""Deterministic stdio fixture; never calls a model, network, or research vault."""
import json
import os
import sys
import uuid
import copy
from pathlib import Path

home = Path(os.environ['CODEX_HOME'])
if (home / 'fail-runtime-start').exists():
    count = home / 'failed-runtime-starts'
    count.write_text(str(int(count.read_text()) + 1) if count.exists() else '1')
    sys.exit(1)
archive = home / 'fixture-threads.json'
threads = json.loads(archive.read_text()) if archive.exists() else {}
loaded_threads = set()
launches = home / 'runtime-launches'
launches.write_text(str(int(launches.read_text()) + 1) if launches.exists() else '1')
extra_roots = []
oauth_request = None
oauth_signed_in = False
pending_questions = {}
pending_approvals = {}
pending_child_reads = []
client_capabilities = {}
tool_config_file = home / 'fixture-tool-config.json'

def tool_config():
    return json.loads(tool_config_file.read_text()) if tool_config_file.exists() else {'version': 0, 'servers': {}}

def write(value):
    data = (json.dumps(value, ensure_ascii=False) + '\n').encode()
    # Deliberately split Unicode and frame boundaries.
    for offset in range(0, len(data), 7):
        sys.stdout.buffer.write(data[offset:offset + 7])
        sys.stdout.buffer.flush()

def turn_metadata(turn):
    return {**turn, 'items': [], 'itemsView': 'notLoaded'}

def event(method, params):
    if method in ('turn/started', 'turn/completed'):
        turn = params['turn']
        if turn.get('startedAt') is not None and method == 'turn/completed':
            turn['completedAt'] = turn['startedAt'] + 38
            turn['durationMs'] = 38500
        params = {**params, 'turn': turn_metadata(turn)}
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
        if request['id'] in pending_approvals:
            (home / 'runtime-approval-response.json').write_text(json.dumps(request))
            count = home / 'runtime-approval-response-count'
            count.write_text(str((int(count.read_text()) if count.exists() else 0) + 1))
            if not (home / 'hold-approval-resolution').exists():
                tid = pending_approvals.pop(request['id'])
                event('serverRequest/resolved', {'threadId': tid, 'requestId': request['id']})
        if request['id'] in pending_questions:
            (home / 'question-response.json').write_text(json.dumps(request))
            if not (home / 'hold-question-resolution').exists():
                tid = pending_questions.pop(request['id'])
                event('serverRequest/resolved', {'threadId': tid, 'requestId': request['id']})
        continue
    result = {}
    if method == 'initialize':
        client_capabilities = params.get('capabilities', {})
    elif method == 'account/read':
        result = {'account': {'type': 'chatgpt'}}
    elif method == 'model/list':
        result = {'data': [{'id': 'fixture-picker', 'model': 'fixture-model',
            'displayName': 'Fixture Model', 'isDefault': True, 'hidden': False,
            'defaultReasoningEffort': 'medium', 'inputModalities': ['text', 'image'],
            'supportedReasoningEfforts': [{'reasoningEffort': e, 'description': e}
                for e in ['low', 'medium', 'high']]}]}
    elif method == 'config/read':
        config = tool_config()
        result = {'config': {'model': 'fixture-model', 'model_reasoning_effort': 'low',
            'web_search': 'cached', 'mcp_servers': config['servers']},
            'layers': [{'name': {'type': 'user', 'file': str(home / 'config.toml')},
                'version': str(config['version']), 'config': {'mcp_servers': config['servers']}}]}
    elif method == 'config/batchWrite':
        config = tool_config()
        if params.get('expectedVersion') != str(config['version']):
            write({'id': request['id'], 'error': {'code': -32602, 'message': 'Configuration changed; reload before saving.'}})
            continue
        for edit in params['edits']:
            tail = edit['keyPath'][len('mcp_servers.'):]
            name, end = json.JSONDecoder().raw_decode(tail)
            field = tail[end:]
            if field:
                if edit['value'] is None:
                    config['servers'][name].pop(field[1:], None)
                else:
                    config['servers'][name][field[1:]] = edit['value']
            elif edit['value'] is None:
                config['servers'].pop(name, None)
            else:
                config['servers'][name] = edit['value']
        config['version'] += 1
        tool_config_file.write_text(json.dumps(config))
        result = {'filePath': str(home / 'config.toml'), 'version': str(config['version']), 'status': 'ok'}
    elif method == 'skills/list':
        completion = home / 'finish-tool-auth'
        if completion.exists() and oauth_request:
            success = completion.read_text() == 'success'
            completion.unlink()
            oauth_signed_in = success
            event('mcpServer/oauthLogin/completed', {'name': oauth_request['name'],
                'threadId': oauth_request.get('threadId'), 'success': success,
                'error': None if success else 'Fixture sign-in was cancelled'})
        enabled = not (home / 'method-disabled').exists()
        skills = [] if (home / 'method-missing').exists() else [
            {'name': 'source-analysis', 'path': str(home / 'methods' / 'source-analysis' / 'SKILL.md'),
             'description': 'Compare the source and its interpretation.', 'scope': 'user',
             'enabled': enabled, 'interface': {'displayName': 'Source Analysis'},
             'dependencies': {'tools': [{'type': 'mcp', 'value': 'scholium'}]}}]
        skills += [{'name': Path(root).name, 'path': str(Path(root) / 'SKILL.md'),
            'description': 'Associated fixture method.', 'scope': 'user', 'enabled': True}
            for root in extra_roots]
        result = {'data': [{'cwd': params['cwds'][0], 'skills': skills, 'errors': []}]}
    elif method == 'skills/extraRoots/set':
        counter = home / 'roots-request-count'
        counter.write_text(str((int(counter.read_text()) if counter.exists() else 0) + 1))
        if (home / 'hold-roots').exists():
            continue
        if (home / 'reject-roots').exists():
            write({'id': request['id'], 'error': {'code': -32602, 'message': 'Fixture refused method roots'}})
            continue
        extra_roots = params['extraRoots']
        (home / 'applied-roots.json').write_text(json.dumps(extra_roots))
    elif method == 'skills/config/write':
        flag = home / 'method-disabled'
        if params['enabled']:
            flag.unlink(missing_ok=True)
        else:
            flag.touch()
        result = {'effectiveEnabled': params['enabled']}
    elif method == 'mcpServerStatus/list':
        result = {'data': [{'name': 'scholium', 'authStatus': 'unsupported',
            'runtimeStatus': 'connected' if params.get('threadId') else None,
            'tools': {'scholium_read_note': {}, 'scholium_search': {}},
            'resources': [], 'resourceTemplates': []}], 'nextCursor': None}
        if (home / 'oauth-fixture').exists():
            result['data'].append({'name': 'fixture-library', 'authStatus': 'oAuth' if oauth_signed_in else 'notLoggedIn',
                'runtimeStatus': 'notStarted' if oauth_signed_in else 'authenticationRequired',
                'tools': {}, 'resources': [], 'resourceTemplates': []})
        for name, config in tool_config()['servers'].items():
            result['data'].append({'name': name, 'authStatus': 'unsupported',
                'runtimeStatus': 'notStarted' if config.get('enabled', True) else 'disabled',
                'tools': {}, 'resources': [], 'resourceTemplates': []})
    elif method == 'mcpServer/oauth/login':
        oauth_request = params
        if (home / 'hold-tool-auth').exists():
            continue
        result = {'authorizationUrl': 'file:///fixture' if (home / 'unsafe-auth-url').exists()
            else 'https://auth.example.test/authorize?state=fixture'}
    elif method == 'account/rateLimits/read':
        release = home / 'release-queued-turn'
        if release.exists():
            release.unlink()
            for tid, thread in threads.items():
                for turn in thread['turns']:
                    if turn.get('releaseQueuedFixture') and turn.get('status') == 'inProgress':
                        mid = str(uuid.uuid4())
                        reply = {'type': 'agentMessage', 'id': mid, 'text': 'Queued fixture reply'}
                        turn['items'].append(reply)
                        event('item/agentMessage/delta', {'threadId': tid, 'turnId': turn['id'], 'itemId': mid,
                            'delta': reply['text']})
                        event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': reply})
                        turn['status'] = 'completed'
                        event('turn/completed', {'threadId': tid, 'turn': turn})
        completion = home / 'complete-background-activity'
        if completion.exists():
            exit_code = int(completion.read_text())
            completion.unlink()
            for tid, thread in threads.items():
                for turn in thread['turns']:
                    for item in turn['items']:
                        if item.get('backgroundFixture') and item.get('status') == 'inProgress':
                            item.update(status='completed', exitCode=exit_code)
                            event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': item})
            save()
        for request_id, response in pending_child_reads:
            write({'id': request_id, 'result': response})
        pending_child_reads.clear()
        if (home / 'resolve-approvals').exists():
            for rid, tid in list(pending_approvals.items()):
                event('serverRequest/resolved', {'threadId': tid, 'requestId': rid})
                del pending_approvals[rid]
        if (home / 'resolve-questions').exists():
            for rid, tid in list(pending_questions.items()):
                event('serverRequest/resolved', {'threadId': tid, 'requestId': rid})
                del pending_questions[rid]
        result = {'rateLimitsByLimitId': {'fixture': {'limitName': 'Fixture',
            'primary': {'usedPercent': 25, 'windowDurationMins': 300, 'resetsAt': 1800000000},
            'secondary': None}}, 'rateLimits': {}}
    elif method == 'thread/loaded/list':
        (home / 'settings-idle-probes').write_text('checked')
        if (home / 'settings-probe-hold').exists():
            continue
        result = {'data': [17] if (home / 'settings-probe-malformed').exists() else sorted(loaded_threads), 'nextCursor': None}
    elif method == 'thread/backgroundTerminals/list':
        (home / 'settings-background-probes').write_text('checked')
        result = {'data': [{'processId': 'background-fixture'}] if (home / 'settings-background-command').exists() else [], 'nextCursor': None}
    elif method == 'thread/start':
        tid = str(uuid.uuid4())
        threads[tid] = {'id': tid, 'turns': []}
        loaded_threads.add(tid)
        result = {'thread': threads[tid]}
        (home / 'configuration.json').write_text(json.dumps(params))
        save()
    elif method in ('thread/read', 'thread/resume'):
        thread = threads.get(params['threadId'])
        if thread is None or (home / 'missing-thread-history').exists():
            write({'id': request['id'], 'error': {'code': -32600, 'message': 'thread not loaded: ' + params['threadId']}})
            continue
        if thread.get('parentThreadId'):
            marker = home / 'complete-parent-before-input'
            if marker.exists():
                marker.unlink()
                parent = threads[thread['parentThreadId']]
                parent['turns'][-1]['status'] = 'completed'
                event('turn/completed', {'threadId': parent['id'], 'turn': parent['turns'][-1]})
                pending_child_reads.append((request['id'], {'thread': copy.deepcopy(thread)}))
                save()
                continue
            (home / 'child-read-count').write_text(str(int((home / 'child-read-count').read_text()) + 1) if (home / 'child-read-count').exists() else '1')
            if (home / 'hold-child-read').exists():
                continue
            if (home / 'confirm-child-stop').exists():
                thread['turns'][-1]['status'] = 'interrupted'
                thread['status'] = {'type': 'idle'}
            if params.get('includeTurns') and (home / 'rotate-child-turn').exists():
                (home / 'rotate-child-turn').unlink()
                thread['turns'][-1]['status'] = 'completed'
                thread['turns'].append({'id': str(uuid.uuid4()), 'status': 'inProgress', 'items': []})
            if method == 'thread/resume':
                (home / 'unexpected-child-resume').write_text('resumed')
        result = {'thread': copy.deepcopy(thread)}
        if method == 'thread/read' and params.get('includeTurns') and (home / 'malformed-public-history').exists() and result['thread']['turns']:
            latest = result['thread']['turns'][-1]
            for item in latest['items']:
                if item.get('type') == 'agentMessage':
                    item['text'] = 'Unconfirmed replacement must not enter local history.'
            latest['items'].append({'id': 'malformed-public-item', 'type': 'agentMessage'})
        if 'status' not in result['thread']:
            active = any(turn.get('status') == 'inProgress' for turn in thread.get('turns', []))
            result['thread']['status'] = {'type': 'active' if active else 'idle'}
        if (home / 'settings-runtime-active').exists():
            result['thread']['status'] = {'type': 'active'}
        if thread.get('parentThreadId') and (home / 'unrelated-child-parent').exists():
            result['thread']['parentThreadId'] = 'unrelated-runtime-parent'
        if thread.get('parentThreadId') and not params.get('includeTurns'):
            result['thread']['turns'] = []
        if method == 'thread/resume':
            if params['threadId'] not in loaded_threads:
                (home / 'configuration.json').write_text(json.dumps(params))
                loaded_threads.add(params['threadId'])
    elif method == 'thread/turns/list':
        thread = threads[params['threadId']]
        offset = int(params.get('cursor') or '0')
        turns = list(reversed(thread['turns']))
        result = {'data': copy.deepcopy(turns[offset:offset + 25]),
            'nextCursor': str(offset + 25) if len(turns) > offset + 25 else None, 'backwardsCursor': None}
    elif method == 'thread/fork':
        (home / 'last-fork.json').write_text(json.dumps(params))
        counter = home / 'fork-count'
        counter.write_text(str((int(counter.read_text()) if counter.exists() else 0) + 1))
        if (home / 'hold-fork').exists():
            continue
        if (home / 'reject-fork').exists():
            write({'id': request['id'], 'error': {'code': -32602, 'message': 'Fixture refused the branch'}})
            continue
        source = threads[params['threadId']]
        tid = str(uuid.uuid4())
        boundary = next(i for i, t in enumerate(source['turns']) if t['id'] == params.get('beforeTurnId', params.get('lastTurnId')))
        end = boundary if 'beforeTurnId' in params else boundary + 1
        if (home / 'wrong-fork-boundary').exists():
            end = len(source['turns'])
        threads[tid] = {'id': tid, 'turns': copy.deepcopy(source['turns'][:end])}
        result = {'thread': threads[tid]}
        save()
    elif method in ('turn/start', 'turn/steer'):
        (home / 'last-turn.json').write_text(json.dumps(params))
        tid = params['threadId']
        text = params['input'][0]['text']
        turn_id = str(uuid.uuid4())
        user = {'id': str(uuid.uuid4()), 'type': 'userMessage', 'clientId': params['clientUserMessageId'], 'content': params['input']}
        if 'omit-client-id' in text:
            del user['clientId']
        if method == 'turn/steer':
            turn = threads[tid]['turns'][-1]
            if turn['status'] != 'inProgress' or params.get('expectedTurnId') != turn['id']:
                write({'id': request['id'], 'error': {'code': -32602, 'message': 'Fixture active turn changed'}})
                continue
            turn['items'].append(user)
        else:
            turn = {'id': turn_id, 'status': 'inProgress', 'items': [user]}
            if 'timed activity' in text:
                turn['startedAt'] = 1788912000
            if 'hold-queue' in text:
                turn['releaseQueuedFixture'] = True
            threads[tid]['turns'].append(turn)
        if (home / 'hold-parent-input').exists():
            save()
            continue
        event('turn/started', {'threadId': tid, 'turn': turn})
        if 'delegation' in text:
            children = [tid + '-child-a', tid + '-child-b']
            parent = tid
            if 'nested-child' in text:
                parent = tid + '-coordinator'
                threads[parent] = {'id': parent, 'parentThreadId': tid, 'agentNickname': 'Coordinator',
                    'status': {'type': 'idle'}, 'turns': []}
            for index, child in enumerate(children):
                child_turn = {'id': child + '-turn', 'status': 'inProgress' if index == 0 else 'completed', 'items': [
                    {'id': child + '-request', 'type': 'userMessage', 'content': [{'type': 'text', 'text': '核对所选原文，保留页码。'},
                        {'type': 'localImage', 'path': '/Synthetic/Page.png'}]},
                    {'id': child + '-private', 'type': 'reasoning', 'summary': 'synthetic-private-reasoning'},
                    {'id': child + '-tool', 'type': 'mcpToolCall', 'server': 'scholium', 'tool': 'scholium_read_note',
                        'status': 'completed', 'arguments': {}},
                    {'id': child + '-reply', 'type': 'agentMessage', 'text': '第一处原文支持较窄的解释；第二处仍需核对。'}]}
                older = [{'id': child + '-older-' + str(n), 'status': 'completed', 'items': []} for n in range(26)] if 'paginated-child' in text else []
                threads[child] = {'id': child, 'parentThreadId': parent, 'agentNickname': '原文核验' if index == 0 else '异议检查',
                    'agentRole': 'explorer', 'status': {'type': 'active', 'activeFlags': []} if index == 0 else {'type': 'idle'},
                    'historyMode': 'paginated' if 'paginated-child' in text else 'legacy', 'turns': older + [child_turn]}
            if 'nested-report' in text:
                grandchild = children[0] + '-reader'
                threads[grandchild] = {'id': grandchild, 'parentThreadId': children[0],
                    'agentNickname': '段落核对', 'status': {'type': 'idle'}, 'turns': [
                        {'id': grandchild + '-turn', 'status': 'completed', 'items': [
                            {'id': grandchild + '-reply', 'type': 'agentMessage', 'text': '第二页第三段：只核对这一段。'},
                            {'id': grandchild + '-report', 'type': 'collabAgentToolCall',
                                'senderThreadId': grandchild, 'tool': 'sendMessage', 'status': 'completed',
                                'receiverThreadIds': [children[0]], 'agentsStates': {}}]}]}
                threads['unrelated-report-target'] = {'id': 'unrelated-report-target',
                    'parentThreadId': 'other-conversation', 'status': {'type': 'idle'}, 'turns': []}
                threads[children[0]]['turns'][-1]['items'].append({
                    'id': children[0] + '-report', 'type': 'collabAgentToolCall',
                    'senderThreadId': children[0], 'tool': 'sendMessage', 'status': 'completed',
                    'receiverThreadIds': [grandchild, children[1], tid, 'unrelated-report-target'],
                    'agentsStates': {grandchild: {'status': 'completed', 'message': '第二页段落已核对。'}}})
            report = {'id': 'delegation-' + turn['id'], 'type': 'collabAgentToolCall',
                'senderThreadId': tid, 'tool': 'spawnAgent', 'status': 'inProgress',
                'receiverThreadIds': children,
                'prompt': '核对所提供的两处原文，保留页码与不确定之处。',
                'agentsStates': {children[0]: {'status': 'running'},
                    children[1]: {'status': 'completed', 'message': '核验报告：第二处尚无直接支持。'}}}
            event('item/started', {'threadId': tid, 'turnId': turn['id'], 'item': report})
            report['status'] = 'completed'
            turn['items'].append(report)
            event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': report})
            lifecycle = {'id': 'child-event-' + turn['id'], 'type': 'subAgentActivity',
                'agentThreadId': children[0], 'agentPath': '/root/source-check', 'kind': 'interacted'}
            turn['items'].append(lifecycle)
            event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': lifecycle})
        if 'async-form' in text:
            question = {'id': 'async-' + turn['id'], 'type': 'agentMessage', 'delivery': 'async',
                'text': 'Choose how to read and where to begin.', 'questions': [
                    {'title': 'How should we read this passage?', 'options': ['Compare the passages', 'Examine an objection']},
                    {'title': 'Where should we begin?', 'options': ['First paragraph', 'Conclusion']}]}
            turn['items'].append(question)
            event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': question})
        if 'questions' in text:
            rid = 'question-' + turn['id']
            pending_questions[rid] = tid
            if 'tool-questions' in text:
                tool_item = {'id': rid, 'type': 'mcpToolCall', 'server': 'fixture_library', 'tool': 'choose_source',
                    'arguments': {'privateFixtureArgument': 'do-not-archive-this-argument'}, 'status': 'inProgress'}
                turn['items'].append(tool_item)
                event('item/started', {'threadId': tid, 'turnId': turn['id'], 'item': tool_item})
            questions = [{'id': 'approach', 'header': 'Approach', 'question': 'How should we read this passage?',
                'isOther': True, 'options': [
                    {'label': 'Compare the passages', 'description': 'Start from the supplied source.'},
                    {'label': 'Examine an objection', 'description': 'Consider an alternative interpretation.'}]},
                {'id': 'private', 'header': 'Private', 'question': 'Synthetic private input', 'isSecret': True}]
            if 'malformed-questions' in text:
                questions.append(questions[0])
            if 'secret-choice-questions' in text:
                questions[1]['options'] = [{'label': 'synthetic-private-option', 'description': 'Private fixture choice'}]
            write({'id': rid, 'method': 'item/tool/requestUserInput', 'params': {
                'threadId': tid, 'turnId': turn['id'], 'itemId': rid, 'isBlocking': True, 'questions': questions}})
        if 'phased' in text:
            progress = {'type': 'agentMessage', 'id': 'progress-' + turn_id, 'phase': 'commentary', 'text': '正在核对公开来源。'}
            turn['items'].append(progress)
            event('item/started', {'threadId': tid, 'turnId': turn['id'], 'item': {**progress, 'text': ''}})
            event('item/agentMessage/delta', {'threadId': tid, 'turnId': turn['id'], 'itemId': progress['id'], 'delta': progress['text']})
            event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': progress})
        if 'capabilities' in text:
            event('turn/plan/updated', {'threadId': tid, 'turnId': turn['id'],
                'explanation': 'Public fixture plan', 'plan': [
                    {'step': 'Read the source', 'status': 'completed'},
                    {'step': 'Compare the passages', 'status': 'inProgress'}]})
            event('thread/tokenUsage/updated', {'threadId': tid, 'turnId': turn['id'],
                'tokenUsage': {'last': {'totalTokens': 1200}, 'total': {'totalTokens': 3600},
                    'modelContextWindow': 32000}})
        if 'activity' in text:
            activity = {'id': 'command-' + turn_id, 'type': 'commandExecution', 'command': 'Inspect research materials', 'status': 'inProgress', 'commandActions': [], 'cwd': str(home)}
            if 'background' in text:
                activity['backgroundFixture'] = True
            turn['items'].append(activity)
            event('item/started', {'threadId': tid, 'turnId': turn['id'], 'item': activity})
            event('item/commandExecution/outputDelta', {'threadId': tid, 'turnId': turn['id'], 'itemId': activity['id'], 'delta': 'Reading public fixture data.'})
            if 'hold' not in text and 'background' not in text:
                activity.update(status='completed', cwd='/fixture', durationMs=123, exitCode=7 if 'failed-activity' in text else 0)
                if 'long-output' in text:
                    activity['aggregatedOutput'] = '\n'.join('Output line ' + str(n) for n in range(120))
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
   - 区分 `works` 的原文与 `topics` 中的问题。
   - 保留中文与 English 混排的出处。

```text
source → interpretation → objection
```

| 讨论内容 | 后续工作 |
|---|---|
| 已经说明的区别 | 回到相关笔记核对 |
| 仍不清楚的问题 | 继续追问并保留分歧 |

最后一段测试正常的长回复。研究材料仍在正文区域；聊天负责让交流顺畅地持续下去。"""
            event('item/agentMessage/delta', {'threadId': tid, 'itemId': mid, 'delta': reply})
            item = {'type': 'agentMessage', 'id': mid, 'text': reply}
            if 'phased' in text: item['phase'] = 'final_answer'
            turn['items'].append(item)
            event('item/completed', {'threadId': tid, 'item': item})
            turn['status'] = 'completed'
            if 'fail-turn' in text:
                turn['status'] = 'failed'
                turn['error'] = {'message': 'Synthetic execution failure'}
            event('turn/completed', {'threadId': tid, 'turn': turn})
            if 'duplicate-completion' in text:
                event('turn/completed', {'threadId': tid, 'turn': turn})
        if 'approval' in text:
            rid = 'approval-' + turn['id']
            if 'duplicate-approval' in text and pending_approvals:
                rid = next(iter(pending_approvals))
            pending_approvals[rid] = tid
            approval_method = 'item/commandExecution/requestApproval'
            approval_params = {'threadId': tid, 'turnId': turn['id'], 'itemId': 'command-1', 'command': 'echo fixture', 'cwd': str(home)}
            if 'linked-approval' in text:
                approval_params['itemId'] = 'command-' + turn_id
            if 'runtime-mcp-approval' in text:
                approval_method = 'mcpServer/elicitation/request'
                approval_params = {'threadId': tid, 'turnId': turn['id'], 'serverName': 'scholium',
                    'mode': 'form', '_meta': {'codex_approval_kind': 'mcp_tool_call', 'persist': ['session', 'always']},
                    'message': 'Allow scholium_update_note for QA Topic.md?',
                    'requestedSchema': {'type': 'object', 'properties': {}}}
            elif 'runtime-permission-approval' in text:
                approval_method = 'item/permissions/requestApproval'
                approval_params = {'threadId': tid, 'turnId': turn['id'], 'itemId': rid, 'cwd': str(home),
                    'permissions': {'network': {'enabled': True}, 'fileSystem': {'entries': [
                        {'access': 'read', 'path': {'type': 'path', 'path': '/fixture/sources'}},
                        {'access': 'write', 'path': {'type': 'glob_pattern', 'pattern': '/fixture/output/**/*.md'}},
                        {'access': 'deny', 'path': {'type': 'path', 'path': '/fixture/private'}}]}}}
            elif 'runtime-session-approval' in text:
                approval_params['availableDecisions'] = ['acceptForSession', 'decline']
            elif 'runtime-policy-approval' in text:
                approval_params['availableDecisions'] = [{'acceptWithExecpolicyAmendment': {'execpolicy_amendment': ['echo']}}, 'decline']
            elif 'runtime-cancel-approval' in text:
                approval_params['availableDecisions'] = ['accept', 'cancel']
            elif 'runtime-stdin-approval' in text:
                approval_params['kind'] = 'writeStdin'
                approval_params['command'] = 'continue\n'
            elif 'runtime-command-extra-approval' in text and client_capabilities.get('experimentalApi'):
                approval_params['additionalPermissions'] = {'network': {'enabled': True},
                    'fileSystem': {'write': ['/fixture/output']}}
            elif 'runtime-stale-approval' in text:
                approval_params['turnId'] = 'earlier-turn'
            write({'id': rid, 'method': approval_method, 'params': approval_params})
        save()
        if 'disconnect' in text:
            sys.exit(0)
        result = {'turnId': 'wrong-turn' if 'mismatched-steer-ack' in text else turn['id']} if method == 'turn/steer' else {'turn': turn_metadata(turn)}
    elif method == 'thread/compact/start':
        tid = params['threadId']
        turn = {'id': str(uuid.uuid4()), 'status': 'inProgress', 'items': []}
        threads[tid]['turns'].append(turn)
        event('turn/started', {'threadId': tid, 'turn': turn})
        item = {'id': str(uuid.uuid4()), 'type': 'contextCompaction'}
        turn['items'].append(item)
        event('item/started', {'threadId': tid, 'turnId': turn['id'], 'item': item})
        if not (home / 'hold-compaction').exists():
            event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': item})
            turn['status'] = 'completed'
            event('turn/completed', {'threadId': tid, 'turn': turn})
        save()
    elif method == 'turn/interrupt':
        tid = params['threadId']
        turn = threads[tid]['turns'][-1]
        if threads[tid].get('parentThreadId'):
            if params['turnId'] != turn['id']:
                write({'id': request['id'], 'error': {'code': -32602, 'message': 'Fixture active turn changed'}})
                continue
            (home / 'child-interrupt.json').write_text(json.dumps(params))
            counter = home / 'child-interrupt-count'
            counter.write_text(str(int(counter.read_text()) + 1) if counter.exists() else '1')
            if (home / 'hold-child-stop').exists():
                write({'id': request['id'], 'result': {}})
                continue
            threads[tid]['status'] = {'type': 'idle'}
        turn['status'] = 'interrupted'
        for item in turn['items']:
            if item.get('type') == 'commandExecution' and item.get('status') == 'inProgress' and not item.get('backgroundFixture'):
                item.update(status='failed', exitCode=130)
                event('item/completed', {'threadId': tid, 'turnId': turn['id'], 'item': item})
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
