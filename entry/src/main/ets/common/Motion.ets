import { curves } from '@kit.ArkUI';

// 鸿蒙动效体系：弹簧优先、可打断、带回弹；避免线性硬切
export class Motion {
  // 快弹：列表项、按钮回弹
  static springSnappy(): ICurve {
    return curves.springMotion(0.55, 0.92);
  }

  // 柔入：页面/卡片出现
  static springSoft(): ICurve {
    return curves.springMotion(0.72, 0.96);
  }

  // 回弹：气泡、空状态徽标
  static springBounce(): ICurve {
    return curves.springMotion(0.48, 0.78);
  }

  // 手势跟随：侧栏、拖拽（鸿蒙 responsiveSpring）
  static springGesture(): ICurve {
    return curves.responsiveSpringMotion(0.38, 0.88);
  }

  // 底部抽屉
  static springSheet(): ICurve {
    return curves.springMotion(0.58, 0.90);
  }

  static enterOpt(): AnimateParam {
    return { curve: Motion.springSoft() };
  }

  static bounceOpt(): AnimateParam {
    return { curve: Motion.springBounce() };
  }

  static snappyOpt(): AnimateParam {
    return { curve: Motion.springSnappy() };
  }

  static sheetOpt(): AnimateParam {
    return { curve: Motion.springSheet() };
  }

  static gestureOpt(): AnimateParam {
    return { curve: Motion.springGesture() };
  }

  static leaveOpt(): AnimateParam {
    return { duration: 160, curve: Curve.EaseIn };
  }

  static tapOpt(): AnimateParam {
    return { curve: Motion.springGesture() };
  }

  // 消息气泡入场：透明度 + 缩放 + 上移
  static bubbleIn(): TransitionEffect {
    return TransitionEffect.OPACITY.animation(Motion.enterOpt())
      .combine(TransitionEffect.scale({ x: 0.94, y: 0.94 }).animation(Motion.bounceOpt()))
      .combine(TransitionEffect.translate({ y: 14 }).animation(Motion.enterOpt()));
  }

  // 卡片/芯片入场
  static cardIn(): TransitionEffect {
    return TransitionEffect.OPACITY.animation(Motion.enterOpt())
      .combine(TransitionEffect.scale({ x: 0.96, y: 0.96 }).animation(Motion.snappyOpt()))
      .combine(TransitionEffect.translate({ y: 10 }).animation(Motion.enterOpt()));
  }

  // 底部抽屉
  static sheetIn(): TransitionEffect {
    return TransitionEffect.translate({ y: 56 }).animation(Motion.sheetOpt())
      .combine(TransitionEffect.OPACITY.animation(Motion.enterOpt()));
  }

  // 侧栏项
  static listItemIn(): TransitionEffect {
    return TransitionEffect.OPACITY.animation(Motion.enterOpt())
      .combine(TransitionEffect.translate({ x: -12 }).animation(Motion.snappyOpt()));
  }
}
