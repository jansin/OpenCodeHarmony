import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0C0D;

export class Logger {
  static i(tag: string, msg: string): void {
    hilog.info(DOMAIN, tag, '%{public}s', msg);
  }

  static w(tag: string, msg: string): void {
    hilog.warn(DOMAIN, tag, '%{public}s', msg);
  }

  static e(tag: string, msg: string): void {
    hilog.error(DOMAIN, tag, '%{public}s', msg);
  }
}