import { http } from '@kit.NetworkKit';
import { Logger } from '../../common/utils/Logger';

const TAG = 'StreamClient';

export class SseEvent {
  name: string = '';
  properties: Record<string, Object> = {};

  constructor(name: string, properties: Record<string, Object>) {
    this.name = name;
    this.properties = properties;
  }
}

// Minimal SSE client built on http.requestInStream().
// Parity with the custom EventSource used by RN/Expo clients: buffered split on
// blank lines, 'data:' payload JSON, exponential reconnect (1s -> 30s).
export class StreamClient {
  private url: string;
  private authHeader: string;
  private req: http.HttpRequest | null = null;
  private chunk: number[] = [];
  private buffer: string = '';
  private stopped: boolean = true;
  private retryDelay: number = 1000;
  private retryTimer: number = -1;
  private connected: boolean = false;

  onEvent: (e: SseEvent) => void = () => {
  };
  onStatus: (up: boolean) => void = () => {
  };

  constructor(url: string, authHeader: string) {
    this.url = url;
    this.authHeader = authHeader;
  }

  start(): void {
    if (!this.stopped) {
      return;
    }
    this.stopped = false;
    this.retryDelay = 1000;
    this.connect();
  }

  stop(): void {
    this.stopped = true;
    if (this.retryTimer >= 0) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
    this.closeReq();
  }

  private closeReq(): void {
    if (this.req !== null) {
      const r = this.req;
      this.req = null;
      try {
        r.off('dataReceive');
        r.off('dataEnd');
        r.off('headersReceive');
        r.destroy();
      } catch (e) {
        Logger.w(TAG, 'closeReq err');
      }
    }
  }

  private connect(): void {
    if (this.stopped) {
      return;
    }
    const req = http.createHttp();
    this.setConnected(false);
    const headers: Record<string, string> = {
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Authorization': this.authHeader
    };
    try {
      req.on('headersReceive', (header: Object) => {
        this.setConnected(true);
        this.retryDelay = 1000;
      });
      req.on('dataReceive', (data: ArrayBuffer) => {
        this.buffer += this.bytesToText(data);
        this.digest();
      });
      req.on('dataEnd', () => {
        if (this.req !== req) {
          return;
        }
        this.closeReq();
        this.scheduleReconnect();
      });
      this.req = req;
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: headers,
        readTimeout: 300000
      };
      req.requestInStream(this.url, options).then((code: number) => {
        Logger.i(TAG, 'stream closed code=' + code);
      }).catch((err: Error) => {
        Logger.w(TAG, 'stream err ' + err.message);
        if (this.req === req) {
          this.closeReq();
          this.scheduleReconnect();
        }
      });
    } catch (e) {
      Logger.w(TAG, 'connect threw');
      this.closeReq();
      this.scheduleReconnect();
    }
  }

  private setConnected(up: boolean): void {
    if (this.connected !== up) {
      this.connected = up;
      this.onStatus(up);
    }
  }

  // Incremental UTF-8 decoding: multi-byte sequences split across chunk
  // boundaries are buffered in this.chunk until completed.
  private bytesToText(data: ArrayBuffer): string {
    const u8 = new Uint8Array(data);
    const buf = this.chunk;
    for (let i = 0; i < u8.length; i++) {
      buf.push(u8[i]);
    }
    let out = '';
    let i = 0;
    const n = buf.length;
    while (i < n) {
      const b0 = buf[i];
      if (b0 < 0x80) {
        out += String.fromCharCode(b0);
        i++;
      } else if ((b0 & 0xE0) === 0xC0) {
        if (i + 1 >= n) {
          break;
        }
        out += String.fromCharCode(((b0 & 0x1F) << 6) | (buf[i + 1] & 0x3F));
        i += 2;
      } else if ((b0 & 0xF0) === 0xE0) {
        if (i + 2 >= n) {
          break;
        }
        out += String.fromCharCode(((b0 & 0x0F) << 12) | ((buf[i + 1] & 0x3F) << 6) | (buf[i + 2] & 0x3F));
        i += 3;
      } else if ((b0 & 0xF8) === 0xF0) {
        if (i + 3 >= n) {
          break;
        }
        const cp = ((b0 & 0x07) << 18) | ((buf[i + 1] & 0x3F) << 12) |
          ((buf[i + 2] & 0x3F) << 6) | (buf[i + 3] & 0x3F);
        out += String.fromCharCode(0xD800 + ((cp - 0x10000) >> 10));
        out += String.fromCharCode(0xDC00 + ((cp - 0x10000) & 0x3FF));
        i += 4;
      } else {
        // invalid/continuation byte: drop it
        i++;
      }
    }
    if (i > 0) {
      this.chunk = buf.slice(i);
    }
    return out;
  }

  private scheduleReconnect(): void {
    if (this.stopped) {
      return;
    }
    if (this.retryTimer >= 0) {
      return;
    }
    const delay = this.retryDelay;
    this.retryDelay = Math.min(this.retryDelay * 2, 30000);
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.connect();
    }, delay);
  }

  private digest(): void {
    let idx = 0;
    while (true) {
      const sep = this.buffer.indexOf('\n\n', idx);
      if (sep < 0) {
        break;
      }
      const raw = this.buffer.substring(idx, sep);
      idx = sep + 2;
      this.parseFrame(raw);
    }
    if (idx > 0) {
      this.buffer = this.buffer.substring(idx);
    }
    if (this.buffer.length > 2 * 1024 * 1024) {
      this.buffer = '';
    }
  }

  // frame lines, e.g.
  //   data: {"type":"hello",...}
  private parseFrame(raw: string): void {
    const lines = raw.split('\n');
    let data = '';
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith('data:')) {
        let payload = line.substring(5);
        if (payload.startsWith(' ')) {
          payload = payload.substring(1);
        }
        data += payload;
      }
    }
    if (data.length === 0) {
      return;
    }
    try {
      const o = JSON.parse(data) as Record<string, Object>;
      const type = o['type'] as string;
      const propsObj = o['properties'];
      if (propsObj === undefined || propsObj === null || typeof propsObj !== 'object') {
        this.onEvent(new SseEvent(type, {}));
      } else {
        this.onEvent(new SseEvent(type, propsObj as Record<string, Object>));
      }
    } catch (e) {
      Logger.w(TAG, 'bad frame');
    }
  }
}