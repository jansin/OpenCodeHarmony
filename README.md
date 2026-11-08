# OpenCodeHarmony

OpenCode 的 HarmonyOS(OpenHarmony)客户端,把 OpenCode 的 AI 编码助手带到大屏设备上。

## 功能特性

- **聊天对话**:与 OpenCode 后端会话,支持流式输出(打字机效果)、`/init`、`/share`、`/summarize` 等 slash 命令补全
- **Agent 模式**:build / plan 两种模式
- **会话管理**:侧边栏会话列表、新建/删除会话、会话内搜索(顶栏放大镜)、消息内链接点击(复制/浏览器打开)
- **Markdown 渲染**:标题、列表、引用、代码块(一键复制)、粗体、行内代码、链接,解析带缓存
- **消息列表**:`LazyForEach` 增量更新 + 滚动到底合并,长会话流畅
- **性能与省电**:SSE 活跃时暂停 REST 兜底轮询;应用切后台自动降频(5s 轮询)
- **模型选择**:按服务商分组,免费/付费分区(仿 ohos-OpenCode 样式),动态从 `/providers` 拉取
- **图片附件**:相册多选(最多 4 张),按文件头识别格式
- **操作审批**:`build` 模式下工具调用审批、多选方案确认
- **Diff / Todo**:查看文件差异、任务清单
- **深色模式**:跟随系统

## 环境要求

- DevEco Studio 5.x(API 24,`targetSdkVersion` 6.1.1(24))
- OpenHarmony 设备 / 模拟器(真机需开启调试,签名见下文)
- 一台运行 OpenCode 后端的电脑(server 目录内含可选的本地代理)

## 构建

命令行构建 debug 包(需先配置 SDK 与 JDK 环境变量):

```powershell
$env:DEVECO_SDK_HOME='C:\Program Files\Huawei\DevEco Studio5\sdk'
$env:JAVA_HOME='C:\Program Files\Huawei\DevEco Studio5\jbr'
$env:PATH='C:\Program Files\Huawei\DevEco Studio5\jbr\bin;' + $env:PATH
& 'C:\Program Files\Huawei\DevEco Studio5\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default -p module=entry@default -p buildMode=debug --no-daemon
```

产物:`entry\build\default\outputs\default\entry-default-signed.hap`

## 安装运行

```powershell
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap
hdc shell aa force-stop com.jason.opencode
hdc shell aa start -a EntryAbility -b com.jason.opencode
```

启动后在"连接"页填入 OpenCode 后端地址(格式 `http://<电脑IP>:<端口>`),保存后即可对话。

## 正式发布签名

debug 包只能用于开发调试,正式分发需在 AppGallery Connect 申请正式证书:

1. **注册开发者并实名认证**:打开 AppGallery Connect(https://developer.huawei.com/consumer/cn/),完成账号注册与实名认证。
2. **创建应用**:在"我的应用"中创建应用,包名填写 `com.jason.opencode`,记录 App ID。
3. **生成签名证书(.cer)**:
   - 在 AGC 控制台"用户与访问 → 证书管理"生成新的签名证书;
   - 下载证书文件并记录证书指纹(SHA-256)。
4. **生成密钥库(.p12)**:
   - 使用 `keytool` 生成密钥库,或从 AGC 申请;
   - 密码与别名妥善保存。
5. **创建发布 Profile**:
   - 在 AGC"开发服务 → HarmonyOS 应用 → 证书/Profile 管理"创建发布 Profile;
   - 关联步骤 2 的应用与步骤 3 的证书。
6. **配置到工程**:
   - DevEco Studio 打开工程 → File → Project Structure → Signing Configs;
   - 取消"自动签名",填入 `.p12` 路径与密码、`.cer` 证书、`.p7b` Profile;
   - 确认与 AGC 证书指纹一致。
7. **构建发布包**:
   ```powershell
   hvigorw.bat assembleHap --mode module -p product=default -p module=entry@default -p buildMode=release --no-daemon
   ```
   产物在 `entry\build\default\intermediates\hap\` 下,上传 AGC 分发即可。

> 注意:released 签名包的 Profile 有设备白名单限制,真机安装前需在 AGC 把设备加入白名单。

## 目录结构

```
entry\src\main\ets\
  common\        主题、动效、窗口软阴影、密钥与通知工具
  data\          业务数据:AppStore(状态/轮询/SSE)、CacheStore(异步持久化)、ZenStore
  data\api\      ApiClient、StreamClient、EventStreamBridge(SSE)、ZenStream
  view\          UI:ChatView、ZenChatView、MessageBubble、ModelPicker、RichTextBlock 等
  entryability\  生命周期(前后台降频接入)
docs\            改进记录
tools\           PC 端启动 opencode serve 与会话同步脚本
```

> `server\` 目录未包含在本仓库中：那是开发期遗留的 REST 示例骨架，未接入 OpenCode。应用直连本机的 `opencode serve`（默认 `http://<电脑IP>:4096`），无需中间层。

## 构建与签名

本仓库**不携带任何签名材料**：`build-profile.json5` 里的 `signingConfigs` 为空。克隆后用 DevEco Studio 打开工程，在 `File → Project Structure → Signing Configs` 开启「自动签名」即可真机调试。

## 许可证

本项目以 [MIT License](LICENSE) 开源。

## 相关项目

- [OpenCode](https://opencode.ai) —— 上游 AI 编码助手（MIT），本应用是它的 HarmonyOS 客户端。
- [ohos-OpenCode](https://github.com/Andrereoo/ohos-OpenCode) —— UI 样式参考。

