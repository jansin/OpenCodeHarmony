import { common } from '@kit.AbilityKit';
import { appStore } from '../data/AppStore';
import { ConnectView } from '../view/ConnectView';
import { HomeView } from '../view/HomeView';
import { DiffView } from '../view/DiffView';
import { TodoView } from '../view/TodoView';
import { SettingsView } from '../view/SettingsView';
import { ZenChatView } from '../view/ZenChatView';
import { FileBrowserView } from '../view/FileBrowserView';
import { zenStore } from '../data/ZenStore';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import { SoftPageBg, SoftAppLogo } from '../common/ui/SoftChrome';
import { Notifier } from '../common/utils/Notifier';
import { WindowChrome } from '../common/utils/WindowChrome';

@Entry
@Component
struct Index {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  @State view: string = 'loading'; // loading | connect | home | chat | diff | todo | zen | settings | files
  @State pageOpacity: number = 1;
  @State themeGen: number = 0;
  @State connectCanBack: boolean = false;
  private ctx: common.Context | null = null;

  onDarkMode(): void {
    this.themeGen += 1;
  }

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.ctx = ctx;
    appStore.loadSaved(ctx);
    appStore.attachCacheContext(ctx);
    zenStore.load(ctx);
    Notifier.init(ctx);
    if (appStore.notifyEnabled) {
      Notifier.requestEnable(ctx);
    }
    WindowChrome.applyBarColors();
    // 结算主题：auto 跟随系统 current colorMode，light/dark 强制
    const colorMode = ctx.config.colorMode;
    appStore.resolveDarkMode(colorMode === 0); // COLOR_MODE_DARK = 0, LIGHT = 1
    appStore.syncAppColorMode();
    WindowChrome.applyBarColors();
    appStore.on('connected', this.onConnected);
    if (appStore.hasSaved) {
      this.goView('home');
      appStore.autoConnect().then(() => {
        // 断连或启动失败：回填上次缓存，弱网/离线仍可浏览历史会话
        if (!appStore.connected) {
          appStore.loadCacheFromDisk();
        }
      });
    } else {
      this.connectCanBack = false;
      this.goView('connect');
    }
  }

  aboutToDisappear(): void {
    appStore.off('connected', this.onConnected);
  }

  private onConnected = (): void => {
    if (this.ctx !== null) {
      appStore.persist(this.ctx);
    }
    this.goView('home');
  };

  // 页面切换：鸿蒙弹簧淡入淡出
  private goView(next: string): void {
    if (next === this.view) {
      return;
    }
    this.getUIContext().animateTo(Motion.leaveOpt(), () => {
      this.pageOpacity = 0.4;
    });
    setTimeout(() => {
      this.view = next;
      this.pageOpacity = 0.4;
      this.getUIContext().animateTo(Motion.bounceOpt(), () => {
        this.pageOpacity = 1;
      });
    }, 120);
  }

  build() {
    Stack() {
      if (this.view === 'connect') {
        ConnectView({
          showBack: this.connectCanBack,
          onConnected: () => this.onConnected(),
          onBack: () => {
            this.goView('home');
          }
        })
      } else if (this.view === 'diff') {
        DiffView({
          onBack: () => {
            this.goView('home');
          }
        })
      } else if (this.view === 'todo') {
        TodoView({
          onBack: () => {
            this.goView('home');
          }
        })
      } else if (this.view === 'files') {
        FileBrowserView({
          onBack: () => {
            this.goView('home');
          }
        })
      } else if (this.view === 'zen') {
        ZenChatView({
          onBack: () => {
            this.goView('home');
          },
          onOpenSettings: () => {
            this.goView('settings');
          }
        })
      } else if (this.view === 'settings') {
        SettingsView({
          onBack: () => {
            this.goView('home');
          }
        })
      } else if (this.view === 'home') {
        HomeView({
          onOpenSettings: () => {
            this.goView('settings');
          },
          onConfigureServer: () => {
            this.connectCanBack = true;
            this.goView('connect');
          },
          onOpenDiff: () => {
            this.goView('diff');
          },
          onOpenTodo: () => {
            this.goView('todo');
          },
          onOpenFiles: () => {
            this.goView('files');
          },
          onOpenZen: () => {
            this.goView('zen');
          }
        })
      } else {
        Stack() {
          SoftPageBg()
          Column({ space: Theme.spaceMd }) {
            SoftAppLogo({ sizeVp: 72, radiusVp: 18, animated: true })
            LoadingProgress()
              .width(28)
              .height(28)
              .color(Theme.brandPrimary)
            Text('OpenCode')
              .fontSize(Theme.typeHeadline)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.textPrimary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bgPrimaryOf(this.darkMode))
    .opacity(this.pageOpacity)
    .translate({ x: 0, y: this.themeGen >= 0 ? 0 : 0 })
  }
}
