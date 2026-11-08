import { appStore } from '../data/AppStore';
import { ApiClient } from '../data/api/ApiClient';
import { common } from '@kit.AbilityKit';
import { Logger } from '../common/utils/Logger';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import {
  SoftPrimaryButton, SoftSecondaryButton, SoftAppLogo, SoftTextButton,
  SoftPageBg, SoftBanner, SoftChip, SoftTopBar
} from '../common/ui/SoftChrome';

const TAG = 'ConnectView';
const URL_HINT = 'http://192.168.1.100:4096';

@Component
export struct ConnectView {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @State url: string = '';
  @State password: string = '';
  @State loading: boolean = false;
  @State testing: boolean = false;
  @State testOk: boolean = false;
  @State err: string = '';
  @State showPw: boolean = false;
  @State appear: number = 0;
  onConnected: (() => void) = () => {};
  onBack: (() => void) = () => {};
  @Prop showBack: boolean = false;

  aboutToAppear(): void {
    this.url = appStore.server.url;
    this.password = appStore.server.password;
    this.appear = 0;
    setTimeout(() => {
      this.getUIContext().animateTo(Motion.bounceOpt(), () => {
        this.appear = 1;
      });
    }, 16);
    setTimeout(() => {
      this.appear = 1;
    }, 500);
  }

  private friendlyError(raw: string): string {
    const m = raw.toLowerCase();
    if (m.indexOf('401') >= 0 || m.indexOf('unauthorized') >= 0) {
      return '\u8BA4\u8BC1\u5931\u8D25\uFF0C\u8BF7\u68C0\u67E5\u5BC6\u7801';
    }
    if (m.indexOf('network') >= 0 || m.indexOf('connect') >= 0 || m.indexOf('failed to connect') >= 0) {
      return '\u65E0\u6CD5\u8FDE\u63A5\u670D\u52A1\u5668\uFF0C\u8BF7\u786E\u8BA4\u7535\u8111\u5DF2\u542F\u52A8 opencode serve\uFF0C\u4E14\u624B\u673A\u4E0E\u7535\u8111\u5728\u540C\u4E00\u5C40\u57DF\u7F51';
    }
    if (m.indexOf('timeout') >= 0) {
      return '\u8FDE\u63A5\u8D85\u65F6\uFF0C\u8BF7\u68C0\u67E5\u5730\u5740\u4E0E\u7F51\u7EDC';
    }
    if (raw.length > 120) {
      return raw.substring(0, 120) + '\u2026';
    }
    return raw;
  }

  private doConnect(): void {
    let u = this.url.trim();
    if (u.length === 0) {
      this.err = '\u8BF7\u8F93\u5165\u670D\u52A1\u5668\u5730\u5740\uFF0C\u4F8B\u5982 ' + URL_HINT;
      return;
    }
    if (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    const pw = this.password.trim();
    this.loading = true;
    this.err = '';
    appStore.connect(u, pw).then(() => {
      this.loading = false;
      this.onConnected();
    }).catch((e: Error) => {
      this.loading = false;
      this.err = this.friendlyError(e.message);
      Logger.w(TAG, 'connect failed ' + e.message);
    });
  }

  private testConnection(): void {
    let u = this.url.trim();
    if (u.length === 0) {
      this.err = '\u8BF7\u8F93\u5165\u670D\u52A1\u5668\u5730\u5740';
      return;
    }
    if (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    this.testing = true;
    this.testOk = false;
    this.err = '';
    const api = new ApiClient(u, this.password.trim());
    api.health().then(() => {
      this.testing = false;
      this.testOk = true;
    }).catch((e: Error) => {
      this.testing = false;
      this.testOk = false;
      this.err = this.friendlyError(e.message);
      Logger.w(TAG, 'test failed ' + e.message);
    });
  }

  build() {
    Stack() {
      SoftPageBg()

      Column() {
        if (this.showBack) {
          SoftTopBar({
            title: '\u8FDE\u63A5\u670D\u52A1\u5668',
            useDrawerIcon: false,
            onBack: () => {
              this.onBack();
            }
          })
        }

        Scroll() {
          Column() {
            Column({ space: Theme.spaceSm }) {
              SoftAppLogo({ sizeVp: 80, radiusVp: 20, animated: true })
                .margin({ bottom: Theme.spaceMd })

              Text('OpenCode')
                .fontSize(Theme.typeDisplay)
                .fontWeight(FontWeight.Bold)
                .fontColor(Theme.textPrimaryOf(this.darkMode))
              Text('\u624B\u673A\u7AEF AI \u7ED3\u5BF9\u7F16\u7A0B\n\u8FDE\u63A5\u7535\u8111\u4E0A\u7684 opencode serve')
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textSecondaryOf(this.darkMode))
                .textAlign(TextAlign.Center)
                .lineHeight(20)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: this.showBack ? 12 : (48 + this.statusBarHeight), bottom: 20 })
            .opacity(1)
            .translate({ y: (1 - this.appear) * 12 })

            Column({ space: Theme.spaceMd }) {
              Column({ space: 6 }) {
                Text('\u670D\u52A1\u5668\u5730\u5740')
                  .fontSize(Theme.typeCaption)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textSecondaryOf(this.darkMode))
                  .width('100%')
                TextInput({ placeholder: URL_HINT, text: this.url })
                  .type(InputType.URL)
                  .onChange((v: string) => {
                    this.url = v;
                    this.testOk = false;
                  })
                  .height(Theme.tapMin)
                  .fontSize(Theme.typeBodySm)
                  .fontColor(Theme.textPrimaryOf(this.darkMode))
                  .placeholderColor(Theme.textTertiaryOf(this.darkMode))
                  .backgroundColor(Theme.softFillOf(this.darkMode))
                  .borderRadius(Theme.radiusMd)
                  .border({ width: 0.5, color: Theme.borderMutedOf(this.darkMode) })
                  .padding({ left: Theme.spaceMd, right: Theme.spaceMd })
              }
              .width('100%')

              Column({ space: 6 }) {
                Text('\u5BC6\u7801\uFF08\u53EF\u9009\uFF09')
                  .fontSize(Theme.typeCaption)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textSecondaryOf(this.darkMode))
                  .width('100%')
                Row({ space: 8 }) {
                  TextInput({
                    placeholder: '\u82E5\u670D\u52A1\u5668\u8BBE\u7F6E\u4E86\u5BC6\u7801\u8BF7\u586B\u5199',
                    text: this.password
                  })
                    .type(this.showPw ? InputType.Normal : InputType.Password)
                    .layoutWeight(1)
                    .onChange((v: string) => {
                      this.password = v;
                      this.testOk = false;
                    })
                    .height(Theme.tapMin)
                    .fontSize(Theme.typeBodySm)
                    .fontColor(Theme.textPrimaryOf(this.darkMode))
                    .placeholderColor(Theme.textTertiaryOf(this.darkMode))
                    .backgroundColor(Theme.softFillOf(this.darkMode))
                    .borderRadius(Theme.radiusMd)
                    .border({ width: 0.5, color: Theme.borderMutedOf(this.darkMode) })
                    .padding({ left: Theme.spaceMd, right: Theme.spaceMd })
                  SoftChip({
                    label: this.showPw ? '\u9690\u85CF' : '\u663E\u793A',
                    active: this.showPw,
                    onTap: () => {
                      this.showPw = !this.showPw;
                    }
                  })
                }
                .width('100%')
              }
              .width('100%')

              Text('\u4EC5\u652F\u6301\u5C40\u57DF\u7F51\u81EA\u6258\u7BA1\u3002\u8BF7\u5148\u5728\u7535\u8111\u8FD0\u884C opencode serve\uFF0C\u518D\u586B\u5199\u672C\u673A\u5C40\u57DF\u7F51 IP\u3002')
                .fontSize(Theme.typeCaption)
                .fontColor(Theme.textTertiaryOf(this.darkMode))
                .lineHeight(17)
                .width('100%')

              SoftSecondaryButton({
                label: this.testing ? '\u6D4B\u8BD5\u4E2D\u2026' : '\u6D4B\u8BD5\u8FDE\u63A5',
                isEnabled: !this.testing && !this.loading,
                onTap: () => {
                  this.testConnection();
                }
              })

              if (this.testOk) {
                SoftBanner({ text: '\u8FDE\u63A5\u6210\u529F\uFF0C\u53EF\u4EE5\u8FDB\u5165', tone: 'success' })
              }

              if (this.err.length > 0) {
                SoftBanner({ text: this.err, tone: 'danger' })
              }

              SoftPrimaryButton({
                label: this.loading ? '\u8FDE\u63A5\u4E2D\u2026' : '\u8FDE\u63A5\u5E76\u8FDB\u5165',
                loading: this.loading,
                isEnabled: !this.loading,
                onTap: () => {
                  this.doConnect();
                }
              })

              SoftTextButton({
                label: '\u6E05\u9664\u5DF2\u4FDD\u5B58\u7684\u8FDE\u63A5',
                onTap: () => {
                  const ctx = this.getUIContext().getHostContext() as common.Context;
                  appStore.clearSaved(ctx);
                  this.url = '';
                  this.password = '';
                  this.testOk = false;
                  this.err = '';
                }
              })
            }
            .width('100%')
            .padding(Theme.spaceXl)
            .margin({ left: Theme.spaceLg, right: Theme.spaceLg })
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radius2xl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev3())
            .opacity(1)
            .translate({ y: (1 - this.appear) * 14 })

            Text('OpenCode Mobile 1.0.0\n\u5C40\u57DF\u7F51\u81EA\u6258\u7BA1 \u00B7 \u975E\u4E91\u7AEF\u6258\u7BA1\u670D\u52A1')
              .fontSize(Theme.typeCaption)
              .fontColor(Theme.textTertiaryOf(this.darkMode))
              .textAlign(TextAlign.Center)
              .margin({ top: Theme.spaceXl, bottom: Theme.space2xl })
              .opacity(this.appear)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
