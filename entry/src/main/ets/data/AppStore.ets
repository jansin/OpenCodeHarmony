import { preferences } from '@kit.ArkData';
import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { ApiClient } from './api/ApiClient';
import { EventStreamBridge } from './api/EventStreamBridge';
import { CacheStore } from './CacheStore';
import { Theme } from '../common/Theme';
import { Logger } from '../common/utils/Logger';
import { Notifier } from '../common/utils/Notifier';
import { SecretBox } from '../common/utils/SecretBox';
import { Toast } from '../common/utils/Toast';
import { WindowChrome } from '../common/utils/WindowChrome';
import {
  ServerConfig, Project, SessionInfo, MessageInfo, MessagesPayload, Part,
  ProviderInfo, FileDiff, TodoItem, Approval, QuestionRequest, AttachmentInput
} from '../common/model/Types';

const TAG = 'AppStore';

// minimalist typed emitter
export type Listener = () => void;

class Emitter {
  private map: Map<string, Listener[]> = new Map();

  on(name: string, l: Listener): void {
    let arr = this.map.get(name);
    if (arr === undefined) {
      arr = [];
      this.map.set(name, arr);
    }
    arr.push(l);
  }

  off(name: string, l: Listener): void {
    const arr = this.map.get(name);
    if (arr === undefined) {
      return;
    }
    const i = arr.indexOf(l);
    if (i >= 0) {
      arr.splice(i, 1);
    }
  }

  emit(name: string): void {
    const arr = this.map.get(name);
    if (arr === undefined) {
      return;
    }
    const copy = arr.slice();
    for (let i = 0; i < copy.length; i++) {
      copy[i]();
    }
  }
}

// Single source of truth, mirroring the Zustand store used by reference clients.
export class AppStore {
  server: ServerConfig = new ServerConfig();
  api: ApiClient | null = null;
  connected: boolean = false;
  version: string = '';
  projects: Project[] = [];
  currentProject: Project | null = null;
  providers: ProviderInfo[] = [];
  sessions: SessionInfo[] = [];
  sessionStatus: Record<string, string> = {}; // sessionID -> 'idle'|'busy'|'retry'
  currentSessionId: string = '';
  currentSessionTitle: string = '';
  working: boolean = false;
  lastError: string = '';
  hasSaved: boolean = false;
  // 是否在 working 状态变化时发系统通知提醒
  notifyEnabled: boolean = true;

  // ---- M2 ----
  currentProviderID: string = '';
  currentModelID: string = '';
  currentAgent: string = 'build'; // build | plan，切换时同步到服务端会话
  approvals: Approval[] = [];
  questions: QuestionRequest[] = [];
  diffs: FileDiff[] = [];
  todos: TodoItem[] = [];
  reviewDirty: boolean = false;

  // message payloads keyed by message id
  private messages: Map<string, MessageInfo> = new Map();
  private parts: Map<string, Part[]> = new Map();
  private em = new Emitter();

  // ---- 历史消息分页 ----
  // 当前会话"更早历史"分页游标（X-Next-Cursor）；空 = 没有更早或服务端不支持
  private historyCursor: string = '';
  // 分页拉回的更早历史独立存放，最新窗口轮询（applyPayloads）替换消息表时回填，避免丢失
  private extraMessages: Map<string, MessageInfo> = new Map();
  private extraParts: Map<string, Part[]> = new Map();
  // 是否还有更早历史可加载 / 正在加载（ChatView 顶部入口读取）
  hasMoreHistory: boolean = true;
  loadingMoreHistory: boolean = false;

  // ---- 本地缓存（弱网离线可读）----
  // 最近一次成功轮询后自动落盘；断连或启动失败时读回兜底
  private cacheCtx: common.Context | null = null;
  private lastCacheAt: number = 0;

  attachCacheContext(ctx: common.Context): void {
    this.cacheCtx = ctx;
  }

  on(name: string, l: Listener): void {
    this.em.on(name, l);
  }

  off(name: string, l: Listener): void {
    this.em.off(name, l);
  }

  private emit(name: string): void {
    this.em.emit(name);
  }

  // ---- polling driver ----
  // SSE dataReceive/dataEnd never fire on this device for streaming responses
  // (same limitation the reference OHOS client documents), so remote state is
  // refreshed on a timer from the REST API instead.
  private pollTimer: number = -1;
  private pollTick: number = 0;
  // 应用退到后台时降频轮询：省电、减少无界面场景下的无谓网络请求
  private background: boolean = false;
  private lastFp: string = '';
  private triggeredAt: number = 0;
  // 本机发送时所见的服务端消息最大 created（服务端时钟）。
  // 用于区分"发送前历史"与"本次产出"，避免跨设备时钟偏差把
  // 已结束的 assistant 消息当历史忽略，导致 working 永不复位。
  private sendBaseCreated: number = 0;
  // 最近一次"数据发生变化"的时间（applyPayloads 实际更新消息时刷新）。
  // 用于判断任务是否真的停摆：若长时间无新数据且服务端状态为 idle，强制结束 working。
  private lastActivityAt: number = 0;
  // 本轮任务是否曾在 /session/status 见过 busy/retry。
  // OpenCode 对 idle 会话常直接省略条目（返回 {}），不能只等 type==='idle'。
  private sessionBusySeen: boolean = false;
  // 用户在本机点了「停止」：在下次 sendMessage 前禁止 detectWorking 把 working 拉回 true。
  // 否则 abort 后服务端 finish 未落库时，轮询会因「未完成 assistant」再次显示思考中。
  private abortLatch: boolean = false;
  // 已应用的远程焦点时间戳，避免重复跟随；本地切换后短暂忽略回声
  private appliedFocusAt: number = 0;
  private ignoreRemoteFocusUntil: number = 0;
  private followingRemoteFocus: boolean = false;
  private pollFailCount: number = 0;

  // ---- 真流式：SSE /event 事件桥 ----
  // 设备支持 SSE 时，文本/推理增量经事件流实时落地（逐 token）；
  // 不支持时自动回退高频轮询 + 打字机。轮询始终作为兜底数据源。
  private eventBridge: EventStreamBridge | null = null;
  private sseActive: boolean = false;
  // SSE 最近活跃时间戳：活跃期内跳过 REST 全量拉取，只刷轻量端点
  private lastSseAt: number = 0;
  // SSE 落地中的文本增量缓冲：textID -> 累计文本（供 delta 拼接一致性）
  private sseTextBuffer: Map<string, string> = new Map();
  private sseReasoningBuffer: Map<string, string> = new Map();
  // SSE 收到事件后暂停一次轮询的冷却，避免重复拉取
  private lastSseRefreshAt: number = 0;

  startStream(): void {
    if (this.api === null || !this.connected) {
      return;
    }
    this.startPolling();
  }

  startPolling(): void {
    if (this.pollTimer >= 0) {
      return;
    }
    this.pollTick = 0;
    this.pollTimer = setTimeout(this.pollTickFn, 200);
  }

  private pollIntervalMs(): number {
    // 应用在后台时放慢到 5s：界面不可见，无需高频跟随，兼顾省电与后台通知及时性
    if (this.background) {
      return 5000;
    }
    // 工作中 / 等用户授权时加快轮询（SSE 不可用时的真流式兜底）
    if (this.working || this.approvals.length > 0 || this.questions.length > 0) {
      return 200;
    }
    return 2000;
  }

  // 前后台切换：后台降频省电；回前台立即刷新一次
  setBackground(bg: boolean): void {
    this.background = bg;
    if (!bg) {
      this.pollOnce();
    }
  }

  private pollTickFn = (): void => {
    this.pollOnce();
    if (this.pollTimer >= 0) {
      this.pollTimer = setTimeout(this.pollTickFn, this.pollIntervalMs());
    }
  };

  async pollOnce(): Promise<void> {
    if (this.api === null || !this.connected) {
      return;
    }
    const sid = this.currentSessionId;
    // SSE 活跃期间跳过 REST 全量拉取：消息数据已由事件流实时落地，
    // 避免每 200ms 重复 JSON 解析/指纹比对（省电省流量）。
    const sseFresh = Date.now() - this.lastSseAt < 2500;
    if (sid.length > 0 && !sseFresh) {
      try {
        // 只拉最新 40 条，避免大会话把手机打挂
        const payloads = await this.fetchWindow(sid, this.working ? 30 : 40);
        // 切换会话后丢弃过期轮询结果，避免串会话
        if (this.currentSessionId === sid) {
          this.applyPayloads(payloads);
          this.detectWorking(payloads);
          if (this.pollFailCount >= 4) {
            // 断连恢复：重新通知 PC TUI 对齐当前会话（失败记录日志）
            this.api.selectSession(sid).catch((e: Error) => {
              Logger.w(TAG, 'selectSession(rc) failed: ' + e.message);
            });
          }
          this.pollFailCount = 0;
          if (this.lastError === 'disconnected') {
            this.lastError = '';
            this.emit('status');
          }
          // 数据更新成功后落盘缓存（节流：间隔 >=3s 才写一次；异步 I/O 不阻塞主线程）
          const now = Date.now();
          if (this.cacheCtx !== null && now - this.lastCacheAt >= 3000) {
            this.lastCacheAt = now;
            await CacheStore.persist('poll', this.cacheCtx, this.server.url, sid,
              this.sessions, this.getMessages(), this.parts);
          }
        }
      } catch (e) {
        // 连续失败才提示断连，避免瞬时抖动误报
        this.pollFailCount++;
        if (this.pollFailCount >= 4 && this.lastError !== 'disconnected') {
          this.lastError = 'disconnected';
          this.emit('status');
        }
      }
    }
    if (sid.length > 0) {
      this.pollTick++;
      if (this.pollTick % 3 === 0 && this.working) {
        this.refreshDiffs();
        this.refreshTodos();
      }
    }
    // 权限/问答与会话无关也要刷，避免错过 PC 弹出的目录授权
    this.refreshApprovalsAndQuestions();
    this.pollTick++;
    // 会话焦点跟随要够快：每轮都刷列表并检查 ocFocus
    this.refreshSessions();
    // 工作中每轮刷 session status（PC 停止后常返回 {}，需及时强制复位 working）；
    // 空闲时仍按 5 拍降频。
    if (this.working || this.pollTick % 5 === 0) {
      this.refreshSessionStatus();
    }
  }

  // SSE 活跃时，REST 拉回的 text part 可能落后于逐 token 增量。
  // 用本地累积的增量文本替换服务端同 part 的 text，保证连续一致。
  private mergeSseParts(messageID: string, serverParts: Part[]): Part[] {
    if (!this.sseActive || this.sseTextBuffer.size === 0 && this.sseReasoningBuffer.size === 0) {
      return serverParts;
    }
    const out: Part[] = [];
    for (let i = 0; i < serverParts.length; i++) {
      const p = serverParts[i];
      const isText = p.type === 'text';
      const isReasoning = p.type === 'reasoning';
      if (isText || isReasoning) {
        const buf = isReasoning ? this.sseReasoningBuffer : this.sseTextBuffer;
        // 尝试精确 part.id 匹配，其次按 type 顺序匹配首个文本
        let acc = buf.get(p.id);
        if (acc === undefined) {
          buf.forEach((val: string, key: string) => {
            if (acc !== undefined) {
              return;
            }
            if (key.indexOf('part_') >= 0) {
              return;
            }
            if ((isReasoning && key.indexOf('reasoning') === 0) || (!isReasoning && key.indexOf('reasoning') !== 0)) {
              acc = val;
            }
          });
        }
        if (acc !== undefined) {
          p.text = acc;
        }
      }
      out.push(p);
    }
    return out;
  }

  private applyPayloads(payloads: MessagesPayload[]): void {
    const newMsgs = new Map<string, MessageInfo>();
    const newParts = new Map<string, Part[]>();
    let fp = '';
    for (let i = 0; i < payloads.length; i++) {
      const p = payloads[i];
      if (p.message.id.length === 0) {
        continue;
      }
      // 丢掉本地乐观消息占位（服务端已有真实消息后）
      newMsgs.set(p.message.id, p.message);
      // SSE 活跃时保留本地 text 增量，避免 REST 全量覆盖逐 token 输出
      const parts = this.mergeSseParts(p.message.id, p.parts);
      newParts.set(p.message.id, parts);
      fp += p.message.id + ':' + p.message.finish + ':' + p.message.error.length + ':';
      fp += parts.length + ':';
      for (let j = 0; j < parts.length; j++) {
        fp += parts[j].id + ':' + parts[j].text.length + ':' + parts[j].toolState + ';';
      }
    }
    // 保留尚未被服务端回显的本地乐观消息
    const oldMsgs = this.messages;
    const oldParts = this.parts;
    oldMsgs.forEach((m: MessageInfo, id: string) => {
      if (id.indexOf('local_') !== 0 || newMsgs.has(id)) {
        return;
      }
      const localParts = oldParts.get(id);
      const localText = localParts !== undefined && localParts.length > 0 ? localParts[0].text : '';
      let duplicated = false;
      newMsgs.forEach((sm: MessageInfo, sid: string) => {
        if (duplicated || sm.role !== 'user') {
          return;
        }
        const sp = newParts.get(sid);
        if (sp !== undefined && sp.length > 0 && sp[0].text === localText) {
          duplicated = true;
        }
      });
      if (!duplicated) {
        newMsgs.set(id, m);
        if (localParts !== undefined) {
          newParts.set(id, localParts);
        }
      }
    });
    // 合并分页加载的更早历史：最新窗口轮询替换消息表时回填，避免已加载的历史被清掉
    const toDrop: string[] = [];
    this.extraMessages.forEach((m: MessageInfo, id: string) => {
      if (newMsgs.has(id)) {
        // 窗口已前移到覆盖该条，以窗口数据为准并释放 extra 副本
        toDrop.push(id);
        return;
      }
      newMsgs.set(id, m);
      const ep = this.extraParts.get(id);
      if (ep !== undefined) {
        newParts.set(id, ep);
      }
    });
    for (let i = 0; i < toDrop.length; i++) {
      this.extraMessages.delete(toDrop[i]);
      this.extraParts.delete(toDrop[i]);
    }
    if (fp === this.lastFp && newMsgs.size === this.messages.size) {
      return;
    }
    this.lastActivityAt = Date.now();
    this.lastFp = fp;
    this.messages = newMsgs;
    this.parts = newParts;
    this.emit('messages');
  }

  private isTerminalFinish(finish: string): boolean {
    if (finish.length === 0) {
      return false;
    }
    // tool-calls / tool-use 表示还要继续跑工具，不能算结束
    if (finish === 'tool-calls' || finish === 'tool_calls' || finish === 'tool-use') {
      return false;
    }
    return finish === 'stop' || finish === 'end_turn' || finish === 'length' || finish === 'error' ||
      finish === 'cancelled' || finish === 'aborted';
  }

  // 由服务器消息真相判定"当前是否仍在产出"：
  // - 本机发送过（triggeredAt>0）：看发送后未完结的 assistant；
  // - 仅跟随会话（triggeredAt===0）：不能只靠 finish 为空判忙（很多已完成消息也不带 finish），
  //   必须配合 /session/status 的 busy|retry，否则一进会话就会误显「思考中」。
  private detectWorking(payloads: MessagesPayload[]): void {
    // 有待回答问题 / 权限审批时，视为仍在工作，避免 UI 提前结束
    const waitingUser = this.approvals.length > 0 || this.questions.length > 0;
    let inFlight = waitingUser || this.isInFlight(payloads);
    // 本机已中止：在下次发送前不再因未落库的 finish 把转圈拉回来
    if (this.abortLatch && !waitingUser) {
      inFlight = false;
    }
    // 服务端 /session/status 为权威兜底。SSE 在本设备不可靠、任务在 PC 侧
    // 中止/切换模型等场景消息 finish 可能不落库，导致"PC 停了手机还在转"。
    // idle 条目可能被省略（返回 {}），见过 busy 后缺席也视为已停。
    if (inFlight && !waitingUser && this.shouldForceStopFromStatus()) {
      Logger.w(TAG, 'server status idle/absent & quiet, forcing working=false');
      inFlight = false;
    }
    if (inFlight !== this.working) {
      const prev = this.working;
      this.working = inFlight;
      if (!inFlight) {
        this.triggeredAt = 0;
        this.sessionBusySeen = false;
      }
      this.emit('status');
      // 仅后台提醒，避免前台刷通知
      if (this.notifyEnabled && this.background) {
        const title = this.currentSessionTitle.length > 0 ? this.currentSessionTitle : 'OpenCode';
        if (inFlight) {
          Notifier.notifyTaskStart(title, '\u4EFB\u52A1\u5F00\u59CB\u8FD0\u884C\uFF0C\u6B63\u5728\u5904\u7406\u4E2D\u2026');
        } else if (prev) {
          Notifier.notifyTaskDone(title, '\u4EFB\u52A1\u5DF2\u5B8C\u6210');
        }
      } else if (!inFlight && prev) {
        Notifier.cancelTask();
      }
    }
  }

  // /session/status：busy/retry 继续；idle 或（曾 busy 后缺席）且短暂静默 → 强制停
  private shouldForceStopFromStatus(): boolean {
    const sid = this.currentSessionId;
    if (sid.length === 0) {
      return false;
    }
    if (this.approvals.length > 0 || this.questions.length > 0) {
      return false;
    }
    const st = this.sessionStatus[sid];
    if (st === 'busy' || st === 'retry') {
      this.sessionBusySeen = true;
      return false;
    }
    const quietMs = Date.now() - this.lastActivityAt;
    // 步间/刚停后给一点缓冲，避免误杀
    if (quietMs < 1200) {
      return false;
    }
    if (st === 'idle') {
      return true;
    }
    // OpenCode 常对 idle 会话不返回条目：曾 busy 后缺席 ≈ 已停
    if ((st === undefined || st.length === 0) && this.sessionBusySeen) {
      return true;
    }
    // 从未刷到 busy，但已有未完结 assistant 且长时间无活动（PC 侧 abort 未落 finish）
    if ((st === undefined || st.length === 0) && quietMs > 6000 && this.hasOpenAssistantLocally()) {
      return true;
    }
    return false;
  }

  private hasOpenAssistantLocally(): boolean {
    let latestId = '';
    let latestCreated = -1;
    // 不用 forEach 闭包赋值：ArkTS 会把外层联合类型错误收窄成 never
    const ids = Array.from(this.messages.keys());
    for (let i = 0; i < ids.length; i++) {
      const m = this.messages.get(ids[i]);
      if (m === undefined || m.role !== 'assistant') {
        continue;
      }
      if (m.created > latestCreated) {
        latestCreated = m.created;
        latestId = m.id;
      }
    }
    if (latestId.length === 0) {
      return false;
    }
    const msg = this.messages.get(latestId);
    if (msg === undefined) {
      return false;
    }
    return msg.error.length === 0 && !this.isTerminalFinish(msg.finish);
  }

  private forceStopWorking(reason: string): void {
    if (!this.working && this.triggeredAt === 0 && this.abortLatch) {
      return;
    }
    Logger.w(TAG, 'forceStopWorking: ' + reason);
    this.abortLatch = true;
    this.working = false;
    this.triggeredAt = 0;
    this.sessionBusySeen = false;
    this.emit('status');
  }

  // 本机中止时立刻给未完结 assistant 打上终态，避免打字机/思考条继续认「进行中」
  private sealOpenAssistantsLocally(finish: string): void {
    let changed = false;
    const ids = Array.from(this.messages.keys());
    for (let i = 0; i < ids.length; i++) {
      const m = this.messages.get(ids[i]);
      if (m === undefined || m.role !== 'assistant') {
        continue;
      }
      if (m.error.length > 0 || this.isTerminalFinish(m.finish)) {
        continue;
      }
      m.finish = finish;
      changed = true;
    }
    if (changed) {
      this.lastFp = '';
      this.emit('messages');
    }
  }

  private isInFlight(payloads: MessagesPayload[]): boolean {
    let latestAssistant: MessageInfo | null = null;
    for (let i = 0; i < payloads.length; i++) {
      const m = payloads[i].message;
      if (m.role !== 'assistant') {
        continue;
      }
      if (this.triggeredAt > 0 && m.created > 0 && m.created <= this.sendBaseCreated) {
        // 本机发送前已回显的消息（以发送前服务端最大 created 为基线，
        // 服务端自身时钟一致，不跨设备比较），避免被历史 finish 冒然判停
        continue;
      }
      if (latestAssistant === null || m.created > latestAssistant.created) {
        latestAssistant = m;
      }
    }
    if (latestAssistant === null) {
      // 尚无本次产出的 assistant 消息：仅当本机刚发送过才视为工作中（等待产出）
      return this.triggeredAt > 0;
    }
    const open = latestAssistant.error.length === 0 && !this.isTerminalFinish(latestAssistant.finish);
    if (!open) {
      return false;
    }
    // 本机本轮已发送：未完结 assistant = 思考中
    if (this.triggeredAt > 0) {
      return true;
    }
    // 仅打开/跟随会话：finish 缺失很常见，必须以服务端 status 为准
    const sid = this.currentSessionId;
    if (sid.length === 0) {
      return false;
    }
    const st = this.sessionStatus[sid];
    return st === 'busy' || st === 'retry';
  }

  stopStream(): void {
    this.stopPolling();
  }

  stopPolling(): void {
    if (this.pollTimer >= 0) {
      clearTimeout(this.pollTimer);
      this.pollTimer = -1;
    }
  }

  // ---- 真流式事件桥 ----
  private startEventBridge(): void {
    if (this.api === null || this.eventBridge !== null) {
      return;
    }
    const bridge = new EventStreamBridge();
    bridge.onTextDelta = (sid: string, mid: string, tid: string, delta: string) => {
      this.applyTextDelta(sid, mid, tid, delta);
    };
    bridge.onReasoningDelta = (sid: string, mid: string, rid: string, delta: string) => {
      this.applyTextDelta(sid, mid, rid, delta);
    };
    bridge.onMessageUpdated = (sid: string, _mid: string) => {
      this.refreshFromSse(sid);
    };
    bridge.onSessionIdle = (sid: string) => {
      this.finishFromSse(sid);
    };
    bridge.onSessionError = (sid: string) => {
      this.finishFromSse(sid);
    };
    bridge.onUnsupported = () => {
      this.sseActive = false;
    };
    this.eventBridge = bridge;
    bridge.start(this.api.getBaseUrl(), this.api.getAuthHeader());
    Logger.i(TAG, 'event bridge started');
  }

  private stopEventBridge(): void {
    if (this.eventBridge !== null) {
      this.eventBridge.stop();
      this.eventBridge = null;
    }
    this.sseActive = false;
    this.sseTextBuffer.clear();
    this.sseReasoningBuffer.clear();
  }

  // 文本/推理增量直接累计到 part 并立即刷新 UI（真流式）
  private applyTextDelta(sid: string, mid: string, partKey: string, delta: string): void {
    if (this.api === null || sid !== this.currentSessionId) {
      return;
    }
    this.sseActive = true;
    this.lastSseAt = Date.now();
    const isReasoning = partKey.indexOf('reasoning') === 0;
    const buf = isReasoning ? this.sseReasoningBuffer : this.sseTextBuffer;
    let acc = buf.get(partKey);
    if (acc === undefined) {
      acc = '';
    }
    acc += delta;
    buf.set(partKey, acc);
    // 找到对应 part 增量追加；找不到先拉全量（SSE 可能比 REST 更早到达）
    let found = false;
    const parts = this.parts.get(mid);
    if (parts !== undefined) {
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        if (p.type === 'text' && (p.id === partKey || this.matchPart(p, partKey, isReasoning))) {
          p.text = acc;
          found = true;
          break;
        }
      }
    }
    if (!found) {
      this.pullSessionOnce(sid);
    } else {
      this.lastFp = '';
      this.emit('messages');
      this.emit('status');
    }
  }

  // partKey 可能不等于 part.id（SSE 的 textID），尝试按 type 顺序匹配当前消息首个 text part
  private matchPart(p: Part, partKey: string, isReasoning: boolean): boolean {
    if (isReasoning) {
      return p.type === 'reasoning';
    }
    return p.type === 'text';
  }

  // 事件桥通知消息更新：SSE 可信时立即拉一次全量替代依赖轮询间隔
  private refreshFromSse(sid: string): void {
    if (this.api === null || sid !== this.currentSessionId) {
      return;
    }
    this.sseActive = true;
    this.lastSseAt = Date.now();
    const now = Date.now();
    if (now - this.lastSseRefreshAt < 250) {
      return;
    }
    this.lastSseRefreshAt = now;
    this.pullSessionOnce(sid);
  }

  // session.idle / session.error：任务结束，立即结算 working 并停止打字机
  private finishFromSse(sid: string): void {
    if (this.api === null || sid !== this.currentSessionId) {
      return;
    }
    this.sseActive = true;
    this.lastSseAt = Date.now();
    // 不等消息 finish 落库：PC 已停就立刻清 working，避免打字机/转圈卡住
    this.forceStopWorking('sse session.idle/error');
    this.pullSessionOnce(sid);
  }

  // 拉一次当前会话全量并结算 working（事件桥与高频轮询共用）
  private async pullSessionOnce(sid: string): Promise<void> {
    if (this.api === null || !this.connected) {
      return;
    }
    try {
      const payloads = await this.fetchWindow(sid, 30);
      if (this.currentSessionId !== sid) {
        return;
      }
      this.applyPayloads(payloads);
      this.detectWorking(payloads);
    } catch (e) {
      Logger.w(TAG, 'pullSessionOnce failed');
    }
  }

  async connect(url: string, password: string): Promise<void> {
    this.lastError = '';
    const base = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    const api = new ApiClient(base, password);
    try {
      const version = await api.health();
      this.server.url = base;
      this.server.password = password;
      this.api = api;
      this.version = version;
      this.connected = true;
      this.currentProviderID = '';
      this.currentModelID = '';
      await this.loadProjects();
      this.lastFp = '';
      this.startPolling();
      this.startEventBridge();
      await this.refreshSessions();
      this.refreshProviders();
      this.emit('connected');
      this.emit('sessions');
    } catch (e) {
      this.connected = false;
      this.api = null;
      this.lastError = e instanceof Error ? e.message : 'connect failed';
      throw new Error(this.lastError);
    }
  }

  // silent re-connect using saved config, used at app start
  async autoConnect(): Promise<void> {
    if (this.hasSaved && this.server.url.length > 0) {
      try {
        await this.connect(this.server.url, this.server.password);
      } catch (e) {
        this.connected = false;
        this.lastError = e instanceof Error ? e.message : 'auto connect failed';
        this.emit('status');
      }
    }
  }

  // 断连/启动失败时，把上次落盘的会话与消息回填，弱网离线可读
  loadCacheFromDisk(): void {
    if (this.cacheCtx === null || this.server.url.length === 0) {
      return;
    }
    const c = CacheStore.load('app', this.cacheCtx, this.server.url);
    if (c === null) {
      return;
    }
    this.sessions = c.sessions;
    this.currentSessionId = c.currentSid;
    this.currentSessionTitle = '';
    this.syncSessionTitle();
    this.messages.clear();
    this.parts.clear();
    this.historyCursor = '';
    this.hasMoreHistory = true;
    this.loadingMoreHistory = false;
    this.extraMessages.clear();
    this.extraParts.clear();
    for (let i = 0; i < c.messages.length; i++) {
      this.messages.set(c.messages[i].id, c.messages[i]);
    }
    c.parts.forEach((pArr: Part[], id: string) => {
      this.parts.set(id, pArr);
    });
    this.working = false;
    this.emit('sessions');
    this.emit('messages');
    this.emit('status');
    Logger.i(TAG, 'cache loaded: sessions=' + c.sessions.length.toString() +
      ' messages=' + c.messages.length.toString());
  }

  disconnect(): void {
    this.stopPolling();
    this.stopEventBridge();
    this.api = null;
    this.connected = false;
    this.lastFp = '';
    this.triggeredAt = 0;
    this.sendBaseCreated = 0;
    this.sessionBusySeen = false;
    this.abortLatch = false;
    this.pollFailCount = 0;
    this.sessions = [];
    this.currentSessionId = '';
    this.messages.clear();
    this.parts.clear();
    this.working = false;
    this.historyCursor = '';
    this.hasMoreHistory = true;
    this.loadingMoreHistory = false;
    this.extraMessages.clear();
    this.extraParts.clear();
    this.emit('sessions');
    this.emit('status');
  }

  private async loadProjects(): Promise<void> {
    if (this.api === null) {
      return;
    }
    try {
      this.projects = await this.api.listProjects();
      if (this.projects.length > 0) {
        this.currentProject = this.projects[0];
        const dir = this.currentProject.directory;
        if (dir.length > 0) {
          this.api.directory = dir;
        }
      }
    } catch (e) {
      Logger.w(TAG, 'loadProjects failed');
    }
  }

  async refreshSessions(): Promise<void> {
    if (this.api === null) {
      return;
    }
    try {
      const s = await this.api.listSessions();
      s.sort((a: SessionInfo, b: SessionInfo) => b.updated - a.updated);
      this.sessions = s;
      if (this.currentSessionId.length > 0) {
        this.syncSessionTitle();
      }
      this.emit('sessions');
      await this.followRemoteFocus();
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : 'list sessions failed';
    }
  }

  // 在会话列表中找 ocFocus 最新的会话；若比本地更新且不是当前会话则跟随
  private async followRemoteFocus(): Promise<void> {
    if (this.followingRemoteFocus || this.api === null) {
      return;
    }
    let bestId = '';
    let bestAt = 0;
    let bestSource = '';
    for (let i = 0; i < this.sessions.length; i++) {
      const s = this.sessions[i];
      if (s.ocFocus > bestAt) {
        bestAt = s.ocFocus;
        bestId = s.id;
        bestSource = s.ocFocusSource;
      }
    }
    if (bestId.length === 0 || bestAt <= this.appliedFocusAt) {
      return;
    }
    // 仅忽略本机刚广播的回声；电脑/browser 来的焦点始终跟随
    if (bestSource === 'phone' && Date.now() < this.ignoreRemoteFocusUntil) {
      this.appliedFocusAt = bestAt;
      return;
    }
    if (bestId === this.currentSessionId) {
      this.appliedFocusAt = bestAt;
      return;
    }
    Logger.i(TAG, 'follow remote focus -> ' + bestId + ' src=' + bestSource + ' at=' + bestAt.toString());
    this.followingRemoteFocus = true;
    this.appliedFocusAt = bestAt;
    try {
      await this.openSession(bestId, false);
      this.emit('focus');
    } finally {
      this.followingRemoteFocus = false;
    }
  }

  private publishFocus(sessionID: string): void {
    if (this.api === null || sessionID.length === 0) {
      return;
    }
    const at = Date.now();
    this.appliedFocusAt = at;
    this.ignoreRemoteFocusUntil = at + 3000;
    this.api.publishSessionFocus(sessionID, 'phone', at).catch((e: Error) => {
      Logger.w(TAG, 'publishSessionFocus failed: ' + e.message);
    });
  }

  // 拉取各会话运行状态（busy/idle/retry），供会话列表展示进行中标记
  async refreshSessionStatus(): Promise<void> {
    if (this.api === null) {
      return;
    }
    try {
      this.sessionStatus = await this.api.listSessionStatus();
      const st = this.sessionStatus[this.currentSessionId];
      if (st === 'busy' || st === 'retry') {
        this.sessionBusySeen = true;
      }
      this.emit('sessions');
      // SSE 跳过 REST 时仍靠 status 把 working 拉回；消息 finish 可能滞后
      if (this.working && this.shouldForceStopFromStatus()) {
        this.forceStopWorking('poll session status');
      }
    } catch (e) {
      // 旧版服务或瞬时失败：保持上次状态即可
      Logger.w(TAG, 'listSessionStatus failed');
    }
  }

  // 从会话列表反查当前会话标题，供顶栏/标题栏展示
  syncSessionTitle(): void {
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === this.currentSessionId && this.sessions[i].title.length > 0) {
        if (this.currentSessionTitle !== this.sessions[i].title) {
          this.currentSessionTitle = this.sessions[i].title;
          this.emit('title');
        }
        return;
      }
    }
  }

  getSessionTitle(): string {
    this.syncSessionTitle();
    return this.currentSessionTitle;
  }

  getSessions(): SessionInfo[] {
    return this.sessions;
  }

  async createSession(): Promise<SessionInfo | null> {
    if (this.api === null) {
      return null;
    }
    try {
      const s = await this.api.createSession('New session');
      // 通知 PC 端 TUI 切换到新建会话（失败记录日志，不影响手机端使用）
      this.api.selectSession(s.id).catch((e: Error) => {
        Logger.w(TAG, 'selectSession(new) failed: ' + e.message);
      });
      this.publishFocus(s.id);
      await this.refreshSessions();
      return s;
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : 'create failed';
      return null;
    }
  }

  async deleteSession(sessionID: string): Promise<boolean> {
    if (this.api === null) {
      return false;
    }
    try {
      await this.api.deleteSession(sessionID);
      if (this.currentSessionId === sessionID) {
        this.currentSessionId = '';
        this.currentSessionTitle = '';
      }
      await this.refreshSessions();
      return true;
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : 'delete failed';
      return false;
    }
  }

  // 启动时优先复用带焦点标记的会话，其次最近更新；没有会话才新建
  async resolveStartupSession(): Promise<SessionInfo | null> {
    if (this.api === null) {
      return null;
    }
    try {
      await this.refreshSessions();
      if (this.sessions.length === 0) {
        return await this.createSession();
      }
      let best: SessionInfo = this.sessions[0];
      for (let i = 0; i < this.sessions.length; i++) {
        const s = this.sessions[i];
        if (s.ocFocus > best.ocFocus) {
          best = s;
        }
      }
      if (best.ocFocus > 0) {
        this.appliedFocusAt = best.ocFocus;
        return best;
      }
      // refreshSessions 已按 updated 降序
      return this.sessions[0];
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : 'resolve session failed';
      return null;
    }
  }

  // publishFocus=true：本机主动切换，广播给电脑；false：跟随远程，不再回写焦点
  async openSession(sessionID: string, publishFocus: boolean = true): Promise<void> {
    this.currentSessionId = sessionID;
    this.triggeredAt = 0;
    this.sendBaseCreated = 0;
    this.sessionBusySeen = false;
    this.currentSessionTitle = '';
    this.syncSessionTitle();
    this.messages.clear();
    this.parts.clear();
    this.lastFp = '';
    this.sseTextBuffer.clear();
    this.sseReasoningBuffer.clear();
    this.historyCursor = '';
    this.hasMoreHistory = true;
    this.loadingMoreHistory = false;
    this.extraMessages.clear();
    this.extraParts.clear();
    this.approvals = [];
    this.questions = [];
    this.diffs = [];
    this.todos = [];
    this.reviewDirty = false;
    this.working = false;
    this.abortLatch = false;
    this.emit('status');
    this.emit('approvals');
    this.emit('questions');
    this.emit('review');
    this.emit('messages');
    if (this.api === null) {
      return;
    }
    // 通知 PC 端 TUI 跟随切换到同一会话；失败记录日志便于排查
    this.api.selectSession(sessionID).catch((e: Error) => {
      Logger.w(TAG, 'selectSession failed: ' + e.message);
    });
    if (publishFocus) {
      this.publishFocus(sessionID);
    }
    this.startPolling();
    // 评审/状态不阻塞首屏：先拉消息进聊天，后台再补齐
    this.loadReview().catch((e: Error) => {
      Logger.w(TAG, 'loadReview failed: ' + e.message);
    });
    this.refreshSessionStatus().catch((e: Error) => {
      Logger.w(TAG, 'refreshSessionStatus failed: ' + e.message);
    });
    try {
      const payloads = await this.fetchWindow(sessionID, 40);
      // 快速连切会话时丢弃过期结果，避免旧会话消息覆盖新会话
      if (this.currentSessionId !== sessionID) {
        return;
      }
      this.applyPayloads(payloads);
      this.refreshApprovalsAndQuestions().catch((e: Error) => {
        Logger.w(TAG, 'refresh AQ failed: ' + e.message);
      });
      this.detectWorking(payloads);
    } catch (e) {
      if (this.currentSessionId !== sessionID) {
        return;
      }
      this.lastError = e instanceof Error ? e.message : 'load messages failed';
      this.emit('status');
    }
  }

  async loadReview(): Promise<void> {
    const sid = this.currentSessionId;
    if (sid.length === 0 || this.api === null) {
      return;
    }
    await Promise.all([
      this.refreshDiffs(),
      this.refreshTodos()
    ]);
    this.reviewDirty = false;
    this.emit('review');
  }

  async refreshDiffs(): Promise<void> {
    if (this.api === null || this.currentSessionId.length === 0) {
      return;
    }
    try {
      this.diffs = await this.api.listDiffs(this.currentSessionId);
      this.emit('review');
    } catch (e) {
      Logger.w(TAG, 'listDiffs failed');
    }
  }

  async refreshTodos(): Promise<void> {
    if (this.api === null || this.currentSessionId.length === 0) {
      return;
    }
    try {
      this.todos = await this.api.listTodos(this.currentSessionId);
      this.emit('review');
    } catch (e) {
      Logger.w(TAG, 'listTodos failed');
    }
  }

  getDiffs(): FileDiff[] {
    return this.diffs;
  }

  getTodos(): TodoItem[] {
    return this.todos;
  }

  getApprovals(): Approval[] {
    return this.approvals;
  }

  getQuestions(): QuestionRequest[] {
    return this.questions;
  }

  async refreshApprovalsAndQuestions(): Promise<void> {
    if (this.api === null) {
      return;
    }
    try {
      const perms = await this.api.listPermissions();
      const nextApprovals: Approval[] = [];
      for (let i = 0; i < perms.length; i++) {
        const p = perms[i];
        const a = new Approval();
        a.requestID = p.id;
        a.sessionID = p.sessionID;
        a.permission = p.permission;
        a.patterns = p.patterns;
        a.apiVersion = p.apiVersion;
        nextApprovals.push(a);
      }
      let approvalsChanged = nextApprovals.length !== this.approvals.length;
      if (!approvalsChanged) {
        for (let i = 0; i < nextApprovals.length; i++) {
          if (nextApprovals[i].requestID !== this.approvals[i].requestID) {
            approvalsChanged = true;
            break;
          }
        }
      }
      let firstNew = true;
      if (approvalsChanged && this.notifyEnabled && this.background) {
        // 新到达的审批请求才提醒，避免轮询每次重复通知
        for (let i = 0; i < nextApprovals.length; i++) {
          let existed = false;
          for (let j = 0; j < this.approvals.length; j++) {
            if (nextApprovals[i].requestID === this.approvals[j].requestID) {
              existed = true;
              break;
            }
          }
          if (!existed) {
            if (firstNew) {
              Notifier.notifyApproval(
                this.currentSessionTitle.length > 0 ? this.currentSessionTitle : 'OpenCode',
                '\u6709\u65B0\u7684\u5DE5\u5177\u6743\u9650\u8BF7\u6C42\u7B49\u5F85\u786E\u8BA4');
              firstNew = false;
            }
            break;
          }
        }
      }
      if (approvalsChanged) {
        this.approvals = nextApprovals;
        this.emit('approvals');
        if (nextApprovals.length > 0 && !this.working) {
          this.working = true;
          this.emit('status');
        }
        // 权限若属于其他会话，自动切过去，避免手机停在旧会话看不见弹窗
        if (nextApprovals.length > 0) {
          const targetSid = nextApprovals[0].sessionID;
          if (targetSid.length > 0 && targetSid !== this.currentSessionId && !this.followingRemoteFocus) {
            Logger.i(TAG, 'permission forces session -> ' + targetSid);
            this.followingRemoteFocus = true;
            try {
              await this.openSession(targetSid, false);
              this.emit('focus');
            } finally {
              this.followingRemoteFocus = false;
            }
          }
        }
      }
    } catch (e) {
      Logger.w(TAG, 'listPermissions failed');
    }
    try {
      const qs = await this.api.listQuestions();
      const nextQ: QuestionRequest[] = [];
      for (let i = 0; i < qs.length; i++) {
        nextQ.push(qs[i]);
      }
      let qChanged = nextQ.length !== this.questions.length;
      if (!qChanged) {
        for (let i = 0; i < nextQ.length; i++) {
          if (nextQ[i].id !== this.questions[i].id) {
            qChanged = true;
            break;
          }
        }
      }
      if (qChanged) {
        if (this.notifyEnabled && this.background) {
          for (let i = 0; i < nextQ.length; i++) {
            let existed = false;
            for (let j = 0; j < this.questions.length; j++) {
              if (nextQ[i].id === this.questions[j].id) {
                existed = true;
                break;
              }
            }
            if (!existed) {
              Notifier.notifyQuestion(
                this.currentSessionTitle.length > 0 ? this.currentSessionTitle : 'OpenCode',
                '\u6709\u65B0\u7684\u95EE\u9898\u7B49\u5F85\u56DE\u7B54');
              break;
            }
          }
        }
        this.questions = nextQ;
        this.emit('questions');
        if (nextQ.length > 0) {
          const targetSid = nextQ[0].sessionID;
          if (targetSid.length > 0 && targetSid !== this.currentSessionId && !this.followingRemoteFocus) {
            this.followingRemoteFocus = true;
            try {
              await this.openSession(targetSid, false);
              this.emit('focus');
            } finally {
              this.followingRemoteFocus = false;
            }
          }
        }
      }
    } catch (e) {
      Logger.w(TAG, 'listQuestions failed');
    }
  }

  getProviders(): ProviderInfo[] {
    return this.providers;
  }

  async refreshProviders(): Promise<void> {
    if (this.api === null) {
      return;
    }
    try {
      this.providers = await this.api.listProviders();
      this.emit('providers');
    } catch (e) {
      Logger.w(TAG, 'listProviders failed');
    }
  }

  // returns display label, e.g. 'anthropic·claude-3-5-sonnet'
  currentModelLabel(): string {
    if (this.currentProviderID.length === 0 || this.currentModelID.length === 0) {
      return '模型';
    }
    return '模型: ' + this.modelDisplayName(this.currentProviderID, this.currentModelID);
  }

  // 模型 id → 服务端显示名；取不到则用 id 的简名（去 provider 前缀）
  modelDisplayName(providerID: string, modelID: string): string {
    if (modelID.length === 0) {
      return '';
    }
    if (providerID.length > 0) {
      for (let i = 0; i < this.providers.length; i++) {
        const p = this.providers[i];
        if (p.id === providerID) {
          for (let j = 0; j < p.models.length; j++) {
            if (p.models[j].id === modelID) {
              return p.models[j].name;
            }
          }
          break;
        }
      }
    }
    // 兜底：尝试按 modelID 前缀反查 provider
    const slash = modelID.indexOf('/');
    if (slash > 0) {
      const pid = modelID.substring(0, slash);
      const short = modelID.substring(slash + 1);
      for (let i = 0; i < this.providers.length; i++) {
        if (this.providers[i].id === pid) {
          for (let j = 0; j < this.providers[i].models.length; j++) {
            if (this.providers[i].models[j].id === short) {
              return this.providers[i].models[j].name;
            }
          }
          break;
        }
      }
      return short;
    }
    return modelID;
  }

  setModel(providerID: string, modelID: string): void {
    this.currentProviderID = providerID;
    this.currentModelID = modelID;
    this.emit('model');
    // 同步到服务端会话，让 PC 版 TUI 立即感知（新版 server 端点；旧版 404 忽略）
    const sid = this.currentSessionId;
    if (sid.length > 0 && this.api !== null) {
      this.api.switchSessionModel(sid, providerID, modelID).catch((e: Error) => {
        Logger.w(TAG, 'switchSessionModel ignored ' + e.message);
      });
    }
  }

  setAgent(agent: string): void {
    if (this.currentAgent === agent) {
      return;
    }
    this.currentAgent = agent;
    this.emit('model');
    const sid = this.currentSessionId;
    if (sid.length > 0 && this.api !== null) {
      this.api.switchSessionAgent(sid, agent).catch((e: Error) => {
        Logger.w(TAG, 'switchSessionAgent ignored ' + e.message);
      });
    }
  }

  async replyApproval(approvalID: string, reply: string): Promise<void> {
    if (this.api === null) {
      return;
    }
    let sid = this.currentSessionId;
    let apiVersion = 1;
    let removed: Approval | null = null;
    const idx = this.approvals.findIndex((a: Approval) => a.requestID === approvalID);
    if (idx >= 0) {
      removed = this.approvals[idx];
      if (removed.sessionID.length > 0) {
        sid = removed.sessionID;
      }
      apiVersion = removed.apiVersion;
      this.approvals.splice(idx, 1);
      this.emit('approvals');
    }
    try {
      await this.api.replyPermission(sid, approvalID, reply, apiVersion);
      this.abortLatch = false;
      this.working = true;
      this.triggeredAt = Date.now();
      this.sendBaseCreated = this.maxSeenCreated();
      this.sessionBusySeen = false;
      this.lastActivityAt = Date.now();
      this.emit('status');
      this.pollOnce();
    } catch (e) {
      const msg = e instanceof Error ? e.message : '权限回复失败';
      Logger.w(TAG, 'replyPermission failed: ' + msg);
      // 失败时恢复卡片，避免用户以为已授权而 PC 仍卡住
      if (removed !== null) {
        this.approvals.unshift(removed);
        this.emit('approvals');
      } else {
        this.refreshApprovalsAndQuestions();
      }
      this.lastError = '权限操作失败，请重试';
      this.emit('status');
      Toast.show('权限操作失败，请重试');
    }
  }

  async replyQuestion(questionID: string, answers: string[][]): Promise<void> {
    if (this.api === null) {
      return;
    }
    let removed: QuestionRequest | null = null;
    const idx = this.questions.findIndex((q: QuestionRequest) => q.id === questionID);
    if (idx >= 0) {
      removed = this.questions[idx];
      this.questions.splice(idx, 1);
      this.emit('questions');
    }
    try {
      await this.api.replyQuestion(questionID, answers);
      this.abortLatch = false;
      this.working = true;
      this.triggeredAt = Date.now();
      this.sendBaseCreated = this.maxSeenCreated();
      this.sessionBusySeen = false;
      this.lastActivityAt = Date.now();
      this.emit('status');
      this.startPolling();
    } catch (e) {
      Logger.w(TAG, 'replyQuestion failed');
      if (removed !== null) {
        this.questions.unshift(removed);
        this.emit('questions');
      } else {
        this.refreshApprovalsAndQuestions();
      }
      Toast.show('回答提交失败，请重试');
    }
  }

  // early model send: pass current model when a message is sent while streaming stopped
  currentSessionMessagesCount(): number {
    return this.messages.size;
  }

  getMessages(): MessageInfo[] {
    const out: MessageInfo[] = [];
    this.messages.forEach((m: MessageInfo) => {
      out.push(m);
    });
    out.sort((a: MessageInfo, b: MessageInfo) => a.created - b.created);
    return out;
  }

  getHasMoreHistory(): boolean {
    return this.hasMoreHistory;
  }

  isLoadingMoreHistory(): boolean {
    return this.loadingMoreHistory;
  }

  // 拉取最新窗口并记录分页游标；游标只在首页窗口首次拉取时记录，
  // 加载了更早页后由 loadMoreHistory 维护，避免窗口前移覆盖游标
  private async fetchWindow(sid: string, limit: number): Promise<MessagesPayload[]> {
    if (this.api === null) {
      return [];
    }
    const page = await this.api.listMessagesCursor(sid, limit);
    if (this.currentSessionId !== sid) {
      return [];
    }
    if (this.historyCursor.length === 0) {
      this.historyCursor = page.next;
      if (page.next.length === 0 && this.hasMoreHistory) {
        this.hasMoreHistory = false;
        this.emit('messages');
      }
    }
    return page.payloads;
  }

  // 加载当前会话更早历史（before 游标分页，每页 30 条）。
  // 追加到消息表立即显示，并存入 extra 副本供后续窗口轮询合并保留。
  async loadMoreHistory(): Promise<void> {
    const sid = this.currentSessionId;
    if (this.api === null || !this.connected || sid.length === 0) {
      return;
    }
    if (this.loadingMoreHistory || !this.hasMoreHistory || this.historyCursor.length === 0) {
      return;
    }
    this.loadingMoreHistory = true;
    this.emit('messages');
    try {
      const page = await this.api.listMessagesCursor(sid, 30, this.historyCursor);
      if (this.currentSessionId !== sid) {
        return;
      }
      let added = false;
      for (let i = 0; i < page.payloads.length; i++) {
        const p = page.payloads[i];
        if (p.message.id.length === 0) {
          continue;
        }
        if (this.messages.has(p.message.id) || this.extraMessages.has(p.message.id)) {
          continue;
        }
        this.extraMessages.set(p.message.id, p.message);
        this.extraParts.set(p.message.id, p.parts);
        this.messages.set(p.message.id, p.message);
        this.parts.set(p.message.id, p.parts);
        added = true;
      }
      this.historyCursor = page.next;
      if (page.next.length === 0) {
        this.hasMoreHistory = false;
      }
      if (added) {
        this.emit('messages');
      }
    } catch (e) {
      Logger.w(TAG, 'loadMoreHistory failed');
    } finally {
      if (this.currentSessionId === sid) {
        this.loadingMoreHistory = false;
        this.emit('messages');
      }
    }
  }

  // 当前会话已回显消息的最大 created（服务端时钟）。
  // 用作发送时的基线：同源时钟，不受手机/PC 时钟偏差影响。
  private maxSeenCreated(): number {
    let max = 0;
    this.messages.forEach((m: MessageInfo) => {
      // 排除本地乐观消息：其 created 是手机时钟，混入会污染服务端基线
      if (m.id.indexOf('local_') === 0 || m.created <= max) {
        return;
      }
      max = m.created;
    });
    return max;
  }

  getParts(messageID: string): Part[] {
    const p = this.parts.get(messageID);
    return p === undefined ? [] : p;
  }

  // 从目标消息开始截断并重发（删除该消息及其后所有消息，再重发文本）
  async truncateAndResend(messageID: string): Promise<void> {
    const sid = this.currentSessionId;
    if (sid.length === 0 || this.api === null) {
      return;
    }
    const all = this.getMessages();
    let idx = -1;
    for (let i = 0; i < all.length; i++) {
      if (all[i].id === messageID) {
        idx = i;
        break;
      }
    }
    if (idx < 0) {
      return;
    }
    let text = '';
    const parts = this.getParts(messageID);
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (p.type === 'text') {
        text = p.text;
        break;
      }
    }
    if (text.trim().length === 0) {
      this.lastError = '无法重发：该消息没有文本内容';
      this.emit('status');
      return;
    }
    // 收集目标消息及之后所有服务端消息 id（服务端 removeMessage 不级联，需逐条删）
    const toDelete: string[] = [];
    for (let i = idx; i < all.length; i++) {
      const m = all[i];
      if (m.id.indexOf('local_') === 0) {
        continue;
      }
      toDelete.push(m.id);
    }
    for (let i = 0; i < toDelete.length; i++) {
      const mid = toDelete[i];
      try {
        await this.api.deleteMessage(sid, mid);
      } catch (e) {
        Logger.w(TAG, 'truncate delete fail ' + mid + ' ' + (e instanceof Error ? e.message : ''));
      }
      this.messages.delete(mid);
      this.parts.delete(mid);
      // 分页历史副本同步清理，避免被后续窗口轮询合并"复活"
      this.extraMessages.delete(mid);
      this.extraParts.delete(mid);
    }
    this.emit('messages');
    await this.sendMessage(text);
  }

  async sendMessage(text: string, attachments?: AttachmentInput[] | null): Promise<void> {
    const sid = this.currentSessionId;
    if (sid.length === 0 || this.api === null) {
      this.lastError = '未连接服务器或没有会话';
      this.emit('status');
      return;
    }
    this.lastError = '';
    this.abortLatch = false;
    this.working = true;
    this.triggeredAt = Date.now();
    this.sendBaseCreated = this.maxSeenCreated();
    this.sessionBusySeen = false;
    this.lastActivityAt = Date.now();
    // 新轮对话开始：清空上一轮 SSE 增量缓冲
    this.sseTextBuffer.clear();
    this.sseReasoningBuffer.clear();
    this.startPolling();

    // 乐观更新：立刻在 UI 显示用户消息
    const localId = 'local_' + this.triggeredAt;
    const localMsg = new MessageInfo();
    localMsg.id = localId;
    localMsg.sessionID = sid;
    localMsg.role = 'user';
    localMsg.created = this.triggeredAt;
    const localParts: Part[] = [];
    const localPart = new Part();
    localPart.id = localId + '_p';
    localPart.type = 'text';
    localPart.text = text;
    localParts.push(localPart);
    if (attachments !== undefined && attachments !== null) {
      for (let i = 0; i < attachments.length; i++) {
        const a = attachments[i];
        const ap = new Part();
        ap.id = localId + '_a' + i.toString();
        ap.type = 'file';
        ap.filePath = a.filename;
        ap.text = a.isImage ? '🖼 ' + a.filename : '📎 ' + a.filename;
        localParts.push(ap);
      }
    }
    this.messages.set(localId, localMsg);
    this.parts.set(localId, localParts);
    this.lastFp = '';
    this.emit('messages');
    this.emit('status');

    try {
      await this.api.sendMessage(sid, text, this.currentProviderID, this.currentModelID, attachments,
        this.currentAgent);
      // 立即拉一次，尽快替换本地临时消息
      const payloads = await this.fetchWindow(sid, 40);
      this.applyPayloads(payloads);
      this.detectWorking(payloads);
    } catch (e) {
      this.lastError = e instanceof Error ? e.message : 'send failed';
      this.working = false;
      this.emit('status');
      Logger.w(TAG, 'sendMessage failed ' + this.lastError);
    }
  }

  async abort(): Promise<void> {
    const sid = this.currentSessionId;
    if (sid.length === 0 || this.api === null) {
      return;
    }
    // 先本地封口并拉闸，再请求服务端，避免轮询把「思考中」刷回来
    this.sealOpenAssistantsLocally('aborted');
    this.forceStopWorking('local abort');
    try {
      await this.api.abort(sid);
    } catch (e) {
      Logger.w(TAG, 'abort failed');
    }
    // 再拉一次状态，仍受 abortLatch 保护
    try {
      const payloads = await this.fetchWindow(sid, 40);
      this.applyPayloads(payloads);
      this.sealOpenAssistantsLocally('aborted');
      this.detectWorking(payloads);
    } catch (e) {
      Logger.w(TAG, 'abort refresh failed');
    }
  }

  // ---- persistence（密码经 SecretBox 轻量混淆落盘；正式安全存储后续迁 HUKS）----
  private static PREF_NAME = 'oc_prefs';
  private static KEY_URL = 'url';
  private static KEY_PASSWORD = 'pw';
  private static KEY_NOTIFY = 'notify';
  private static KEY_DARKMODE = 'darkmode';

  // 深色模式偏好：'auto' 跟随系统 | 'light' 仅亮色 | 'dark' 仅深色
  darkModePref: string = 'auto';

  setDarkMode(pref: string, systemDark: boolean): void {
    this.darkModePref = pref;
    const dark = pref === 'dark' || (pref === 'auto' && systemDark);
    Theme.applyDark(dark);
    // 必须先写 Theme，再通知 UI：组件依赖 darkMode 重绘时读到的已是新色板
    AppStorage.setOrCreate('darkMode', dark);
    WindowChrome.applyBarColors();
    this.syncAppColorMode();
    this.persistRef();
  }

  // 首启/系统色切换时重新结算配色
  resolveDarkMode(systemDark: boolean): void {
    const dark = this.darkModePref === 'dark' || (this.darkModePref === 'auto' && systemDark);
    Theme.applyDark(dark);
    AppStorage.setOrCreate('darkMode', dark);
    WindowChrome.applyBarColors();
  }

  // 同步应用级 colorMode，让系统控件（Toggle 等）跟随；仅在用户改偏好时调用，避免与 onConfigurationUpdate 互递归
  syncAppColorMode(): void {
    if (this.cacheCtx === null) {
      return;
    }
    try {
      const appCtx = (this.cacheCtx as common.UIAbilityContext).getApplicationContext();
      if (this.darkModePref === 'dark') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else if (this.darkModePref === 'light') {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else {
        appCtx.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (e) {
      Logger.w(TAG, 'syncAppColorMode failed');
    }
  }

  persistRef(): void {
    try {
      // 组件上下文不一定可得（AppStore 是普通类），优先复用 Index 启动时挂的上下文
      if (this.cacheCtx !== null) {
        this.persist(this.cacheCtx);
        return;
      }
      const ctx = getContext(this) as common.Context;
      this.persist(ctx);
    } catch (e) {
      Logger.w(TAG, 'persistRef failed');
    }
  }

  persist(ctx: common.Context): void {
    try {
      const pref = preferences.getPreferencesSync(ctx, { name: AppStore.PREF_NAME });
      pref.putSync(AppStore.KEY_URL, this.server.url);
      pref.putSync(AppStore.KEY_PASSWORD, SecretBox.seal(this.server.password));
      pref.putSync(AppStore.KEY_NOTIFY, this.notifyEnabled);
      pref.putSync(AppStore.KEY_DARKMODE, this.darkModePref);
      pref.flush();
      this.hasSaved = true;
    } catch (e) {
      Logger.w(TAG, 'persist failed');
    }
  }

  loadSaved(ctx: common.Context): void {
    try {
      const pref = preferences.getPreferencesSync(ctx, { name: AppStore.PREF_NAME });
      this.server.url = pref.getSync(AppStore.KEY_URL, '') as string;
      const rawPw = pref.getSync(AppStore.KEY_PASSWORD, '') as string;
      this.server.password = SecretBox.open(rawPw);
      this.notifyEnabled = pref.getSync(AppStore.KEY_NOTIFY, true) as boolean;
      const dm = pref.getSync(AppStore.KEY_DARKMODE, 'auto') as string;
      this.darkModePref = dm === 'light' || dm === 'dark' ? dm : 'auto';
      this.hasSaved = this.server.url.length > 0;
    } catch (e) {
      this.hasSaved = false;
    }
  }

  clearSaved(ctx: common.Context): void {
    try {
      const pref = preferences.getPreferencesSync(ctx, { name: AppStore.PREF_NAME });
      pref.deleteSync(AppStore.KEY_URL);
      pref.deleteSync(AppStore.KEY_PASSWORD);
      pref.flush();
    } catch (e) {
      Logger.w(TAG, 'clearSaved pref failed');
    }
    this.server.url = '';
    this.server.password = '';
    this.hasSaved = false;
    this.disconnect();
  }
}

export const appStore = new AppStore();