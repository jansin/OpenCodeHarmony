import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { WantAgent } from '@ohos.wantAgent';
import { Logger } from './Logger';

const TAG = 'Notifier';

export class Notifier {
  private static ctx: common.UIAbilityContext | null = null;
  private static agent: WantAgent | null = null;
  private static slotReady: boolean = false;

  static readonly ID_TASK = 9101;
  static readonly ID_DONE = 9102;
  static readonly ID_APPROVAL = 9103;
  static readonly ID_QUESTION = 9104;
  static readonly ID_TEST = 9105;

  static init(context: common.UIAbilityContext): void {
    Notifier.ctx = context;
    Notifier.ensureSlot();
    Notifier.prepareWantAgent();
  }

  static requestEnable(context: common.UIAbilityContext): void {
    Notifier.ctx = context;
    Notifier.ensureSlot();
    Notifier.prepareWantAgent();
    notificationManager.isNotificationEnabled().then((enabled: boolean) => {
      if (enabled) {
        return;
      }
      notificationManager.requestEnableNotification(context).catch((e: Error) => {
        Logger.w(TAG, 'requestEnableNotification failed: ' + e.message);
      });
    }).catch((e: Error) => {
      Logger.w(TAG, 'isNotificationEnabled failed: ' + e.message);
    });
  }

  static async isEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (_e) {
      return false;
    }
  }

  private static ensureSlot(): void {
    if (Notifier.slotReady) {
      return;
    }
    try {
      notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION).then(() => {
        Notifier.slotReady = true;
      }).catch((e: Error) => {
        Logger.w(TAG, 'addSlot failed: ' + e.message);
      });
    } catch (e) {
      Logger.w(TAG, 'addSlot throw: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  private static prepareWantAgent(): void {
    if (Notifier.ctx === null || Notifier.agent !== null) {
      return;
    }
    const info: wantAgent.WantAgentInfo = {
      wants: [
        {
          bundleName: Notifier.ctx.abilityInfo.bundleName,
          abilityName: 'EntryAbility'
        }
      ],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 100,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    wantAgent.getWantAgent(info).then((agent: WantAgent) => {
      Notifier.agent = agent;
    }).catch((e: Error) => {
      Logger.w(TAG, 'getWantAgent failed: ' + e.message);
    });
  }

  static notifyTaskStart(title: string, text: string): void {
    Notifier.publish(Notifier.ID_TASK, title, text, true);
  }

  static notifyTaskDone(title: string, text: string): void {
    Notifier.cancel(Notifier.ID_TASK);
    Notifier.publish(Notifier.ID_DONE, title, text, false);
  }

  static notifyApproval(title: string, text: string): void {
    Notifier.publish(Notifier.ID_APPROVAL, title, text, true);
  }

  static notifyQuestion(title: string, text: string): void {
    Notifier.publish(Notifier.ID_QUESTION, title, text, false);
  }

  static notifyTest(): void {
    Notifier.publish(Notifier.ID_TEST, 'OpenCode', '\u8FD9\u662F\u4E00\u6761\u6D4B\u8BD5\u901A\u77E5', false);
  }

  static cancelTask(): void {
    Notifier.cancel(Notifier.ID_TASK);
  }

  static cancelTransient(): void {
    Notifier.cancel(Notifier.ID_TASK);
    Notifier.cancel(Notifier.ID_APPROVAL);
    Notifier.cancel(Notifier.ID_QUESTION);
  }

  static cancel(id: number): void {
    try {
      notificationManager.cancel(id).catch(() => {
      });
    } catch (_e) {
    }
  }

  static notify(title: string, text: string): void {
    Notifier.publish(Notifier.ID_DONE, title, text, false);
  }

  private static publish(id: number, title: string, text: string, ongoing: boolean): void {
    try {
      const request: notificationManager.NotificationRequest = {
        id: id,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title.length > 0 ? title : 'OpenCode',
            text: text
          }
        },
        isOngoing: ongoing,
        isAlertOnce: true
      };
      if (Notifier.agent !== null) {
        request.wantAgent = Notifier.agent;
      }
      notificationManager.publish(request).catch((e: Error) => {
        Logger.w(TAG, 'publish failed: ' + e.message);
      });
    } catch (e) {
      Logger.w(TAG, 'notify failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }
}
