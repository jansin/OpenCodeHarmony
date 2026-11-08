import { Theme } from '../Theme';
import { Motion } from '../Motion';

// ---- App Logo：统一使用应用图标 ----
@Component
export struct SoftAppLogo {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State appear: number = 1;
  @Prop sizeVp: number = 64;
  @Prop radiusVp: number = 16;
  @Prop animated: boolean = false;

  aboutToAppear(): void {
    if (this.animated) {
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
  }

  build() {
    Image($r('app.media.app_icon'))
      .width(this.sizeVp)
      .height(this.sizeVp)
      .borderRadius(this.radiusVp)
      .objectFit(ImageFit.Cover)
      .shadow(this.sizeVp >= 48
        ? { radius: 18, color: Theme.shadowSoft, offsetX: 0, offsetY: 8 }
        : { radius: 8, color: Theme.shadowSoft, offsetX: 0, offsetY: 3 })
      .scale({ x: 0.92 + this.appear * 0.08, y: 0.92 + this.appear * 0.08 })
      .opacity(1)
      .clip(true)
  }
}

// ---- 顶栏返回 ----
@Component
export struct SoftBackButton {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @State private themeGen: number = 0;
  onTap: (() => void) = () => {};
  @Prop useDrawerIcon: boolean = false;

  onDarkMode(): void {
    this.themeGen += 1;
  }

  build() {
    Button() {
      Image(this.useDrawerIcon
        ? $r('sys.media.ohos_ic_public_drawer_open')
        : $r('sys.media.ohos_ic_public_arrow_left'))
        .width(Theme.chromeIcon)
        .height(Theme.chromeIcon)
        .fillColor(Theme.textPrimaryOf(this.darkMode))
    }
    .type(ButtonType.Circle)
    .width(Theme.chromeBtn)
    .height(Theme.chromeBtn)
    .backgroundColor(Theme.glassBgOf(this.darkMode))
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 1, color: Theme.glassBorderOf(this.darkMode) })
    .scale({ x: this.pressed, y: this.pressed })
    .opacity(this.themeGen >= 0 ? 1 : 1)
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.9;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- Soft 顶栏：悬浮玻璃胶囊（Spatial L2）----
@Component
export struct SoftTopBar {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @Prop title: string = '';
  onBack: (() => void) = () => {};
  @Prop useDrawerIcon: boolean = false;
  @State private themeGen: number = 0;

  onDarkMode(): void {
    this.themeGen += 1;
  }

  build() {
    Column() {
      Row() {
        SoftBackButton({
          onTap: () => {
            this.onBack();
          },
          useDrawerIcon: this.useDrawerIcon
        })
        Text(this.title)
          .fontSize(Theme.typeTitle)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimaryOf(this.darkMode))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank().width(Theme.chromeBtn)
      }
      .width('100%')
      .height(Theme.topBarH)
      .padding({ left: Theme.spaceSm, right: Theme.spaceSm })
      .backgroundColor(Theme.glassBgOf(this.darkMode))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .borderRadius(Theme.radiusXl)
      .border({ width: 1, color: Theme.glassBorderOf(this.darkMode) })
    }
    .width('100%')
    .padding({
      left: Theme.floatInset,
      right: Theme.floatInset,
      top: this.statusBarHeight + 6,
      bottom: 6
    })
    .opacity(this.themeGen >= 0 ? 1 : 1)
  }
}

// ---- 主按钮：实心华为蓝，无厚阴影 ----
@Component
export struct SoftPrimaryButton {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @State private themeGen: number = 0;
  @Prop label: string = '';
  @Prop loading: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop stretch: boolean = true;
  onTap: (() => void) = () => {};

  onDarkMode(): void {
    this.themeGen += 1;
  }

  build() {
    Button() {
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(Color.White)
        }
        Text(this.label)
          .fontSize(Theme.typeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textOnAccent)
      }
      .padding({ left: this.stretch ? 0 : 20, right: this.stretch ? 0 : 20 })
    }
    .type(ButtonType.Capsule)
    .constraintSize(this.stretch ? { minWidth: '100%' } : { minWidth: 88 })
    .width(this.stretch ? '100%' : 96)
    .height(this.stretch ? 48 : 44)
    .backgroundColor(Theme.brandPrimaryOf(this.darkMode))
    .border({
      width: 1,
      color: this.darkMode ? 'rgba(91, 155, 255, 0.55)' : 'rgba(10, 89, 247, 0.28)'
    })
    .enabled(this.isEnabled && !this.loading)
    .opacity(this.isEnabled && !this.loading ? 1 : 0.4)
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (!this.isEnabled || this.loading) {
        return;
      }
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.97;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- 次按钮：浅底 ----
@Component
export struct SoftSecondaryButton {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @State private themeGen: number = 0;
  @Prop label: string = '';
  @Prop isEnabled: boolean = true;
  @Prop stretch: boolean = true;
  onTap: (() => void) = () => {};

  onDarkMode(): void {
    this.themeGen += 1;
  }

  build() {
    Button(this.label)
      .type(ButtonType.Capsule)
      .width(this.stretch ? '100%' : 96)
      .padding({ left: 16, right: 16 })
      .height(this.stretch ? 48 : 44)
      .fontSize(Theme.typeBody)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textPrimaryOf(this.darkMode))
      .backgroundColor(Theme.glassBgOf(this.darkMode))
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 1, color: Theme.glassBorderOf(this.darkMode) })
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? 1 : 0.45)
      .scale({ x: this.pressed, y: this.pressed })
      .onTouch((e: TouchEvent) => {
        if (!this.isEnabled) {
          return;
        }
        if (e.type === TouchType.Down) {
          this.getUIContext().animateTo(Motion.tapOpt(), () => {
            this.pressed = 0.97;
          });
        } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
          this.getUIContext().animateTo(Motion.bounceOpt(), () => {
            this.pressed = 1;
          });
        }
      })
      .onClick(() => {
        this.onTap();
      })
  }
}

// ---- 描边/危险文字按钮 ----
@Component
export struct SoftTextButton {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop label: string = '';
  @Prop danger: boolean = false;
  @Prop isEnabled: boolean = true;
  onTap: (() => void) = () => {};

  build() {
    Button(this.label)
      .type(ButtonType.Capsule)
      .height(40)
      .fontSize(Theme.typeBodySm)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.danger ? Theme.accentRed : Theme.brandPrimaryOf(this.darkMode))
      .backgroundColor(Color.Transparent)
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? 1 : 0.45)
      .onClick(() => {
        this.onTap();
      })
  }
}

// ---- 工具芯片（Diff / Todo / 模型）----
@Component
export struct SoftChip {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop label: string = '';
  @Prop active: boolean = false;
  @Prop maxWidth: number = 0;
  onTap: (() => void) = () => {};

  build() {
    Button() {
      Text(this.label)
        .fontSize(Theme.typeCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.active ? Theme.brandPrimaryOf(this.darkMode) : Theme.textSecondaryOf(this.darkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .type(ButtonType.Capsule)
    .height(30)
    .backgroundColor(this.active ? Theme.infoSoft : Theme.glassBgOf(this.darkMode))
    .backgroundBlurStyle(this.active ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK)
    .border({ width: 1, color: this.active ? Theme.brandPrimaryOf(this.darkMode) : Theme.glassBorderOf(this.darkMode) })
    .padding({ left: 12, right: 12 })
    .constraintSize({ maxWidth: this.maxWidth > 0 ? this.maxWidth : 200 })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- 空状态 ----
@Component
export struct SoftEmptyState {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop title: string = '';
  @Prop subtitle: string = '';

  build() {
    Column({ space: Theme.spaceSm }) {
      SoftAppLogo({ sizeVp: 72, radiusVp: 18, animated: true })
        .margin({ bottom: Theme.spaceMd })
      Text(this.title)
        .fontSize(Theme.typeHeadline)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary)
        .textAlign(TextAlign.Center)
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(Theme.typeBodySm)
          .fontColor(Theme.textSecondary)
          .textAlign(TextAlign.Center)
          .lineHeight(Theme.lineBody)
          .padding({ left: Theme.spaceXl, right: Theme.spaceXl })
          .margin({ top: 2 })
      }
    }
    .width('100%')
    .padding({ left: Theme.spaceLg, right: Theme.spaceLg, top: Theme.spaceXl, bottom: Theme.spaceXl })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// ---- 顶栏图标按钮 ----
@Component
export struct SoftIconButton {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  icon: Resource = $r('sys.media.ohos_ic_public_add');
  @Prop tint: string = '';
  @Prop fill: string = '';
  @Prop btnSize: number = Theme.chromeBtn;
  @Prop iconSize: number = Theme.chromeIcon;
  onTap: (() => void) = () => {};

  build() {
    Button() {
      Image(this.icon)
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.tint.length > 0 ? this.tint : Theme.textPrimary)
    }
    .type(ButtonType.Circle)
    .width(this.btnSize)
    .height(this.btnSize)
    .backgroundColor(this.fill.length > 0 ? this.fill : Theme.glassBg())
    .backgroundBlurStyle(this.fill.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK)
    .border({ width: 1, color: this.fill.length > 0 ? Color.Transparent : Theme.glassBorder })
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.9;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- 三段切换：鸿蒙 Segment 白底滑块风格 ----
@Component
export struct SoftTripleSegment {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  labels: string[] = ['A', 'B', 'C'];
  @Prop selected: number = 0;
  onChange: ((i: number) => void) = (_i: number) => {};
  @State private themeGen: number = 0;

  onDarkMode(): void {
    this.themeGen += 1;
  }

  build() {
    Row({ space: 0 }) {
      this.segCell(0)
      this.segCell(1)
      this.segCell(2)
    }
    .width('100%')
    .padding(3)
    .backgroundColor(Theme.softFillOf(this.darkMode))
    .borderRadius(Theme.radiusMd)
    .opacity(this.themeGen >= 0 ? 1 : 1)
  }

  @Builder
  segCell(i: number) {
    Column() {
      Text(i < this.labels.length ? this.labels[i] : '')
        .fontSize(Theme.typeBodySm)
        .fontWeight(this.selected === i ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.selected === i
          ? Theme.brandPrimaryOf(this.darkMode)
          : Theme.textSecondaryOf(this.darkMode))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .layoutWeight(1)
    .height(34)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selected === i ? Theme.bgCardOf(this.darkMode) : Color.Transparent)
    .borderRadius(Theme.radiusSm)
    .animation(Motion.snappyOpt())
    .onClick(() => {
      this.onChange(i);
    })
  }
}

// ---- 双段切换 ----
@Component
export struct SoftSegment {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop left: string = '';
  @Prop right: string = '';
  @Prop selected: number = 0;
  onChange: ((i: number) => void) = (_i: number) => {};

  build() {
    Row({ space: 0 }) {
      Column() {
        Text(this.left)
          .fontSize(Theme.typeBodySm)
          .fontWeight(this.selected === 0 ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selected === 0 ? Theme.brandPrimary : Theme.textSecondary)
      }
      .layoutWeight(1)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.selected === 0 ? Theme.bgCard : Color.Transparent)
      .borderRadius(Theme.radiusSm)
      .shadow(this.selected === 0
        ? { radius: 6, color: Theme.shadowSoft, offsetX: 0, offsetY: 1 }
        : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
      .animation(Motion.snappyOpt())
      .onClick(() => {
        this.onChange(0);
      })

      Column() {
        Text(this.right)
          .fontSize(Theme.typeBodySm)
          .fontWeight(this.selected === 1 ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.selected === 1 ? Theme.brandPrimary : Theme.textSecondary)
      }
      .layoutWeight(1)
      .height(34)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.selected === 1 ? Theme.bgCard : Color.Transparent)
      .borderRadius(Theme.radiusSm)
      .shadow(this.selected === 1
        ? { radius: 6, color: Theme.shadowSoft, offsetX: 0, offsetY: 1 }
        : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
      .animation(Motion.snappyOpt())
      .onClick(() => {
        this.onChange(1);
      })
    }
    .width('100%')
    .padding(3)
    .backgroundColor(Theme.softFill)
    .borderRadius(Theme.radiusMd)
  }
}

// ---- 页面氛围底：Spatial 远景双色洗光 ----
@Component
export struct SoftPageBg {
  @StorageProp('darkMode') @Watch('onDarkMode') darkMode: boolean = Theme.isDark;
  @State private themeGen: number = 0;

  onDarkMode(): void {
    this.themeGen += 1;
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 168,
          colors: [
            [Theme.atmosphereTopOf(this.darkMode), 0],
            [Theme.atmosphereMidOf(this.darkMode), 0.28],
            [Theme.bgPrimaryOf(this.darkMode), 0.55],
            [Theme.bgPrimaryOf(this.darkMode), 1]
          ]
        })
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 320,
          colors: [
            ['rgba(0,0,0,0)', 0],
            ['rgba(0,0,0,0)', 0.42],
            [Theme.atmosphereAccentOf(this.darkMode), 1]
          ]
        })
        .opacity(0.85)
    }
    .width('100%')
    .height('100%')
    .opacity(this.themeGen >= 0 ? 1 : 1)
  }
}

// ---- Soft 空间卡片（L1）----
@Component
export struct SoftCard {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @BuilderParam content: () => void = this.defaultContent;
  paddingVp: number = Theme.spaceLg;
  radiusVp: number = Theme.radiusXl;
  interactive: boolean = false;
  onTap: (() => void) = () => {};

  @Builder
  defaultContent() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.paddingVp)
    .backgroundColor(Theme.bgCardOf(this.darkMode))
    .borderRadius(this.radiusVp)
    .border({ width: 1, color: Theme.borderMutedOf(this.darkMode) })
    .shadow(Theme.elev1())
    .onClick(() => {
      if (this.interactive) {
        this.onTap();
      }
    })
  }
}

// ---- Soft 状态条 ----
@Component
export struct SoftBanner {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop text: string = '';
  @Prop tone: string = 'info';
  onTap: (() => void) = () => {};

  private bg(): string {
    if (this.tone === 'success') {
      return Theme.successSoft;
    }
    if (this.tone === 'warning') {
      return Theme.warningSoft;
    }
    if (this.tone === 'danger') {
      return Theme.dangerSoft;
    }
    return Theme.infoSoft;
  }

  private fg(): string {
    if (this.tone === 'success') {
      return Theme.accentGreen;
    }
    if (this.tone === 'warning') {
      return Theme.accentOrange;
    }
    if (this.tone === 'danger') {
      return Theme.accentRed;
    }
    return Theme.brandPrimary;
  }

  build() {
    Row({ space: 8 }) {
      Circle({ width: 7, height: 7 }).fill(this.fg())
      Text(this.text)
        .fontSize(Theme.typeBodySm)
        .fontColor(this.fg())
        .layoutWeight(1)
        .lineHeight(18)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 10 })
    .backgroundColor(this.bg())
    .borderRadius(Theme.radiusMd)
    .border({ width: 1, color: Theme.glassBorder })
    .shadow(Theme.elev1())
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- Soft 设置/导航行 ----
@Component
export struct SoftNavRow {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  onTap: (() => void) = () => {};

  build() {
    Row() {
      Column() {
        Text(this.title)
          .fontSize(Theme.typeBody)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(Theme.typeCaption)
            .fontColor(Theme.textTertiary)
            .margin({ top: 2 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(18)
        .fontColor(Theme.textTertiary)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 14, bottom: 14 })
    .backgroundColor(Theme.bgCard)
    .borderRadius(Theme.radiusMd)
    .border({ width: 1, color: Theme.borderMuted })
    .shadow(Theme.elev1())
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.98;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- Soft 符号图标钮（放大镜等）----
@Component
export struct SoftSymbolButton {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  symbol: Resource = $r('sys.symbol.magnifyingglass');
  @Prop tint: string = '';
  @Prop fill: string = '';
  @Prop btnSize: number = Theme.chromeBtn;
  @Prop iconSize: number = 16;
  onTap: (() => void) = () => {};

  build() {
    Button() {
      SymbolGlyph(this.symbol)
        .fontSize(this.iconSize)
        .fontColor([this.tint.length > 0 ? this.tint : Theme.textPrimary])
    }
    .type(ButtonType.Circle)
    .width(this.btnSize)
    .height(this.btnSize)
    .backgroundColor(this.fill.length > 0 ? this.fill : Theme.glassBg())
    .backgroundBlurStyle(this.fill.length > 0 ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK)
    .border({ width: 1, color: this.fill.length > 0 ? Color.Transparent : Theme.glassBorder })
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.9;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- Soft 快捷磁贴 ----
@Component
export struct SoftActionTile {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @Prop label: string = '';
  @Prop accent: boolean = false;
  icon: Resource = $r('sys.media.ohos_ic_public_add');
  @Prop useSymbol: boolean = false;
  symbol: Resource = $r('sys.symbol.ohos_star');
  onTap: (() => void) = () => {};

  build() {
    Column({ space: 4 }) {
      if (this.useSymbol) {
        SymbolGlyph(this.symbol)
          .fontSize(18)
          .fontColor([this.accent ? Theme.brandPrimary : Theme.textSecondary])
      } else {
        Image(this.icon)
          .width(18)
          .height(18)
          .fillColor(this.accent ? Theme.brandPrimary : Theme.textSecondary)
      }
      Text(this.label)
        .fontSize(Theme.typeCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.accent ? Theme.brandPrimary : Theme.textSecondary)
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(this.softFillOrAccent())
    .backgroundBlurStyle(this.accent ? BlurStyle.NONE : BlurStyle.COMPONENT_THICK)
    .borderRadius(Theme.radiusMd)
    .border({ width: 1, color: Theme.glassBorder })
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.94;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }

  private softFillOrAccent(): string {
    return this.accent ? Theme.infoSoft : Theme.glassBg();
  }
}

// ---- Soft 搜索条 ----
@Component
export struct SoftSearchBar {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop placeholder: string = '\u641C\u7D22\u2026';
  @Prop value: string = '';
  onChange: ((v: string) => void) = (_v: string) => {};

  build() {
    Row({ space: 8 }) {
      SymbolGlyph($r('sys.symbol.magnifyingglass'))
        .fontSize(16)
        .fontColor([Theme.textTertiary])
      TextInput({ placeholder: this.placeholder, text: this.value })
        .layoutWeight(1)
        .height(34)
        .fontSize(Theme.typeBodySm)
        .backgroundColor(Color.Transparent)
        .fontColor(Theme.textPrimary)
        .placeholderColor(Theme.textTertiary)
        .padding({ left: 0, right: 4 })
        .onChange((v: string) => {
          this.onChange(v);
        })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
    .backgroundColor(Theme.glassBg())
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .border({ width: 1, color: Theme.glassBorder })
    .borderRadius(Theme.radiusLg)
  }
}

// ---- Soft 发送 / 中止：高对比胶囊，保证深浅色都看得见 ----
@Component
export struct SoftSendButton {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @Prop isEnabled: boolean = true;
  // true = 思考中，显示中止；false = 空闲，显示发送
  @Prop working: boolean = false;
  onTap: (() => void) = () => {};

  private canTap(): boolean {
    return this.working || this.isEnabled;
  }

  private bg(): string {
    if (this.working) {
      return this.darkMode ? '#F87171' : '#DC2626';
    }
    return Theme.brandPrimaryOf(this.darkMode);
  }

  build() {
    Button() {
      if (this.working) {
        Column()
          .width(10)
          .height(10)
          .borderRadius(2)
          .backgroundColor(Color.White)
      } else {
        Text('\u25B2')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
      }
    }
    .type(ButtonType.Circle)
    .width(36)
    .height(36)
    .backgroundColor(this.bg())
    .border({
      width: 1,
      color: this.working
        ? (this.darkMode ? 'rgba(248, 113, 113, 0.55)' : 'rgba(220, 38, 38, 0.35)')
        : (this.darkMode ? 'rgba(91, 155, 255, 0.55)' : 'rgba(10, 89, 247, 0.25)')
    })
    .enabled(this.canTap())
    .opacity(this.canTap() ? 1 : 0.4)
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (!this.canTap()) {
        return;
      }
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.92;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

// ---- Soft 悬浮跳转胶囊 ----
@Component
export struct SoftJumpPill {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @Prop label: string = '';
  onTap: (() => void) = () => {};

  build() {
    Button(this.label)
      .type(ButtonType.Capsule)
      .height(36)
      .fontSize(Theme.typeBodySm)
      .fontWeight(FontWeight.Medium)
      .fontColor(Theme.textPrimary)
      .backgroundColor(Theme.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 1, color: Theme.glassBorder })
      .padding({ left: 16, right: 16 })
      .onClick(() => {
        this.onTap();
      })
  }
}

// ---- Soft 提示卡（Claude/ChatGPT 风格空态建议）----
@Component
export struct SoftPromptCard {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State pressed: number = 1;
  @Prop title: string = '';
  @Prop subtitle: string = '';
  onTap: (() => void) = () => {};

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(Theme.typeBodySm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textPrimary)
        .width('100%')
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(Theme.typeCaption)
          .fontColor(Theme.textTertiary)
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .backgroundColor(Theme.bgCard)
    .borderRadius(Theme.radiusLg)
    .border({ width: 1, color: Theme.borderMuted })
    .shadow(Theme.elev1())
    .scale({ x: this.pressed, y: this.pressed })
    .onTouch((e: TouchEvent) => {
      if (e.type === TouchType.Down) {
        this.getUIContext().animateTo(Motion.tapOpt(), () => {
          this.pressed = 0.97;
        });
      } else if (e.type === TouchType.Up || e.type === TouchType.Cancel) {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.pressed = 1;
        });
      }
    })
    .onClick(() => {
      this.onTap();
    })
  }
}

