import { appStore } from '../data/AppStore';
import { ProviderInfo, ModelInfo } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import { SoftLightSense } from '../common/ui/SoftLightSense';
import { SoftChip, SoftEmptyState } from '../common/ui/SoftChrome';

@Component
export struct ModelPicker {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  onClose: (() => void) = () => {
  };
  onPick: ((providerID: string, modelID: string) => void) = (_providerID: string, _modelID: string) => {
  };

  @State providers: ProviderInfo[] = [];
  @State curProvider: string = appStore.currentProviderID;
  @State curModel: string = appStore.currentModelID;
  @State selPid: string = appStore.currentProviderID;
  @State loading: boolean = false;
  @State sheetY: number = 80;
  @State overlayA: number = 0;

  private onProviders = (): void => {
    this.providers = appStore.getProviders();
    this.ensureSelection();
  };

  private ensureSelection(): void {
    if (this.providers.length === 0) {
      return;
    }
    let found = false;
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === this.selPid) {
        found = true;
        break;
      }
    }
    if (!found) {
      this.selPid = this.providers[0].id;
    }
  }

  aboutToAppear(): void {
    this.providers = appStore.getProviders();
    this.curProvider = appStore.currentProviderID;
    this.curModel = appStore.currentModelID;
    this.ensureSelection();
    appStore.on('providers', this.onProviders);
    if (this.providers.length === 0 && !this.loading) {
      this.loading = true;
      appStore.refreshProviders().then(() => {
        this.loading = false;
        this.providers = appStore.getProviders();
        this.ensureSelection();
      }).catch(() => {
        this.loading = false;
      });
    }
    setTimeout(() => {
      this.getUIContext().animateTo(Motion.sheetOpt(), () => {
        this.sheetY = 0;
        this.overlayA = 1;
      });
    }, 16);
  }

  aboutToDisappear(): void {
    appStore.off('providers', this.onProviders);
  }

  private closeAnimated(): void {
    this.getUIContext().animateTo(Motion.gestureOpt(), () => {
      this.sheetY = 120;
      this.overlayA = 0;
    });
    setTimeout(() => {
      this.onClose();
    }, 260);
  }

  private isCurrent(pID: string, mID: string): boolean {
    return this.curProvider === pID && this.curModel === mID;
  }

  private pick(pID: string, mID: string): void {
    appStore.setModel(pID, mID);
    this.curProvider = pID;
    this.curModel = mID;
    this.onPick(pID, mID);
    this.closeAnimated();
  }

  private selProvider(): ProviderInfo | null {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === this.selPid) {
        return this.providers[i];
      }
    }
    return null;
  }

  private freeOf(p: ProviderInfo): ModelInfo[] {
    const out: ModelInfo[] = [];
    for (let i = 0; i < p.models.length; i++) {
      if (p.models[i].isFree) {
        out.push(p.models[i]);
      }
    }
    return out;
  }

  private paidOf(p: ProviderInfo): ModelInfo[] {
    const out: ModelInfo[] = [];
    for (let i = 0; i < p.models.length; i++) {
      if (!p.models[i].isFree) {
        out.push(p.models[i]);
      }
    }
    return out;
  }

  private accent(): string {
    return Theme.brandPrimary;
  }

  private rowBg(isCurrent: boolean): string {
    if (isCurrent) {
      return Theme.infoSoft;
    }
    return Theme.softFill;
  }

  @Builder
  sectionHeader(title: string, count: number, color: string) {
    Row({ space: 8 }) {
      SoftChip({
        label: title,
        active: true
      })
      Text(count.toString() + ' \u4E2A')
        .fontSize(Theme.typeCaption)
        .fontColor(Theme.textTertiary)
      Row()
        .height(1)
        .layoutWeight(1)
        .backgroundColor(color)
        .opacity(0.2)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 8, bottom: 2 })
  }

  @Builder
  modelRow(m: ModelInfo, isFree: boolean) {
    Row({ space: 12 }) {
      Row()
        .width(8)
        .height(8)
        .borderRadius(Theme.radiusSm)
        .backgroundColor(this.isCurrent(this.selPid, m.id)
          ? this.accent()
          : (isFree ? Theme.accentGreen : Theme.accentOrange))
      Text(m.name)
        .fontSize(Theme.typeBodySm)
        .fontColor(this.isCurrent(this.selPid, m.id) ? this.accent() : Theme.textPrimary)
        .fontWeight(this.isCurrent(this.selPid, m.id) ? FontWeight.Medium : FontWeight.Regular)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.isCurrent(this.selPid, m.id)) {
        Text('\u2713')
          .fontSize(14)
          .fontColor(this.accent())
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .height(46)
    .padding({ left: 14, right: 14 })
    .borderRadius(Theme.radiusSm)
    .backgroundColor(this.rowBg(this.isCurrent(this.selPid, m.id)))
    .border({
      width: 0.5,
      color: this.isCurrent(this.selPid, m.id) ? this.accent() : Theme.borderMuted
    })
    .visualEffect(SoftLightSense.card())
    .onClick(() => {
      this.pick(this.selPid, m.id);
    })
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.overlay)
        .opacity(this.overlayA)
        .onClick(() => {
          this.closeAnimated();
        })

      Column({ space: 10 }) {
        Row()
          .width(40)
          .height(4)
          .borderRadius(2)
          .backgroundColor(Theme.border)
          .margin({ top: 10 })

        Text('\u9009\u62E9\u6A21\u578B')
          .fontSize(Theme.typeTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .width('100%')
          .textAlign(TextAlign.Center)

        if (this.loading) {
          Column({ space: 10 }) {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(Theme.brandPrimary)
            Text('\u52A0\u8F7D\u6A21\u578B\u5217\u8868...')
              .fontSize(Theme.typeBodySm)
              .fontColor(Theme.textSecondary)
          }
          .margin({ top: 28, bottom: 28 })
        } else if (this.providers.length === 0) {
          SoftEmptyState({
            title: '\u6682\u65E0\u53EF\u7528\u6A21\u578B',
            subtitle: '\u8BF7\u786E\u8BA4\u7535\u8111\u7AEF\u5DF2\u767B\u5F55/\u8FDE\u63A5\u81F3\u5C11\u4E00\u4E2A\u670D\u52A1\u5546'
          })
            .margin({ top: 12, bottom: 24 })
        } else {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.providers, (p: ProviderInfo) => {
                SoftChip({
                  label: p.name,
                  active: this.selPid === p.id,
                  onTap: () => {
                    this.selPid = p.id;
                  }
                })
              }, (p: ProviderInfo) => p.id)
            }
            .padding({ left: 14, right: 14 })
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .height(34)
          .width('100%')

          Scroll() {
            Column({ space: 6 }) {
              if (this.selProvider() !== null) {
                if (this.freeOf(this.selProvider() as ProviderInfo).length > 0) {
                  this.sectionHeader('\u514D\u8D39', this.freeOf(this.selProvider() as ProviderInfo).length,
                    Theme.accentGreen)
                  ForEach(this.freeOf(this.selProvider() as ProviderInfo), (m: ModelInfo) => {
                    this.modelRow(m, true)
                  }, (m: ModelInfo) => m.id)
                }
                if (this.paidOf(this.selProvider() as ProviderInfo).length > 0) {
                  Divider()
                    .color(Theme.borderMuted)
                    .margin({ top: 8, bottom: 2 })
                  this.sectionHeader('\u4ED8\u8D39', this.paidOf(this.selProvider() as ProviderInfo).length,
                    Theme.accentOrange)
                  ForEach(this.paidOf(this.selProvider() as ProviderInfo), (m: ModelInfo) => {
                    this.modelRow(m, false)
                  }, (m: ModelInfo) => m.id)
                }
              }
            }
            .width('100%')
            .padding({ left: 10, right: 10, bottom: 12 })
          }
          .constraintSize({ maxHeight: 440 })
          .width('100%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)

          Row() {
            Text('\u5F53\u524D\uFF1A')
              .fontSize(Theme.typeCaption)
              .fontColor(Theme.textTertiary)
            Text(appStore.currentModelLabel())
              .fontSize(Theme.typeCaption)
              .fontColor(this.accent())
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 14 })
        }
      }
      .width('100%')
      .constraintSize({ maxHeight: 560 })
      .padding({ top: 6, bottom: 8 })
      .backgroundColor(Theme.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius({ topLeft: Theme.radiusXl, topRight: Theme.radiusXl })
      .border({ width: { top: 0.5 }, color: Theme.borderMuted })
      .visualEffect(SoftLightSense.sheet())
      .shadow({ radius: 28, color: Theme.shadowStrong, offsetX: 0, offsetY: -4 })
      .translate({ y: this.sheetY })
    }
    .width('100%')
    .height('100%')
  }
}
