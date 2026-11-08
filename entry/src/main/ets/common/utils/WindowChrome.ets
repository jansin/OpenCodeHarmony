import { window } from '@kit.ArkUI';
import { Theme } from '../Theme';
import { Logger } from './Logger';

const TAG = 'WindowChrome';

// 沉浸式系统栏：内容延展到状态栏下方，各页顶栏自行加 statusBarHeight 避让
export class WindowChrome {
  private static win: window.Window | null = null;

  static async enable(mainWindow: window.Window): Promise<void> {
    WindowChrome.win = mainWindow;
    try {
      await mainWindow.setWindowLayoutFullScreen(true);
      WindowChrome.applyBarColors();
      WindowChrome.refreshAvoidArea();
      mainWindow.on('avoidAreaChange', () => {
        WindowChrome.refreshAvoidArea();
      });
    } catch (e) {
      Logger.w(TAG, 'enable failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  static applyBarColors(): void {
    if (WindowChrome.win === null) {
      return;
    }
    const content = Theme.isDark ? '#F1F5F9' : '#0F172A';
    try {
      WindowChrome.win.setWindowSystemBarProperties({
        statusBarColor: '#00000000',
        navigationBarColor: '#00000000',
        statusBarContentColor: content,
        navigationBarContentColor: content
      });
    } catch (e) {
      Logger.w(TAG, 'setWindowSystemBarProperties failed: ' + (e instanceof Error ? e.message : String(e)));
    }
  }

  static refreshAvoidArea(): void {
    if (WindowChrome.win === null) {
      return;
    }
    try {
      const sys = WindowChrome.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      const nav = WindowChrome.win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      const top = px2vp(sys.topRect.height);
      const bottom = px2vp(nav.bottomRect.height > 0 ? nav.bottomRect.height : sys.bottomRect.height);
      AppStorage.setOrCreate<number>('statusBarHeight', top);
      AppStorage.setOrCreate<number>('navBarHeight', bottom);
    } catch (e) {
      Logger.w(TAG, 'refreshAvoidArea failed: ' + (e instanceof Error ? e.message : String(e)));
      AppStorage.setOrCreate<number>('statusBarHeight', 0);
      AppStorage.setOrCreate<number>('navBarHeight', 0);
    }
  }
}
