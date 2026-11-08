import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { common } from '@kit.AbilityKit';
import { SessionInfo, MessageInfo, Part } from '../common/model/Types';
import { Logger } from '../common/utils/Logger';

const TAG = 'CacheStore';
const VER = 1;

class CacheSession {
  id: string = '';
  title: string = '';
  worktree: string = '';
  created: number = 0;
  updated: number = 0;
  ocFocus: number = 0;
  ocFocusSource: string = '';
  tokensInput: number = 0;
  tokensOutput: number = 0;
  cost: number = 0;
  messageCount: number = 0;
  lastText: string = '';
}

class CachePart {
  id: string = '';
  type: string = 'text';
  text: string = '';
  toolName: string = '';
  toolInput: string = '';
  toolState: string = '';
  filePath: string = '';
}

class CacheMessage {
  id: string = '';
  sessionID: string = '';
  role: string = 'user';
  parentID: string = '';
  modelID: string = '';
  providerID: string = '';
  created: number = 0;
  finish: string = '';
  error: string = '';
  parts: CachePart[] = [];
}

class CacheBundle {
  version: number = VER;
  src: string = '';
  savedAt: number = 0;
  currentSid: string = '';
  sessions: CacheSession[] = [];
  messages: CacheMessage[] = [];
}

export class CacheData {
  sessions: SessionInfo[] = [];
  currentSid: string = '';
  messages: MessageInfo[] = [];
  parts: Map<string, Part[]> = new Map();
}

function toCacheSession(s: SessionInfo): CacheSession {
  const c = new CacheSession();
  c.id = s.id;
  c.title = s.title;
  c.worktree = s.worktree;
  c.created = s.created;
  c.updated = s.updated;
  c.ocFocus = s.ocFocus;
  c.ocFocusSource = s.ocFocusSource;
  c.tokensInput = s.tokensInput;
  c.tokensOutput = s.tokensOutput;
  c.cost = s.cost;
  c.messageCount = s.messageCount;
  c.lastText = s.lastText;
  return c;
}

function toCacheMessage(m: MessageInfo, pArr: Part[]): CacheMessage {
  const c = new CacheMessage();
  c.id = m.id;
  c.sessionID = m.sessionID;
  c.role = m.role;
  c.parentID = m.parentID;
  c.modelID = m.modelID;
  c.providerID = m.providerID;
  c.created = m.created;
  c.finish = m.finish;
  c.error = m.error;
  for (let i = 0; i < pArr.length; i++) {
    const p = pArr[i];
    const cp = new CachePart();
    cp.id = p.id;
    cp.type = p.type;
    cp.text = p.text;
    cp.toolName = p.toolName;
    cp.toolInput = p.toolInput;
    cp.toolState = p.toolState;
    cp.filePath = p.filePath;
    c.parts.push(cp);
  }
  return c;
}

function toSessionInfo(c: CacheSession): SessionInfo | null {
  if (c.id.length === 0) {
    return null;
  }
  const s = new SessionInfo();
  s.id = c.id;
  s.title = c.title;
  s.worktree = c.worktree;
  s.created = c.created;
  s.updated = c.updated;
  s.ocFocus = c.ocFocus;
  s.ocFocusSource = c.ocFocusSource;
  s.tokensInput = c.tokensInput;
  s.tokensOutput = c.tokensOutput;
  s.cost = c.cost;
  s.messageCount = c.messageCount;
  s.lastText = c.lastText;
  return s;
}

function toMessageInfo(c: CacheMessage): MessageInfo | null {
  if (c.id.length === 0) {
    return null;
  }
  const m = new MessageInfo();
  m.id = c.id;
  m.sessionID = c.sessionID;
  m.role = c.role;
  m.parentID = c.parentID;
  m.modelID = c.modelID;
  m.providerID = c.providerID;
  m.created = c.created;
  m.finish = c.finish;
  m.error = c.error;
  return m;
}

export class CacheStore {
  private static FILE = 'oc_cache.json';

  private static filePath(ctx: common.Context): string {
    return ctx.filesDir + '/' + CacheStore.FILE;
  }

  // 序列化后写盘；失败静默（缓存是锦上添花）
  // 全程异步 I/O，避免在轮询主线程上同步阻塞（流式期间每 3s 一次全量落盘）
  static async persist(entityName: string, ctx: common.Context, src: string, currentSid: string,
    sessions: SessionInfo[], messages: MessageInfo[], parts: Map<string, Part[]>): Promise<void> {
    try {
      const bundle = new CacheBundle();
      bundle.src = src;
      bundle.savedAt = Date.now();
      bundle.currentSid = currentSid;
      for (let i = 0; i < sessions.length; i++) {
        bundle.sessions.push(toCacheSession(sessions[i]));
      }
      // 只存最近的 40 条，避免单文件过大
      const sorted: MessageInfo[] = messages.slice();
      sorted.sort((a: MessageInfo, b: MessageInfo) => a.created - b.created);
      const from = sorted.length > 40 ? sorted.length - 40 : 0;
      for (let i = from; i < sorted.length; i++) {
        const m = sorted[i];
        const pArr = parts.get(m.id);
        const p = pArr === undefined ? [] : pArr;
        bundle.messages.push(toCacheMessage(m, p));
      }
      const path = CacheStore.filePath(ctx);
      const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const data = JSON.stringify(bundle);
        let written = 0;
        while (written < data.length) {
          const n = await fs.write(file.fd, data, { offset: written });
          if (n <= 0) {
            break;
          }
          written += n;
        }
      } finally {
        await fs.close(file.fd);
      }
    } catch (e) {
      Logger.w(TAG, entityName + ': persist failed');
    }
  }

  // 读取缓存；返回 null 表示无缓存或解析失败
  static load(entityName: string, ctx: common.Context, src: string): CacheData | null {
    try {
      const path = CacheStore.filePath(ctx);
      if (!fs.accessSync(path)) {
        return null;
      }
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      let text = '';
      try {
        const stat = fs.statSync(path);
        const buf = new ArrayBuffer(stat.size);
        const n = fs.readSync(file.fd, buf);
        if (n > 0) {
          // 用 TextDecoder 按 UTF-8 解码，避免逐字节 fromCharCode 把中文变成乱码
          const dec = new util.TextDecoder('utf-8');
          text = dec.decodeToString(new Uint8Array(buf, 0, n));
        }
      } finally {
        fs.closeSync(file.fd);
      }
      if (text.length === 0) {
        return null;
      }
      const raw = JSON.parse(text) as CacheBundle;
      if (raw.version !== VER || raw.src !== src) {
        return null;
      }
      const data = new CacheData();
      data.currentSid = raw.currentSid;
      for (let i = 0; i < raw.sessions.length; i++) {
        const s = toSessionInfo(raw.sessions[i]);
        if (s !== null) {
          data.sessions.push(s);
        }
      }
      for (let i = 0; i < raw.messages.length; i++) {
        const m = toMessageInfo(raw.messages[i]);
        if (m === null) {
          continue;
        }
        const pArr: Part[] = [];
        for (let j = 0; j < raw.messages[i].parts.length; j++) {
          const cp = raw.messages[i].parts[j];
          const p = new Part();
          p.id = cp.id;
          p.type = cp.type;
          p.text = cp.text;
          p.toolName = cp.toolName;
          p.toolInput = cp.toolInput;
          p.toolState = cp.toolState;
          p.filePath = cp.filePath;
          pArr.push(p);
        }
        data.messages.push(m);
        data.parts.set(m.id, pArr);
      }
      return data;
    } catch (e) {
      Logger.w(TAG, entityName + ': load failed');
      return null;
    }
  }

  static clear(entityName: string, ctx: common.Context): void {
    try {
      const path = CacheStore.filePath(ctx);
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (e) {
      Logger.w(TAG, entityName + ': clear failed');
    }
  }
}