import { describe, it, expect } from '@ohos/hypium';
import {
  strO, numO, boolO, objO,
  Project, SessionInfo, MessageInfo, Part, MessagesPayload,
  ModelInfo, ProviderInfo, PermissionRequest, FileDiff, TodoItem,
  FileNode, FileContent, FileStatusInfo, FindMatch, QuestionRequest,
  fmtTime, fmtGroup, fmtCount, fmtSessionTime
} from '../main/ets/common/model/Types';

function rec(entries: [string, Object | null | undefined][]): Record<string, Object> {
  const o: Record<string, Object> = {};
  for (let i = 0; i < entries.length; i++) {
    o[entries[i][0]] = entries[i][1] as Object;
  }
  return o;
}

export default function typesTest() {
  describe('helpers', () => {
    it('strO_returns_default_for_missing_nullish', 0, () => {
      expect(strO({}, 'k', 'd')).assertEqual('d');
      expect(strO(rec([['k', null]]), 'k', 'd')).assertEqual('d');
      expect(strO(rec([['k', undefined]]), 'k', 'd')).assertEqual('d');
    });
    it('strO_stringifies_non_string', 0, () => {
      expect(strO(rec([['k', 42]]), 'k', 'd')).assertEqual('42');
      expect(strO(rec([['k', true]]), 'k', 'd')).assertEqual('true');
    });
    it('numO_parses_and_defaults', 0, () => {
      expect(numO({}, 'k', 7)).assertEqual(7);
      expect(numO(rec([['k', '3']]), 'k', 7)).assertEqual(3);
      expect(numO(rec([['k', 2.5]]), 'k', 7)).assertEqual(2.5);
      expect(numO(rec([['k', 'not-a-number']]), 'k', 7)).assertEqual(7);
    });
    it('boolO_coerces', 0, () => {
      expect(boolO({}, 'k', true)).assertEqual(true);
      expect(boolO(rec([['k', true]]), 'k', false)).assertEqual(true);
      expect(boolO(rec([['k', false]]), 'k', true)).assertEqual(false);
    });
    it('objO_rejects_arrays_and_scalars', 0, () => {
      expect(objO({}, 'k')).assertNull();
      expect(objO(rec([['k', [1, 2]]]), 'k')).assertNull();
      expect(objO(rec([['k', 'x']]), 'k')).assertNull();
      const inner: Record<string, Object> = { 'a': 1 };
      expect(objO(rec([['k', inner]]), 'k')).assertEqual(inner);
    });
  });

  describe('Project.fromJson', () => {
    it('falls_back_directory_to_path', 0, () => {
      const p = Project.fromJson(rec([['id', 'p1'], ['path', '/repo'], ['worktree', '/w']]));
      expect(p.id).assertEqual('p1');
      expect(p.path).assertEqual('/repo');
      expect(p.directory).assertEqual('/repo');
      expect(p.worktree).assertEqual('/w');
    });
    it('keeps_explicit_directory', 0, () => {
      const p = Project.fromJson(rec([['id', 'p1'], ['path', '/repo'], ['directory', '/other']]));
      expect(p.directory).assertEqual('/other');
    });
  });

  describe('SessionInfo.fromJson', () => {
    it('parses_numeric_time_tokens_metadata', 0, () => {
      const time: Record<string, Object> = { 'created': 1000, 'updated': 2000 };
      const tokens: Record<string, Object> = { 'input': 11, 'output': 22 };
      const meta: Record<string, Object> = { 'ocFocus': 999, 'ocFocusSource': 'phone' };
      const o = rec([
        ['id', 's1'], ['title', 'hi'], ['worktree', '/w'], ['time', time],
        ['metadata', meta], ['tokens', tokens], ['cost', 1.5]
      ]);
      const s = SessionInfo.fromJson(o);
      expect(s.id).assertEqual('s1');
      expect(s.title).assertEqual('hi');
      expect(s.created).assertEqual(1000);
      expect(s.updated).assertEqual(2000);
      expect(s.ocFocus).assertEqual(999);
      expect(s.ocFocusSource).assertEqual('phone');
      expect(s.tokensInput).assertEqual(11);
      expect(s.tokensOutput).assertEqual(22);
      expect(s.cost).assertEqual(1.5);
    });
    it('parses_iso_string_time_when_numeric_missing', 0, () => {
      const time: Record<string, Object> = { 'created': '2026-01-02T03:04:05.000Z' };
      const o = rec([['id', 's1'], ['time', time]]);
      const s = SessionInfo.fromJson(o);
      expect(s.created).assertEqual(Date.parse('2026-01-02T03:04:05.000Z'));
      expect(s.updated).assertEqual(0);
    });
    it('defaults_missing_fields', 0, () => {
      const s = SessionInfo.fromJson({});
      expect(s.id).assertEqual('');
      expect(s.title).assertEqual('');
      expect(s.created).assertEqual(0);
    });
  });

  describe('MessageInfo.fromJson', () => {
    it('parses_error_object', 0, () => {
      const err: Record<string, Object> = { 'name': 'Abort', 'message': 'user aborted' };
      const o = rec([['id', 'm1'], ['role', 'assistant'], ['error', err]]);
      const m = MessageInfo.fromJson(o);
      expect(m.id).assertEqual('m1');
      expect(m.role).assertEqual('assistant');
      expect(m.error).assertContain('Abort');
      expect(m.error).assertContain('user aborted');
    });
    it('parses_error_string', 0, () => {
      const o = rec([['id', 'm1'], ['error', 'boom']]);
      const m = MessageInfo.fromJson(o);
      expect(m.error).assertEqual('boom');
    });
    it('parses_numeric_created', 0, () => {
      const time: Record<string, Object> = { 'created': 123456 };
      const o = rec([['id', 'm1'], ['time', time]]);
      expect(MessageInfo.fromJson(o).created).assertEqual(123456);
    });
    it('defaults_role_to_user', 0, () => {
      expect(MessageInfo.fromJson(rec([['id', 'm1']])).role).assertEqual('user');
    });
  });

  describe('Part.fromJson', () => {
    it('parses_tool_as_string_with_state', 0, () => {
      const inputObj = rec([['command', 'ls']]);
      const timeObj = rec([['start', 1], ['end', 2]]);
      const state: Record<string, Object> = {
        'status': 'completed', 'title': 'Run bash',
        'input': inputObj, 'output': 'a.txt', 'time': timeObj
      };
      const o = rec([['id', 'p1'], ['type', 'tool'], ['tool', 'bash'], ['state', state]]);
      const p = Part.fromJson(o);
      expect(p.toolName).assertEqual('bash');
      expect(p.toolState).assertEqual('completed');
      expect(p.toolTitle).assertEqual('Run bash');
      expect(p.toolInput).assertContain('command');
      expect(p.toolOutput).assertEqual('a.txt');
      expect(p.toolStartTime).assertEqual(1);
      expect(p.toolEndTime).assertEqual(2);
    });
    it('parses_tool_as_object_with_name', 0, () => {
      const tool: Record<string, Object> = { 'name': 'bash' };
      const o = rec([['id', 'p1'], ['tool', tool]]);
      expect(Part.fromJson(o).toolName).assertEqual('bash');
    });
    it('falls_back_to_name_field', 0, () => {
      const o = rec([['id', 'p1'], ['type', 'tool'], ['name', 'bash']]);
      expect(Part.fromJson(o).toolName).assertEqual('bash');
    });
    it('parses_plain_text_part', 0, () => {
      const o = rec([['id', 'p1'], ['type', 'text'], ['text', 'hello']]);
      const p = Part.fromJson(o);
      expect(p.type).assertEqual('text');
      expect(p.text).assertEqual('hello');
    });
  });

  describe('MessagesPayload.fromJson', () => {
    it('parses_info_and_parts', 0, () => {
      const info: Record<string, Object> = { 'id': 'm1', 'role': 'user' };
      const parts: Object[] = [
        rec([['id', 'pa'], ['type', 'text'], ['text', 'a']]),
        rec([['id', 'pb'], ['type', 'reasoning'], ['text', 'r']])
      ];
      const o = rec([['info', info], ['parts', parts]]);
      const m = MessagesPayload.fromJson(o);
      expect(m.message.id).assertEqual('m1');
      expect(m.parts.length).assertEqual(2);
      expect(m.parts[0].text).assertEqual('a');
      expect(m.parts[1].type).assertEqual('reasoning');
    });
    it('handles_missing_parts', 0, () => {
      const info: Record<string, Object> = { 'id': 'm1' };
      const o = rec([['info', info]]);
      expect(MessagesPayload.fromJson(o).parts.length).assertEqual(0);
    });
  });

  describe('ModelInfo.fromJson', () => {
    it('marks_free_when_cost_all_zero', 0, () => {
      const cost: Record<string, Object> = { 'input': 0, 'output': 0 };
      const o = rec([['id', 'm1'], ['cost', cost]]);
      const m = ModelInfo.fromJson(o, 'prov');
      expect(m.isFree).assertTrue();
      expect(m.providerID).assertEqual('prov');
    });
    it('marks_paid_when_cost_nonzero', 0, () => {
      const cost: Record<string, Object> = { 'input': 1, 'output': 0 };
      const o = rec([['id', 'm1'], ['cost', cost]]);
      expect(ModelInfo.fromJson(o, 'prov').isFree).assertFalse();
    });
    it('marks_free_by_name_fallback', 0, () => {
      const o = rec([['id', 'gpt-free-1']]);
      expect(ModelInfo.fromJson(o, 'prov').isFree).assertTrue();
    });
    it('falls_back_name_to_id', 0, () => {
      const o = rec([['id', 'm1']]);
      const m = ModelInfo.fromJson(o, 'prov');
      expect(m.name).assertEqual('m1');
    });
  });

  describe('ProviderInfo.fromJson', () => {
    it('parses_models_array', 0, () => {
      const models: Object[] = [
        rec([['id', 'a'], ['name', 'Model A']]),
        rec([['id', 'b']])
      ];
      const o = rec([['id', 'p1'], ['name', 'Prov'], ['models', models]]);
      const p = ProviderInfo.fromJson(o);
      expect(p.id).assertEqual('p1');
      expect(p.name).assertEqual('Prov');
      expect(p.models.length).assertEqual(2);
      expect(p.models[0].name).assertEqual('Model A');
      expect(p.models[1].name).assertEqual('b');
    });
    it('parses_models_dict_and_injects_key_as_id', 0, () => {
      const dict: Record<string, Object> = { 'm1': rec([['name', 'M1']]) };
      const o = rec([['id', 'p1'], ['models', dict]]);
      const p = ProviderInfo.fromJson(o);
      expect(p.models.length).assertEqual(1);
      expect(p.models[0].id).assertEqual('m1');
      expect(p.models[0].name).assertEqual('M1');
    });
    it('falls_back_name_to_id', 0, () => {
      const o = rec([['id', 'p1']]);
      expect(ProviderInfo.fromJson(o).name).assertEqual('p1');
    });
  });

  describe('PermissionRequest.fromJson', () => {
    it('parses_v1_permission_patterns', 0, () => {
      const patterns: Object[] = ['a.txt', 'b.txt'];
      const o = rec([['id', 'pr1'], ['sessionID', 's1'], ['permission', 'read'], ['patterns', patterns]]);
      const pr = PermissionRequest.fromJson(o, '');
      expect(pr.id).assertEqual('pr1');
      expect(pr.sessionID).assertEqual('s1');
      expect(pr.permission).assertEqual('read');
      expect(pr.patterns).assertEqual('a.txt b.txt');
      expect(pr.apiVersion).assertEqual(1);
    });
    it('parses_v2_action_resources', 0, () => {
      const resources: Object[] = ['/dir'];
      const o = rec([['id', 'pr2'], ['sessionID', 's2'], ['action', 'external_directory'], ['resources', resources]]);
      const pr = PermissionRequest.fromJson(o, '');
      expect(pr.permission).assertEqual('external_directory');
      expect(pr.patterns).assertEqual('/dir');
      expect(pr.apiVersion).assertEqual(2);
    });
    it('prefers_explicit_sessionID_argument', 0, () => {
      const o = rec([['id', 'pr1'], ['sessionID', 'from-json']]);
      expect(PermissionRequest.fromJson(o, 'from-arg').sessionID).assertEqual('from-arg');
    });
  });

  describe('simple models', () => {
    it('FileDiff.fromJson', 0, () => {
      const o = rec([['file', 'a.ts'], ['before', 'x'], ['after', 'y'], ['additions', 3], ['deletions', 1]]);
      const d = FileDiff.fromJson(o);
      expect(d.file).assertEqual('a.ts');
      expect(d.before).assertEqual('x');
      expect(d.after).assertEqual('y');
      expect(d.additions).assertEqual(3);
      expect(d.deletions).assertEqual(1);
    });
    it('TodoItem.fromJson_defaults_pending', 0, () => {
      const o = rec([['id', 't1'], ['title', 'Fix bug']]);
      const t = TodoItem.fromJson(o);
      expect(t.id).assertEqual('t1');
      expect(t.title).assertEqual('Fix bug');
      expect(t.status).assertEqual('pending');
    });
    it('FileNode.fromJson', 0, () => {
      const o = rec([['name', 'src'], ['path', 'src'], ['absolute', '/r/src'], ['type', 'directory'], ['ignored', true]]);
      const n = FileNode.fromJson(o);
      expect(n.name).assertEqual('src');
      expect(n.type).assertEqual('directory');
      expect(n.ignored).assertTrue();
      expect(n.absolute).assertEqual('/r/src');
    });
    it('FileContent.fromJson', 0, () => {
      const o = rec([['type', 'binary'], ['content', 'aGk='], ['mimeType', 'image/png'], ['encoding', 'base64']]);
      const c = FileContent.fromJson(o);
      expect(c.type).assertEqual('binary');
      expect(c.content).assertEqual('aGk=');
      expect(c.mimeType).assertEqual('image/png');
      expect(c.encoding).assertEqual('base64');
    });
    it('FileStatusInfo.fromJson', 0, () => {
      const o = rec([['path', 'a.ts'], ['added', 2], ['removed', 1], ['status', 'modified']]);
      const s = FileStatusInfo.fromJson(o);
      expect(s.path).assertEqual('a.ts');
      expect(s.added).assertEqual(2);
      expect(s.removed).assertEqual(1);
      expect(s.status).assertEqual('modified');
    });
    it('FindMatch.fromJson_parses_nested_text_objects', 0, () => {
      const pathObj: Record<string, Object> = { 'text': '/r/a.ts' };
      const linesObj: Record<string, Object> = { 'text': 'hello' };
      const o = rec([['path', pathObj], ['lines', linesObj], ['line_number', 5], ['absolute_offset', 99]]);
      const m = FindMatch.fromJson(o);
      expect(m.path).assertEqual('/r/a.ts');
      expect(m.lineText).assertEqual('hello');
      expect(m.lineNumber).assertEqual(5);
      expect(m.absoluteOffset).assertEqual(99);
    });
    it('QuestionRequest.fromJson', 0, () => {
      const opts: Object[] = [rec([['label', 'Yes'], ['description', 'ok']]), rec([['label', 'No']])];
      const qs: Object[] = [rec([['question', 'Go?'], ['header', 'H'], ['multiple', true], ['options', opts]])];
      const o = rec([['id', 'q1'], ['sessionID', 's1'], ['questions', qs]]);
      const q = QuestionRequest.fromJson(o);
      expect(q.id).assertEqual('q1');
      expect(q.questions.length).assertEqual(1);
      expect(q.questions[0].question).assertEqual('Go?');
      expect(q.questions[0].multiple).assertTrue();
      expect(q.questions[0].options.length).assertEqual(2);
      expect(q.questions[0].options[1].label).assertEqual('No');
    });
  });

  describe('time formatting', () => {
    it('fmtTime_empty_for_zero', 0, () => {
      expect(fmtTime(0)).assertEqual('');
      expect(fmtTime(-1)).assertEqual('');
    });
    it('fmtTime_hh_mm', 0, () => {
      const d = new Date(2026, 0, 5, 9, 7);
      expect(fmtTime(d.getTime())).assertEqual('09:07');
    });
    it('fmtCount_thresholds', 0, () => {
      expect(fmtCount(999)).assertEqual('999');
      expect(fmtCount(1234)).assertEqual('1.2k');
      expect(fmtCount(2500000)).assertEqual('2.5M');
    });
    it('fmtGroup_today', 0, () => {
      const now = new Date();
      expect(fmtGroup(now.getTime() - 1)).assertEqual('今天');
    });
    it('fmtGroup_yesterday', 0, () => {
      const now = new Date();
      const yesterday = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1, 12, 0);
      expect(fmtGroup(yesterday.getTime())).assertEqual('昨天');
    });
    it('fmtGroup_earlier_and_invalid', 0, () => {
      expect(fmtGroup(0)).assertEqual('更早');
      const now = new Date();
      const old = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 3, 12, 0);
      expect(fmtGroup(old.getTime())).assertEqual('更早');
    });
    it('fmtSessionTime_same_day_is_hhmm', 0, () => {
      const now = new Date();
      const d = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 8, 30);
      expect(fmtSessionTime(d.getTime())).assertEqual('08:30');
    });
    it('fmtSessionTime_other_day_is_mm_dd', 0, () => {
      expect(fmtSessionTime(0)).assertEqual('');
      const d = new Date(2026, 6, 3, 8, 30);
      expect(fmtSessionTime(d.getTime())).assertEqual('07-03');
    });
  });
}
