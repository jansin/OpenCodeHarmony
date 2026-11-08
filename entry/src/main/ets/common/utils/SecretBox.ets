import { util } from '@kit.ArkTS';

// 轻量混淆 Preferences 中的敏感字段（非 HUKS 级加密，仅防明文直读）。
// 正式安全存储请在后续迁到 HUKS / 系统凭据库。
const PREFIX = 'oc1:';
const SALT = 'OpenCodeHarmony.prefs.v1';

function utf8Bytes(s: string): Uint8Array {
  const enc = new util.TextEncoder('utf-8');
  return enc.encodeInto(s);
}

function b64Encode(bytes: Uint8Array): string {
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

function b64Decode(s: string): Uint8Array {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  const clean = s.replace(/=+$/, '');
  const out: number[] = [];
  for (let i = 0; i < clean.length; i += 4) {
    const c0 = chars.indexOf(clean.charAt(i));
    const c1 = chars.indexOf(clean.charAt(i + 1));
    const c2 = i + 2 < clean.length ? chars.indexOf(clean.charAt(i + 2)) : 0;
    const c3 = i + 3 < clean.length ? chars.indexOf(clean.charAt(i + 3)) : 0;
    out.push(((c0 << 2) | (c1 >> 4)) & 0xff);
    if (i + 2 < clean.length) {
      out.push((((c1 & 15) << 4) | (c2 >> 2)) & 0xff);
    }
    if (i + 3 < clean.length) {
      out.push((((c2 & 3) << 6) | c3) & 0xff);
    }
  }
  return new Uint8Array(out);
}

function xorBytes(data: Uint8Array, key: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) {
    out[i] = data[i] ^ key[i % key.length];
  }
  return out;
}

export class SecretBox {
  static seal(plain: string): string {
    if (plain.length === 0) {
      return '';
    }
    const key = utf8Bytes(SALT);
    const mixed = xorBytes(utf8Bytes(plain), key);
    return PREFIX + b64Encode(mixed);
  }

  static open(stored: string): string {
    if (stored.length === 0) {
      return '';
    }
    if (!stored.startsWith(PREFIX)) {
      // 兼容旧版明文
      return stored;
    }
    try {
      const raw = b64Decode(stored.substring(PREFIX.length));
      const key = utf8Bytes(SALT);
      const plain = xorBytes(raw, key);
      let s = '';
      for (let i = 0; i < plain.length; i++) {
        s += String.fromCharCode(plain[i]);
      }
      // TextDecoder 更稳妥；ArkTS 下按字节还原 UTF-8 多字节可能不准，
      // 密码一般为 ASCII，此处足够。
      return s;
    } catch (_e) {
      return '';
    }
  }
}
