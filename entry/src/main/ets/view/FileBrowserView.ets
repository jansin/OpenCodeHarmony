import { appStore } from '../data/AppStore';
import { FileNode, FileContent, FileStatusInfo, FindMatch } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { SoftLightSense } from '../common/ui/SoftLightSense';
import {
  SoftBackButton, SoftIconButton, SoftSegment, SoftChip,
  SoftSecondaryButton, SoftEmptyState, SoftBanner
} from '../common/ui/SoftChrome';

const TAG = 'FileBrowser';

// Remote file browser: list + preview + full-text search
@Component
export struct FileBrowserView {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  onBack: (() => void) = () => {};

  @State mode: string = 'browse'; // browse | search
  @State segSel: number[] = [0];
  @State path: string = '';
  @State nodes: FileNode[] = [];
  @State statusMap: Map<string, string> = new Map();
  @State busy: boolean = false;
  @State err: string = '';
  @State viewFile: string = '';
  @State fileContent: FileContent | null = null;
  @State fileBusy: boolean = false;
  @State searchText: string = '';
  @State matches: FindMatch[] = [];
  @State searching: boolean = false;

  aboutToAppear(): void {
    this.loadDir('');
    this.loadStatus();
  }

  private loadDir(p: string): void {
    if (appStore.api === null) {
      this.err = '\u672A\u8FDE\u63A5\u670D\u52A1\u5668';
      return;
    }
    this.busy = true;
    this.err = '';
    this.path = p;
    appStore.api.listFiles(p).then((list: FileNode[]) => {
      this.busy = false;
      const dirs: FileNode[] = [];
      const files: FileNode[] = [];
      for (let i = 0; i < list.length; i++) {
        if (list[i].type === 'directory') {
          dirs.push(list[i]);
        } else {
          files.push(list[i]);
        }
      }
      this.nodes = dirs.concat(files);
    }).catch((e: Error) => {
      this.busy = false;
      this.err = e.message;
      console.warn(TAG + ' listFiles ' + p + ' ' + e.message);
    });
  }

  private loadStatus(): void {
    if (appStore.api === null) {
      return;
    }
    appStore.api.listFileStatus().then((list: FileStatusInfo[]) => {
      const m: Map<string, string> = new Map();
      for (let i = 0; i < list.length; i++) {
        m.set(list[i].path, list[i].status);
      }
      this.statusMap = m;
    }).catch((e: Error) => {
      console.warn(TAG + ' file status ' + e.message);
    });
  }

  private enterDir(n: FileNode): void {
    this.loadDir(n.path);
  }

  private enterFile(n: FileNode): void {
    this.viewFile = n.path;
    this.fileContent = null;
    this.fileBusy = true;
    if (appStore.api === null) {
      this.fileBusy = false;
      return;
    }
    appStore.api.readFile(n.path).then((c: FileContent) => {
      this.fileBusy = false;
      this.fileContent = c;
    }).catch((e: Error) => {
      this.fileBusy = false;
      this.err = e.message;
      console.warn(TAG + ' readFile ' + n.path + ' ' + e.message);
    });
  }

  private goUp(): void {
    if (this.path.length === 0) {
      return;
    }
    const idx = this.path.lastIndexOf('/');
    const parent = idx < 0 ? '' : this.path.substring(0, idx);
    this.loadDir(parent);
  }

  private runSearch(): void {
    const q = this.searchText.trim();
    if (q.length === 0 || appStore.api === null) {
      return;
    }
    this.searching = true;
    this.err = '';
    this.matches = [];
    appStore.api.findText(q).then((list: FindMatch[]) => {
      this.searching = false;
      this.matches = list;
    }).catch((e: Error) => {
      this.searching = false;
      this.err = e.message;
      console.warn(TAG + ' findText ' + e.message);
    });
  }

  private statusBadge(n: FileNode): string {
    if (n.type === 'directory') {
      return '';
    }
    const s = this.statusMap.get(n.path);
    return s === undefined ? '' : s;
  }

  private badgeColor(s: string): string {
    if (s === 'added') {
      return Theme.accentGreen;
    } else if (s === 'modified') {
      return Theme.accentOrange;
    } else if (s === 'deleted') {
      return Theme.accentRed;
    }
    return Theme.textTertiary;
  }

  private shortName(p: string): string {
    const idx = p.lastIndexOf('/');
    return idx < 0 ? p : p.substring(idx + 1);
  }

  private back(): void {
    if (this.viewFile.length > 0) {
      this.viewFile = '';
      this.fileContent = null;
      return;
    }
    if (this.mode === 'search') {
      this.mode = 'browse';
      this.segSel = [0];
      return;
    }
    this.onBack();
  }

  private displayText(c: FileContent): string {
    let t = c.content;
    if (t.length > 200000) {
      t = t.substring(0, 200000) + '\n... (\u5DF2\u622A\u65AD)';
    }
    return t;
  }

  @Builder
  pathBar() {
    Row({ space: 6 }) {
      SoftIconButton({
        icon: $r('sys.media.ohos_ic_public_arrow_up'),
        btnSize: 28,
        iconSize: 12,
        onTap: () => {
          this.goUp();
        }
      })
      Text(this.path.length > 0 ? this.path : '/')
        .fontSize(Theme.typeCaption)
        .fontColor(Theme.textTertiary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8, bottom: 8 })
    .backgroundColor(Theme.glassBg())
    .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
    .visualEffect(SoftLightSense.glass())
    .border({ width: { bottom: 0.5 }, color: Theme.borderMuted })
  }

  @Builder
  fileList() {
    if (this.nodes.length === 0 && !this.busy) {
      Column() {
        SoftEmptyState({
          title: '\u7A7A\u76EE\u5F55',
          subtitle: '\u5F53\u524D\u8DEF\u5F84\u4E0B\u6CA1\u6709\u6587\u4EF6'
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 4 }) {
        ForEach(this.nodes, (n: FileNode) => {
          ListItem() {
            Row({ space: 10 }) {
              SoftChip({
                label: n.type === 'directory' ? 'DIR' : 'FILE',
                active: n.type === 'directory'
              })
              Text(n.name)
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textPrimary)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              if (this.statusBadge(n).length > 0) {
                Text(this.statusBadge(n) === 'modified' ? 'M' : (this.statusBadge(n) === 'added' ? 'A' : 'D'))
                  .fontSize(Theme.typeCaption)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.badgeColor(this.statusBadge(n)))
                  .border({ width: 1, color: this.badgeColor(this.statusBadge(n)) })
                  .borderRadius(Theme.radiusSm)
                  .padding({ left: 5, right: 5, top: 1, bottom: 1 })
              }
            }
            .width('100%')
            .padding({ left: 14, right: 14, top: 11, bottom: 11 })
            .backgroundColor(Theme.glassBg())
            .borderRadius(Theme.radiusSm)
            .visualEffect(SoftLightSense.card())
            .onClick(() => {
              if (n.type === 'directory') {
                this.enterDir(n);
              } else {
                this.enterFile(n);
              }
            })
          }
        }, (n: FileNode) => n.type + n.path)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 8, right: 8 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
  }

  @Builder
  fileView() {
    Column() {
      Row({ space: 8 }) {
        SoftBackButton({
          onTap: () => {
            this.viewFile = '';
            this.fileContent = null;
          }
        })
        Column() {
          Text(this.shortName(this.viewFile))
            .fontSize(Theme.typeBodySm)
            .fontColor(Theme.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(this.viewFile)
            .fontSize(Theme.typeCaption)
            .fontColor(Theme.textTertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height(Theme.topBarH + this.statusBarHeight)
      .padding({ left: Theme.spaceSm, right: Theme.spaceSm, top: this.statusBarHeight })
      .backgroundColor(Theme.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .visualEffect(SoftLightSense.glass())
      .border({ width: { bottom: 0.5 }, color: Theme.borderMuted })

      if (this.fileBusy) {
        Column() {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(Theme.brandPrimary)
            .margin({ bottom: 8 })
          Text('\u8BFB\u53D6\u4E2D...')
            .fontSize(Theme.typeBodySm)
            .fontColor(Theme.textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.fileContent === null) {
        Blank().layoutWeight(1)
      } else if (this.fileContent.type === 'binary') {
        Column() {
          SoftEmptyState({
            title: '\u4E8C\u8FDB\u5236\u6587\u4EF6',
            subtitle: '\u65E0\u6CD5\u76F4\u63A5\u9884\u89C8'
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Text(this.displayText(this.fileContent))
            .fontSize(Theme.typeBodySm)
            .fontColor(Theme.textPrimary)
            .width('100%')
            .padding(14)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.TopStart)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  searchView() {
    Column() {
      Row({ space: 8 }) {
        TextInput({ placeholder: '\u641C\u7D22\u4EE3\u7801...', text: this.searchText })
          .fontSize(Theme.typeBodySm)
          .fontColor(Theme.textPrimary)
          .placeholderColor(Theme.textTertiary)
          .backgroundColor(Theme.bgInput)
          .borderRadius(Theme.radiusSm)
          .layoutWeight(1)
          .height(36)
          .padding({ left: 10, right: 10 })
          .visualEffect(SoftLightSense.soft())
          .onChange((v: string) => {
            this.searchText = v;
          })
        SoftSecondaryButton({
          label: this.searching ? '...' : '\u641C\u7D22',
          stretch: false,
          isEnabled: !this.searching,
          onTap: () => {
            this.runSearch();
          }
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 6 })

      Text('\u5168\u6587\u641C\u7D22\u5F53\u524D\u9879\u76EE\uFF08\u670D\u52A1\u7AEF ripgrep\uFF0C\u6700\u591A 100 \u6761\uFF09')
        .fontSize(Theme.typeCaption)
        .fontColor(Theme.textTertiary)
        .width('100%')
        .padding({ left: 14, bottom: 6 })

      if (this.matches.length === 0 && !this.searching) {
        Column() {
          SoftEmptyState({
            title: this.searchText.length > 0 ? '\u65E0\u5339\u914D\u7ED3\u679C' : '\u641C\u7D22\u4EE3\u7801',
            subtitle: this.searchText.length > 0
              ? '\u8BD5\u8BD5\u5176\u4ED6\u5173\u952E\u8BCD'
              : '\u8F93\u5165\u5173\u952E\u5B57\u641C\u7D22\u9879\u76EE\u6587\u4EF6\u5185\u5BB9'
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 4 }) {
          ForEach(this.matches, (m: FindMatch) => {
            ListItem() {
              Column({ space: 3 }) {
                Row({ space: 8 }) {
                  Text(m.path)
                    .fontSize(Theme.typeBodySm)
                    .fontColor(Theme.brandPrimary)
                    .layoutWeight(1)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text('L' + m.lineNumber.toString())
                    .fontSize(Theme.typeCaption)
                    .fontColor(Theme.textTertiary)
                }
                Text(m.lineText.length > 200 ? m.lineText.substring(0, 200) + '...' : m.lineText)
                  .fontSize(Theme.typeBodySm)
                  .fontColor(Theme.textSecondary)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor(Theme.glassBg())
              .borderRadius(Theme.radiusSm)
              .border({ width: 0.5, color: Theme.borderMuted })
              .visualEffect(SoftLightSense.card())
              .onClick(() => {
                this.viewFile = m.path;
                this.fileContent = null;
                this.fileBusy = true;
                if (appStore.api === null) {
                  this.fileBusy = false;
                  return;
                }
                appStore.api.readFile(m.path).then((c: FileContent) => {
                  this.fileBusy = false;
                  this.fileContent = c;
                }).catch((e: Error) => {
                  this.fileBusy = false;
                  this.err = e.message;
                  console.warn(TAG + ' readFile ' + m.path + ' ' + e.message);
                });
              })
            }
          }, (m: FindMatch) => m.path + ':' + m.lineNumber.toString())
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .layoutWeight(1)
  }

  build() {
    Stack() {
      if (this.viewFile.length > 0) {
        this.fileView()
      } else {
        Column() {
          Row({ space: 8 }) {
            SoftBackButton({
              onTap: () => {
                this.back();
              }
            })
            Text(this.mode === 'search'
              ? '\u641C\u7D22'
              : (this.path.length > 0 ? this.shortName(this.path) : '\u6587\u4EF6'))
              .fontSize(Theme.typeTitle)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
              .layoutWeight(1)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ minWidth: 0 })
          }
          .width('100%')
          .height(Theme.topBarH + this.statusBarHeight)
          .padding({ left: Theme.spaceSm, right: Theme.spaceMd, top: this.statusBarHeight })
          .backgroundColor(Theme.glassBg())
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .visualEffect(SoftLightSense.glass())
          .border({ width: { bottom: 0.5 }, color: Theme.borderMuted })

          SoftSegment({
            left: '\u6D4F\u89C8',
            right: '\u641C\u7D22',
            selected: this.mode === 'search' ? 1 : 0,
            onChange: (i: number) => {
              this.segSel = [i];
              this.mode = i === 0 ? 'browse' : 'search';
            }
          })
          .width('100%')
          .padding({ left: Theme.spaceMd, right: Theme.spaceMd, top: Theme.spaceSm, bottom: Theme.spaceSm })

          if (this.mode === 'search') {
            this.searchView()
          } else {
            this.pathBar()
            this.fileList()
          }

          if (this.busy) {
            Row({ space: 6 }) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(Theme.brandPrimary)
              Text('\u52A0\u8F7D\u4E2D...')
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textTertiary)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ bottom: 8 })
          }

          if (this.err.length > 0) {
            SoftBanner({
              text: this.err,
              tone: 'danger'
            })
              .padding({ left: 16, right: 16, bottom: 8 })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.bgPrimary)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.bgPrimary)
  }
}
