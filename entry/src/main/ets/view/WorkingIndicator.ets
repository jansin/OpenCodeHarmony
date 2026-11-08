import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';

// Agent 思考中：轻量胶囊，不做玻璃发光
@Component
export struct WorkingIndicator {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State appear: number = 0;

  aboutToAppear(): void {
    this.appear = 0;
    this.getUIContext().animateTo(Motion.bounceOpt(), () => {
      this.appear = 1;
    });
    setTimeout(() => {
      this.appear = 1;
    }, 400);
  }

  build() {
    Row({ space: 10 }) {
      LoadingProgress()
        .width(16)
        .height(16)
        .color(Theme.brandPrimary)

      Text('Agent \u6B63\u5728\u601D\u8003\u2026')
        .fontSize(Theme.typeBodySm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textSecondary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      Circle({ width: 6, height: 6 })
        .fill(Theme.brandPrimary)
        .opacity(0.55 + this.appear * 0.45)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 11, bottom: 11 })
    .margin({ left: 16, right: 16, top: 4, bottom: 2 })
    .backgroundColor(Theme.glassBg())
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .borderRadius(Theme.radiusXl)
    .border({ width: 0.5, color: Theme.glassBorder })
    .shadow(Theme.elev1())
    .opacity(1)
    .translate({ y: (1 - this.appear) * 8 })
    .scale({ x: 0.97 + this.appear * 0.03, y: 0.97 + this.appear * 0.03 })
  }
}
