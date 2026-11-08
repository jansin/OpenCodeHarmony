import { StreamClient, SseEvent } from './StreamClient';
import { Logger } from '../../common/utils/Logger';

const TAG = 'EventStreamBridge';

// 文本增量事件（session.next.text.delta / reasoning.delta）的 properties
class DeltaPayload {
  timestamp: number = 0;
  sessionID: string = '';
  assistantMessageID: string = '';
  textID: string = '';
  reasoningID: string = '';
  delta: string = '';
}

// 全局事件流桥：连接 /event，把文本/推理增量实时喂给 AppStore，
// 使手机端在设备支持 SSE 时获得真正的逐 token 流式输出。
// 若设备在探针窗口内连 headersReceive 都收不到，自动标记 unsupported 并停止，
// 上层回退到高频轮询 + 打字机。
export class EventStreamBridge {
  private client: StreamClient | null = null;
  private startedAt: number = 0;
  private probeTimer: number = -1;
  private supported: boolean = false;
  private stopped: boolean = true;

  // 回调：收到增量/关键事件时通知 AppStore
  onTextDelta: (sessionID: string, messageID: string, textID: string, delta: string) => void = () => {
  };
  onReasoningDelta: (sessionID: string, messageID: string, reasoningID: string, delta: string) => void = () => {
  };
  onMessageUpdated: (sessionID: string, messageID: string) => void = () => {
  };
  onSessionIdle: (sessionID: string) => void = () => {
  };
  onSessionError: (sessionID: string) => void = () => {
  };
  onUnsupported: () => void = () => {
  };

  isSupported(): boolean {
    return this.supported;
  }

  start(baseUrl: string, authHeader: string): void {
    if (!this.stopped) {
      return;
    }
    this.stopped = false;
    this.supported = false;
    this.startedAt = Date.now();
    const url = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) + '/event' : baseUrl + '/event';
    const client = new StreamClient(url, authHeader);
    client.onEvent = (e: SseEvent) => {
      this.handleEvent(e);
    };
    // headersReceive 即视为 SSE 可达；空闲无业务事件时不要误判为设备不支持
    client.onStatus = (up: boolean) => {
      if (up) {
        this.markSupported();
      }
    };
    this.client = client;
    client.start();
    // 探针：15s 内连 headers 都收不到，才回退轮询
    this.probeTimer = setTimeout(() => {
      this.probeTimer = -1;
      if (!this.supported) {
        Logger.i(TAG, 'SSE unsupported on this device, falling back to polling');
        this.stop();
        this.onUnsupported();
      }
    }, 15000);
  }

  stop(): void {
    this.stopped = true;
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
    if (this.client !== null) {
      this.client.stop();
      this.client = null;
    }
  }

  private markSupported(): void {
    if (this.supported) {
      return;
    }
    this.supported = true;
    if (this.probeTimer >= 0) {
      clearTimeout(this.probeTimer);
      this.probeTimer = -1;
    }
  }

  private handleEvent(e: SseEvent): void {
    // 收到任何真实事件即认为设备支持 SSE（探针取消）
    this.markSupported();
    const p = e.properties;
    if (e.name === 'session.next.text.delta') {
      const sid = this.str(p, 'sessionID');
      const mid = this.str(p, 'assistantMessageID');
      const tid = this.str(p, 'textID');
      const d = this.str(p, 'delta');
      if (sid.length > 0 && mid.length > 0) {
        this.onTextDelta(sid, mid, tid, d);
      }
      return;
    }
    if (e.name === 'session.next.reasoning.delta') {
      const sid = this.str(p, 'sessionID');
      const mid = this.str(p, 'assistantMessageID');
      const rid = this.str(p, 'reasoningID');
      const d = this.str(p, 'delta');
      if (sid.length > 0 && mid.length > 0) {
        this.onReasoningDelta(sid, mid, rid, d);
      }
      return;
    }
    if (e.name === 'session.next.tool.called' ||
      e.name === 'session.next.tool.success' ||
      e.name === 'session.next.tool.failed' ||
      e.name === 'session.next.step.started' ||
      e.name === 'session.next.step.ended') {
      const sid = this.str(p, 'sessionID');
      const mid = this.str(p, 'assistantMessageID');
      if (sid.length > 0 && mid.length > 0) {
        this.onMessageUpdated(sid, mid);
      }
      return;
    }
    if (e.name === 'message.updated' || e.name === 'message.part.updated') {
      const sid = this.str(p, 'sessionID');
      const mid = e.name === 'message.updated' ? this.messageIdOf(p) : this.str(p, 'messageID');
      if (sid.length > 0 && mid.length > 0) {
        this.onMessageUpdated(sid, mid);
      }
      return;
    }
    if (e.name === 'session.idle') {
      const sid = this.str(p, 'sessionID');
      if (sid.length > 0) {
        this.onSessionIdle(sid);
      }
      return;
    }
    if (e.name === 'session.error') {
      const sid = this.str(p, 'sessionID');
      if (sid.length > 0) {
        this.onSessionError(sid);
      }
      return;
    }
  }

  private str(o: Record<string, Object>, key: string): string {
    const v = o[key];
    if (v === undefined || v === null) {
      return '';
    }
    return String(v);
  }

  // message.updated 的 info 对象里取 id
  private messageIdOf(p: Record<string, Object>): string {
    const info = p['info'];
    if (info !== undefined && info !== null && typeof info === 'object') {
      const o = info as Record<string, Object>;
      const id = o['id'];
      if (id !== undefined && id !== null) {
        return String(id);
      }
    }
    return '';
  }
}
