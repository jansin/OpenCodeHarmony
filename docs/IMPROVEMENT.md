# OpenCode HarmonyOS 客户端改进清单

> 按优先级排序：P0 = 核心体验缺失，P1 = 常用增强，P2 = 锦上添花。
> 完成后在对应项标注 ✅。

## 跨端联动（手机 ↔ PC TUI）

- [x] **手机切会话 → PC TUI 跟随**：`POST /tui/select-session`（ApiClient.selectSession → AppStore.openSession 调用）
- [x] **手机新建会话 → PC TUI 跟随**：createSession 成功后 selectSession
- [x] **断线重连 → 重新对齐 PC 会话**：pollOnce 恢复时自动 selectSession（仅断连后一次）
- [x] **PC 列表实时刷新**：由 server SSE 广播保证（发消息/abort/删除等自动推送）

## P0 核心体验

- [x] **1. 消息流式跟随滚动** ✅ 已完成（stickToBottom + 「↓ 最新」悬浮按钮）
- [x] **2. 轮询断连自愈** ✅ 已完成（pollFailCount 连续失败 → disconnected 横幅 → 自动重连）
- [x] **3. 会话标题联动顶栏** ✅ 已完成（AppStore.syncSessionTitle → ChatView 顶栏）
- [x] **4. 消息错误展示** ✅ 已完成（MessageBubble error 红色提示条）
- [x] **5. 会话列表左滑删除** ✅ 已完成（swipeAction + AlertDialog 确认）
- [x] **6. 会话列表下拉刷新** ✅ 已完成（Refresh 组件）
- [x] **7. 当前会话高亮 + 进行中标记** ✅ 已完成
- [x] **8. 输入框 `/` 命令补全** ✅ 已完成
- [x] **9. 侧边栏搜索框越界** ✅ 已修复（外层 padding 替代 width+margin）

## P1 增强

- [x] **消息操作菜单**：长按消息 → 复制文本 / 重试
- [x] **消息截断重发**：长按用户消息 →「从此截断重发」删除该消息及其后所有消息再重发（服务端 removeMessage 不级联，客户端逐条 DELETE）
- [x] **代码块复制按钮**：MessageBubble 内解析 ``` 围栏，代码块深色底 + 语言标 + ⧉ 复制（未闭合容错）
- [x] **底部输入区回车发送**：TextArea onKeyEvent Enter=发送
- [x] **Diff 按文件在会话内独立刷新**：打开页面时拉取（原有逻辑即满足）
- [x] **会话列表显示 tokens/成本摘要**：每行显示 🔤 tokens 用量与 $ 成本（server Session 自带 tokensInput/tokensOutput/cost，无需逐会话拉消息；消息条数/末条摘要需额外请求故放弃）
- [x] **发送失败时显示消息旁重试按钮**（sendError 横幅 + 重试/重连）
- [x] **顶栏 working 状态：停止按钮确认框**
- [x] **权限授权同步弹窗**：电脑端弹出工具权限请求时，手机端同会话弹出确认框（允许一次/总是允许/拒绝），新请求到达发系统通知

## P2 锦上添花

- [x] **深色模式**：跟随系统或手动切换（Theme 双色板 applyDark；AppStorage 'darkMode' 广播驱动全部视图重建；EntryAbility.onConfigurationUpdate 监听系统明暗）
- [x] **Zen 对话流式输出**：打字机效果（ZenStore.replay 逐步显示）
- [x] **会话消息流式打字机**：手机端轮询拉回整块文本后，ChatView 对进行中的 assistant 文本按 24ms 渐进 reveal，还原流式观感（轮询数据为源，SSE 设备不触发）
- [x] **会话分组**：按今天/昨天/更早分组展示（Sidebar 会话列表）
- [ ] **项目切换器**：❌ 不可行 — server 无 POST 切换项目端点（`/project` 仅 GET；当前项目由 server 实例决定）
- [x] **会话/会话状态徽标**：Sidebar 会话行显示 busy ● 标记（经 /session/status）
- [x] **图片/文档上传**：发送到会话（附件走 `url` + `source` 内联，无需 multipart；文本文件 ≤512KB 转 UTF-8 文本、图片转 data URI，长按输入框「+」选择）
- [x] **本地缓存**：会话列表/最近 40 条消息 JSON 落盘 `ctx.filesDir`（CacheStore，轮询成功后 ≥3s 节流写入）；启动连接失败/断连时回填，弱网离线可读（仅当缓存源与当前 server.url 匹配）
- [x] **通知提醒**：working 状态变化时系统通知（Notifier 封装 notificationManager；Setting 开关持久化）
- [x] **远程文件浏览器 + 全文搜索**：侧边栏 Files 入口；📂 目录树浏览（git 状态 A/M/D 徽标）+ 文件内容查看（二进制提示）+ 🔍 ripgrep 全文搜索（`/file`、`/file/content`、`/file/status`、`/find`）
- [x] **历史消息分页加载**：会话消息列表顶部「↑ 加载更早消息」入口，上翻到顶自动触发（`onScrollIndex`+入口点按）；服务端 `/session/{id}/message` 的 `X-Next-Cursor` 游标分页，每页 30 条；更早历史独立存 `extraMessages`，最新窗口轮询（`applyPayloads`）合并保留不被清掉，截断重发/切换会话同步清理

## 验证说明

- CLI 编译验证可用（CompileArkTS 全量通过）：`& $node hvigorw.js assembleHap --mode module -p product=default --no-daemon`（需 `DEVECO_SDK_HOME` 指向 DevEco SDK）。
- IDE 外 HAP 打包受环境限制（java app_packing_tool 崩溃，exit 3221226505），装机验证在 DevEco Studio Build Hap 内进行。
- 涉及 UI 的改动由用户截图确认效果。