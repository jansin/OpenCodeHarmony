import { hdsEffect } from '@kit.UIDesignKit';

/**
 * 灵动光感已降级为空效果：点光源 / BLEND 按压阴影在圆钮边缘易产生抗锯齿抖动。
 * 保留 API，避免各调用点大改；需要时再按场景精细加回。
 */
export class SoftLightSense {
  private static none(): VisualEffect {
    return new hdsEffect.HdsEffectBuilder()
      .pressShadow(hdsEffect.PressShadowType.NONE)
      .buildEffect();
  }

  static primary(): VisualEffect {
    return SoftLightSense.none();
  }

  static soft(): VisualEffect {
    return SoftLightSense.none();
  }

  static icon(): VisualEffect {
    return SoftLightSense.none();
  }

  static glass(): VisualEffect {
    return SoftLightSense.none();
  }

  static card(): VisualEffect {
    return SoftLightSense.none();
  }

  static sheet(): VisualEffect {
    return SoftLightSense.none();
  }

  static logo(): VisualEffect {
    return SoftLightSense.none();
  }

  static bubble(): VisualEffect {
    return SoftLightSense.none();
  }

  static bright(): VisualEffect {
    return SoftLightSense.none();
  }
}
