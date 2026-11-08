import { Theme } from '../common/Theme';
import { SoftChip } from '../common/ui/SoftChrome';
import { SoftLightSense } from '../common/ui/SoftLightSense';
import { pasteboard } from '@kit.BasicServicesKit';
import { common, Want } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';

// markdown 行内分段：普通 / 加粗 / 行内代码 / 链接
export class InlineSeg {
  text: string = '';
  bold: boolean = false;
  code: boolean = false;
  link: string = '';
}

// markdown 块级元素：text | code | heading | list | quote | rule
export class TextBlock {
  kind: string = 'text';
  level: number = 0;
  text: string = '';
  segs: InlineSeg[] = [];
}

// 解析结果缓存：消息正文在流式结束后、或其他事件触发的重复 rebuild 中保持不变，
// 用内容做 key 直接命中，避免 41Hz 打字机 / 每次 rev++ 都整段重解析 markdown。
// 打字机期间的中间态子串各不相同，会自然淘汰；cap 防止无限增长。
const blocksCache = new Map<string, TextBlock[]>();
const inlineCache = new Map<string, InlineSeg[]>();
const PARSE_CACHE_MAX = 64;

function cacheBlocks(raw: string, blocks: TextBlock[]): TextBlock[] {
  if (blocksCache.size >= PARSE_CACHE_MAX) {
    let oldest: string | undefined = undefined;
    blocksCache.forEach((_v: TextBlock[], k: string) => {
      if (oldest === undefined) {
        oldest = k;
      }
    });
    if (oldest !== undefined) {
      blocksCache.delete(oldest);
    }
  }
  blocksCache.set(raw, blocks);
  return blocks;
}

function cacheInline(text: string, segs: InlineSeg[]): InlineSeg[] {
  if (inlineCache.size >= PARSE_CACHE_MAX) {
    let oldest: string | undefined = undefined;
    inlineCache.forEach((_v: InlineSeg[], k: string) => {
      if (oldest === undefined) {
        oldest = k;
      }
    });
    if (oldest !== undefined) {
      inlineCache.delete(oldest);
    }
  }
  inlineCache.set(text, segs);
  return segs;
}

// 解析 ```...``` 围栏、标题、列表、引用、分隔线，其余为段落
function parseBlocks(raw: string): TextBlock[] {
  const hit = blocksCache.get(raw);
  if (hit !== undefined) {
    return hit;
  }
  const blocks: TextBlock[] = [];
  const lines = raw.split('\n');
  let codeBuffer: string[] = [];
  let inCode = false;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();
    if (!inCode) {
      if (trimmed.startsWith('```')) {
        inCode = true;
        codeBuffer = [];
        continue;
      }
      const b = new TextBlock();
      if (line.startsWith('### ')) {
        b.kind = 'heading';
        b.level = 3;
        b.text = line.substring(4);
        blocks.push(b);
        continue;
      }
      if (line.startsWith('## ')) {
        b.kind = 'heading';
        b.level = 2;
        b.text = line.substring(3);
        blocks.push(b);
        continue;
      }
      if (line.startsWith('# ')) {
        b.kind = 'heading';
        b.level = 1;
        b.text = line.substring(2);
        blocks.push(b);
        continue;
      }
      if (trimmed === '---' || trimmed === '***' || trimmed === '___') {
        b.kind = 'rule';
        blocks.push(b);
        continue;
      }
      if (trimmed.startsWith('> ')) {
        b.kind = 'quote';
        b.text = line.substring(1).trim();
        blocks.push(b);
        continue;
      }
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        b.kind = 'list';
        b.text = trimmed.substring(2);
        blocks.push(b);
        continue;
      }
      const numbered = /^\d+[.)]\s/.exec(trimmed);
      if (numbered !== null) {
        b.kind = 'list';
        b.text = trimmed.substring(numbered[0].length);
        blocks.push(b);
        continue;
      }
      if (trimmed.length === 0) {
        continue;
      }
      b.kind = 'text';
      b.text = trimmed;
      blocks.push(b);
      continue;
    }
    if (trimmed.startsWith('```')) {
      inCode = false;
      const code = codeBuffer.join('\n');
      const cb = new TextBlock();
      cb.kind = 'code';
      cb.text = code;
      blocks.push(cb);
      continue;
    }
    codeBuffer.push(line);
  }
  if (inCode) {
    const cb = new TextBlock();
    cb.kind = 'code';
    cb.text = codeBuffer.join('\n');
    blocks.push(cb);
  }
  return cacheBlocks(raw, blocks);
}

// 解析粗体 / 行内代码 / 链接
function parseInline(text: string): InlineSeg[] {
  const hit = inlineCache.get(text);
  if (hit !== undefined) {
    return hit;
  }
  const segs: InlineSeg[] = [];
  let i = 0;
  let plain = '';
  const flush = (): void => {
    if (plain.length > 0) {
      const s = new InlineSeg();
      s.text = plain;
      segs.push(s);
      plain = '';
    }
  };
  while (i < text.length) {
    const rest = text.substring(i);
    const codeStart = rest.indexOf('`');
    const boldStart = rest.indexOf('**');
    const linkStart = rest.indexOf('[');
    const candidates: number[] = [];
    if (codeStart >= 0) {
      candidates.push(codeStart);
    }
    if (boldStart >= 0) {
      candidates.push(boldStart);
    }
    if (linkStart >= 0) {
      candidates.push(linkStart);
    }
    if (candidates.length === 0) {
      plain += rest;
      break;
    }
    let next = candidates[0];
    for (let k = 1; k < candidates.length; k++) {
      if (candidates[k] < next) {
        next = candidates[k];
      }
    }
    if (next > 0) {
      plain += rest.substring(0, next);
    }
    const marker = rest.substring(next);
    if (marker.startsWith('`')) {
      flush();
      const end = marker.indexOf('`', 1);
      if (end < 0) {
        plain += marker;
        i += marker.length;
        continue;
      }
      const code = marker.substring(1, end);
      const s = new InlineSeg();
      s.text = code;
      s.code = true;
      segs.push(s);
      i += next + 1 + code.length + 1;
      continue;
    }
    if (marker.startsWith('**')) {
      flush();
      const end = marker.indexOf('**', 2);
      if (end < 0) {
        plain += marker;
        i += marker.length;
        continue;
      }
      const bold = marker.substring(2, end);
      const s = new InlineSeg();
      s.text = bold;
      s.bold = true;
      segs.push(s);
      i += next + 2 + bold.length + 2;
      continue;
    }
    if (marker.startsWith('[')) {
      const close = marker.indexOf(']', 1);
      if (close < 0) {
        plain += marker;
        i += marker.length;
        continue;
      }
      const label = marker.substring(1, close);
      const urlOpen = marker.indexOf('(', close);
      if (urlOpen === close + 1) {
        const urlClose = marker.indexOf(')', close);
        if (urlClose > urlOpen) {
          flush();
          const url = marker.substring(urlOpen + 1, urlClose);
          const s = new InlineSeg();
          s.text = label;
          s.link = url;
          segs.push(s);
          i += next + urlClose + 1;
          continue;
        }
      }
      plain += marker;
      i += marker.length;
      continue;
    }
    plain += marker;
    i += marker.length;
  }
  flush();
  if (segs.length === 0) {
    const s = new InlineSeg();
    s.text = text;
    segs.push(s);
  }
  return cacheInline(text, segs);
}

// 富 Markdown 渲染：标题 / 列表 / 引用 / 分隔线 / 代码块(含复制) / 粗体 / 行内代码 / 链接
@Component
export struct RichTextBlock {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  content: string = '';
  isUser: boolean = false;

  private copyToClipboard(text: string): void {
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    pasteboard.getSystemPasteboard().setData(data).then(() => {
    }).catch(() => {
    });
  }

  private openBrowser(url: string): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    ctx.startAbility(want).then(() => {
    }).catch(() => {
    });
  }

  // 点击含链接的段落：复制 / 浏览器打开
  private onTextClick(segs: InlineSeg[]): void {
    const links: string[] = [];
    for (let i = 0; i < segs.length; i++) {
      if (segs[i].link.length > 0) {
        links.push(segs[i].link);
      }
    }
    if (links.length === 0) {
      return;
    }
    if (links.length === 1) {
      this.linkMenu(links[0]);
      return;
    }
    const shown = Math.min(links.length, 5);
    const raw: promptAction.Button[] = [];
    for (let i = 0; i < shown; i++) {
      const b: promptAction.Button = { text: links[i], color: '#666666' };
      raw.push(b);
    }
    const buttons = raw as [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?];
    this.getUIContext().getPromptAction().showActionMenu({
      title: '选择链接',
      buttons: buttons
    }).then((res) => {
      this.linkMenu(links[res.index]);
    }).catch(() => {
    });
  }

  private linkMenu(url: string): void {
    const raw: promptAction.Button[] = [
      { text: '复制链接', color: '#666666' } as promptAction.Button
    ];
    if (url.startsWith('http://') || url.startsWith('https://')) {
      raw.push({ text: '在浏览器中打开', color: '#666666' } as promptAction.Button);
    }
    const buttons = raw as [promptAction.Button, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?, promptAction.Button?];
    this.getUIContext().getPromptAction().showActionMenu({ title: url, buttons: buttons }).then((res) => {
      if (res.index === 0) {
        this.copyToClipboard(url);
      } else if (res.index === 1) {
        this.openBrowser(url);
      }
    }).catch(() => {
    });
  }

  private textColor(): string {
    if (this.isUser) {
      return '#FFFFFF';
    }
    return this.darkMode ? '#D8D8D8' : '#282828';
  }

  @Builder
  inlineBuild(segs: InlineSeg[], fontSize: number, textAlignEnd: boolean) {
    Text() {
      ForEach(segs, (seg: InlineSeg, segIndex: number) => {
        Span(seg.text)
          .fontSize(seg.code ? fontSize - 1 : fontSize)
          .fontFamily(seg.code ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(seg.code ? (this.isUser ? '#E6EDF3' : (this.darkMode ? '#D6D6D6' : '#303030')) :
            (seg.link.length > 0 ? (this.isUser ? '#B8D8FF' : Theme.accentBlue) :
              (this.isUser ? '#FFFFFF' : (this.darkMode ? '#D8D8D8' : '#282828'))))
          .fontWeight(seg.bold ? FontWeight.Bold : FontWeight.Regular)
          .decoration({
            type: seg.link.length > 0 ? TextDecorationType.Underline : TextDecorationType.None,
            color: seg.link.length > 0 ? (this.isUser ? '#B8D8FF' : Theme.accentBlue) : Color.Transparent
          })
          .backgroundColor(seg.code ? (this.isUser ? Theme.bgHover : Theme.softFill) : Color.Transparent)
      }, (seg: InlineSeg, segIndex: number) => segIndex.toString())
    }
    .fontSize(fontSize)
    .fontColor(this.textColor())
    .width(this.isUser ? 'auto' : '100%')
    .wordBreak(WordBreak.BREAK_ALL)
    .textAlign(textAlignEnd ? TextAlign.End : TextAlign.Start)
    .copyOption(CopyOptions.LocalDevice)
    .onClick(() => {
      this.onTextClick(segs);
    })
  }

  build() {
    Column({ space: 6 }) {
      ForEach(parseBlocks(this.content), (block: TextBlock, index: number) => {
        if (block.kind === 'code') {
          Column({ space: 4 }) {
            Row() {
              Text('code')
                .fontSize(10)
                .fontColor(Theme.textTertiary)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(Theme.softFill)
                .borderRadius(Theme.radiusSm)
              Blank().layoutWeight(1)
              SoftChip({
                label: '\u590D\u5236',
                onTap: () => {
                  this.copyToClipboard(block.text);
                }
              })
            }
            .width('100%')
            Text(block.text)
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.isUser ? Theme.textOnAccent : Theme.textPrimary)
              .width(this.isUser ? 'auto' : '100%')
              .wordBreak(WordBreak.BREAK_ALL)
              .textAlign(this.isUser ? TextAlign.End : TextAlign.Start)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width(this.isUser ? 'auto' : '100%')
          .padding(10)
          .backgroundColor(this.isUser ? Theme.bgHover : Theme.codeBg)
          .borderRadius(Theme.radiusSm)
          .visualEffect(SoftLightSense.card())
        } else if (block.kind === 'heading') {
          Text(block.text)
            .fontSize(block.level === 1 ? 17 : block.level === 2 ? 15 : 14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.textColor())
            .width(this.isUser ? 'auto' : '100%')
            .wordBreak(WordBreak.BREAK_ALL)
            .textAlign(this.isUser ? TextAlign.End : TextAlign.Start)
            .copyOption(CopyOptions.LocalDevice)
        } else if (block.kind === 'list') {
          Row({ space: 6 }) {
            Text('•')
              .fontSize(13)
              .fontColor(this.isUser ? '#D9D9D9' : (this.darkMode ? '#909090' : '#606060'))
            Text(block.text)
              .fontSize(13)
              .fontColor(this.textColor())
              .layoutWeight(1)
              .wordBreak(WordBreak.BREAK_ALL)
              .textAlign(this.isUser ? TextAlign.End : TextAlign.Start)
              .copyOption(CopyOptions.LocalDevice)
          }
          .width(this.isUser ? 'auto' : '100%')
          .alignItems(VerticalAlign.Top)
        } else if (block.kind === 'quote') {
          Text(block.text)
            .fontSize(13)
            .fontStyle(FontStyle.Italic)
            .fontColor(this.isUser ? '#D9D9D9' : (this.darkMode ? '#9A9A9A' : '#666666'))
            .width(this.isUser ? 'auto' : '100%')
            .padding({ left: 8 })
            .border({ width: { left: 3 }, color: this.isUser ? '#9A9A9A' : (this.darkMode ? '#555555' : '#B0B0B0') })
            .wordBreak(WordBreak.BREAK_ALL)
            .textAlign(this.isUser ? TextAlign.End : TextAlign.Start)
            .copyOption(CopyOptions.LocalDevice)
        } else if (block.kind === 'rule') {
          Divider()
            .color(this.isUser ? '#9A9A9A' : (this.darkMode ? '#444444' : '#D0D0D0'))
            .margin({ top: 2, bottom: 2 })
        } else {
          this.inlineBuild(parseInline(block.text), 14, this.isUser)
        }
      }, (block: TextBlock, index: number) => index.toString())
    }
    .width(this.isUser ? 'auto' : '100%')
    .alignItems(this.isUser ? HorizontalAlign.End : HorizontalAlign.Start)
  }
}
