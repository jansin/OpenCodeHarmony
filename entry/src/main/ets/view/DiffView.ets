import { appStore } from '../data/AppStore';
import { FileDiff } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import { SoftLightSense } from '../common/ui/SoftLightSense';
import { SoftTopBar, SoftEmptyState, SoftChip, SoftPageBg } from '../common/ui/SoftChrome';

class DiffLine {
  type: string = ' '; // ' ', '+', '-'
  text: string = '';
}

class FileStats {
  file: string = '';
  added: number = 0;
  removed: number = 0;
  expanded: boolean = false;
  lines: DiffLine[] = [];
}

// simple LCS-based line diff for preview purposes
function computeDiff(before: string, after: string): DiffLine[] {
  const a = before.length > 0 ? before.split('\n') : [];
  const b = after.length > 0 ? after.split('\n') : [];
  const n = a.length;
  const m = b.length;
  // cap to keep the DP bounded on huge diffs
  const maxN = 800;
  const maxM = 800;
  const an = n > maxN ? maxN : n;
  const bm = m > maxM ? maxM : m;
  const dp: number[][] = [];
  for (let i = 0; i <= an; i++) {
    const row: number[] = [];
    for (let j = 0; j <= bm; j++) {
      row.push(0);
    }
    dp.push(row);
  }
  for (let i = an - 1; i >= 0; i--) {
    for (let j = bm - 1; j >= 0; j--) {
      if (a[i] === b[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        dp[i][j] = dp[i + 1][j];
      } else {
        dp[i][j] = dp[i][j + 1];
      }
    }
  }
  const out: DiffLine[] = [];
  let i = 0;
  let j = 0;
  while (i < an && j < bm) {
    if (a[i] === b[j]) {
      const l = new DiffLine();
      l.type = ' ';
      l.text = a[i];
      out.push(l);
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      const l = new DiffLine();
      l.type = '-';
      l.text = a[i];
      out.push(l);
      i++;
    } else {
      const l = new DiffLine();
      l.type = '+';
      l.text = b[j];
      out.push(l);
      j++;
    }
  }
  while (i < an) {
    const l = new DiffLine();
    l.type = '-';
    l.text = a[i];
    out.push(l);
    i++;
  }
  while (j < bm) {
    const l = new DiffLine();
    l.type = '+';
    l.text = b[j];
    out.push(l);
    j++;
  }
  return out;
}

@Component
export struct DiffView {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  onBack: (() => void) = () => {
  };

  @State files: FileStats[] = [];
  @State appear: number = 0;

  // 展开状态按文件持久，避免任务运行期间高频 review 事件反复折叠已展开的 diff
  private expandedMap: Map<string, boolean> = new Map();
  // 文件内容指纹：内容未变时跳过 LCS 重算，减轻高频刷新时的 UI 线程压力
  private lastContent: Map<string, string> = new Map();

  private onReview = (): void => {
    this.rebuild();
  };

  private rebuild(): void {
    const diffs: FileDiff[] = appStore.getDiffs();
    const prevByFile: Map<string, FileStats> = new Map();
    for (let i = 0; i < this.files.length; i++) {
      prevByFile.set(this.files[i].file, this.files[i]);
    }
    const out: FileStats[] = [];
    for (let i = 0; i < diffs.length; i++) {
      const d = diffs[i];
      const key = d.file + '\u0001' + d.before + '\u0001' + d.after;
      const prev = prevByFile.get(d.file);
      let f: FileStats;
      if (prev !== undefined && this.lastContent.get(d.file) === key) {
        // 内容未变：复用上次的行级 diff 与展开状态，只更新统计
        f = prev;
        f.added = d.additions;
        f.removed = d.deletions;
      } else {
        f = new FileStats();
        f.file = d.file;
        f.added = d.additions;
        f.removed = d.deletions;
        f.expanded = this.expandedMap.get(d.file) === true;
        f.lines = computeDiff(d.before, d.after);
      }
      this.lastContent.set(d.file, key);
      this.expandedMap.set(d.file, f.expanded);
      out.push(f);
    }
    this.files = out;
  }

  aboutToAppear(): void {
    appStore.on('review', this.onReview);
    this.rebuild();
    appStore.refreshDiffs();
    setTimeout(() => {
      this.getUIContext().animateTo(Motion.enterOpt(), () => {
        this.appear = 1;
      });
    }, 30);
  }

  aboutToDisappear(): void {
    appStore.off('review', this.onReview);
  }

  private toggle(i: number): void {
    if (i >= 0 && i < this.files.length) {
      const arr = this.files.slice();
      arr[i].expanded = !arr[i].expanded;
      this.expandedMap.set(arr[i].file, arr[i].expanded);
      this.getUIContext().animateTo(Motion.tapOpt(), () => {
        this.files = arr;
      });
    }
  }

  build() {
    Stack() {
      SoftPageBg()

      Column() {
        SoftTopBar({
          title: '变更',
          onBack: () => {
            this.onBack();
          }
        })

        Row({ space: 8 }) {
          if (this.files.length > 0) {
            SoftChip({
              label: '+' + this.totalAdd().toString(),
              active: true,
              onTap: () => {
              }
            })
            SoftChip({
              label: '-' + this.totalDel().toString(),
              onTap: () => {
              }
            })
          } else {
            Text('暂无变更')
              .fontSize(12)
              .fontColor(Theme.textSecondary)
              .layoutWeight(1)
          }
          Blank()
          SoftChip({
            label: '刷新',
            onTap: () => {
              appStore.refreshDiffs();
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 6 })

        if (this.files.length === 0) {
          Column() {
            SoftEmptyState({
              title: '暂无文件变更',
              subtitle: 'Agent 修改文件后会出现在这里'
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .opacity(1)
        } else {
          Scroll() {
            Column({ space: 10 }) {
              ForEach(this.files, (f: FileStats) => {
                Column() {
                  Row() {
                    Column() {
                      Text(f.file)
                        .fontSize(13)
                        .fontWeight(FontWeight.Medium)
                        .fontColor(Theme.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Row({ space: 6 }) {
                        SoftChip({
                          label: '+' + f.added.toString(),
                          active: true,
                          onTap: () => {
                          }
                        })
                        SoftChip({
                          label: '-' + f.removed.toString(),
                          onTap: () => {
                          }
                        })
                      }
                      .margin({ top: 4 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)
                    Text(f.expanded ? '▾' : '▸')
                      .fontSize(14)
                      .fontColor(Theme.textTertiary)
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .padding({ left: 14, right: 14, top: 12, bottom: 12 })
                  .onClick(() => {
                    this.toggle(this.files.indexOf(f));
                  })

                  if (f.expanded) {
                    Column() {
                      ForEach(f.lines, (l: DiffLine, idx: number) => {
                        Row() {
                          Text(l.type)
                            .fontSize(12)
                            .fontFamily('monospace')
                            .fontColor(this.lineColor(l.type))
                            .width(18)
                          Text(l.text)
                            .fontSize(12)
                            .fontFamily('monospace')
                            .fontColor(Theme.textSecondary)
                            .layoutWeight(1)
                            .maxLines(2)
                            .textOverflow({ overflow: TextOverflow.Ellipsis })
                        }
                        .width('100%')
                        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                        .backgroundColor(this.lineBg(l.type))
                      }, (l: DiffLine, idx: number) => f.file + ':' + idx.toString() + ':' + l.type)
                    }
                    .width('100%')
                    .padding({ bottom: 8 })
                    .transition(Motion.cardIn())
                  }
                }
                .width('100%')
                .backgroundColor(Theme.glassBg())
                .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
                .borderRadius(Theme.radiusLg)
                .border({ width: 0.5, color: Theme.borderMuted })
                .shadow({ radius: 18, color: Theme.shadowSoft, offsetX: 0, offsetY: 6 })
                .visualEffect(SoftLightSense.card())
                .clip(false)
              }, (f: FileStats) => f.file)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 12, bottom: 20 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .opacity(1)
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  private lineColor(t: string): string {
    return t === '+' ? Theme.accentGreen : (t === '-' ? Theme.accentRed : Theme.textTertiary);
  }

  private lineBg(t: string): string {
    return t === '+' ? Theme.successSoft : (t === '-' ? Theme.dangerSoft : 'transparent');
  }

  private totalAdd(): number {
    let n = 0;
    for (let i = 0; i < this.files.length; i++) {
      n += this.files[i].added;
    }
    return n;
  }

  private totalDel(): number {
    let n = 0;
    for (let i = 0; i < this.files.length; i++) {
      n += this.files[i].removed;
    }
    return n;
  }
}
