import { Part } from '../common/model/Types';
import { Theme } from '../common/Theme';
import { Motion } from '../common/Motion';
import { SoftIconButton, SoftBanner } from '../common/ui/SoftChrome';
import { pasteboard } from '@kit.BasicServicesKit';
import { appStore } from '../data/AppStore';
import { RichTextBlock } from './RichTextBlock';

// markdown 围栏解析出的一个块：普通文本或代码块
export class MarkdownBlock {
  isCode: boolean = false;
  language: string = '';
  content: string = '';
}

// 解析 ```...``` 围栏，把文本拆成一串普通/代码块
function splitMarkdown(text: string): MarkdownBlock[] {
  const out: MarkdownBlock[] = [];
  let rest = text;
  while (true) {
    const openIdx = rest.indexOf('```');
    if (openIdx < 0) {
      if (rest.length > 0) {
        const b = new MarkdownBlock();
        b.content = rest;
        out.push(b);
      }
      break;
    }
    if (openIdx > 0) {
      const b = new MarkdownBlock();
      b.content = rest.substring(0, openIdx);
      out.push(b);
    }
    const afterOpen = rest.substring(openIdx + 3);
    const closeIdx = afterOpen.indexOf('```');
    if (closeIdx < 0) {
      // 未闭合：整段当代码块
      const b = new MarkdownBlock();
      b.isCode = true;
      let code = afterOpen;
      const nl = code.indexOf('\n');
      if (nl >= 0) {
        b.language = code.substring(0, nl).trim();
        b.content = code.substring(nl + 1);
      } else {
        b.content = code;
      }
      out.push(b);
      break;
    }
    const b = new MarkdownBlock();
    b.isCode = true;
    const code = afterOpen.substring(0, closeIdx);
    const nl = code.indexOf('\n');
    if (nl >= 0) {
      b.language = code.substring(0, nl).trim();
      b.content = code.substring(nl + 1);
    } else {
      b.content = code;
    }
    out.push(b);
    rest = afterOpen.substring(closeIdx + 3);
  }
  return out;
}

function copyToClipboard(text: string): void {
  const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
  pasteboard.getSystemPasteboard().setData(data).then(() => {
  }).catch(() => {
  });
}

// 单个文本/推理 part：assistant 走富 Markdown，user 走简洁气泡内文本
@Component
export struct PartTextBlock {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  text: string = '';
  role: string = 'assistant';
  isReasoning: boolean = false;
  isUser: boolean = false;

  private blocks(): MarkdownBlock[] {
    return splitMarkdown(this.text);
  }

  build() {
    if (this.isReasoning) {
      Column() {
        Text('\u601D\u8003')
          .fontSize(10)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.accentTeal)
          .margin({ bottom: 4 })
        Text(this.text)
          .fontSize(12)
          .fontColor(Theme.textSecondary)
          .fontStyle(FontStyle.Italic)
          .lineHeight(18)
          .width('100%')
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .margin({ top: 4, bottom: 6 })
      .backgroundColor(this.darkMode ? 'rgba(45, 212, 191, 0.08)' : 'rgba(15, 155, 142, 0.06)')
      .border({ width: { left: 3 }, color: Theme.accentTeal })
      .borderRadius(Theme.radiusSm)
    } else if (this.isUser) {
      Column({ space: 6 }) {
        ForEach(this.blocks(), (b: MarkdownBlock, idx: number) => {
          if (b.isCode) {
            Column() {
              Row() {
                Text(b.language.length > 0 ? b.language : 'code')
                  .fontSize(11)
                  .fontColor(Theme.textOnAccent)
                  .opacity(0.8)
                  .layoutWeight(1)
                SoftIconButton({
                  icon: $r('sys.media.ohos_ic_public_copy'),
                  btnSize: 24,
                  iconSize: 14,
                  onTap: () => {
                    copyToClipboard(b.content);
                  }
                })
              }
              .width('100%')
              .padding({ left: 10, right: 6, top: 4, bottom: 4 })

              Text(b.content)
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor('#E8EEF7')
                .width('100%')
                .padding({ left: 10, right: 10, top: 6, bottom: 8 })
                .copyOption(CopyOptions.LocalDevice)
            }
            .width('100%')
            .backgroundColor(Theme.codeBg)
            .borderRadius(Theme.radiusSm)
            .margin({ top: 6 })
          } else {
            Text(b.content)
              .fontSize(15)
              .fontColor(Theme.userBubbleText)
              .lineHeight(Theme.lineBody)
              .copyOption(CopyOptions.LocalDevice)
              .margin({ top: 2 })
              .constraintSize({ maxWidth: '100%' })
          }
        }, (b: MarkdownBlock, idx: number) => idx.toString() + ':' + b.isCode.toString() + ':' + b.content.length)
      }
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ maxWidth: '100%' })
    } else {
      RichTextBlock({ content: this.text, isUser: false })
    }
  }
}

// 工具调用块：可折叠，展示工具名 + 状态 + 输入
@Component
export struct PartToolBlock {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @State expanded: boolean = false;
  toolName: string = '';
  state: string = '';
  input: string = '';
  output: string = '';
  startTime: number = 0;
  endTime: number = 0;

  private stateColor(): string {
    if (this.state === 'running' || this.state === 'pending') {
      return Theme.accentOrange;
    }
    if (this.state === 'error') {
      return Theme.accentRed;
    }
    return Theme.accentGreen;
  }

  private stateLabel(): string {
    if (this.state === 'running' || this.state === 'pending') {
      return '\u8FD0\u884C\u4E2D';
    }
    if (this.state === 'error') {
      return '\u5931\u8D25';
    }
    return '\u5B8C\u6210';
  }

  private stateIcon(): string {
    if (this.state === 'running' || this.state === 'pending') {
      return '●';
    }
    if (this.state === 'error') {
      return '✕';
    }
    return '✓';
  }

  private durationLabel(): string {
    if (this.startTime <= 0 || this.endTime <= 0) {
      return '';
    }
    const ms = Math.max(0, Math.round(this.endTime - this.startTime));
    if (ms < 1000) {
      return ms + 'ms';
    }
    return (ms / 1000).toFixed(1) + 's';
  }

  build() {
    Column() {
      Row() {
        Text(this.stateIcon())
          .fontSize(11)
          .fontColor(this.stateColor())
          .margin({ right: 6 })
        Text(this.toolName.length > 0 ? this.toolName : 'Tool')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.durationLabel().length > 0) {
          Text(this.durationLabel())
            .fontSize(10)
            .fontColor(Theme.textTertiary)
            .margin({ left: 6, right: 6 })
        }
        Text(this.stateLabel())
          .fontSize(11)
          .fontColor(this.stateColor())
          .margin({ left: 4, right: 6 })
        Text(this.expanded ? 'v' : '>')
          .fontSize(10)
          .fontColor(Theme.textTertiary)
      }
      .width('100%')
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
      .onClick(() => {
        this.getUIContext().animateTo(Motion.bounceOpt(), () => {
          this.expanded = !this.expanded;
        });
      })

      if (this.expanded) {
        Column({ space: 6 }) {
          if (this.input.length > 0) {
            Text(this.input)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor('#E8EEF7')
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(Theme.codeBg)
              .borderRadius(Theme.radiusSm)
              .wordBreak(WordBreak.BREAK_ALL)
          }
          if (this.output.length > 0) {
            Text(this.output)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor('#E8EEF7')
              .width('100%')
              .padding({ left: 10, right: 10, top: 8, bottom: 8 })
              .backgroundColor(Theme.codeBg)
              .borderRadius(Theme.radiusSm)
              .wordBreak(WordBreak.BREAK_ALL)
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 8 })
        .transition(Motion.cardIn())
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(Theme.bgCard)
    .border({ width: 0.5, color: Theme.borderMuted })
    .borderRadius(Theme.radiusSm)
    .shadow({ radius: 6, color: Theme.shadowSoft, offsetX: 0, offsetY: 2 })
    .margin({ top: 6, bottom: 4 })
  }
}

// 单条消息气泡：用户=右侧深色气泡(maxWidth 76%)，助手=左侧全宽透明 + 模型标签
@Component
export struct MessageBubble {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  messageID: string = '';
  role: string = 'assistant';
  created: number = 0;
  parts: Part[] = [];
  error: string = '';
  modelID: string = '';

  private isUser(): boolean {
    return this.role === 'user';
  }

  private timeLabel(): string {
    if (this.created <= 0) {
      return '';
    }
    const d = new Date(this.created);
    const hh = d.getHours().toString().padStart(2, '0');
    const mm = d.getMinutes().toString().padStart(2, '0');
    return `${hh}:${mm}`;
  }

  private modelShort(): string {
    let name = this.modelID;
    const slash = name.lastIndexOf('/');
    if (slash >= 0) {
      name = name.substring(slash + 1);
    }
    if (name.length > 24) {
      return name.substring(0, 24) + '…';
    }
    return name;
  }

  private visibleParts(): Part[] {
    const out: Part[] = [];
    for (let i = 0; i < this.parts.length; i++) {
      const p = this.parts[i];
      if (p.type === 'step-start' || p.type === 'step-finish' ||
        p.type === 'patch' || p.type === 'file' || p.type === 'snapshot') {
        continue;
      }
      if (p.type === 'text' || p.type === 'reasoning') {
        if (p.text.length === 0) {
          continue;
        }
        out.push(p);
      } else if (p.type === 'tool') {
        out.push(p);
      } else if (p.text.length > 0) {
        out.push(p);
      }
    }
    return out;
  }

  private collectText(): string {
    let tl = '';
    for (let i = 0; i < this.parts.length; i++) {
      const p = this.parts[i];
      if (p.type === 'text' || p.type === 'reasoning') {
        if (p.text.length > 0) {
          tl += p.text + '\n';
        }
      }
    }
    return tl;
  }

  private copyText(): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.collectText());
    pasteboard.getSystemPasteboard().setData(data).then(() => {
      // 复制成功
    }).catch(() => {
    });
  }

  private retryText(): void {
    // 重新发送该消息文本（仅对用户消息有效，重新触发 AI 处理）
    const t = this.collectText();
    if (t.length > 0) {
      appStore.sendMessage(t);
    }
  }

  private truncateAndResend(): void {
    // 删除该消息及之后所有消息，再重发文本
    appStore.truncateAndResend(this.messageID).then(() => {
    }).catch(() => {
    });
  }

  // 助手头部：小标记 + 次级元信息
  @Builder
  assistantHeader() {
    Row({ space: 8 }) {
      Column()
        .width(7)
        .height(7)
        .borderRadius(3.5)
        .backgroundColor(Theme.brandSecondary)
      Text(this.modelShort().length > 0 ? this.modelShort() : 'Assistant')
        .fontSize(Theme.typeCaption)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      if (this.timeLabel().length > 0) {
        Text(this.timeLabel())
          .fontSize(Theme.typeCaption)
          .fontColor(Theme.textTertiary)
      }
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  // 用户气泡内部内容
  @Builder
  userBubbleContent() {
    Column({ space: 2 }) {
      ForEach(this.visibleParts(), (p: Part) => {
        if (p.type === 'tool') {
          PartToolBlock({
            toolName: p.toolName,
            state: p.toolState,
            input: p.toolInput,
            output: p.toolOutput,
            startTime: p.toolStartTime,
            endTime: p.toolEndTime
          })
        } else if (p.type === 'reasoning') {
          PartTextBlock({ text: p.text, role: this.role, isReasoning: true, isUser: true })
        } else {
          PartTextBlock({ text: p.text, role: this.role, isReasoning: false, isUser: true })
        }
      }, (p: Part) => p.id + ':' + p.text.length + ':' + p.toolState)

      if (this.error.length > 0) {
        SoftBanner({
          text: this.error,
          tone: 'danger'
        })
          .margin({ top: 6 })
          .constraintSize({ maxWidth: '100%' })
      }

      if (this.timeLabel().length > 0) {
        Text(this.timeLabel())
          .fontSize(10)
          .fontColor(Theme.textTertiary)
          .alignSelf(ItemAlign.End)
          .margin({ top: 3 })
      }
    }
    .alignItems(HorizontalAlign.Start)
  }

  // 助手消息内部内容
  @Builder
  assistantContent() {
    Column({ space: 6 }) {
      this.assistantHeader()
      ForEach(this.visibleParts(), (p: Part) => {
        if (p.type === 'tool') {
          PartToolBlock({
            toolName: p.toolName,
            state: p.toolState,
            input: p.toolInput,
            output: p.toolOutput,
            startTime: p.toolStartTime,
            endTime: p.toolEndTime
          })
        } else if (p.type === 'reasoning') {
          PartTextBlock({ text: p.text, role: this.role, isReasoning: true, isUser: false })
        } else {
          PartTextBlock({ text: p.text, role: this.role, isReasoning: false, isUser: false })
        }
      }, (p: Part) => p.id + ':' + p.text.length + ':' + p.toolState)

      if (this.error.length > 0) {
        SoftBanner({
          text: this.error,
          tone: 'danger'
        })
          .margin({ top: 6 })
      }

      SoftIconButton({
        icon: $r('sys.media.ohos_ic_public_copy'),
        btnSize: 28,
        iconSize: 14,
        tint: Theme.textTertiary,
        onTap: () => {
          this.copyText();
        }
      })
        .alignSelf(ItemAlign.End)
        .margin({ top: 2 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Row() {
      if (this.isUser()) {
        Column() {
          this.userBubbleContent()
        }
        .constraintSize({ maxWidth: '82%', minWidth: 56 })
        .padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(Theme.userBubble)
        .borderRadius(Theme.radiusLg)
        .shadow(Theme.elev1())
        .alignItems(HorizontalAlign.Start)
        .bindMenu([
          {
            value: '\u590D\u5236',
            action: () => {
              this.copyText();
            }
          },
          {
            value: '\u91CD\u53D1',
            action: () => {
              this.retryText();
            }
          },
          {
            value: '\u4ECE\u6B64\u622A\u65AD\u91CD\u53D1',
            action: () => {
              this.truncateAndResend();
            }
          }
        ])
      } else {
        Column() {
          this.assistantContent()
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 6, bottom: 6 })
        .backgroundColor(Color.Transparent)
        .alignItems(HorizontalAlign.Start)
        .bindMenu([
          {
            value: '\u590D\u5236',
            action: () => {
              this.copyText();
            }
          }
        ])
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 8 })
    .justifyContent(this.isUser() ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Top)
    .transition(Motion.bubbleIn())
  }
}
