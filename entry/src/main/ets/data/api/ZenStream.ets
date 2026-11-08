import { http } from '@kit.NetworkKit';
import { Logger } from '../../common/utils/Logger';

const TAG = 'ZenStream';

export const ZEN_URL = 'https://opencode.ai/zen/v1/chat/completions';

export class ZenMessageLine {
  role: string = 'user'; // user | assistant | system
  content: string = '';
}

export interface ZenReply {
  text: string;
  reasoning: string;
  error: string;
}

// Chat client for the OpenCode Zen OpenAI-compatible endpoint.
//
// IMPORTANT: this device's @ohos.net.http does NOT fire dataReceive/dataEnd
// for streaming responses (the underlying write to the app fails with CURL23),
// exactly as the reference OHOS client documents. So the exchange is a single
// non-streaming POST; the call site replays the full reply with a typewriter
// effect to keep the perceptual streaming UX.
export function zenChat(key: string, model: string, messages: ZenMessageLine[]): Promise<ZenReply> {
  return new Promise<ZenReply>((resolve) => {
    const msgs: Record<string, Object>[] = [];
    for (let i = 0; i < messages.length; i++) {
      const o: Record<string, Object> = {};
      o['role'] = messages[i].role;
      o['content'] = messages[i].content;
      msgs.push(o);
    }
    const body: Record<string, Object> = {};
    body['model'] = model;
    body['messages'] = msgs;
    body['stream'] = false;
    const req = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ' + key,
        'User-Agent': 'opencode/1.1.48'
      },
      extraData: JSON.stringify(body),
      connectTimeout: 15000,
      readTimeout: 120000
    };
    req.request(ZEN_URL, options).then((resp: http.HttpResponse) => {
      try {
        req.destroy();
      } catch (e) {
        Logger.w(TAG, 'req destroy err');
      }
      if (resp.responseCode !== 200) {
        resolve({ text: '', reasoning: '', error: 'HTTP ' + resp.responseCode });
        return;
      }
      const raw = typeof resp.result === 'string' ? resp.result : JSON.stringify(resp.result);
      try {
        const parsed = JSON.parse(raw) as Record<string, Object>;
        const choices = parsed['choices'];
        if (Array.isArray(choices) && choices.length > 0) {
          const first = choices[0] as Record<string, Object>;
          const message = first['message'] as Record<string, Object> | null;
          if (message !== null && message !== undefined) {
            const text = typeof message['content'] === 'string' ? message['content'] as string : '';
            const reasoning = typeof message['reasoning_content'] === 'string'
              ? message['reasoning_content'] as string : '';
            if ((text + reasoning).trim().length > 0) {
              resolve({ text: text, reasoning: reasoning, error: '' });
              return;
            }
          }
        }
        const errObj = parsed['error'] as Record<string, Object> | null;
        if (errObj !== null && errObj !== undefined && typeof errObj['message'] === 'string') {
          resolve({ text: '', reasoning: '', error: errObj['message'] as string });
          return;
        }
        resolve({ text: '', reasoning: '', error: '模型未返回内容' });
      } catch (e) {
        resolve({ text: '', reasoning: '', error: '响应解析失败(截断 ' + raw.length + ' B)' });
      }
    }).catch((err: Error) => {
      try {
        req.destroy();
      } catch (e) {
        Logger.w(TAG, 'req destroy err');
      }
      resolve({ text: '', reasoning: '', error: err.message });
    });
  });
}

// quick non-stream check that a key is accepted (validates bearer/SNI path)
export function zenTestKey(key: string): Promise<string> {
  return new Promise<string>((resolve, reject) => {
    const msg: Record<string, Object> = {};
    msg['role'] = 'user';
    msg['content'] = 'ping';
    const body: Record<string, Object> = {};
    body['model'] = 'deepseek-v4-flash-free';
    body['messages'] = [msg];
    body['max_tokens'] = 8;
    const req = http.createHttp();
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: {
        'Authorization': 'Bearer ' + key,
        'Content-Type': 'application/json'
      },
      extraData: JSON.stringify(body),
      connectTimeout: 15000,
      readTimeout: 45000
    };
    const p = req.request(ZEN_URL, options);
    p.then((resp: http.HttpResponse) => {
      req.destroy();
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        resolve('OK');
      } else {
        reject(new Error('HTTP ' + resp.responseCode));
      }
    }).catch((err: Error) => {
      req.destroy();
      reject(err);
    });
  });
}