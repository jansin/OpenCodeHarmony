import { zenStore, ZEN_DEFAULT_MODEL } from '../data/ZenStore';
import { ZenMessageLine } from '../data/api/ZenStream';
import { Part } from '../common/model/Types';
import { Theme } from '../common/Theme';
import {
  SoftBackButton, SoftChip, SoftSendButton,
  SoftEmptyState, SoftBanner, SoftPageBg
} from '../common/ui/SoftChrome';
import { MessageBubble } from './MessageBubble';
import { WorkingIndicator } from './WorkingIndicator';

@Component
export struct ZenChatView {
  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;
  onBack: (() => void) = () => {};
  onOpenSettings: (() => void) = () => {};

  private scroller: Scroller = new Scroller();

  @State rev: number = 0;
  @State input: string = '';
  @State working: boolean = false;
  @State assistantText: string = '';
  @State assistantReasoning: string = '';
  @State model: string = ZEN_DEFAULT_MODEL;
  @State keyOk: boolean = true;
  @State lastError: string = '';

  private onZen = (): void => {
    this.working = zenStore.working;
    this.assistantText = zenStore.assistantText;
    this.assistantReasoning = zenStore.assistantReasoning;
    this.model = zenStore.model;
    this.keyOk = zenStore.key.length > 0;
    this.lastError = zenStore.lastError;
    this.rev += 1;
    this.scrollToBottom();
  };

  aboutToAppear(): void {
    this.model = zenStore.model;
    this.assistantText = zenStore.assistantText;
    this.assistantReasoning = zenStore.assistantReasoning;
    this.working = zenStore.working;
    this.keyOk = zenStore.key.length > 0;
    this.lastError = zenStore.lastError;
    zenStore.on('zen', this.onZen);
  }

  aboutToDisappear(): void {
    zenStore.off('zen', this.onZen);
  }

  private scrollToBottom(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  private send(): void {
    const txt = this.input.trim();
    if (txt.length === 0) {
      return;
    }
    this.input = '';
    zenStore.send(txt);
  }

  private abort(): void {
    zenStore.abort();
  }

  private partForUser(m: ZenMessageLine): Part {
    const p = new Part();
    p.id = 'z';
    p.type = 'text';
    p.text = m.content;
    return p;
  }

  private partsForAssistant(m: ZenMessageLine): Part[] {
    const out: Part[] = [];
    if (m.content.length > 0) {
      const p = new Part();
      p.id = 'a';
      p.type = 'text';
      p.text = m.content;
      out.push(p);
    }
    return out;
  }

  private isEmpty(): boolean {
    return zenStore.messages.length === 0 && !this.working;
  }

  build() {
    Stack() {
      SoftPageBg()

      Column() {
        Column() {
          Row({ space: 6 }) {
            SoftBackButton({
              onTap: () => {
                this.onBack();
              }
            })
            Text('Zen 对话')
              .fontSize(Theme.typeTitle)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(this.rev.toString())
              .width(1)
              .height(1)
              .opacity(0)

            SoftChip({
              label: '新对话',
              onTap: () => {
                zenStore.resetConversation();
              }
            })

            SoftChip({
              label: '设置',
              onTap: () => {
                this.onOpenSettings();
              }
            })
          }
          .width('100%')
          .height(Theme.topBarH)
          .padding({ left: Theme.spaceSm, right: Theme.spaceSm })
          .backgroundColor(Theme.glassBg())
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .borderRadius(Theme.radiusXl)
          .border({ width: 0.5, color: Theme.glassBorder })
          .shadow(Theme.elev2())
        }
        .width('100%')
        .padding({
          left: Theme.floatInset,
          right: Theme.floatInset,
          top: this.statusBarHeight + 6,
          bottom: 6
        })

      if (this.isEmpty()) {
        Column() {
          SoftEmptyState({
            title: '开始 Zen 对话',
            subtitle: '连接 OpenAI 兼容 API，轻量直聊'
          })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ scroller: this.scroller, space: 8 }) {
          ForEach(zenStore.messages, (m: ZenMessageLine, idx: number) => {
            ListItem() {
              if (m.role === 'user') {
                MessageBubble({
                  messageID: 'zu' + idx,
                  role: 'user',
                  created: 0,
                  parts: [this.partForUser(m)]
                })
              } else {
                MessageBubble({
                  messageID: 'za' + idx,
                  role: 'assistant',
                  created: 0,
                  parts: this.partsForAssistant(m)
                })
              }
            }
          }, (m: ZenMessageLine, idx: number) => idx + ':' + m.content.length)

          if (this.working) {
            ListItem() {
              MessageBubble({
                messageID: 'zt',
                role: 'assistant',
                created: 0,
                parts: this.streamingParts()
              })
            }
            ListItem() {
              Column() {
                WorkingIndicator()
              }
              .width('100%')
              .padding({ left: 16, right: 16 })
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Off)
      }

      if (!this.keyOk) {
        Column() {
          SoftBanner({
            text: '未配置 Zen API Key，请在设置中填写',
            tone: 'warning',
            onTap: () => {
              this.onOpenSettings();
            }
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })
      } else if (this.lastError.length > 0) {
        Column() {
          SoftBanner({
            text: this.lastError,
            tone: 'danger'
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 6 })
      }

      Row() {
        SoftChip({
          label: this.model,
          maxWidth: 220,
          active: true,
          onTap: () => {
            this.onOpenSettings();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ bottom: 8 })

      Column() {
        Row({ space: 8 }) {
          TextInput({ placeholder: '输入消息，回车发送', text: this.input })
            .layoutWeight(1)
            .height(44)
            .fontSize(Theme.typeBody)
            .backgroundColor(Color.Transparent)
            .fontColor(Theme.textPrimary)
            .placeholderColor(Theme.textTertiary)
            .padding({ left: 4, right: 4 })
            .onChange((v: string) => {
              this.input = v;
            })
            .onSubmit((_enterKey: EnterKeyType) => {
              this.send();
            })

          SoftSendButton({
            working: this.working,
            isEnabled: this.keyOk && this.input.trim().length > 0,
            onTap: () => {
              if (this.working) {
                this.abort();
              } else {
                this.send();
              }
            }
          })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .margin({ left: Theme.floatInset, right: Theme.floatInset, bottom: 12 + this.navBarHeight })
      .backgroundColor(Theme.glassBg())
      .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
      .border({ width: 0.5, color: Theme.glassBorder })
      .borderRadius(Theme.radiusXl)
      .shadow(Theme.elev2())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  private streamingParts(): Part[] {
    const out: Part[] = [];
    if (this.assistantReasoning.length > 0) {
      const r = new Part();
      r.id = 'r';
      r.type = 'reasoning';
      r.text = this.assistantReasoning;
      out.push(r);
    }
    if (this.assistantText.length > 0) {
      const p = new Part();
      p.id = 't';
      p.type = 'text';
      p.text = this.assistantText;
      out.push(p);
    }
    if (out.length === 0) {
      const p = new Part();
      p.id = 'w';
      p.type = 'text';
      p.text = '思考中...';
      out.push(p);
    }
    return out;
  }
}
