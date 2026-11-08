export class ShadowElev {
  radius: number = 14;
  color: string = 'rgba(15, 23, 42, 0.07)';
  offsetX: number = 0;
  offsetY: number = 4;
}

// OpenCode Spatial UI（API 24 美学适配）
// 参考：HarmonyOS 空间美学 — 多层景深、悬浮玻璃、空间阴影、克制灵动光感
// 不使用 API 26 systemMaterial；用毛玻璃 + 分层阴影模拟空间层级
export class Theme {
  static isDark: boolean = false;

  // ---- Spatial 景深层 ----
  // L0 远景画布 / L1 内容面 / L2 悬浮玻璃（顶栏·输入·侧栏）/ L3 主操作
  static bgPrimary: string = '#EEF1F6';
  static bgSecondary: string = '#E4E8EF';
  static bgTertiary: string = '#D8DEE8';
  static bgHover: string = '#CDD5E1';
  static bgInput: string = '#FFFFFF';
  static bgSidebar: string = 'rgba(255, 255, 255, 0.72)';
  static bgCard: string = '#FFFFFF';
  static softFill: string = '#E8ECF3';
  static glassLight: string = 'rgba(255, 255, 255, 0.64)';
  static glassDark: string = 'rgba(18, 22, 30, 0.72)';
  static glassBorder: string = 'rgba(255, 255, 255, 0.55)';
  static atmosphereTop: string = 'rgba(10, 89, 247, 0.10)';
  static atmosphereAccent: string = 'rgba(13, 148, 136, 0.06)';
  static atmosphereMid: string = 'rgba(238, 241, 246, 0.92)';

  // ---- Lines ----
  static border: string = '#D5DBE5';
  static borderMuted: string = 'rgba(15, 23, 42, 0.06)';
  static hairline: string = 'rgba(15, 23, 42, 0.08)';

  // ---- Text ----
  static textPrimary: string = '#0F172A';
  static textSecondary: string = '#64748B';
  static textTertiary: string = '#94A3B8';
  static textOnAccent: string = '#FFFFFF';

  // ---- Brand：华为蓝，克制使用 ----
  static accentBlue: string = '#0A59F7';
  static accentTeal: string = '#0D9488';
  static accentGreen: string = '#16A34A';
  static accentPurple: string = '#7C3AED';
  static accentOrange: string = '#EA580C';
  static accentRed: string = '#DC2626';
  static brandPrimary: string = '#0A59F7';
  static brandSecondary: string = '#0D9488';

  static codeBg: string = '#0F172A';
  static userBubble: string = '#E8F0FE';
  static userBubbleText: string = '#0B1F4D';
  static aiBubble: string = 'transparent';
  static overlay: string = 'rgba(15, 23, 42, 0.36)';
  static shadowSoft: string = 'rgba(15, 23, 42, 0.07)';
  static shadowMid: string = 'rgba(15, 23, 42, 0.12)';
  static shadowStrong: string = 'rgba(15, 23, 42, 0.18)';
  static successSoft: string = 'rgba(22, 163, 74, 0.10)';
  static dangerSoft: string = 'rgba(220, 38, 38, 0.10)';
  static warningSoft: string = 'rgba(234, 88, 12, 0.10)';
  static infoSoft: string = 'rgba(10, 89, 247, 0.10)';

  // ---- Layout ----
  static sidebarWidth: number = 304;
  static radiusSm: number = 14;
  static radiusMd: number = 18;
  static radiusLg: number = 22;
  static radiusXl: number = 28;
  static radius2xl: number = 36;
  static spaceXs: number = 4;
  static spaceSm: number = 8;
  static spaceMd: number = 12;
  static spaceLg: number = 16;
  static spaceXl: number = 24;
  static space2xl: number = 32;
  static floatInset: number = 12;

  static typeCaption: number = 12;
  static typeBodySm: number = 14;
  static typeBody: number = 16;
  static typeTitle: number = 17;
  static typeHeadline: number = 24;
  static typeDisplay: number = 32;
  static lineBody: number = 24;
  static topBarH: number = 52;
  static chromeBtn: number = 36;
  static chromeIcon: number = 20;
  static tapMin: number = 44;

  static glassBg(): string {
    return Theme.isDark ? Theme.glassDark : Theme.glassLight;
  }

  // 按当前模式取色（供 UI 绑定 this.darkMode，保证切换时颜色值真的变）
  static bgPrimaryOf(dark: boolean): string {
    return dark ? '#0B0E14' : '#EEF1F6';
  }

  static bgCardOf(dark: boolean): string {
    return dark ? '#151B24' : '#FFFFFF';
  }

  static bgInputOf(dark: boolean): string {
    return dark ? '#171D27' : '#FFFFFF';
  }

  static softFillOf(dark: boolean): string {
    return dark ? '#1C2430' : '#E8ECF3';
  }

  static textPrimaryOf(dark: boolean): string {
    return dark ? '#F1F5F9' : '#0F172A';
  }

  static textSecondaryOf(dark: boolean): string {
    return dark ? '#94A3B8' : '#64748B';
  }

  static textTertiaryOf(dark: boolean): string {
    return dark ? '#64748B' : '#94A3B8';
  }

  static glassBgOf(dark: boolean): string {
    return dark ? 'rgba(18, 22, 30, 0.78)' : 'rgba(255, 255, 255, 0.64)';
  }

  static glassBorderOf(dark: boolean): string {
    return dark ? 'rgba(255, 255, 255, 0.08)' : 'rgba(255, 255, 255, 0.55)';
  }

  static borderMutedOf(dark: boolean): string {
    return dark ? 'rgba(255, 255, 255, 0.06)' : 'rgba(15, 23, 42, 0.06)';
  }

  static brandPrimaryOf(dark: boolean): string {
    return dark ? '#5B9BFF' : '#0A59F7';
  }

  static atmosphereTopOf(dark: boolean): string {
    return dark ? 'rgba(82, 145, 255, 0.14)' : 'rgba(10, 89, 247, 0.10)';
  }

  static atmosphereMidOf(dark: boolean): string {
    return dark ? 'rgba(11, 14, 20, 0.94)' : 'rgba(238, 241, 246, 0.92)';
  }

  static atmosphereAccentOf(dark: boolean): string {
    return dark ? 'rgba(45, 212, 191, 0.08)' : 'rgba(13, 148, 136, 0.06)';
  }

  /** 无阴影 */
  static elev0(): ShadowElev {
    const s = new ShadowElev();
    s.radius = 0;
    s.color = 'rgba(0,0,0,0)';
    s.offsetX = 0;
    s.offsetY = 0;
    return s;
  }

  /** L1 内容面：轻抬 */
  static elev1(): ShadowElev {
    const s = new ShadowElev();
    s.radius = 14;
    s.color = Theme.shadowSoft;
    s.offsetX = 0;
    s.offsetY = 4;
    return s;
  }

  /** L2 悬浮玻璃：顶栏 / 输入 / 侧栏 */
  static elev2(): ShadowElev {
    const s = new ShadowElev();
    s.radius = 28;
    s.color = Theme.shadowMid;
    s.offsetX = 0;
    s.offsetY = 10;
    return s;
  }

  /** L3 主操作 / 模态 */
  static elev3(): ShadowElev {
    const s = new ShadowElev();
    s.radius = 40;
    s.color = Theme.shadowStrong;
    s.offsetX = 0;
    s.offsetY = 16;
    return s;
  }

  static applyDark(dark: boolean): void {
    Theme.isDark = dark;
    if (dark) {
      Theme.bgPrimary = '#0B0E14';
      Theme.bgSecondary = '#131820';
      Theme.bgTertiary = '#1A212B';
      Theme.bgHover = '#242C38';
      Theme.bgInput = '#171D27';
      Theme.bgSidebar = 'rgba(18, 22, 30, 0.78)';
      Theme.bgCard = '#151B24';
      Theme.softFill = '#1C2430';
      Theme.glassLight = 'rgba(255, 255, 255, 0.64)';
      Theme.glassDark = 'rgba(18, 22, 30, 0.78)';
      Theme.glassBorder = 'rgba(255, 255, 255, 0.08)';
      Theme.atmosphereTop = 'rgba(82, 145, 255, 0.14)';
      Theme.atmosphereAccent = 'rgba(45, 212, 191, 0.08)';
      Theme.atmosphereMid = 'rgba(11, 14, 20, 0.94)';
      Theme.border = '#2A3340';
      Theme.borderMuted = 'rgba(255, 255, 255, 0.06)';
      Theme.hairline = 'rgba(255, 255, 255, 0.08)';
      Theme.textPrimary = '#F1F5F9';
      Theme.textSecondary = '#94A3B8';
      Theme.textTertiary = '#64748B';
      Theme.textOnAccent = '#FFFFFF';
      Theme.accentBlue = '#5B9BFF';
      Theme.accentTeal = '#2DD4BF';
      Theme.accentGreen = '#4ADE80';
      Theme.accentPurple = '#A78BFA';
      Theme.accentOrange = '#FB923C';
      Theme.accentRed = '#F87171';
      Theme.brandPrimary = '#5B9BFF';
      Theme.brandSecondary = '#2DD4BF';
      Theme.codeBg = '#080A0E';
      Theme.userBubble = '#1A2740';
      Theme.userBubbleText = '#DBEAFE';
      Theme.aiBubble = 'transparent';
      Theme.overlay = 'rgba(0, 0, 0, 0.55)';
      Theme.shadowSoft = 'rgba(0, 0, 0, 0.30)';
      Theme.shadowMid = 'rgba(0, 0, 0, 0.42)';
      Theme.shadowStrong = 'rgba(0, 0, 0, 0.55)';
      Theme.successSoft = 'rgba(74, 222, 128, 0.14)';
      Theme.dangerSoft = 'rgba(248, 113, 113, 0.14)';
      Theme.warningSoft = 'rgba(251, 146, 60, 0.14)';
      Theme.infoSoft = 'rgba(91, 155, 255, 0.14)';
    } else {
      Theme.bgPrimary = '#EEF1F6';
      Theme.bgSecondary = '#E4E8EF';
      Theme.bgTertiary = '#D8DEE8';
      Theme.bgHover = '#CDD5E1';
      Theme.bgInput = '#FFFFFF';
      Theme.bgSidebar = 'rgba(255, 255, 255, 0.72)';
      Theme.bgCard = '#FFFFFF';
      Theme.softFill = '#E8ECF3';
      Theme.glassLight = 'rgba(255, 255, 255, 0.64)';
      Theme.glassDark = 'rgba(18, 22, 30, 0.72)';
      Theme.glassBorder = 'rgba(255, 255, 255, 0.55)';
      Theme.atmosphereTop = 'rgba(10, 89, 247, 0.10)';
      Theme.atmosphereAccent = 'rgba(13, 148, 136, 0.06)';
      Theme.atmosphereMid = 'rgba(238, 241, 246, 0.92)';
      Theme.border = '#D5DBE5';
      Theme.borderMuted = 'rgba(15, 23, 42, 0.06)';
      Theme.hairline = 'rgba(15, 23, 42, 0.08)';
      Theme.textPrimary = '#0F172A';
      Theme.textSecondary = '#64748B';
      Theme.textTertiary = '#94A3B8';
      Theme.textOnAccent = '#FFFFFF';
      Theme.accentBlue = '#0A59F7';
      Theme.accentTeal = '#0D9488';
      Theme.accentGreen = '#16A34A';
      Theme.accentPurple = '#7C3AED';
      Theme.accentOrange = '#EA580C';
      Theme.accentRed = '#DC2626';
      Theme.brandPrimary = '#0A59F7';
      Theme.brandSecondary = '#0D9488';
      Theme.codeBg = '#0F172A';
      Theme.userBubble = '#E8F0FE';
      Theme.userBubbleText = '#0B1F4D';
      Theme.aiBubble = 'transparent';
      Theme.overlay = 'rgba(15, 23, 42, 0.36)';
      Theme.shadowSoft = 'rgba(15, 23, 42, 0.07)';
      Theme.shadowMid = 'rgba(15, 23, 42, 0.12)';
      Theme.shadowStrong = 'rgba(15, 23, 42, 0.18)';
      Theme.successSoft = 'rgba(22, 163, 74, 0.10)';
      Theme.dangerSoft = 'rgba(220, 38, 38, 0.10)';
      Theme.warningSoft = 'rgba(234, 88, 12, 0.10)';
      Theme.infoSoft = 'rgba(10, 89, 247, 0.10)';
    }
  }
}

export function projectShortName(path: string): string {
  if (path.length === 0) {
    return 'project';
  }
  let normalized = path;
  while (normalized.indexOf('\\') >= 0) {
    normalized = normalized.replace('\\', '/');
  }
  const parts = normalized.split('/');
  for (let i = parts.length - 1; i >= 0; i--) {
    if (parts[i].length > 0) {
      return parts[i];
    }
  }
  return path;
}

export function projectInitial(name: string): string {
  if (name.length === 0) {
    return 'P';
  }
  return name.substring(0, 1).toUpperCase();
}
