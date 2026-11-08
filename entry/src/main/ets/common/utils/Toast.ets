import { promptAction } from '@kit.ArkUI';
import { Logger } from './Logger';

const TAG = 'Toast';

export class Toast {
  static show(message: string, duration: number = 2500): void {
    if (message.length === 0) {
      return;
    }
    try {
      promptAction.showToast({
        message: message,
        duration: duration
      });
    } catch (e) {
      Logger.w(TAG, 'showToast failed');
    }
  }
}
