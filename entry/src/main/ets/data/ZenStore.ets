import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/utils/Logger';
import { SecretBox } from '../common/utils/SecretBox';
import { ZenMessageLine, zenChat, zenTestKey, ZenReply } from './api/ZenStream';

const TAG = 'ZenStore';

// Zen Key 默认留空：硬编码真实密钥会随 APK 分发被提取冒用，
// 用户需在设置里自行填写（已保存的 Key 不受影响）
export const ZEN_DEFAULT_KEY = '';
export const ZEN_DEFAULT_MODEL = 'deepseek-v4-flash-free';
export const ZEN_ENDPOINT = 'https://opencode.ai/zen/v1';

export type ZenListener = () => void;

class ZenEmitter {
  private map: Map<string, ZenListener[]> = new Map();

  on(name: string, l: ZenListener): void {
    let arr = this.map.get(name);
    if (arr === undefined) {
      arr = [];
      this.map.set(name, arr);
    }
    arr.push(l);
  }

  off(name: string, l: ZenListener): void {
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

// Phone-side direct model chat (OpenCode Zen), independent of the PC server.
export class ZenStore {
  key: string = ZEN_DEFAULT_KEY;
  model: string = ZEN_DEFAULT_MODEL;
  messages: ZenMessageLine[] = [];
  assistantText: string = '';
  assistantReasoning: string = '';
  working: boolean = false;
  lastError: string = '';
  lastSaved: boolean = false;

  private em = new ZenEmitter();
  private replayTimer: number = -1;

  on(name: string, l: ZenListener): void {
    this.em.on(name, l);
  }

  off(name: string, l: ZenListener): void {
    this.em.off(name, l);
  }

  private emit(name: string): void {
    this.em.emit(name);
  }

  getKey(): string {
    return this.key;
  }

  getModel(): string {
    return this.model;
  }

  // replace + persist key from the settings page
  setKey(k: string): void {
    this.key = k.trim().length > 0 ? k.trim() : this.key;
  }

  setModel(m: string): void {
    this.model = m.trim().length > 0 ? m.trim() : this.model;
  }

  save(ctx: common.Context): void {
    try {
      const pref = preferences.getPreferencesSync(ctx, { name: 'zen_prefs' });
      pref.putSync('zen_key', SecretBox.seal(this.key));
      pref.putSync('zen_model', this.model);
      pref.flush();
      this.lastSaved = true;
    } catch (e) {
      Logger.w(TAG, 'zen save failed');
      this.lastSaved = false;
    }
  }

  load(ctx: common.Context): void {
    try {
      const pref = preferences.getPreferencesSync(ctx, { name: 'zen_prefs' });
      const k = pref.getSync('zen_key', '') as string;
      if (typeof k === 'string' && k.length > 0) {
        this.key = SecretBox.open(k);
      }
      const m = pref.getSync('zen_model', '') as string;
      if (typeof m === 'string' && m.length > 0) {
        this.model = m;
      }
      this.lastSaved = this.key.length > 0;
    } catch (e) {
      Logger.w(TAG, 'zen load failed');
    }
  }

  resetConversation(): void {
    this.messages = [];
    this.assistantText = '';
    this.assistantReasoning = '';
    this.emit('zen');
  }

  clearKey(): void {
    this.key = '';
    this.messages = [];
    this.emit('zen');
  }

  // verify the key works against the Zen endpoint
  test(ctx: common.Context): Promise<string> {
    return zenTestKey(this.key);
  }

  async send(text: string): Promise<void> {
    if (text.trim().length === 0 || this.working) {
      return;
    }
    const userMsg = new ZenMessageLine();
    userMsg.role = 'user';
    userMsg.content = text.trim();
    const history = this.messages.slice();
    history.push(userMsg);
    this.messages = history;
    this.assistantText = '';
    this.assistantReasoning = '';
    this.working = true;
    this.lastError = '';
    this.emit('zen');
    await this.runStream();
  }

  private runStream(): Promise<void> {
    return new Promise<void>((resolve) => {
      zenChat(this.key, this.model, this.messages).then((reply: ZenReply) => {
        this.replay(reply, resolve);
      });
    });
  }

  private replay(reply: ZenReply, done: () => void): void {
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
      this.replayTimer = -1;
    }
    if (reply.error.length > 0) {
      this.working = false;
      this.lastError = reply.error;
      this.emit('zen');
      done();
      return;
    }
    const step = Math.max(24, Math.ceil((reply.reasoning.length + reply.text.length) / 60));
    let shownR = 0;
    let shownT = 0;
    this.assistantReasoning = '';
    this.assistantText = '';
    let stop = false;
    const tick = () => {
      if (stop) {
        return;
      }
      try {
        if (shownR < reply.reasoning.length) {
          shownR = Math.min(reply.reasoning.length, shownR + step);
          this.assistantReasoning = reply.reasoning.substring(0, shownR);
        } else if (shownT < reply.text.length) {
          shownT = Math.min(reply.text.length, shownT + step);
          this.assistantText = reply.text.substring(0, shownT);
        } else {
          this.finishReply(done);
          return;
        }
        this.emit('zen');
        this.replayTimer = setTimeout(tick, 24);
      } catch (e) {
        Logger.w(TAG, 'replay threw');
        this.finishReply(done);
      }
    };
    tick();
  }

  private finishReply(done: () => void): void {
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
      this.replayTimer = -1;
    }
    this.working = false;
    const am = new ZenMessageLine();
    am.role = 'assistant';
    am.content = this.assistantText;
    this.messages = this.messages.slice();
    this.messages.push(am);
    this.emit('zen');
    done();
  }

  abort(): void {
    if (this.replayTimer >= 0) {
      clearTimeout(this.replayTimer);
      this.replayTimer = -1;
    }
    if (this.messages.length > 0) {
      this.finishReply(() => {
      });
    } else {
      this.working = false;
      this.emit('zen');
    }
  }
}

export const zenStore = new ZenStore();