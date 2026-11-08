import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../../common/utils/Logger';
import {
  Project, SessionInfo, MessagesPayload, strO, ProviderInfo, FileDiff, TodoItem,
  QuestionRequest, PermissionRequest, AttachmentInput, FileNode, FileContent,
  FileStatusInfo, FindMatch
} from '../../common/model/Types';

const TAG = 'ApiClient';

export class ApiError extends Error {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.code = code;
  }
}

// 分页拉取结果：消息列表 + 下一页游标（X-Next-Cursor，空表示没有更早）
export class MessagesPage {
  payloads: MessagesPayload[] = [];
  next: string = '';
}

// Basic auth: base64(username:password)
function utf8Bytes(s: string): Uint8Array {
  const enc = new util.TextEncoder('utf-8');
  return enc.encodeInto(s);
}

function base64Encode(bytes: Uint8Array): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const b0 = bytes[i];
    const b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
    const b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
    out += chars.charAt(b0 >> 2);
    out += chars.charAt(((b0 & 3) << 4) | (b1 >> 4));
    out += i + 1 < bytes.length ? chars.charAt(((b1 & 15) << 2) | (b2 >> 6)) : '=';
    out += i + 2 < bytes.length ? chars.charAt(b2 & 63) : '=';
  }
  return out;
}

// OpenCode 1.15+ 要求 prompt_async 携带 messageID / part.id
function ocId(prefix: string): string {
  const t = Date.now().toString(36);
  const r = Math.floor(Math.random() * 1e9).toString(36);
  return prefix + t + r;
}

export class ApiClient {
  private baseUrl: string;
  private password: string;
  private username: string;
  directory: string = '';

  constructor(baseUrl: string, password: string, username: string = 'opencode') {
    this.baseUrl = baseUrl;
    this.password = password;
    this.username = username;
  }

  getBaseUrl(): string {
    return this.baseUrl;
  }

  getAuthHeader(): string {
    return 'Basic ' + base64Encode(utf8Bytes(this.username + ':' + this.password));
  }

  private url(path: string): string {
    return this.baseUrl + path;
  }

  private headers(withJson: boolean): Record<string, string> {
    const h: Record<string, string> = {};
    h['Authorization'] = this.getAuthHeader();
    h['Accept'] = 'application/json';
    if (this.directory.length > 0) {
      h['x-opencode-directory'] = this.directory;
    }
    if (withJson) {
      h['Content-Type'] = 'application/json';
    }
    return h;
  }

  private request(method: http.RequestMethod, path: string, body: string,
    onHeader: (h: Object) => void = (): void => {
    }): Promise<string> {
    return new Promise<string>((resolve, reject) => {
      const req = http.createHttp();
      const isBody = body.length > 0;
      const options: http.HttpRequestOptions = {
        method: method,
        header: this.headers(isBody),
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: false
      };
      if (isBody) {
        options.extraData = body;
      }
      req.request(this.url(path), options).then((resp: http.HttpResponse) => {
        req.destroy();
        const code = resp.responseCode;
        // 204 No Content：prompt_async 成功时常见
        if (code >= 200 && code < 300) {
          try {
            onHeader(resp.header);
          } catch (e) {
            Logger.w(TAG, 'onHeader err');
          }
          const r = resp.result;
          if (r === undefined || r === null) {
            resolve('');
            return;
          }
          resolve('' + r);
          return;
        }
        let detail = '';
        try {
          detail = resp.result !== undefined && resp.result !== null ? ('' + resp.result) : '';
        } catch (_e) {
          detail = '';
        }
        // 生产日志脱敏：截断响应体，避免 token/路径整段落盘
        const safeDetail = detail.length > 160 ? (detail.substring(0, 160) + '…') : detail;
        Logger.w(TAG, 'HTTP ' + code + ' ' + path + (safeDetail.length > 0 ? (' ' + safeDetail) : ''));
        const userDetail = detail.length > 80 ? (detail.substring(0, 80) + '…') : detail;
        reject(new ApiError(code, 'HTTP ' + code + (userDetail.length > 0 ? (': ' + userDetail) : '')));
      }).catch((err: Error) => {
        req.destroy();
        Logger.w(TAG, 'request failed ' + path + ' ' + err.message);
        reject(new ApiError(0, 'network error: ' + err.message));
      });
    });
  }

  private get(path: string): Promise<string> {
    return this.request(http.RequestMethod.GET, path, '');
  }

  private post(path: string, bodyJson: string | null): Promise<string> {
    return this.request(http.RequestMethod.POST, path, bodyJson === null ? '' : bodyJson);
  }

  async health(): Promise<string> {
    const txt = await this.get('/global/health');
    const o = JSON.parse(txt) as Record<string, Object>;
    return strO(o, 'version', '');
  }

  async listProjects(): Promise<Project[]> {
    const txt = await this.get('/project');
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: Project[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(Project.fromJson(arr[i]));
    }
    return out;
  }

  async listSessions(): Promise<SessionInfo[]> {
    const txt = await this.get('/session');
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: SessionInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(SessionInfo.fromJson(arr[i]));
    }
    return out;
  }

  async createSession(title: string): Promise<SessionInfo> {
    const body = '{"title":' + JSON.stringify(title) + '}';
    const txt = await this.post('/session', body);
    const o = JSON.parse(txt) as Record<string, Object>;
    return SessionInfo.fromJson(o);
  }

  async deleteSession(sessionID: string): Promise<void> {
    await this.request(http.RequestMethod.DELETE, '/session/' + sessionID, '');
  }

  // 删除单条消息（服务端 removeMessage 不级联，截断需逐条删）
  async deleteMessage(sessionID: string, messageID: string): Promise<void> {
    await this.request(http.RequestMethod.DELETE, '/session/' + sessionID + '/message/' + messageID, '');
  }

  // 让 PC 端 TUI 切换到指定会话（服务器发布 TuiEvent.SessionSelect）
  async selectSession(sessionID: string): Promise<void> {
    const body = '{"sessionID":' + JSON.stringify(sessionID) + '}';
    await this.post('/tui/select-session', body);
  }

  // 写入会话焦点时间戳，供手机/浏览器互相跟随切换
  // 注：部分 OH SDK 的 RequestMethod 无 PATCH，这里用字符串方法名发起请求
  async publishSessionFocus(sessionID: string, source: string, focusAt: number): Promise<void> {
    const meta: Record<string, Object> = {};
    meta['ocFocus'] = focusAt;
    meta['ocFocusSource'] = source;
    const bodyObj: Record<string, Object> = {};
    bodyObj['metadata'] = meta;
    const body = JSON.stringify(bodyObj);
    await new Promise<string>((resolve, reject) => {
      const req = http.createHttp();
      const options: http.HttpRequestOptions = {
        method: 'PATCH' as http.RequestMethod,
        header: this.headers(true),
        extraData: body,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 15000,
        readTimeout: 60000,
        usingCache: false
      };
      req.request(this.url('/session/' + sessionID), options).then((resp: http.HttpResponse) => {
        try {
          req.destroy();
        } catch (e) {
          Logger.w(TAG, 'req destroy err');
        }
        const code = resp.responseCode;
        const raw = typeof resp.result === 'string' ? resp.result as string : JSON.stringify(resp.result);
        if (code >= 200 && code < 300) {
          resolve(raw);
          return;
        }
        reject(new ApiError(code, 'HTTP ' + code + ' PATCH /session/' + sessionID));
      }).catch((err: Error) => {
        try {
          req.destroy();
        } catch (e) {
          Logger.w(TAG, 'req destroy err');
        }
        reject(new ApiError(0, 'network error: ' + err.message));
      });
    });
  }

  // 各会话运行状态：{ [sessionID]: { type: 'idle'|'busy'|'retry' } }
  async listSessionStatus(): Promise<Record<string, string>> {
    const txt = await this.get('/session/status');
    const o = JSON.parse(txt) as Record<string, Object>;
    const out: Record<string, string> = {};
    const keys = Object.keys(o);
    for (let i = 0; i < keys.length; i++) {
      const v = o[keys[i]] as Record<string, Object>;
      const st = typeof v === 'object' ? (v['type'] as string) : '';
      if (typeof st === 'string' && st.length > 0) {
        out[keys[i]] = st;
      }
    }
    return out;
  }

  async listMessages(sessionID: string, limit: number = 40): Promise<MessagesPayload[]> {
    // 大会话全量拉取可达数 MB，手机会卡死；limit 返回最新 N 条
    let path = '/session/' + sessionID + '/message';
    if (limit > 0) {
      path = path + '?limit=' + limit.toString();
    }
    const txt = await this.get(path);
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: MessagesPayload[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(MessagesPayload.fromJson(arr[i]));
    }
    return out;
  }

  // 响应头大小写不敏感取值（http 返回的 header 键名可能是小写）
  private headerValue(h: Object, name: string): string {
    if (h === undefined || h === null) {
      return '';
    }
    const o = h as Record<string, Object>;
    const keys = Object.keys(o);
    const lower = name.toLowerCase();
    for (let i = 0; i < keys.length; i++) {
      if (keys[i].toLowerCase() === lower) {
        const v = o[keys[i]];
        if (v === undefined || v === null) {
          return '';
        }
        return '' + v;
      }
    }
    return '';
  }

  // 分页拉取：limit=最新 N 条；before=上一页的游标（X-Next-Cursor）取更早消息
  // 返回 { payloads, next }，next 为空表示没有更早历史或服务端不支持游标
  async listMessagesCursor(sessionID: string, limit: number, before?: string): Promise<MessagesPage> {
    let path = '/session/' + sessionID + '/message?limit=' + limit.toString();
    if (before !== undefined && before.length > 0) {
      path = path + '&before=' + encodeURIComponent(before);
    }
    let next = '';
    const txt = await this.request(http.RequestMethod.GET, path, '', (h: Object) => {
      next = this.headerValue(h, 'x-next-cursor');
    });
    const page = new MessagesPage();
    const arr = JSON.parse(txt) as Record<string, Object>[];
    for (let i = 0; i < arr.length; i++) {
      page.payloads.push(MessagesPayload.fromJson(arr[i]));
    }
    page.next = next;
    return page;
  }

  async sendMessage(sessionID: string, text: string, providerID?: string, modelID?: string,
    attachments?: AttachmentInput[] | null, agent?: string): Promise<string> {
    // OpenCode 1.15+：必须带 messageID + parts[].id（part id 必须以 prt 开头）
    const messageID = ocId('msg_');
    const parts: string[] = [];
    if (text.trim().length > 0) {
      const partID = ocId('prt_');
      parts.push('{"id":' + JSON.stringify(partID) +
        ',"type":"text","text":' + JSON.stringify(text) + '}');
    }
    if (attachments !== undefined && attachments !== null) {
      for (let i = 0; i < attachments.length; i++) {
        const a = attachments[i];
        const partID = ocId('prt_');
        if (a.isImage) {
          parts.push('{"id":' + JSON.stringify(partID) +
            ',"type":"file","mime":' + JSON.stringify(a.mime) +
            ',"filename":' + JSON.stringify(a.filename) +
            ',"url":' + JSON.stringify(a.content) + '}');
        } else {
          // 文本文件：内容直传 source.text（url 用占位名，服务端以 source 为准）
          parts.push('{"id":' + JSON.stringify(partID) +
            ',"type":"file","mime":' + JSON.stringify(a.mime) +
            ',"filename":' + JSON.stringify(a.filename) +
            ',"url":"' + a.filename.replace(/"/g, '%22') + '"' +
            ',"source":{"type":"file","path":' + JSON.stringify(a.filename) +
            ',"text":{"value":' + JSON.stringify(a.content) + ',"start":0,"end":' + a.content.length.toString() + '}}}');
        }
      }
    }
    const ag = agent !== undefined && agent.length > 0 ? agent : 'build';
    let body = '{"messageID":' + JSON.stringify(messageID) +
      ',"agent":' + JSON.stringify(ag) + ',"parts":[' + parts.join(',') + ']}';
    if (providerID !== undefined && modelID !== undefined && providerID.length > 0 && modelID.length > 0) {
      body = '{"messageID":' + JSON.stringify(messageID) +
        ',"agent":' + JSON.stringify(ag) + ',"parts":[' + parts.join(',') +
        '],"model":{"providerID":' + JSON.stringify(providerID) +
        ',"modelID":' + JSON.stringify(modelID) + '}}';
    }
    await this.post('/session/' + sessionID + '/prompt_async', body);
    return messageID;
  }

  private sessionSwitchOK: boolean = true; // 服务端是否支持会话级 agent/model 切换端点

  // 切换会话的 Agent 模式并同步到服务端（新版 server 端点；旧版返回 SPA 页面则自动禁用）
  async switchSessionAgent(sessionID: string, agent: string): Promise<void> {
    if (!this.sessionSwitchOK) {
      return;
    }
    try {
      const txt = await this.post('/session/' + sessionID + '/agent',
        '{"agent":' + JSON.stringify(agent) + '}');
      if (!this.isJson(txt)) {
        this.sessionSwitchOK = false;
      }
    } catch (_e) {
      this.sessionSwitchOK = false;
    }
  }

  // 切换会话模型并同步到服务端（新版 server 端点；旧版返回 SPA 页面则自动禁用）
  async switchSessionModel(sessionID: string, providerID: string, modelID: string): Promise<void> {
    if (!this.sessionSwitchOK) {
      return;
    }
    try {
      const txt = await this.post('/session/' + sessionID + '/model',
        '{"model":{"providerID":' + JSON.stringify(providerID) +
        ',"modelID":' + JSON.stringify(modelID) + '}}');
      if (!this.isJson(txt)) {
        this.sessionSwitchOK = false;
      }
    } catch (_e) {
      this.sessionSwitchOK = false;
    }
  }

  private isJson(txt: string): boolean {
    const t = txt.trimStart();
    return t.length > 0 && (t.charAt(0) === '{' || t.charAt(0) === '[');
  }

  async abort(sessionID: string): Promise<void> {
    await this.post('/session/' + sessionID + '/abort', null);
  }

  // ==== 远程文件浏览 / 搜索 ====

  // GET /file?path= 列出目录（path 为空为项目根）
  async listFiles(path: string): Promise<FileNode[]> {
    const txt = await this.get('/file?path=' + encodeURIComponent(path));
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: FileNode[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(FileNode.fromJson(arr[i]));
    }
    return out;
  }

  // GET /file/content?path= 读取文件
  async readFile(path: string): Promise<FileContent> {
    const txt = await this.get('/file/content?path=' + encodeURIComponent(path));
    return FileContent.fromJson(JSON.parse(txt) as Record<string, Object>);
  }

  // GET /file/status git 追踪状态
  async listFileStatus(): Promise<FileStatusInfo[]> {
    const txt = await this.get('/file/status');
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: FileStatusInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(FileStatusInfo.fromJson(arr[i]));
    }
    return out;
  }

  // GET /find?pattern= 全文搜索（ripgrep，最多 10 条）
  async findText(pattern: string): Promise<FindMatch[]> {
    const txt = await this.get('/find?pattern=' + encodeURIComponent(pattern));
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: FindMatch[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(FindMatch.fromJson(arr[i]));
    }
    return out;
  }

  // GET /find/file?query= 按文件名搜索
  async findFiles(query: string): Promise<string[]> {
    const txt = await this.get('/find/file?query=' + encodeURIComponent(query));
    const arr = JSON.parse(txt) as Object[];
    const out: string[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(arr[i] as string);
    }
    return out;
  }

  // GET /provider -> { all: Provider[], default, connected }
  // 只展示已连接（connected）的服务商；connected 为空则不回退到全量目录
  async listProviders(): Promise<ProviderInfo[]> {
    const txt = await this.get('/provider');
    const o = JSON.parse(txt) as Record<string, Object>;
    const connectedIds: string[] = [];
    const connectedRaw = o['connected'];
    if (Array.isArray(connectedRaw)) {
      const arr = connectedRaw as Object[];
      for (let i = 0; i < arr.length; i++) {
        const id = String(arr[i]);
        if (id.length > 0) {
          connectedIds.push(id);
        }
      }
    }
    if (connectedIds.length === 0) {
      Logger.w(TAG, 'no connected providers from /provider');
      return [];
    }
    const out: ProviderInfo[] = [];
    const all = o['all'];
    if (Array.isArray(all)) {
      const raw = all as Object[];
      for (let i = 0; i < raw.length; i++) {
        const p = ProviderInfo.fromJson(raw[i] as Record<string, Object>);
        if (connectedIds.indexOf(p.id) >= 0) {
          out.push(p);
        }
      }
    }
    if (out.length === 0) {
      Logger.w(TAG, 'connected providers not found in /provider.all');
    }
    return out;
  }

  async listDiffs(sessionID: string): Promise<FileDiff[]> {
    const txt = await this.get('/session/' + sessionID + '/diff');
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: FileDiff[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(FileDiff.fromJson(arr[i]));
    }
    return out;
  }

  async listTodos(sessionID: string): Promise<TodoItem[]> {
    const txt = await this.get('/session/' + sessionID + '/todo');
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: TodoItem[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(TodoItem.fromJson(arr[i]));
    }
    return out;
  }

  // OpenCode 1.18: 合并 v1 /permission 与 v2 /api/permission/request（目录访问等走 v2）
  async listPermissions(): Promise<PermissionRequest[]> {
    const byId = new Map<string, PermissionRequest>();
    try {
      const txt = await this.get('/permission');
      const arr = JSON.parse(txt) as Record<string, Object>[];
      if (Array.isArray(arr)) {
        for (let i = 0; i < arr.length; i++) {
          const o = arr[i];
          const pr = PermissionRequest.fromJson(o, strO(o, 'sessionID', ''));
          pr.apiVersion = 1;
          if (pr.id.length > 0) {
            byId.set(pr.id, pr);
          }
        }
      }
    } catch (e) {
      Logger.w(TAG, 'listPermissions v1 failed');
    }
    try {
      const txt2 = await this.get('/api/permission/request');
      const root = JSON.parse(txt2) as Record<string, Object>;
      const dataObj = root['data'];
      if (dataObj !== undefined && Array.isArray(dataObj)) {
        const arr2 = dataObj as Record<string, Object>[];
        for (let i = 0; i < arr2.length; i++) {
          const o = arr2[i];
          const pr = PermissionRequest.fromJson(o, strO(o, 'sessionID', ''));
          pr.apiVersion = 2;
          if (pr.id.length > 0) {
            byId.set(pr.id, pr);
          }
        }
      }
    } catch (e) {
      Logger.w(TAG, 'listPermissions v2 failed');
    }
    const out: PermissionRequest[] = [];
    byId.forEach((v: PermissionRequest) => {
      out.push(v);
    });
    return out;
  }

  async replyPermission(sessionID: string, permissionID: string, reply: string,
    apiVersion: number = 1): Promise<void> {
    const body = '{"reply":' + JSON.stringify(reply) + '}';
    if (apiVersion >= 2 && sessionID.length > 0) {
      await this.post('/api/session/' + sessionID + '/permission/' + permissionID + '/reply', body);
      return;
    }
    try {
      await this.post('/permission/' + permissionID + '/reply', body);
    } catch (e) {
      // v1 失败时回退 v2（部分环境只挂 v2）
      if (sessionID.length > 0) {
        await this.post('/api/session/' + sessionID + '/permission/' + permissionID + '/reply', body);
        return;
      }
      const msg = e instanceof Error ? e.message : 'permission reply failed';
      throw new ApiError(0, msg);
    }
  }

  // GET /question，POST /question/{id}/reply {"answers":[["option label"]]}
  async listQuestions(): Promise<QuestionRequest[]> {
    const txt = await this.get('/question');
    const arr = JSON.parse(txt) as Record<string, Object>[];
    const out: QuestionRequest[] = [];
    for (let i = 0; i < arr.length; i++) {
      out.push(QuestionRequest.fromJson(arr[i]));
    }
    return out;
  }

  async replyQuestion(questionID: string, answers: string[][]): Promise<void> {
    const body = '{"answers":' + JSON.stringify(answers) + '}';
    await this.post('/question/' + questionID + '/reply', body);
  }
}