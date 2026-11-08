import { appStore } from '../data/AppStore';
import { SessionInfo } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import { ChatView } from './ChatView';
import { SidebarView } from './SidebarView';
import {
  SoftAppLogo, SoftPrimaryButton, SoftSecondaryButton,
  SoftPageBg, SoftBanner, SoftEmptyState
} from '../common/ui/SoftChrome';

@Component
export struct HomeView {
  onOpenSettings: (() => void) = () => {};
  onConfigureServer: (() => void) = () => {};
  onOpenDiff: (() => void) = () => {};
  onOpenTodo: (() => void) = () => {};
  onOpenFiles: (() => void) = () => {};
  onOpenZen: (() => void) = () => {};

  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @State sessionID: string = '';
  @State showSidebar: boolean = false;
  @State sidebarX: number = -Theme.sidebarWidth;
  @State overlayAlpha: number = 0;
  @State ready: boolean = false;
  @State loading: boolean = true;
  @State statusText: string = '连接中…';
  @State err: string = '';
  @State bootAppear: number = 0;
  private bootstrapping: boolean = false;
  private closeTimer: number = -1;

  private onConnected = (): void => {
    this.bootstrap();
  };

  private onStatus = (): void => {
    if (!appStore.connected && this.sessionID.length === 0) {
      this.loading = false;
      this.statusText = '连接失败';
      this.err = appStore.lastError.length > 0 ? appStore.lastError : '无法连接到服务器';
    }
  };

  // 电脑端切换会话后，AppStore 跟随焦点并通知这里改当前会话
  private onRemoteSessionFocus = (): void => {
    const id = appStore.currentSessionId;
    if (id.length === 0 || id === this.sessionID) {
      return;
    }
    this.sessionID = id;
    this.ready = true;
    this.loading = false;
    this.err = '';
    this.closeSidebar();
  };

  aboutToAppear(): void {
    appStore.on('connected', this.onConnected);
    appStore.on('status', this.onStatus);
    appStore.on('focus', this.onRemoteSessionFocus);
    if (appStore.connected && appStore.api !== null) {
      this.bootstrap();
    } else {
      this.loading = true;
      this.statusText = appStore.hasSaved ? '正在连接服务器…' : '未连接，请先配置服务器';
      this.err = appStore.lastError;
      if (!appStore.hasSaved) {
        this.loading = false;
      }
    }
    setTimeout(() => {
      this.getUIContext().animateTo(Motion.bounceOpt(), () => {
        this.bootAppear = 1;
      });
    }, 30);
  }

  aboutToDisappear(): void {
    appStore.off('connected', this.onConnected);
    appStore.off('status', this.onStatus);
    appStore.off('focus', this.onRemoteSessionFocus);
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }

  private bootstrap(): void {
    // 避免 connected + aboutToAppear 重复进入
    if (this.bootstrapping) {
      return;
    }
    // 已对齐当前会话则保持；断线后 currentSessionId 被清空，重连须重新 resolve/open
    if (this.sessionID.length > 0 && this.ready && appStore.currentSessionId === this.sessionID) {
      return;
    }
    this.bootstrapping = true;
    this.loading = true;
    this.statusText = '同步电脑会话…';
    this.err = '';
    // 复用最近活跃会话（通常即电脑端正在看的），没有才新建
    appStore.resolveStartupSession().then((s: SessionInfo | null) => {
      this.bootstrapping = false;
      if (s !== null && s.id.length > 0) {
        // 先进入聊天页，会话加载在后台进行，避免卡在「同步中」
        this.sessionID = s.id;
        this.ready = true;
        this.loading = false;
        this.err = '';
        appStore.openSession(s.id, true).catch((_e: Error) => {
          this.err = appStore.lastError.length > 0 ? appStore.lastError : '打开会话失败';
        });
        return;
      }
      this.ready = false;
      this.loading = false;
      this.err = appStore.lastError.length > 0 ? appStore.lastError : '无法同步会话，请点重试';
      this.statusText = '无法打开会话';
    });
  }

  private openSidebar(): void {
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
    this.showSidebar = true;
    this.sidebarX = -Theme.sidebarWidth;
    this.overlayAlpha = 0;
    this.getUIContext().animateTo(Motion.gestureOpt(), () => {
      this.sidebarX = 0;
      this.overlayAlpha = 1;
    });
  }

  private closeSidebar(): void {
    this.getUIContext().animateTo(Motion.gestureOpt(), () => {
      this.sidebarX = -Theme.sidebarWidth;
      this.overlayAlpha = 0;
    });
    if (this.closeTimer >= 0) {
      clearTimeout(this.closeTimer);
    }
    this.closeTimer = setTimeout(() => {
      this.showSidebar = false;
      this.closeTimer = -1;
    }, 280);
  }

  private selectSession(id: string): void {
    this.sessionID = id;
    this.ready = true;
    this.loading = false;
    this.err = '';
    this.closeSidebar();
  }

  private newChat(): void {
    if (!appStore.connected || appStore.api === null) {
      this.err = '尚未连接服务器';
      return;
    }
    appStore.createSession().then((s: SessionInfo | null) => {
      if (s !== null) {
        this.sessionID = s.id;
        this.ready = true;
        this.loading = false;
        this.err = '';
      } else {
        this.err = appStore.lastError.length > 0 ? appStore.lastError : '创建会话失败';
      }
      this.closeSidebar();
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.ready && this.sessionID.length > 0) {
        ChatView({
          sessionID: this.sessionID,
          onOpenSidebar: () => {
            this.openSidebar();
          },
          onNewChat: () => {
            this.newChat();
          },
          onOpenDiff: () => {
            this.onOpenDiff();
          },
          onOpenTodo: () => {
            this.onOpenTodo();
          }
        })

        // 聊天视图内的操作失败提示（如新建会话失败），轻点可关闭
        if (this.err.length > 0) {
          Column() {
            SoftBanner({
              text: this.err,
              tone: 'danger',
              onTap: () => {
                this.err = '';
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .margin({ top: this.statusBarHeight + 6 + Theme.topBarH + 8 })
          .alignItems(HorizontalAlign.Center)
          .transition(TransitionEffect.OPACITY.animation({ duration: 200 })
            .combine(TransitionEffect.translate({ y: -8 }).animation({ duration: 220 })))
        }
      } else {
        Stack() {
          SoftPageBg()

          Column({ space: Theme.spaceMd }) {
            if (this.loading) {
              SoftAppLogo({ sizeVp: 72, radiusVp: 18, animated: true })
                .margin({ bottom: Theme.spaceSm })
              LoadingProgress()
                .width(28)
                .height(28)
                .color(Theme.brandPrimary)
                .margin({ bottom: 4 })
            } else {
              SoftEmptyState({
                title: 'OpenCode',
                subtitle: this.statusText
              })
            }

            if (this.loading) {
              Text('OpenCode')
                .fontSize(Theme.typeHeadline)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimary)
              Text(this.statusText)
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textSecondary)
            }

            if (appStore.server.url.length > 0) {
              Text(appStore.server.url)
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textTertiary)
                .padding({ left: 24, right: 24 })
                .textAlign(TextAlign.Center)
            }
            if (this.err.length > 0) {
              SoftBanner({
                text: this.err,
                tone: 'danger'
              })
                .width('86%')
            }
            if (!this.loading && !appStore.connected) {
              Text('请先在电脑启动: opencode serve --port 4096 --hostname 0.0.0.0')
                .fontSize(Theme.typeCaption)
                .fontColor(Theme.textTertiary)
                .padding({ left: 28, right: 28 })
                .textAlign(TextAlign.Center)
            }
            if (!this.loading) {
              Column({ space: 10 }) {
                if (!appStore.connected) {
                  SoftSecondaryButton({
                    label: '重试连接',
                    onTap: () => {
                      this.loading = true;
                      this.statusText = '正在连接服务器…';
                      this.err = '';
                      if (appStore.hasSaved) {
                        appStore.autoConnect();
                      } else {
                        this.onConfigureServer();
                      }
                    }
                  })
                }
                SoftPrimaryButton({
                  label: appStore.connected ? '同步电脑会话' : '去连接',
                  onTap: () => {
                    if (appStore.connected) {
                      this.sessionID = '';
                      this.ready = false;
                      this.bootstrap();
                    } else {
                      this.onConfigureServer();
                    }
                  }
                })
              }
              .width('100%')
              .padding({ left: 40, right: 40 })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .opacity(1)
          .translate({ y: (1 - this.bootAppear) * 16 })
        }
        .width('100%')
        .height('100%')
      }

      if (this.showSidebar) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(Theme.overlay)
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .opacity(this.overlayAlpha)
          .onClick(() => {
            this.closeSidebar();
          })

        SidebarView({
          onClose: () => {
            this.closeSidebar();
          },
          onSelectSession: (id: string) => {
            this.selectSession(id);
          },
          onNewChat: () => {
            this.newChat();
          },
          onOpenSettings: () => {
            this.closeSidebar();
            this.onOpenSettings();
          },
          onConfigureServer: () => {
            this.closeSidebar();
            this.onConfigureServer();
          },
          onOpenZen: () => {
            this.closeSidebar();
            this.onOpenZen();
          },
          onOpenFiles: () => {
            this.closeSidebar();
            this.onOpenFiles();
          }
        })
          .width(Theme.sidebarWidth)
          .height('100%')
          .translate({ x: this.sidebarX })
          .shadow({ radius: 28, color: Theme.shadowStrong, offsetX: 6, offsetY: 0 })
      }
    }
    .width('100%')
    .height('100%')
  }
}
