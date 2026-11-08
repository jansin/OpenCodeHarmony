// OpenCode HarmonyOS client - data models.
// Types mirror the OpenCode server OpenAPI schema (packages/sdk/js/src/gen/types.gen.ts).

export function strO(o: Record<string, Object>, key: string, def: string): string {
  const v = o[key];
  if (v === undefined || v === null) {
    return def;
  }
  if (typeof v === 'string') {
    return v as string;
  }
  return String(v);
}

export function numO(o: Record<string, Object>, key: string, def: number): number {
  const v = o[key];
  if (v === undefined || v === null) {
    return def;
  }
  if (typeof v === 'number') {
    return v as number;
  }
  const n = Number(v);
  return Number.isNaN(n) ? def : n;
}

export function boolO(o: Record<string, Object>, key: string, def: boolean): boolean {
  const v = o[key];
  if (v === undefined || v === null) {
    return def;
  }
  return Boolean(v);
}

export function objO(o: Record<string, Object>, key: string): Record<string, Object> | null {
  const v = o[key];
  if (v instanceof Object && !Array.isArray(v)) {
    return v as Record<string, Object>;
  }
  return null;
}

export class ServerConfig {
  url: string = '';
  password: string = '';
}

// 上传到会话的附件（服务端 FilePartInput）：
// - 文本文件：content 直接经 source.text 注入，url 用占位名
// - 图片：content 为 data URI（data:image/png;base64,...），走 url 字段
export class AttachmentInput {
  filename: string = '';
  mime: string = '';
  content: string = ''; // 文本内容 或 data URI
  isImage: boolean = false;
}

export class Project {
  id: string = '';
  path: string = '';
  worktree: string = '';
  directory: string = '';

  static fromJson(o: Record<string, Object>): Project {
    const p = new Project();
    p.id = strO(o, 'id', '');
    p.path = strO(o, 'path', '');
    p.worktree = strO(o, 'worktree', '');
    p.directory = strO(o, 'directory', '');
    if (p.directory.length === 0 && p.path.length > 0) {
      p.directory = p.path;
    }
    return p;
  }
}

export class SessionInfo {
  id: string = '';
  title: string = '';
  worktree: string = '';
  created: number = 0;
  updated: number = 0;
  // 跨端会话焦点同步（写入 session.metadata）
  ocFocus: number = 0;
  ocFocusSource: string = '';
  // 会话聚合指标（session.tokens / session.cost），供列表摘要展示
  tokensInput: number = 0;
  tokensOutput: number = 0;
  cost: number = 0;
  messageCount: number = 0;
  lastText: string = '';

  static fromJson(o: Record<string, Object>): SessionInfo {
    const s = new SessionInfo();
    s.id = strO(o, 'id', '');
    s.title = strO(o, 'title', '');
    s.worktree = strO(o, 'worktree', '');
    const timeObj = objO(o, 'time');
    if (timeObj !== null) {
      s.created = numO(timeObj, 'created', 0);
      s.updated = numO(timeObj, 'updated', 0);
      if (s.created <= 0) {
        const parsed = Date.parse(strO(timeObj, 'created', ''));
        s.created = Number.isNaN(parsed) ? 0 : parsed;
      }
      if (s.updated <= 0) {
        const parsed = Date.parse(strO(timeObj, 'updated', ''));
        s.updated = Number.isNaN(parsed) ? 0 : parsed;
      }
    }
    const meta = objO(o, 'metadata');
    if (meta !== null) {
      s.ocFocus = numO(meta, 'ocFocus', 0);
      s.ocFocusSource = strO(meta, 'ocFocusSource', '');
    }
    const tokens = objO(o, 'tokens');
    if (tokens !== null) {
      s.tokensInput = numO(tokens, 'input', 0);
      s.tokensOutput = numO(tokens, 'output', 0);
    }
    s.cost = numO(o, 'cost', 0);
    return s;
  }
}

export class MessageInfo {
  id: string = '';
  sessionID: string = '';
  role: string = 'user'; // user | assistant | system
  parentID: string = '';
  modelID: string = '';
  providerID: string = '';
  created: number = 0;
  finish: string = '';
  error: string = '';

  static fromJson(o: Record<string, Object>): MessageInfo {
    const m = new MessageInfo();
    m.id = strO(o, 'id', '');
    m.sessionID = strO(o, 'sessionID', '');
    m.role = strO(o, 'role', 'user');
    m.parentID = strO(o, 'parentID', '');
    m.modelID = strO(o, 'modelID', '');
    m.providerID = strO(o, 'providerID', '');
    const timeObj = objO(o, 'time');
    if (timeObj !== null) {
      // OpenCode 返回毫秒时间戳数字，不是 ISO 字符串
      const createdNum = numO(timeObj, 'created', 0);
      if (createdNum > 0) {
        m.created = createdNum;
      } else {
        const createdStr = strO(timeObj, 'created', '');
        const parsed = Date.parse(createdStr);
        m.created = Number.isNaN(parsed) ? 0 : parsed;
      }
    }
    m.finish = strO(o, 'finish', '');
    // error 可能是对象 { name, data } 或字符串
    const errObj = objO(o, 'error');
    if (errObj !== null) {
      m.error = strO(errObj, 'name', '') + ' ' + strO(errObj, 'message', '');
      if (m.error.trim().length === 0) {
        m.error = JSON.stringify(errObj);
      }
    } else {
      m.error = strO(o, 'error', '');
    }
    return m;
  }
}

export class Part {
  id: string = '';
  type: string = 'text'; // text | reasoning | tool | file | step-start | ...
  text: string = '';
  toolName: string = '';
  toolInput: string = '';
  toolOutput: string = '';
  toolState: string = ''; // pending | running | completed | error
  toolTitle: string = '';
  toolStartTime: number = 0;
  toolEndTime: number = 0;
  filePath: string = '';

  static fromJson(o: Record<string, Object>): Part {
    const p = new Part();
    p.id = strO(o, 'id', '');
    p.type = strO(o, 'type', 'text');
    p.text = strO(o, 'text', '');
    // 新版 tool：type=tool, tool="bash", state={status,input,output,time}
    const toolVal = o['tool'];
    if (typeof toolVal === 'string') {
      p.toolName = toolVal as string;
    } else {
      const toolObj = objO(o, 'tool');
      if (toolObj !== null) {
        p.toolName = strO(toolObj, 'name', '');
      }
    }
    if (p.toolName.length === 0) {
      p.toolName = strO(o, 'name', '');
    }
    const stateObj = objO(o, 'state');
    if (stateObj !== null) {
      p.toolState = strO(stateObj, 'status', strO(stateObj, 'state', ''));
      p.toolTitle = strO(stateObj, 'title', '');
      const inputObj = objO(stateObj, 'input');
      if (inputObj !== null) {
        p.toolInput = JSON.stringify(inputObj);
      } else {
        const inputStr = strO(stateObj, 'input', '');
        if (inputStr.length > 0) {
          p.toolInput = inputStr;
        }
      }
      p.toolOutput = strO(stateObj, 'output', strO(stateObj, 'error', ''));
      const timeObj = objO(stateObj, 'time');
      if (timeObj !== null) {
        p.toolStartTime = numO(timeObj, 'start', 0);
        p.toolEndTime = numO(timeObj, 'end', 0);
      }
    } else {
      p.toolState = strO(o, 'state', '');
      const inputObj = objO(o, 'input');
      if (inputObj !== null) {
        p.toolInput = JSON.stringify(inputObj);
      }
    }
    p.filePath = strO(o, 'path', '');
    return p;
  }
}

export class MessagesPayload {
  message: MessageInfo = new MessageInfo();
  parts: Part[] = [];

  static fromJson(o: Record<string, Object>): MessagesPayload {
    const m = new MessagesPayload();
    const info = objO(o, 'info');
    if (info !== null) {
      m.message = MessageInfo.fromJson(info);
    }
    const parts = o['parts'];
    if (Array.isArray(parts)) {
      const raw = parts as Object[];
      for (let i = 0; i < raw.length; i++) {
        m.parts.push(Part.fromJson(raw[i] as Record<string, Object>));
      }
    }
    return m;
  }
}

export class ChatItem {
  messageID: string = '';
  role: string = 'user';
  text: string = '';
  reasoning: string = '';
  toolName: string = '';
  toolInput: string = '';
  toolState: string = '';
  created: number = 0;
}

export function fmtTime(ts: number): string {
  if (ts <= 0) {
    return '';
  }
  const d = new Date(ts);
  const hh = d.getHours().toString().padStart(2, '0');
  const mm = d.getMinutes().toString().padStart(2, '0');
  return `${hh}:${mm}`;
}

// 会话列表分组标签：今天 / 昨天 / 更早
export function fmtGroup(ts: number): string {
  if (ts <= 0) {
    return '更早';
  }
  const now = new Date();
  const d = new Date(ts);
  const s = (now.getHours() * 60 + now.getMinutes()) * 60000;
  if (now.getTime() - d.getTime() < s && now.getDate() === d.getDate()) {
    return '今天';
  }
  const y = new Date(now.getFullYear(), now.getMonth(), now.getDate() - 1);
  if (d >= y) {
    return '昨天';
  }
  return '更早';
}

// 会话列表时间显示：今天显示 HH:mm，其余显示日期
export function fmtCount(n: number): string {
  if (n < 1000) {
    return n.toString();
  }
  if (n < 1000000) {
    return (Math.round(n / 100) / 10).toFixed(1) + 'k';
  }
  return (Math.round(n / 100000) / 10).toFixed(1) + 'M';
}

export function fmtSessionTime(ts: number): string {
  if (ts <= 0) {
    return '';
  }
  const d = new Date(ts);
  const now = new Date();
  const hh = d.getHours().toString().padStart(2, '0');
  const mm = d.getMinutes().toString().padStart(2, '0');
  if (now.getDate() === d.getDate() && now.getMonth() === d.getMonth() &&
    now.getFullYear() === d.getFullYear() && now.getTime() - d.getTime() < 86400000) {
    return `${hh}:${mm}`;
  }
  const mo = (d.getMonth() + 1).toString().padStart(2, '0');
  const da = d.getDate().toString().padStart(2, '0');
  return `${mo}-${da}`;
}

// ---- M2: models / diff / todo / permissions ----

export class ModelInfo {
  id: string = '';
  name: string = '';
  providerID: string = '';
  isFree: boolean = false;

  static fromJson(o: Record<string, Object>, providerID: string): ModelInfo {
    const m = new ModelInfo();
    m.id = strO(o, 'id', '');
    let n = strO(o, 'name', '');
    if (n.length === 0) {
      n = m.id;
    }
    m.name = n;
    m.providerID = strO(o, 'providerID', providerID);
    // 免费模型判定：cost 均为 0（输入+输出），或 id/name 显式标记 free
    m.isFree = ModelInfo.isFreeModel(o, m.id);
    return m;
  }

  private static isFreeModel(o: Record<string, Object>, id: string): boolean {
    const cost = objO(o, 'cost');
    if (cost !== null) {
      const input = numO(cost, 'input', 1);
      const output = numO(cost, 'output', 1);
      if (input === 0 && output === 0) {
        return true;
      }
    }
    const low = (id + ' ' + strO(o, 'name', '')).toLowerCase();
    return low.indexOf('free') >= 0;
  }
}

export class ProviderInfo {
  id: string = '';
  name: string = '';
  models: ModelInfo[] = [];

  static fromJson(o: Record<string, Object>): ProviderInfo {
    const p = new ProviderInfo();
    p.id = strO(o, 'id', '');
    let n = strO(o, 'name', '');
    if (n.length === 0) {
      n = p.id;
    }
    p.name = n;
    const models = o['models'];
    if (Array.isArray(models)) {
      const raw = models as Object[];
      for (let i = 0; i < raw.length; i++) {
        p.models.push(ModelInfo.fromJson(raw[i] as Record<string, Object>, p.id));
      }
    } else if (models instanceof Object) {
      // server 返回的是 { modelID: ModelObj } 字典
      const map = models as Record<string, Object>;
      const ids = Object.keys(map);
      for (let i = 0; i < ids.length; i++) {
        const mv = map[ids[i]];
        if (mv instanceof Object) {
          const rec = mv as Record<string, Object>;
          // 部分字典值的 id 字段缺失，补上键名
          const merged: Record<string, Object> = {};
          const recKeys = Object.keys(rec);
          for (let j = 0; j < recKeys.length; j++) {
            merged[recKeys[j]] = rec[recKeys[j]];
          }
          if (strO(rec, 'id', '').length === 0) {
            merged['id'] = ids[i];
          }
          p.models.push(ModelInfo.fromJson(merged, p.id));
        }
      }
    }
    return p;
  }
}

export class PermissionRequest {
  id: string = '';
  sessionID: string = '';
  permission: string = '';
  patterns: string = '';
  // v1: /permission ；v2: /api/permission/request（external_directory 等走 v2）
  apiVersion: number = 1;

  static fromJson(o: Record<string, Object>, sessionID: string): PermissionRequest {
    const pr = new PermissionRequest();
    pr.sessionID = sessionID.length > 0 ? sessionID : strO(o, 'sessionID', '');
    pr.id = strO(o, 'id', '');
    // v1: permission + patterns；v2: action + resources
    pr.permission = strO(o, 'permission', '');
    if (pr.permission.length === 0) {
      pr.permission = strO(o, 'action', '');
      pr.apiVersion = 2;
    }
    const pats = o['patterns'];
    if (Array.isArray(pats)) {
      pr.patterns = (pats as Object[]).map((x: Object) => String(x)).join(' ');
    }
    if (pr.patterns.length === 0) {
      const resources = o['resources'];
      if (Array.isArray(resources)) {
        pr.patterns = (resources as Object[]).map((x: Object) => String(x)).join('\n');
        pr.apiVersion = 2;
      }
    }
    return pr;
  }
}

export class FileDiff {
  file: string = '';
  before: string = '';
  after: string = '';
  additions: number = 0;
  deletions: number = 0;

  static fromJson(o: Record<string, Object>): FileDiff {
    const d = new FileDiff();
    d.file = strO(o, 'file', '');
    d.before = strO(o, 'before', '');
    d.after = strO(o, 'after', '');
    d.additions = numO(o, 'additions', 0);
    d.deletions = numO(o, 'deletions', 0);
    return d;
  }
}

export class TodoItem {
  id: string = '';
  title: string = '';
  status: string = 'pending'; // pending | in_progress | completed

  static fromJson(o: Record<string, Object>): TodoItem {
    const t = new TodoItem();
    t.id = strO(o, 'id', '');
    t.title = strO(o, 'title', '');
    t.status = strO(o, 'status', 'pending');
    return t;
  }
}

// a single permission approval pending user decision
export class Approval {
  requestID: string = '';
  sessionID: string = '';
  permission: string = '';
  patterns: string = '';
  apiVersion: number = 1;
}

export class QuestionOption {
  label: string = '';
  description: string = '';
}

export class QuestionItem {
  question: string = '';
  header: string = '';
  multiple: boolean = false;
  options: QuestionOption[] = [];
}

// OpenCode Agent 澄清问题（GET /question）
export class QuestionRequest {
  id: string = '';
  sessionID: string = '';
  questions: QuestionItem[] = [];

  static fromJson(o: Record<string, Object>): QuestionRequest {
    const q = new QuestionRequest();
    q.id = strO(o, 'id', '');
    q.sessionID = strO(o, 'sessionID', '');
    const qs = o['questions'];
    if (Array.isArray(qs)) {
      const raw = qs as Object[];
      for (let i = 0; i < raw.length; i++) {
        const qo = raw[i] as Record<string, Object>;
        const item = new QuestionItem();
        item.question = strO(qo, 'question', '');
        item.header = strO(qo, 'header', '');
        item.multiple = boolO(qo, 'multiple', false);
        const opts = qo['options'];
        if (Array.isArray(opts)) {
          const oraw = opts as Object[];
          for (let j = 0; j < oraw.length; j++) {
            const oo = oraw[j] as Record<string, Object>;
            const opt = new QuestionOption();
            opt.label = strO(oo, 'label', '');
            opt.description = strO(oo, 'description', '');
            item.options.push(opt);
          }
        }
        q.questions.push(item);
      }
    }
    return q;
  }
}

// 远程文件浏览：/file 目录条目
export class FileNode {
  name: string = '';
  path: string = '';
  absolute: string = '';
  type: string = 'file'; // file | directory
  ignored: boolean = false;

  static fromJson(o: Record<string, Object>): FileNode {
    const n = new FileNode();
    n.name = strO(o, 'name', '');
    n.path = strO(o, 'path', '');
    n.absolute = strO(o, 'absolute', '');
    n.type = strO(o, 'type', 'file');
    n.ignored = boolO(o, 'ignored', false);
    return n;
  }
}

// /file/content 读取结果
export class FileContent {
  type: string = 'text'; // text | binary
  content: string = '';
  mimeType: string = '';
  encoding: string = ''; // base64 时 content 为 base64

  static fromJson(o: Record<string, Object>): FileContent {
    const c = new FileContent();
    c.type = strO(o, 'type', 'text');
    c.content = strO(o, 'content', '');
    c.mimeType = strO(o, 'mimeType', '');
    c.encoding = strO(o, 'encoding', '');
    return c;
  }
}

// /file/status git 追踪状态
export class FileStatusInfo {
  path: string = '';
  added: number = 0;
  removed: number = 0;
  status: string = ''; // added | deleted | modified

  static fromJson(o: Record<string, Object>): FileStatusInfo {
    const s = new FileStatusInfo();
    s.path = strO(o, 'path', '');
    s.added = numO(o, 'added', 0);
    s.removed = numO(o, 'removed', 0);
    s.status = strO(o, 'status', '');
    return s;
  }
}

// /find 全文搜索单条命中（lines 服务端为 {text}）
export class FindMatch {
  path: string = '';
  lineText: string = '';
  lineNumber: number = 0;
  absoluteOffset: number = 0;

  static fromJson(o: Record<string, Object>): FindMatch {
    const m = new FindMatch();
    const p = o['path'];
    if (p !== undefined && p !== null) {
      m.path = strO(p as Record<string, Object>, 'text', '');
    }
    const ls = o['lines'];
    if (ls !== undefined && ls !== null) {
      m.lineText = strO(ls as Record<string, Object>, 'text', '');
    }
    m.lineNumber = numO(o, 'line_number', 0);
    m.absoluteOffset = numO(o, 'absolute_offset', 0);
    return m;
  }
}