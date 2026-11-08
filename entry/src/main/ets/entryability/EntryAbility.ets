import { AbilityConstant, ConfigurationConstant, UIAbility, Want, Configuration } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { appStore } from '../data/AppStore';
import { WindowChrome } from '../common/utils/WindowChrome';
import { Notifier } from '../common/utils/Notifier';

// 0x0000 是系统保留值可能被过滤，用自定义 domain
const DOMAIN = 0xD0F70000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    AppStorage.setOrCreate<number>('statusBarHeight', 0);
    AppStorage.setOrCreate<number>('navBarHeight', 0);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      windowStage.getMainWindow().then((win: window.Window) => {
        WindowChrome.enable(win);
      }).catch((e: Error) => {
        hilog.error(DOMAIN, 'testTag', 'getMainWindow failed: %{public}s', e.message);
      });
    });

    Notifier.init(this.context);
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    appStore.setBackground(false);
    Notifier.cancelTransient();
    WindowChrome.applyBarColors();
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    appStore.setBackground(true);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    if (newConfig.colorMode !== undefined) {
      appStore.resolveDarkMode(newConfig.colorMode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      WindowChrome.applyBarColors();
    }
  }
}
