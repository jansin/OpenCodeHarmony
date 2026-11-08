import { appStore } from '../data/AppStore';
import { SessionInfo, fmtSessionTime, fmtGroup, fmtCount } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import {
  SoftAppLogo, SoftIconButton, SoftEmptyState, SoftNavRow, SoftChip, SoftBanner,
  SoftSearchBar, SoftActionTile
} from '../common/ui/SoftChrome';

@Component
export struct SidebarView {
  onClose: (() => void) = () => {};
  onSelectSession: ((id: string) => void) = (_id: string) => {};
  onNewChat: (() => void) = () => {};
  onOpenSettings: (() => void) = () => {};
  onConfigureServer: (() => void) = () => {};
  onOpenZen: (() => void) = () => {};
  onOpenFiles: (() => void) = () => {};

  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  @State sessions: SessionInfo[] = [];
  @State keyword: string = '';
  @State activeId: string = '';

  private subSessions = (): void => {
    this.sessions = appStore.getSessions();
  };

  private syncActive = (): void => {
    this.activeId = appStore.currentSessionId;
  };

  aboutToAppear(): void {
    this.sessions = appStore.getSessions();
    this.activeId = appStore.currentSessionId;
    appStore.on('sessions', this.subSessions);
    appStore.on('focus', this.syncActive);
    appStore.on('status', this.syncActive);
    appStore.refreshSessions();
    appStore.refreshSessionStatus();
  }

  aboutToDisappear(): void {
    appStore.off('sessions', this.subSessions);
    appStore.off('focus', this.syncActive);
    appStore.off('status', this.syncActive);
  }

  private lastSessionsRef: SessionInfo[] | null = null;
  private lastKeyword: string = '';
  private cachedFiltered: SessionInfo[] = [];

  private filtered(): SessionInfo[] {
    const k = this.keyword.trim().toLowerCase();
    if (k.length === 0) {
      return this.sessions;
    }
    // 只在会话列表引用或关键词变化时重算，避免渲染期每项都全量过滤一遍
    if (this.lastSessionsRef === this.sessions && this.lastKeyword === k) {
      return this.cachedFiltered;
    }
    this.lastSessionsRef = this.sessions;
    this.lastKeyword = k;
    const out: SessionInfo[] = [];
    for (let i = 0; i < this.sessions.length; i++) {
      const t = this.sessions[i].title.toLowerCase();
      if (t.indexOf(k) >= 0) {
        out.push(this.sessions[i]);
      }
    }
    this.cachedFiltered = out;
    return out;
  }

  private doDelete(s: SessionInfo): void {
    // 延迟到确认对话框回调后执行，避免在 swipeAction 手势内直接发起异步删除
    this.getUIContext().showAlertDialog({
      title: '删除会话',
      message: '确定删除 "' + (s.title.length > 0 ? s.title : '无标题会话') + '" 吗？此操作不可恢复。',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: Color.Red,
        action: () => {
          this.doDeleteConfirmed(s);
        }
      }
    });
  }

  private doDeleteConfirmed(s: SessionInfo): void {
    appStore.deleteSession(s.id).then((ok: boolean) => {
      if (!ok) {
        return;
      }
      this.sessions = appStore.getSessions();
      if (this.activeId === s.id) {
        if (this.sessions.length > 0) {
          this.activeId = this.sessions[0].id;
          this.onSelectSession(this.activeId);
        } else {
          this.activeId = '';
          this.onNewChat();
        }
      }
    });
  }

  @Builder
  deleteAction(s: SessionInfo) {
    Button('删除')
      .fontSize(13)
      .width(72)
      .height('100%')
      .backgroundColor(Theme.accentRed)
      .borderRadius(Theme.radiusSm)
      .fontColor(Color.White)
      .onClick(() => {
        this.doDelete(s);
      })
  }

  build() {
    Column() {
      // 顶部用户信息
      Column() {
        Row() {
          SoftAppLogo({ sizeVp: 36, radiusVp: 10, animated: false })
          Column() {
            Text('Developer')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
            SoftChip({
              label: appStore.connected ? '\u5DF2\u8FDE\u63A5' : '\u672A\u8FDE\u63A5',
              active: appStore.connected,
              onTap: () => {
              }
            })
              .margin({ top: 4 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 10 })

          SoftIconButton({
            icon: $r('sys.media.ohos_ic_public_close'),
            btnSize: 28,
            iconSize: 14,
            onTap: () => {
              this.onClose();
            }
          })
        }
        .width('100%')
        .margin({ bottom: 14 })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 16 + this.statusBarHeight, bottom: 12 })
      .border({ width: { bottom: 0.5 }, color: Theme.borderMuted })

      if (!appStore.connected) {
        Column() {
          SoftBanner({
            text: '\u672A\u8FDE\u63A5\u670D\u52A1\u5668\uFF0C\u70B9\u51FB\u5E95\u90E8\u914D\u7F6E',
            tone: 'warning',
            onTap: () => {
              this.onConfigureServer();
            }
          })
        }
        .width('100%')
        .padding({ left: 14, right: 14, top: 8 })
      }

      // 搜索
      Column() {
        SoftSearchBar({
          placeholder: '\u641C\u7D22\u4F1A\u8BDD\u2026',
          value: this.keyword,
          onChange: (v: string) => {
            this.keyword = v;
          }
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 10, bottom: 4 })

      // 快速操作
      Row({ space: 6 }) {
        SoftActionTile({
          label: '\u65B0\u5EFA',
          accent: true,
          icon: $r('sys.media.ohos_ic_public_add'),
          onTap: () => {
            this.onNewChat();
          }
        })
          .layoutWeight(1)
        SoftActionTile({
          label: '\u5237\u65B0',
          icon: $r('sys.media.ohos_ic_public_restore'),
          onTap: () => {
            appStore.refreshSessions();
          }
        })
          .layoutWeight(1)
        SoftActionTile({
          label: '\u6587\u4EF6',
          icon: $r('sys.media.ohos_ic_normal_white_grid_folder'),
          onTap: () => {
            this.onOpenFiles();
          }
        })
          .layoutWeight(1)
        SoftActionTile({
          label: 'Zen',
          useSymbol: true,
          symbol: $r('sys.symbol.ohos_star'),
          onTap: () => {
            this.onOpenZen();
          }
        })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 10 })

      // 会话区标题
      Row() {
        Text('会话')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textTertiary)
        Blank()
        SoftIconButton({
          icon: $r('sys.media.ohos_ic_public_add'),
          btnSize: 24,
          iconSize: 12,
          onTap: () => {
            this.onNewChat();
          }
        })
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 4, bottom: 6 })

      if (this.filtered().length === 0) {
        Column() {
          SoftEmptyState({
            title: this.keyword.length > 0 ? '无匹配会话' : '暂无会话',
            subtitle: this.keyword.length > 0
              ? '试试其他关键词'
              : '点 New Chat 开始新对话'
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 2 }) {
          ForEach(this.filtered(), (s: SessionInfo, idx: number) => {
            if (idx === 0 || fmtGroup(s.updated) !== fmtGroup(this.filtered()[idx - 1].updated)) {
              ListItem() {
                Text(fmtGroup(s.updated))
                  .fontSize(10)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textTertiary)
                  .padding({ left: 8, right: 8, top: 6 })
                  .width('100%')
              }
            }
            ListItem() {
              Row() {
                Text('◇')
                  .fontSize(12)
                  .fontColor(this.activeId === s.id ? Theme.accentBlue : Theme.textTertiary)
                  .width(20)
                Column() {
                  Row() {
                    Text(s.title.length > 0 ? s.title : '(无标题会话)')
                      .fontSize(13)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.activeId === s.id ? Theme.accentBlue : Theme.textPrimary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    if (appStore.sessionStatus[s.id] === 'busy') {
                      SoftChip({
                        label: '忙碌',
                        active: true,
                        onTap: () => {
                        }
                      })
                        .margin({ left: 4 })
                    }
                  }
                  .width('100%')
                  Text(fmtSessionTime(s.updated))
                    .fontSize(11)
                    .fontColor(Theme.textTertiary)
                    .margin({ top: 2 })
                  Row({ space: 6 }) {
                    if (s.tokensInput + s.tokensOutput > 0) {
                      SoftChip({
                        label: fmtCount(s.tokensInput + s.tokensOutput) + ' tokens',
                        onTap: () => {
                        }
                      })
                    }
                    if (s.cost > 0) {
                      SoftChip({
                        label: '$' + s.cost.toFixed(2),
                        onTap: () => {
                        }
                      })
                    }
                  }
                  .width('100%')
                  .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 4 })
              }
              .width('100%')
              .padding({ left: 8, right: 8, top: 8, bottom: 8 })
              .borderRadius(Theme.radiusMd)
              .backgroundColor(this.activeId === s.id ? Theme.infoSoft : Theme.glassBg())
              .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
              .border({ width: 0.5, color: this.activeId === s.id ? Theme.brandPrimary : Theme.glassBorder })
              .shadow(this.activeId === s.id ? Theme.elev1() : Theme.elev0())
              .onClick(() => {
                this.activeId = s.id;
                this.onSelectSession(s.id);
              })
            }
            .transition(Motion.listItemIn())
            .swipeAction({
              end: this.deleteAction(s),
              edgeEffect: SwipeEdgeEffect.Spring
            })
          }, (s: SessionInfo) => s.id)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 6, right: 6 })
      }

      // 底部
      Column({ space: 6 }) {
        SoftNavRow({
          title: '设置',
          subtitle: '主题、通知与账户',
          onTap: () => {
            this.onOpenSettings();
          }
        })
        SoftNavRow({
          title: '连接服务器',
          subtitle: appStore.connected ? '已连接' : '配置局域网地址',
          onTap: () => {
            this.onConfigureServer();
          }
        })
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 10, bottom: 14 })
      .border({ width: { top: 0.5 }, color: Theme.borderMuted })
    }
    .width(Theme.sidebarWidth)
    .height('100%')
    .backgroundColor(Theme.glassBg())
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: { right: 0.5 }, color: Theme.glassBorder })
    .shadow(Theme.elev3())
    .alignItems(HorizontalAlign.Start)
  }
}
