import { appStore } from '../data/AppStore';
import { MessageInfo, Part, Approval, QuestionRequest, QuestionItem, QuestionOption, AttachmentInput } from '../common/model/Types';
import { Theme, projectShortName, projectInitial } from '../common/Theme';
import { Motion } from '../common/Motion';
import {
  SoftBackButton, SoftIconButton, SoftEmptyState, SoftChip,
  SoftPrimaryButton, SoftSecondaryButton, SoftTextButton, SoftBanner,
  SoftSymbolButton, SoftSendButton, SoftJumpPill, SoftPromptCard, SoftPageBg
} from '../common/ui/SoftChrome';
import { MessageBubble } from './MessageBubble';
import { ModelPicker } from './ModelPicker';
import { WorkingIndicator } from './WorkingIndicator';
import { util } from '@kit.ArkTS';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';

const TAG = 'ChatView';

// LazyForEach 数据项：消息元信息 + 内容指纹（用于增量 diff）
class MsgItem {
  id: string = '';
  role: string = 'assistant';
  created: number = 0;
  error: string = '';
  modelID: string = '';
  fp: string = '';
}

// 消息列表数据源：仅对实际变化的最小区间发变更通知，
// 长会话（数百条）时避免整列表重建，滚动/流式更流畅。
class MessageDataSource implements IDataSource {
  private data: MsgItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): MsgItem {
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    this.listeners.push(listener);
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const i = this.listeners.indexOf(listener);
    if (i >= 0) {
      this.listeners.splice(i, 1);
    }
  }

  // 增量更新：公共前缀不变；中间按指纹判变更；尾部删/add
  update(next: MsgItem[]): void {
    const old = this.data;
    const listeners = this.listeners;
    let common = 0;
    while (common < old.length && common < next.length && old[common].fp === next[common].fp) {
      common++;
    }
    const midEnd = Math.min(old.length, next.length);
    for (let i = old.length - 1; i >= midEnd; i--) {
      for (let k = 0; k < listeners.length; k++) {
        listeners[k].onDataDelete(i);
      }
    }
    for (let i = common; i < midEnd; i++) {
      if (old[i].fp !== next[i].fp) {
        for (let k = 0; k < listeners.length; k++) {
          listeners[k].onDataChange(i);
        }
      }
    }
    for (let i = midEnd; i < next.length; i++) {
      for (let k = 0; k < listeners.length; k++) {
        listeners[k].onDataAdd(i);
      }
    }
    this.data = next;
  }

  // 打字机 reveal：按 id 定点重绘单条（每 24ms 只重建该条，不重建全列表）
  notifyChange(id: string): void {
    for (let i = 0; i < this.data.length; i++) {
      if (this.data[i].id === id) {
        for (let k = 0; k < this.listeners.length; k++) {
          this.listeners[k].onDataChange(i);
        }
        return;
      }
    }
  }
}

class ImageSniff {
  ext: string = '';
  mime: string = '';
}

// 通过文件头 magic number 识别图片格式
function sniffImageExt(bytes: Uint8Array): ImageSniff {
  const n = bytes.length;
  const jpeg = n > 2 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
  if (jpeg) {
    const r = new ImageSniff();
    r.ext = 'jpg';
    r.mime = 'image/jpeg';
    return r;
  }
  const png = n > 7 && bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4e && bytes[3] === 0x47;
  if (png) {
    const r = new ImageSniff();
    r.ext = 'png';
    r.mime = 'image/png';
    return r;
  }
  const webp = n > 11 && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50;
  if (webp) {
    const r = new ImageSniff();
    r.ext = 'webp';
    r.mime = 'image/webp';
    return r;
  }
  const gif = n > 3 && bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x38;
  if (gif) {
    const r = new ImageSniff();
    r.ext = 'gif';
    r.mime = 'image/gif';
    return r;
  }
  const def = new ImageSniff();
  def.ext = 'jpg';
  def.mime = 'image/jpeg';
  return def;
}

// 常用 slash 命令补全
const SLASH_COMMANDS: string[] = [
  '/init', '/summarize', '/share', '/compact', '/help'
];

class RevealTarget {
  msgId: string = '';
  partId: string = '';
  fullLen: number = 0;
}

// 会话内搜索命中：跳转 index + 摘要
class SearchHit {
  index: number = 0;
  role: string = 'assistant';
  snippet: string = '';
}

@Component
export struct ChatView {
  @Prop @Watch('onSessionIdChange') sessionID: string = '';
  onOpenSidebar: (() => void) = () => {};
  onNewChat: (() => void) = () => {};
  onOpenDiff: (() => void) = () => {};
  onOpenTodo: (() => void) = () => {};

  @StorageProp('darkMode') darkMode: boolean = Theme.isDark;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navBarHeight') navBarHeight: number = 0;

  private scroller: Scroller = new Scroller();

  @State rev: number = 0;
  @State working: boolean = false;
  @State input: string = '';
  @State approvals: Approval[] = [];
  @State questions: QuestionRequest[] = [];
  @State selectedAnswers: string[] = [];
  @State msgList: MessageInfo[] = [];
  @State modelLabel: string = '';
  @State showModel: boolean = false;
  @State showMode: boolean = false;
  @State agentMode: string = 'build'; // build | plan
  @State sendError: string = '';
  @State title: string = '';
  @State stickToBottom: boolean = true;
  @State showCmd: boolean = false;
  @State showAttach: boolean = false;
  @State attachments: AttachmentInput[] = [];
  @State attachError: string = '';
  @State searchMode: boolean = false;
  @State searchQuery: string = '';
  @State searchHits: SearchHit[] = [];
  // 历史消息分页：是否还有更早可加载 / 是否正在加载
  @State sendPressed: number = 1;
  @State hasMore: boolean = true;
  @State loadingMore: boolean = false;

  // ---- 流式打字机 reveal：轮询把整块文本拉回后，渐进显示还原流式观感 ----
  private revealTimer: number = -1;
  private revealMsgId: string = '';
  private revealPartId: string = '';
  private revealChars: number = 0;
  private revealFullLen: number = 0;
  // LazyForEach 消息数据源
  private msgSrc: MessageDataSource = new MessageDataSource();

  private syncMessages(): void {
    this.msgList = appStore.getMessages();
    this.hasMore = appStore.getHasMoreHistory();
    this.loadingMore = appStore.isLoadingMoreHistory();
    const items: MsgItem[] = [];
    for (let i = 0; i < this.msgList.length; i++) {
      const m = this.msgList[i];
      const it = new MsgItem();
      it.id = m.id;
      it.role = m.role;
      it.created = m.created;
      it.error = m.error;
      it.modelID = m.modelID;
      it.fp = this.keyFor(m);
      items.push(it);
    }
    this.msgSrc.update(items);
    this.working = appStore.working;
    this.rev += 1;
    this.updateReveal();
  }

  private onMessages = (): void => {
    this.syncMessages();
    this.scrollToBottom();
  };

  // 定位正在生成的 assistant 文本部分（首个 text part；仅限尚未结束的消息）
  private revealTarget(): RevealTarget | null {
    let latest: MessageInfo | null = null;
    for (let i = 0; i < this.msgList.length; i++) {
      const m = this.msgList[i];
      if (m.role !== 'assistant') {
        continue;
      }
      // 进行中：finish/error 均为空
      if (m.finish.length > 0 || m.error.length > 0) {
        continue;
      }
      if (latest === null || m.created >= latest.created) {
        latest = m;
      }
    }
    if (latest === null) {
      return null;
    }
    const parts = appStore.getParts(latest.id);
    for (let i = 0; i < parts.length; i++) {
      if (parts[i].type === 'text' && parts[i].text.length > 0) {
        const t = new RevealTarget();
        t.msgId = latest.id;
        t.partId = parts[i].id;
        t.fullLen = parts[i].text.length;
        return t;
      }
    }
    return null;
  }

  // 消息已终态：直接整块显示；否则推进打字机
  private updateReveal(): void {
    const t = this.revealTarget();
    if (t === null) {
      // 无进行中的目标（消息已完成 / 被 abort / 出错 / 被清空）：
      // 立即停表并复位，避免残留定时器把已终止的消息"继续打字"，
      // 表现为 PC 已停止而手机端仍在流式。
      this.stopReveal();
      this.msgSrc.notifyChange(this.revealMsgId);
      this.revealMsgId = '';
      this.revealPartId = '';
      this.revealChars = 0;
      this.revealFullLen = 0;
      this.rev += 1;
      return;
    }
    if (t.msgId !== this.revealMsgId) {
      this.revealMsgId = t.msgId;
      this.revealPartId = t.partId;
      this.revealChars = 0;
    }
    // 结束/出错/非工作中 → 立即显示全文
    const finished = !this.working;
    if (finished) {
      this.revealChars = t.fullLen;
      this.revealFullLen = t.fullLen;
      this.stopReveal();
      this.rev += 1;
      this.msgSrc.notifyChange(this.revealMsgId);
      return;
    }
    // 目标变长，更新字段让运行中的定时器继续推进
    if (t.fullLen > this.revealFullLen) {
      this.revealFullLen = t.fullLen;
    }
    if (this.revealTimer < 0) {
      this.startReveal(this.revealFullLen);
    }
  }

  private startReveal(target: number): void {
    // 步长更大、间隔略增：减少主线程压力，流式更顺
    const step = Math.max(8, Math.ceil(target / 36));
    const tick = () => {
      if (this.revealFullLen <= this.revealChars) {
        this.revealChars = this.revealFullLen;
        this.rev += 1;
        this.msgSrc.notifyChange(this.revealMsgId);
        this.stopReveal();
        return;
      }
      const targetNow = this.revealFullLen;
      if (this.revealChars + step >= targetNow) {
        this.revealChars = targetNow;
      } else {
        this.revealChars += step;
      }
      this.rev += 1;
      this.msgSrc.notifyChange(this.revealMsgId);
      this.scrollToBottom();
      this.revealTimer = setTimeout(tick, 32);
    };
    this.revealTimer = setTimeout(tick, 32);
  }

  private stopReveal(): void {
    if (this.revealTimer >= 0) {
      clearTimeout(this.revealTimer);
      this.revealTimer = -1;
    }
  }

  private onStatus = (): void => {
    this.working = appStore.working;
    this.sendError = appStore.lastError;
    this.rev += 1;
    this.updateReveal();
  };

  private onApprovals = (): void => {
    this.approvals = appStore.getApprovals();
    this.rev += 1;
    this.scrollToBottom();
  };

  private onQuestions = (): void => {
    this.questions = appStore.getQuestions();
    this.selectedAnswers = [];
    this.rev += 1;
    this.scrollToBottom();
  };

  private onModel = (): void => {
    this.modelLabel = appStore.currentModelLabel();
  };

  private onTitle = (): void => {
    this.title = appStore.getSessionTitle();
    this.rev += 1;
  };

  aboutToAppear(): void {
    this.working = appStore.working;
    this.modelLabel = appStore.currentModelLabel();
    this.agentMode = appStore.currentAgent;
    this.approvals = appStore.getApprovals();
    this.questions = appStore.getQuestions();
    this.msgList = appStore.getMessages();
    appStore.on('messages', this.onMessages);
    appStore.on('status', this.onStatus);
    appStore.on('approvals', this.onApprovals);
    appStore.on('questions', this.onQuestions);
    appStore.on('model', this.onModel);
    appStore.on('title', this.onTitle);
    // 远程焦点跟随可能已打开该会话，避免重复加载/回写焦点
    if (this.sessionID.length > 0 && appStore.currentSessionId !== this.sessionID) {
      appStore.openSession(this.sessionID);
    } else if (this.sessionID.length > 0) {
      this.syncMessages();
      this.title = appStore.getSessionTitle();
    }
  }

  aboutToDisappear(): void {
    appStore.off('messages', this.onMessages);
    appStore.off('status', this.onStatus);
    appStore.off('approvals', this.onApprovals);
    appStore.off('questions', this.onQuestions);
    appStore.off('model', this.onModel);
    appStore.off('title', this.onTitle);
    this.stopReveal();
  }

  private onSessionIdChange(): void {
    if (this.sessionID.length === 0) {
      return;
    }
    this.stopReveal();
    this.revealMsgId = '';
    this.revealPartId = '';
    this.revealChars = 0;
    this.revealFullLen = 0;
    this.input = '';
    this.approvals = [];
    this.questions = [];
    this.selectedAnswers = [];
    this.msgList = [];
    if (appStore.currentSessionId !== this.sessionID) {
      appStore.openSession(this.sessionID);
    } else {
      this.syncMessages();
      this.title = appStore.getSessionTitle();
    }
    this.rev += 1;
  }

  private partsFor(id: string): Part[] {
    const parts = appStore.getParts(id);
    if (id !== this.revealMsgId || this.revealPartId.length === 0 || this.revealChars <= 0) {
      return parts;
    }
    // 流式 reveal：只对当前正在生成的文本 part 截断，其余原样返回
    const out: Part[] = [];
    for (let i = 0; i < parts.length; i++) {
      const p = parts[i];
      if (p.id === this.revealPartId && p.type === 'text') {
        if (this.revealChars < p.text.length) {
          const cp = new Part();
          cp.id = p.id;
          cp.type = p.type;
          cp.text = p.text.substring(0, this.revealChars);
          cp.toolName = p.toolName;
          cp.toolInput = p.toolInput;
          cp.toolOutput = p.toolOutput;
          cp.toolState = p.toolState;
          cp.toolTitle = p.toolTitle;
          cp.toolStartTime = p.toolStartTime;
          cp.toolEndTime = p.toolEndTime;
          cp.filePath = p.filePath;
          out.push(cp);
          continue;
        }
      }
      out.push(p);
    }
    return out;
  }

  private keyFor(m: MessageInfo): string {
    const ps = appStore.getParts(m.id);
    let key = m.id + ':' + m.error.length;
    for (let i = 0; i < ps.length; i++) {
      key += '|' + ps[i].id + ':' + ps[i].text.length + ':' + ps[i].toolState + ':' + ps[i].toolOutput.length;
    }
    // reveal 进度参与 key，保证打字机逐字重绘
    if (m.id === this.revealMsgId) {
      key += '#r' + this.revealChars.toString();
    }
    return key;
  }

  private pickImages(): void {
    const p = new photoAccessHelper.PhotoViewPicker();
    const opt = new photoAccessHelper.PhotoSelectOptions();
    opt.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    opt.maxSelectNumber = 4;
    p.select(opt).then((res: photoAccessHelper.PhotoSelectResult) => {
      this.showAttach = false;
      const uris = res.photoUris;
      const tasks: Promise<void>[] = [];
      for (let i = 0; i < uris.length; i++) {
        tasks.push(this.addImageAttachment(uris[i]));
      }
      Promise.all(tasks).then(() => {
      }).catch(() => {
      });
    }).catch((e: Error) => {
      this.attachError = '\u9009\u62E9\u56FE\u7247\u5931\u8D25';
      console.warn(TAG + ' photo picker ' + e.message);
    });
  }

  private addImageAttachment(uri: string): Promise<void> {
    return new Promise<void>((resolve) => {
      try {
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(uri);
        const n = stat.size;
        const buf = new ArrayBuffer(n);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        const bytes = new Uint8Array(buf);
        const ext = sniffImageExt(bytes);
        const a = new AttachmentInput();
        a.filename = 'photo_' + Date.now().toString() + '.' + ext.ext;
        a.mime = ext.mime;
        a.content = 'data:' + ext.mime + ';base64,' + new util.Base64Helper().encodeToStringSync(bytes);
        a.isImage = true;
        this.attachments = this.attachments.concat([a]);
        this.attachError = '';
        resolve();
      } catch (e) {
        this.attachError = e instanceof Error ? e.message : '读取图片失败';
        console.warn(TAG + ' read image ' + this.attachError);
        resolve();
      }
    });
  }

  private pickFiles(): void {
    const dp = new picker.DocumentViewPicker();
    const opt = new picker.DocumentSelectOptions();
    opt.maxSelectNumber = 3;
    dp.select(opt).then((uris: string[]) => {
      this.showAttach = false;
      const tasks: Promise<void>[] = [];
      for (let i = 0; i < uris.length; i++) {
        tasks.push(this.addTextAttachment(uris[i]));
      }
      Promise.all(tasks).then(() => {
      }).catch(() => {
      });
    }).catch((e: Error) => {
      this.attachError = '选择文件失败';
      console.warn(TAG + ' doc picker ' + e.message);
    });
  }

  private addTextAttachment(uri: string): Promise<void> {
    return new Promise<void>((resolve) => {
      try {
        const stat = fs.statSync(uri);
        if (stat.size > 512 * 1024) {
          this.attachError = '文本文件超过 512KB，请手动摘要后发送';
          resolve();
          return;
        }
        const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        const buf = new ArrayBuffer(stat.size);
        fs.readSync(file.fd, buf);
        fs.closeSync(file.fd);
        const bytes = new Uint8Array(buf);
        const txt = this.bytesToText(bytes);
        const name = uri.substring(uri.lastIndexOf('/') + 1);
        const a = new AttachmentInput();
        a.filename = name.length > 0 ? name : 'file_' + Date.now().toString() + '.txt';
        a.mime = 'text/plain';
        a.content = txt;
        a.isImage = false;
        this.attachments = this.attachments.concat([a]);
        this.attachError = '';
        resolve();
      } catch (e) {
        this.attachError = e instanceof Error ? e.message : '读取文件失败';
        console.warn(TAG + ' read doc ' + this.attachError);
        resolve();
      }
    });
  }

  private bytesToText(bytes: Uint8Array): string {
    const decoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(bytes);
  }

  private removeAttachment(idx: number): void {
    const next = this.attachments.slice();
    next.splice(idx, 1);
    this.attachments = next;
  }

  private send(): void {
    const txt = this.input.trim();
    if (txt.length === 0 && this.attachments.length === 0) {
      return;
    }
    const att = this.attachments.length > 0 ? this.attachments : null;
    this.input = '';
    this.sendError = '';
    this.stickToBottom = true;
    // sendMessage 在首个 await 前会同步写入乐观消息
    const pending = appStore.sendMessage(txt, att);
    this.attachments = [];
    this.syncMessages();
    this.scrollToBottom();
    pending.then(() => {
      this.sendError = appStore.lastError;
      this.syncMessages();
      this.scrollToBottom();
    });
  }

  private pickCmd(c: string): void {
    this.input = c;
    this.showCmd = false;
    this.send();
  }

  private toggleAnswer(label: string, multiple: boolean): void {
    if (!multiple) {
      this.selectedAnswers = [label];
      return;
    }
    const idx = this.selectedAnswers.indexOf(label);
    if (idx >= 0) {
      const next = this.selectedAnswers.slice();
      next.splice(idx, 1);
      this.selectedAnswers = next;
    } else {
      this.selectedAnswers = this.selectedAnswers.concat([label]);
    }
  }

  private submitQuestion(q: QuestionRequest): void {
    if (this.selectedAnswers.length === 0 || q.questions.length === 0) {
      return;
    }
    const answers: string[][] = [this.selectedAnswers.slice()];
    this.selectedAnswers = [];
    appStore.replyQuestion(q.id, answers).then(() => {
      this.questions = appStore.getQuestions();
      this.working = appStore.working;
      this.rev += 1;
    });
  }

  private abort(): void {
    this.getUIContext().showAlertDialog({
      title: '停止生成',
      message: '确定要中止当前任务吗？',
      autoCancel: true,
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '停止',
        fontColor: Theme.accentRed,
        action: () => {
          // 立刻关思考条，不等服务端往返；AppStore.abortLatch 防止轮询拉回
          this.working = false;
          this.stopReveal();
          this.rev += 1;
          appStore.abort().then(() => {
            this.working = appStore.working;
            this.syncMessages();
            this.rev += 1;
          });
        }
      }
    });
  }

  // 滚动合并标记：流式/打字机高频触发时，只保留一个待执行的滚动
  private scrollPending: boolean = false;

  private scrollToBottom(): void {
    if (!this.stickToBottom) {
      return;
    }
    if (this.scrollPending) {
      return;
    }
    this.scrollPending = true;
    setTimeout(() => {
      this.scrollPending = false;
      this.scroller.scrollEdge(Edge.Bottom);
    }, 100);
  }

  private listItemCount(): number {
    // 0: 加载更早消息入口(有消息时); 之后是消息; 空会话是空状态; 最后可能是 working 指示器
    let count = 0;
    if (this.msgList.length > 0) {
      count += 1;
    }
    if (this.msgList.length === 0 && this.questions.length === 0) {
      count += 1;
    } else {
      count += this.msgList.length;
    }
    if (this.working && this.questions.length === 0 && this.approvals.length === 0) {
      count += 1;
    }
    return count;
  }

  // 上翻到列表顶部时自动加载更早历史（入口可见 + 未在加载 + 还有更多）
  private triggerLoadMore(): void {
    if (!this.hasMore || this.loadingMore) {
      return;
    }
    if (this.msgList.length === 0) {
      return;
    }
    appStore.loadMoreHistory().then(() => {
    }).catch(() => {
    });
  }

  private onListScroll(startIndex: number, endIndex: number): void {
    // 用户上翻查看历史时停止自动跳底；滚回底部恢复跟随
    this.stickToBottom = endIndex >= this.listItemCount() - 1;
    if (startIndex <= 0) {
      // 延迟一拍：等滚动布局稳定再触发，避免初始布局时误加载
      setTimeout(() => {
        this.triggerLoadMore();
      }, 120);
    }
  }

  private jumpToLatest(): void {
    this.stickToBottom = true;
    this.scrollToBottom();
  }

  private onPick(_providerID: string, _modelID: string): void {
    this.modelLabel = appStore.currentModelLabel();
    this.showModel = false;
  }

  private projectName(): string {
    if (appStore.currentProject !== null) {
      return projectShortName(appStore.currentProject.directory);
    }
    return 'OpenCode';
  }

  private projectPath(): string {
    if (appStore.currentProject !== null && appStore.currentProject.directory.length > 0) {
      return appStore.currentProject.directory;
    }
    return '';
  }

  private currentModelShort(): string {
    // 手动选过模型：直接用当前选中的模型
    if (appStore.currentModelID.length > 0) {
      return appStore.modelDisplayName(appStore.currentProviderID, appStore.currentModelID);
    }
    // 未手动选过：回退到当前会话最新 assistant 消息实际使用的模型
    for (let i = this.msgList.length - 1; i >= 0; i--) {
      const m = this.msgList[i];
      if (m.role === 'assistant' && m.modelID.length > 0) {
        return appStore.modelDisplayName(m.providerID, m.modelID);
      }
    }
    return '模型';
  }

  private quickAsk(text: string): void {
    this.input = text;
    this.send();
  }

  private toggleSearch(): void {
    this.searchMode = !this.searchMode;
    if (!this.searchMode) {
      this.searchQuery = '';
      this.searchHits = [];
    } else {
      this.doSearch();
    }
  }

  private doSearch(): void {
    const q = this.searchQuery.trim().toLowerCase();
    if (q.length === 0) {
      this.searchHits = [];
      return;
    }
    const hits: SearchHit[] = [];
    for (let i = 0; i < this.msgList.length; i++) {
      const m = this.msgList[i];
      const ps = appStore.getParts(m.id);
      for (let k = 0; k < ps.length; k++) {
        const p = ps[k];
        if (p.type !== 'text' && p.type !== 'reasoning') {
          continue;
        }
        const low = p.text.toLowerCase();
        const idx = low.indexOf(q);
        if (idx < 0) {
          continue;
        }
        const hit = new SearchHit();
        hit.index = i;
        hit.role = m.role;
        const start = Math.max(0, idx - 20);
        const len = Math.min(p.text.length - start, 60);
        let snip = p.text.substring(start, start + len);
        if (start > 0) {
          snip = '…' + snip;
        }
        if (start + len < p.text.length) {
          snip += '…';
        }
        hit.snippet = snip;
        hits.push(hit);
        break;
      }
    }
    this.searchHits = hits;
  }

  private jumpToHit(index: number): void {
    this.scroller.scrollToIndex(index);
  }

  build() {
    Stack() {
      SoftPageBg()

      Column() {
        // 顶栏：Spatial 悬浮玻璃
        Column() {
          Row() {
            SoftBackButton({
              useDrawerIcon: true,
              onTap: () => {
                this.onOpenSidebar();
              }
            })
            if (this.searchMode) {
              TextInput({ placeholder: '\u641C\u7D22\u672C\u4F1A\u8BDD\u2026', text: this.searchQuery })
                .layoutWeight(1)
                .height(36)
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textPrimary)
                .placeholderColor(Theme.textTertiary)
                .backgroundColor(Theme.softFill)
                .borderRadius(Theme.radiusSm)
                .margin({ left: Theme.spaceSm, right: Theme.spaceSm })
                .onChange((v: string) => {
                  this.searchQuery = v;
                  this.doSearch();
                })
            } else {
              Text(this.title.length > 0 ? this.title : 'OpenCode')
                .fontSize(Theme.typeTitle)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .opacity(0.92)
            }
            Row({ space: 2 }) {
              if (this.searchMode) {
                SoftTextButton({
                  label: '\u5B8C\u6210',
                  onTap: () => {
                    this.toggleSearch();
                  }
                })
              } else {
                SoftSymbolButton({
                  symbol: $r('sys.symbol.magnifyingglass'),
                  onTap: () => {
                    this.toggleSearch();
                  }
                })
                SoftIconButton({
                  icon: $r('sys.media.ohos_ic_public_add'),
                  onTap: () => {
                    this.onNewChat();
                  }
                })
              }
            }
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

        // 隐藏依赖：触发流式重绘
        Text(this.rev.toString())
          .width(1)
          .height(1)
          .opacity(0)

        // 会话内搜索结果：点按跳转到对应消息
        if (this.searchMode) {
          Column() {
            if (this.searchHits.length === 0) {
              Text(this.searchQuery.trim().length === 0 ? '输入关键字搜索本会话' : '没有匹配的消息')
                .fontSize(Theme.typeBodySm)
                .fontColor(Theme.textTertiary)
                .padding({ top: 10, bottom: 10 })
            } else {
              Row() {
                Text('命中 ' + this.searchHits.length.toString() + ' 条')
                  .fontSize(Theme.typeCaption)
                  .fontColor(Theme.brandPrimary)
                Blank()
                Text('点击跳转')
                  .fontSize(Theme.typeCaption)
                  .fontColor(Theme.textTertiary)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 8, bottom: 4 })

              Scroll() {
                Column({ space: 4 }) {
                  ForEach(this.searchHits, (hit: SearchHit, idx: number) => {
                    Row({ space: 8 }) {
                      Text(hit.role === 'user' ? '你' : 'AI')
                        .fontSize(Theme.typeCaption)
                        .fontColor(Color.White)
                        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                        .backgroundColor(hit.role === 'user' ? Theme.accentGreen : Theme.accentPurple)
                        .borderRadius(Theme.radiusSm)
                      Text(hit.snippet)
                        .fontSize(Theme.typeBodySm)
                        .fontColor(Theme.textPrimary)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .layoutWeight(1)
                    }
                    .width('100%')
                    .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                    .backgroundColor(Theme.softFill)
                    .borderRadius(Theme.radiusSm)
                    .border({ width: 0.5, color: Theme.borderMuted })
                    .onClick(() => {
                      this.jumpToHit(hit.index);
                    })
                  }, (hit: SearchHit, idx: number) => idx.toString())
                }
                .width('100%')
                .padding({ left: 12, right: 12, bottom: 8 })
              }
              .constraintSize({ maxHeight: 220 })
              .scrollBar(BarState.Off)
            }
          }
          .width('100%')
          .backgroundColor(Theme.glassBg())
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: { bottom: 0.5 }, color: Theme.borderMuted })
        }

        List({ scroller: this.scroller, space: 4 }) {
          if (this.msgList.length > 0) {
            ListItem() {
              this.loadMoreItem()
            }
          }

          if (this.msgList.length === 0 && this.questions.length === 0) {
            ListItem() {
              Column({ space: Theme.spaceMd }) {
                SoftEmptyState({
                  title: '\u5F00\u59CB\u65B0\u5BF9\u8BDD',
                  subtitle: '\u5199\u4EE3\u7801\u3001\u8C03\u8BD5\u3001\u4F18\u5316\u2014\u2014\u76F4\u63A5\u8BF4'
                })

                Row({ space: 10 }) {
                  SoftPromptCard({
                    title: '\u5199 API',
                    subtitle: '\u5E2E\u6211\u5199\u4E00\u4E2A REST API',
                    onTap: () => {
                      this.quickAsk('\u5E2E\u6211\u5199\u4E00\u4E2A REST API');
                    }
                  })
                    .layoutWeight(1)
                  SoftPromptCard({
                    title: '\u4F18\u5316\u4EE3\u7801',
                    subtitle: '\u5E2E\u6211\u4F18\u5316\u8FD9\u6BB5\u4EE3\u7801',
                    onTap: () => {
                      this.quickAsk('\u5E2E\u6211\u4F18\u5316\u8FD9\u6BB5\u4EE3\u7801');
                    }
                  })
                    .layoutWeight(1)
                }
                .width('100%')
                .margin({ top: Theme.spaceLg })
                Row({ space: 10 }) {
                  SoftPromptCard({
                    title: '\u89E3\u91CA\u4EE3\u7801',
                    subtitle: '\u5E2E\u6211\u89E3\u91CA\u8FD9\u6BB5\u4EE3\u7801',
                    onTap: () => {
                      this.quickAsk('\u5E2E\u6211\u89E3\u91CA\u8FD9\u6BB5\u4EE3\u7801');
                    }
                  })
                    .layoutWeight(1)
                  SoftPromptCard({
                    title: '\u5199\u6D4B\u8BD5',
                    subtitle: '\u5E2E\u6211\u5199\u5355\u5143\u6D4B\u8BD5',
                    onTap: () => {
                      this.quickAsk('\u5E2E\u6211\u5199\u5355\u5143\u6D4B\u8BD5');
                    }
                  })
                    .layoutWeight(1)
                }
                .width('100%')
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 48, bottom: 24 })
              .opacity(1)
            }
          }

          LazyForEach(this.msgSrc, (item: MsgItem, index: number) => {
            ListItem() {
              MessageBubble({
                messageID: item.id,
                role: item.role,
                created: item.created,
                parts: this.partsFor(item.id),
                error: item.error,
                modelID: item.modelID
              })
            }
          }, (item: MsgItem, index: number) => index.toString())

          if (this.working && this.questions.length === 0 && this.approvals.length === 0) {
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
        .backgroundColor(Color.Transparent)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .onScrollIndex((startIndex: number, endIndex: number) => {
          this.onListScroll(startIndex, endIndex);
        })

        if (this.sendError === 'disconnected') {
          Column() {
            SoftBanner({
              text: '\u4E0E\u670D\u52A1\u5668\u8FDE\u63A5\u4E2D\u65AD\uFF0C\u6B63\u5728\u81EA\u52A8\u91CD\u8FDE\u2026',
              tone: 'warning'
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        } else if (this.sendError.length > 0) {
          Row({ space: 8 }) {
            Column() {
              SoftBanner({
                text: this.sendError,
                tone: 'danger'
              })
            }
            .layoutWeight(1)
            SoftChip({
              label: '\u91CD\u8BD5',
              onTap: () => {
                if (this.sendError === 'disconnected' || !appStore.connected) {
                  appStore.autoConnect();
                } else {
                  appStore.startStream();
                }
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
        }

        ForEach(this.questions, (q: QuestionRequest) => {
          Column({ space: 8 }) {
            ForEach(q.questions, (item: QuestionItem, qi: number) => {
              Column({ space: 6 }) {
                if (item.header.length > 0) {
                  Text(item.header)
                    .fontSize(Theme.typeBodySm)
                    .fontColor(Theme.brandPrimary)
                    .fontWeight(FontWeight.Medium)
                }
                Text(item.question)
                  .fontSize(Theme.typeBody)
                  .fontColor(Theme.textPrimary)
                  .width('100%')
                ForEach(item.options, (opt: QuestionOption) => {
                  Row() {
                    Text(this.selectedAnswers.indexOf(opt.label) >= 0 ? '● ' : '○ ')
                      .fontSize(Theme.typeBody)
                      .fontColor(Theme.brandPrimary)
                    Column() {
                      Text(opt.label)
                        .fontSize(Theme.typeBodySm)
                        .fontColor(Theme.textPrimary)
                      if (opt.description.length > 0) {
                        Text(opt.description)
                          .fontSize(Theme.typeCaption)
                          .fontColor(Theme.textSecondary)
                          .margin({ top: 2 })
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding(Theme.spaceSm)
                  .borderRadius(Theme.radiusSm)
                  .backgroundColor(this.selectedAnswers.indexOf(opt.label) >= 0 ?
                    Theme.infoSoft : Theme.softFill)
                  .onClick(() => {
                    this.toggleAnswer(opt.label, item.multiple);
                  })
                }, (opt: QuestionOption) => q.id + '_' + qi + '_' + opt.label)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }, (item: QuestionItem, qi: number) => q.id + '_qi_' + qi.toString())

            SoftPrimaryButton({
              label: '\u63D0\u4EA4\u56DE\u7B54',
              isEnabled: this.selectedAnswers.length > 0,
              onTap: () => {
                this.submitQuestion(q);
              }
            })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(Theme.bgCard)
          .border({ width: 0.5, color: Theme.brandPrimary })
          .borderRadius(Theme.radiusLg)
          .margin({ left: 16, right: 16, bottom: 8 })
          .shadow({ radius: 12, color: Theme.shadowSoft, offsetX: 0, offsetY: 4 })
          .transition(Motion.cardIn())
        }, (q: QuestionRequest) => q.id)

        // 输入区
        Column() {
          Row({ space: 6 }) {
            SoftChip({
              label: 'Diff',
              onTap: () => {
                this.onOpenDiff();
              }
            })
            SoftChip({
              label: 'Todo',
              onTap: () => {
                this.onOpenTodo();
              }
            })
            Blank()
            SoftChip({
              label: this.currentModelShort(),
              maxWidth: 120,
              onTap: () => {
                this.showModel = true;
              }
            })
            SoftChip({
              label: this.agentMode === 'build' ? 'Build' : 'Plan',
              active: true,
              maxWidth: 88,
              onTap: () => {
                this.showMode = true;
              }
            })
          }
          .width('100%')
          .padding({ left: 2, right: 2, bottom: 10 })
          .clip(false)

          Column() {
            TextArea({ placeholder: '\u95EE\u4EFB\u4F55\u5173\u4E8E\u4EE3\u7801\u7684\u95EE\u9898\u2026', text: this.input })
              .height(48)
              .fontSize(Theme.typeBody)
              .fontColor(Theme.textPrimary)
              .placeholderColor(Theme.textTertiary)
              .backgroundColor(Color.Transparent)
              .padding({ left: 4, right: 4, top: 6 })
              .onChange((v: string) => {
                this.input = v;
                this.showCmd = v.length > 0 && v.charAt(0) === '/';
              })
              .onKeyEvent((ev: KeyEvent) => {
                // 回车键（2039）按下即发送；手机软键盘回车默认也是此值
                if (ev.type === KeyType.Down && ev.keyCode === 2039) {
                  this.send();
                  return true;
                }
                return false;
              })

            if (this.showCmd) {
              Column() {
                ForEach(SLASH_COMMANDS, (c: string) => {
                  Row() {
                    Text(c)
                      .fontSize(13)
                      .fontColor(Theme.accentBlue)
                      .fontWeight(FontWeight.Medium)
                    Blank()
                    Text('使用')
                      .fontSize(11)
                      .fontColor(Theme.textTertiary)
                  }
                  .width('100%')
                  .padding({ left: 10, right: 10, top: 9, bottom: 9 })
                  .onClick(() => {
                    this.pickCmd(c);
                  })
                  .border({ width: { bottom: 0.5 }, color: Theme.border })
                }, (c: string) => c)
              }
              .borderRadius(10)
              .backgroundColor(Theme.bgPrimary)
              .border({ width: 0.5, color: Theme.border })
              .margin({ top: 6 })
            }

            if (this.attachments.length > 0) {
              Row({ space: 6 }) {
                ForEach(this.attachments, (a: AttachmentInput, idx: number) => {
                  Row({ space: 4 }) {
                    Text(a.isImage ? '\u56FE' : '\u6587')
                      .fontSize(10)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Theme.brandPrimary)
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .backgroundColor(Theme.infoSoft)
                      .borderRadius(4)
                    Text(a.filename)
                      .fontSize(11)
                      .fontColor(Theme.textSecondary)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Button() {
                      Image($r('sys.media.ohos_ic_public_remove_filled'))
                        .width(12)
                        .height(12)
                        .fillColor(Theme.textSecondary)
                    }
                    .type(ButtonType.Circle)
                    .width(20)
                    .height(20)
                    .backgroundColor(Theme.softFill)
                    .onClick(() => {
                      this.removeAttachment(idx);
                    })
                  }
                  .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  .backgroundColor(Theme.bgTertiary)
                  .borderRadius(12)
                  .constraintSize({ maxWidth: '60%' })
                }, (a: AttachmentInput) => a.filename + a.content.length.toString())
              }
              .width('100%')
              .padding({ left: 4, right: 4, bottom: 4 })
            }

            if (this.attachError.length > 0) {
              Text(this.attachError)
                .fontSize(10)
                .fontColor(Theme.accentRed)
                .padding({ left: 4, bottom: 2 })
            }

            Row() {
              SoftIconButton({
                icon: $r('sys.media.ohos_ic_public_add'),
                tint: Theme.textSecondary,
                onTap: () => {
                  this.showAttach = true;
                }
              })
              Blank()
              SoftSendButton({
                working: this.working,
                isEnabled: this.input.trim().length > 0 || this.attachments.length > 0,
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
            .padding({ left: 2, right: 2, top: 2 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 10, bottom: 10 })
          .backgroundColor(Theme.glassBg())
          .backgroundBlurStyle(BlurStyle.COMPONENT_THICK)
          .border({ width: 0.5, color: Theme.glassBorder })
          .borderRadius(Theme.radiusXl)
          .shadow(Theme.elev2())
        }
        .width('100%')
        .padding({ left: Theme.floatInset, right: Theme.floatInset, top: 4, bottom: 12 + this.navBarHeight })
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)

      if (!this.stickToBottom) {
        SoftJumpPill({
          label: '\u2193 \u6700\u65B0',
          onTap: () => {
            this.jumpToLatest();
          }
        })
          .position({ x: '50%', y: '80%' })
          .markAnchor({ x: '50%', y: '80%' })
      }

      if (this.showModel) {
        ModelPicker({
          onClose: () => {
            this.showModel = false;
          },
          onPick: (pid: string, mid: string) => {
            this.onPick(pid, mid);
          }
        })
      }

      // 权限审批：底部抽屉，强制用户选择
      if (this.approvals.length > 0) {
        Column() {
          Blank()
            .layoutWeight(1)
            .width('100%')
            .onClick(() => {
            })
          Column({ space: Theme.spaceMd }) {
            Row() {
              Column()
                .width(36)
                .height(4)
                .borderRadius(2)
                .backgroundColor(Theme.border)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ bottom: 4 })

            Row() {
              Text('\u6743\u9650\u5BA1\u6279')
                .fontSize(Theme.typeTitle)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.textPrimary)
              Blank()
              Text(this.approvals.length.toString() + ' \u4E2A\u8BF7\u6C42')
                .fontSize(Theme.typeCaption)
                .fontColor(Theme.accentOrange)
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor(Theme.warningSoft)
                .borderRadius(Theme.radiusSm)
            }
            .width('100%')

            ForEach(this.approvals, (a: Approval) => {
              Column() {
                Text(this.approvalTitle(a))
                  .fontSize(Theme.typeBody)
                  .fontColor(Theme.textPrimary)
                  .width('100%')
                if (a.patterns.length > 0) {
                  Text(a.patterns)
                    .fontSize(Theme.typeBodySm)
                    .fontColor(Theme.textSecondary)
                    .width('100%')
                    .margin({ top: 4 })
                    .maxLines(6)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Row({ space: 6 }) {
                  this.approvalBtn('\u5141\u8BB8\u4E00\u6B21', 'once', a.requestID)
                  this.approvalBtn('\u603B\u662F\u5141\u8BB8', 'always', a.requestID)
                  this.approvalBtn('\u62D2\u7EDD', 'reject', a.requestID)
                }
                .width('100%')
                .justifyContent(FlexAlign.Center)
                .margin({ top: 10 })
              }
              .width('100%')
              .padding(Theme.spaceMd)
              .backgroundColor(Theme.softFill)
              .border({ width: 0.5, color: Theme.borderMuted })
              .borderRadius(Theme.radiusMd)
            }, (a: Approval) => a.requestID)
          }
          .width('100%')
          .padding({
            left: Theme.spaceLg,
            right: Theme.spaceLg,
            top: Theme.spaceSm,
            bottom: Theme.spaceXl
          })
          .backgroundColor(Theme.bgCard)
          .borderRadius({ topLeft: Theme.radiusXl, topRight: Theme.radiusXl })
          .shadow(Theme.elev3())
          .transition(Motion.sheetIn())
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.overlay)
        .justifyContent(FlexAlign.End)
      }

      // Agent 模式选择弹层：Build / Plan
      if (this.showMode) {
        Column() {
          Column() {
            Text('选择 Agent 模式')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Theme.textPrimary)
              .width('100%')
              .textAlign(TextAlign.Center)
              .margin({ bottom: 14 })

            this.modeOption('sys.symbol.bolt', 'Build', 'build', '自动写代码、改文件、运行命令')
            this.modeOption('sys.symbol.doc_text', 'Plan', 'plan', '只做规划、不改动代码')

            SoftSecondaryButton({
              label: '\u53D6\u6D88',
              onTap: () => {
                this.showMode = false;
              }
            })
              .margin({ top: 10 })
          }
          .width('88%')
          .padding(16)
          .backgroundColor(Theme.bgCard)
          .borderRadius(Theme.radiusLg)
          .border({ width: 0.5, color: Theme.glassBorder })
          .shadow(Theme.elev3())
          .transition(Motion.cardIn())
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.overlay)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.showMode = false;
        })
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showAttach, this.attachSheet(), {
      height: 260,
      dragBar: false,
      showClose: true,
      backgroundColor: Theme.bgCard
    })
  }

  @Builder
  attachSheet() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          SoftIconButton({
            icon: $r('sys.media.ohos_ic_public_albums'),
            btnSize: 48,
            iconSize: 24,
            onTap: () => {
              this.pickImages();
            }
          })
          Text('从相册选择')
            .fontSize(Theme.typeBodySm)
            .fontColor(Theme.textPrimary)
        }
        .layoutWeight(1)
        .padding({ top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.softFill)
        .borderRadius(Theme.radiusMd)
        .onClick(() => {
          this.pickImages();
        })

        Column({ space: 8 }) {
          SoftIconButton({
            icon: $r('sys.media.ohos_ic_normal_white_grid_doc'),
            btnSize: 48,
            iconSize: 24,
            onTap: () => {
              this.pickFiles();
            }
          })
          Text('从文件选择')
            .fontSize(Theme.typeBodySm)
            .fontColor(Theme.textPrimary)
        }
        .layoutWeight(1)
        .padding({ top: 16, bottom: 16 })
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Theme.softFill)
        .borderRadius(Theme.radiusMd)
        .onClick(() => {
          this.pickFiles();
        })
      }
      .width('100%')

      if (this.attachError.length > 0) {
        SoftBanner({
          text: this.attachError,
          tone: 'danger'
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .backgroundColor(Theme.bgCard)
  }

  // 列表顶部入口：上翻到顶自动加载更早历史，也可点按手动加载
  @Builder
  loadMoreItem() {
    Row({ space: 6 }) {
      if (this.loadingMore) {
        LoadingProgress()
          .width(14)
          .height(14)
          .color(Theme.brandPrimary)
        Text('正在加载更早消息…')
          .fontSize(Theme.typeCaption)
          .fontColor(Theme.textTertiary)
      } else if (this.hasMore) {
        SoftChip({
          label: '\u2191 \u52A0\u8F7D\u66F4\u65E9\u6D88\u606F',
          active: true,
          onTap: () => {
            this.triggerLoadMore();
          }
        })
      } else {
        Text('已到最早消息')
          .fontSize(Theme.typeCaption)
          .fontColor(Theme.textTertiary)
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 10, bottom: 10 })
    .onClick(() => {
      this.triggerLoadMore();
    })
  }

  private approvalTitle(a: Approval): string {
    const p = a.permission;
    if (p === 'external_directory') {
      return '允许访问目录?';
    }
    if (p === 'read') {
      return '允许读取文件?';
    }
    if (p === 'edit' || p === 'write') {
      return '允许修改文件?';
    }
    if (p === 'bash') {
      return '允许执行命令?';
    }
    if (p.length > 0) {
      return '允许 ' + p + ' ?';
    }
    return '允许执行此操作?';
  }

  @Builder
  approvalBtn(label: string, reply: string, requestID: string) {
    Button(label)
      .type(ButtonType.Capsule)
      .fontSize(Theme.typeBodySm)
      .layoutWeight(1)
      .height(40)
      .backgroundColor(reply === 'reject' ? Theme.dangerSoft : (reply === 'always' ? Theme.infoSoft : Theme.softFill))
      .fontColor(reply === 'reject' ? Theme.accentRed : Theme.textPrimary)
      .fontWeight(FontWeight.Medium)
      .onClick(() => {
        appStore.replyApproval(requestID, reply);
      })
  }

  @Builder
  modeOption(iconRes: string, label: string, mode: string, desc: string) {
    Row({ space: 12 }) {
      SymbolGlyph($r(iconRes))
        .fontSize(26)
        .fontColor([this.agentMode === mode ? Theme.accentBlue : Theme.textPrimary])
      Column() {
        Text(label)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.textPrimary)
        Text(desc)
          .fontSize(11)
          .fontColor(Theme.textTertiary)
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      if (this.agentMode === mode) {
        Text('\u2713')
          .fontSize(16)
          .fontColor(Theme.accentBlue)
          .fontWeight(FontWeight.Bold)
      }
    }
    .width('100%')
    .padding(14)
    .margin({ bottom: 10 })
    .backgroundColor(this.agentMode === mode
      ? Theme.infoSoft
      : Theme.softFill)
    .borderRadius(Theme.radiusMd)
    .border({
      width: 0.5,
      color: this.agentMode === mode ? Theme.brandPrimary : Theme.borderMuted
    })
    .onClick(() => {
      this.agentMode = mode;
      this.showMode = false;
      appStore.setAgent(mode);
    })
  }
}
