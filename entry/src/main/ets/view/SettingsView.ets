import { Theme } from '../common/Theme';
import {
  SoftTopBar, SoftTripleSegment, SoftPrimaryButton, SoftSecondaryButton, SoftTextButton,
  SoftBanner, SoftChip, SoftPageBg
} from '../common/ui/SoftChrome';
import { Notifier } from '../common/utils/Notifier';
import { Motion } from '../common/Motion';
import { common } from '@kit.AbilityKit';
import { appStore } from '../data/AppStore';
import { zenStore, ZEN_DEFAULT_MODEL } from '../data/ZenStore';

@Component
export struct SettingsView {
  onBack: (() => void) = () => {};

  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;

  @State url: string = '';
  @State password: string = '';
  @State zenKey: string = '';
  @State zenModel: string = '';
  @State testing: boolean = false;
  @State testResult: string = '';
  @State savedType: number = 0;
  @State notifyEnabled: boolean = true;
  @State segSel: number[] = [0];
  @State appear: number = 0;
  @State themeGen: number = 0;
  @State themeLabels: string[] = ['\u8DDF\u968F\u7CFB\u7EDF', '\u4EAE\u8272', '\u6DF1\u8272'];

  onDarkMode(): void {
    this.themeGen += 1;
  }

  aboutToAppear(): void {
    this.url = appStore.server.url;
    this.password = appStore.server.password;
    this.zenKey = zenStore.getKey();
    this.zenModel = zenStore.getModel();
    this.notifyEnabled = appStore.notifyEnabled;
    this.segSel = [this.idxOf(appStore.darkModePref)];
    setTimeout(() => {
      this.getUIContext().animateTo(Motion.enterOpt(), () => {
        this.appear = 1;
      });
    }, 30);
  }

  private idxOf(pref: string): number {
    if (pref === 'light') {
      return 1;
    }
    if (pref === 'dark') {
      return 2;
    }
    return 0;
  }

  private hostCtx(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private pickDarkMode(pref: string): void {
    const host = this.hostCtx();
    const colorMode = host.config.colorMode;
    appStore.setDarkMode(pref, colorMode === 0);
  }

  private saveAll(): void {
    const ctx = this.hostCtx();
    const nextUrl = this.url.trim();
    const nextPw = this.password;
    const prevUrl = appStore.server.url;
    const prevPw = appStore.server.password;

    // 空地址 = 清除已保存连接并断开
    if (nextUrl.length === 0) {
      appStore.clearSaved(ctx);
      zenStore.setKey(this.zenKey);
      zenStore.setModel(this.zenModel);
      zenStore.save(ctx);
      this.savedType += 1;
      return;
    }

    const needReconnect = nextUrl !== prevUrl || nextPw !== prevPw;
    appStore.server.url = nextUrl;
    appStore.server.password = nextPw;
    appStore.persist(ctx);
    zenStore.setKey(this.zenKey);
    zenStore.setModel(this.zenModel);
    zenStore.save(ctx);
    if (appStore.notifyEnabled !== this.notifyEnabled) {
      appStore.notifyEnabled = this.notifyEnabled;
      appStore.persist(ctx);
      if (this.notifyEnabled) {
        Notifier.requestEnable(ctx);
      }
    }
    if (needReconnect) {
      appStore.disconnect();
      appStore.connect(nextUrl, nextPw).catch((_e: Error) => {
        // lastError 已由 connect 写入，Home 会展示
      });
    }
    this.savedType += 1;
  }

  private testZen(): void {
    const ctx = this.hostCtx();
    if (this.zenKey.trim().length === 0) {
      this.testResult = '密钥为空，请先填写';
      return;
    }
    zenStore.setKey(this.zenKey);
    zenStore.setModel(this.zenModel);
    this.testing = true;
    this.testResult = '';
    zenStore.test(ctx).then(() => {
      this.testing = false;
      this.testResult = '验证通过：密钥有效，可正常对话';
    }).catch((e: Error) => {
      this.testing = false;
      this.testResult = '验证失败：' + e.message;
    });
  }

  build() {
    Stack() {
      SoftPageBg()

      Column() {
        SoftTopBar({
          title: '设置',
          useDrawerIcon: true,
          onBack: () => {
            this.onBack();
          }
        })

        if (this.savedType > 0) {
          SoftBanner({
            text: '已保存',
            tone: 'success'
          })
            .padding({ left: 16, right: 16, top: 8 })
            .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
        }

        Scroll() {
          Column({ space: 12 }) {
            // 连接状态卡
            Column() {
              Row({ space: 10 }) {
                Circle({ width: 10, height: 10 })
                  .fill(appStore.connected ? Theme.accentGreen : Theme.accentRed)
                Text(appStore.connected ? '已连接' : '未连接')
                  .fontSize(15)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Theme.textPrimaryOf(this.darkMode))
                Blank()
                SoftChip({
                  label: appStore.connected ? '在线' : '离线',
                  active: appStore.connected,
                  onTap: () => {
                  }
                })
              }
              .width('100%')
              .margin({ bottom: 12 })
              Text(this.url.length > 0 ? this.url : '未配置服务器')
                .fontSize(13)
                .fontColor(Theme.textSecondaryOf(this.darkMode))
                .width('100%')
                .padding(12)
                .backgroundColor(Theme.softFillOf(this.darkMode))
                .border({ width: 0.5, color: Theme.borderMuted })
                .borderRadius(Theme.radiusSm)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radiusXl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev1())

            this.sectionTitle('服务器')
            Column() {
              this.fieldLabel('服务器地址')
              TextInput({ placeholder: 'http://192.168.1.100:4096', text: this.url })
                .onChange((v: string) => {
                  this.url = v;
                })
                .borderRadius(Theme.radiusSm)
                .backgroundColor(Theme.bgInputOf(this.darkMode))
                .fontColor(Theme.textPrimaryOf(this.darkMode))
                .placeholderColor(Theme.textTertiaryOf(this.darkMode))
                .height(44)
                .padding({ left: 12, right: 12 })
                .border({ width: 0.5, color: Theme.border })
              this.fieldLabel('密码（可选）')
              TextInput({ placeholder: '若服务器设置了密码请填写', text: this.password })
                .type(InputType.Password)
                .onChange((v: string) => {
                  this.password = v;
                })
                .borderRadius(Theme.radiusSm)
                .backgroundColor(Theme.bgInputOf(this.darkMode))
                .fontColor(Theme.textPrimaryOf(this.darkMode))
                .placeholderColor(Theme.textTertiaryOf(this.darkMode))
                .height(44)
                .padding({ left: 12, right: 12 })
                .border({ width: 0.5, color: Theme.border })
                .margin({ top: 8 })
              Text('仅局域网自托管。请确保手机与电脑在同一网络。')
                .fontSize(11)
                .fontColor(Theme.textTertiaryOf(this.darkMode))
                .width('100%')
                .margin({ top: 8 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radiusXl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev1())

            this.sectionTitle('OpenCode Zen（可选）')
            Column() {
              this.fieldLabel('API Key')
              TextInput({ placeholder: '在此填写你的 Zen Key', text: this.zenKey })
                .type(InputType.Password)
                .onChange((v: string) => {
                  this.zenKey = v;
                })
                .borderRadius(Theme.radiusSm)
                .backgroundColor(Theme.bgInputOf(this.darkMode))
                .fontColor(Theme.textPrimaryOf(this.darkMode))
                .placeholderColor(Theme.textTertiaryOf(this.darkMode))
                .height(44)
                .padding({ left: 12, right: 12 })
                .border({ width: 0.5, color: Theme.border })
              this.fieldLabel('模型')
              TextInput({ placeholder: ZEN_DEFAULT_MODEL, text: this.zenModel })
                .onChange((v: string) => {
                  this.zenModel = v;
                })
                .borderRadius(Theme.radiusSm)
                .backgroundColor(Theme.bgInputOf(this.darkMode))
                .fontColor(Theme.textPrimaryOf(this.darkMode))
                .placeholderColor(Theme.textTertiaryOf(this.darkMode))
                .height(44)
                .padding({ left: 12, right: 12 })
                .border({ width: 0.5, color: Theme.border })
                .margin({ top: 8 })
              SoftTextButton({
                label: '清除已保存的 Key',
                onTap: () => {
                  this.zenKey = '';
                  this.testResult = '';
                  zenStore.clearKey();
                }
              })
                .margin({ top: 12 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radiusXl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev1())

            Column({ space: 10 }) {
              SoftPrimaryButton({
                label: '保存',
                onTap: () => {
                  this.saveAll();
                }
              })
              SoftSecondaryButton({
                label: this.testing ? '验证中…' : '测试 Key',
                isEnabled: !this.testing,
                onTap: () => {
                  this.testZen();
                }
              })
            }
            .width('100%')

            if (this.testResult.length > 0) {
              SoftBanner({
                text: this.testResult,
                tone: this.testResult.indexOf('验证通过') >= 0 ? 'success' : 'danger'
              })
                .transition(TransitionEffect.OPACITY.animation({ duration: 200 }))
            }

            this.sectionTitle('外观')
            Column() {
              Row() {
                Text('◐')
                  .width(30)
                  .height(30)
                  .fontSize(14)
                  .textAlign(TextAlign.Center)
                  .borderRadius(Theme.radiusSm)
                  .fontColor(Theme.accentBlue)
                  .backgroundColor(Theme.softFillOf(this.darkMode))
                  .margin({ right: 12 })
                Column() {
                  Text('深色模式')
                    .fontSize(15)
                    .fontColor(Theme.textPrimaryOf(this.darkMode))
                  Text('跟随系统或手动切换主题')
                    .fontSize(12)
                    .fontColor(Theme.textTertiaryOf(this.darkMode))
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
              }
              .width('100%')
              .padding({ bottom: 10 })

              SoftTripleSegment({
                labels: this.themeLabels,
                selected: this.segSel.length > 0 ? this.segSel[0] : 0,
                onChange: (i: number) => {
                  this.segSel = [i];
                  this.pickDarkMode(i === 1 ? 'light' : i === 2 ? 'dark' : 'auto');
                }
              })
              .width('100%')
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radiusXl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev1())

            this.sectionTitle('\u901A\u77E5')
            Column({ space: 12 }) {
              Row() {
                Text('\u25CE')
                  .width(30)
                  .height(30)
                  .fontSize(14)
                  .textAlign(TextAlign.Center)
                  .borderRadius(Theme.radiusSm)
                  .fontColor(Theme.accentTeal)
                  .backgroundColor(Theme.softFillOf(this.darkMode))
                  .margin({ right: 12 })
                Column() {
                  Text('\u540E\u53F0\u4EFB\u52A1\u901A\u77E5')
                    .fontSize(15)
                    .fontColor(Theme.textPrimaryOf(this.darkMode))
                  Text('\u4EC5\u5728 App \u5207\u5230\u540E\u53F0\u65F6\u63D0\u9192\uFF1A\u4EFB\u52A1\u5F00\u59CB/\u5B8C\u6210\u3001\u6743\u9650\u5BA1\u6279\u3001\u95EE\u9898\u56DE\u7B54')
                    .fontSize(12)
                    .fontColor(Theme.textTertiaryOf(this.darkMode))
                    .margin({ top: 2 })
                    .lineHeight(17)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                Toggle({ type: ToggleType.Switch, isOn: this.notifyEnabled })
                  .selectedColor(Theme.accentTeal)
                  .onChange((v: boolean) => {
                    this.notifyEnabled = v;
                    appStore.notifyEnabled = v;
                    appStore.persist(this.hostCtx());
                    if (v) {
                      Notifier.requestEnable(this.hostCtx());
                    }
                  })
              }
              .width('100%')

              SoftSecondaryButton({
                label: '\u53D1\u9001\u6D4B\u8BD5\u901A\u77E5',
                onTap: () => {
                  Notifier.requestEnable(this.hostCtx());
                  Notifier.notifyTest();
                }
              })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radiusXl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev1())

            this.sectionTitle('关于')
            Column() {
              Row() {
                Text('版本')
                  .fontSize(15)
                  .fontColor(Theme.textPrimaryOf(this.darkMode))
                  .layoutWeight(1)
                SoftChip({
                  label: '1.0.0',
                  onTap: () => {
                  }
                })
              }
              .width('100%')
              .margin({ bottom: 8 })
              Text('局域网自托管 AI 编程助手，需配合电脑端 opencode serve 使用。')
                .fontSize(12)
                .fontColor(Theme.textTertiaryOf(this.darkMode))
                .width('100%')
                .lineHeight(18)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(Theme.glassBgOf(this.darkMode))
            .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
            .borderRadius(Theme.radiusXl)
            .border({ width: 0.5, color: Theme.glassBorderOf(this.darkMode) })
            .shadow(Theme.elev1())
            .margin({ bottom: 28 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12 })
          .transition(Motion.cardIn())
          .opacity(1)
          .translate({ y: (1 - this.appear) * 18 })
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
    .translate({ x: 0, y: this.themeGen >= 0 ? 0 : 0 })
  }

  @Builder
  sectionTitle(t: string) {
    Text(t)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textSecondaryOf(this.darkMode))
      .width('100%')
      .padding({ top: 6, bottom: 2 })
  }

  @Builder
  fieldLabel(t: string) {
    Text(t)
      .fontSize(12)
      .fontColor(Theme.textTertiaryOf(this.darkMode))
      .width('100%')
      .margin({ bottom: 6, top: 4 })
  }
}
