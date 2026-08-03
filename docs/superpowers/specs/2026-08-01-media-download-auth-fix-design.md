# 修复媒体文件下载认证缺失

- 日期：2026-08-01
- 影响范围：`astrbot-app`（Flutter 客户端），不涉及服务端插件
- 状态：草稿

## 1. 问题

手机 App 端收到 bot 的图片或文件消息时，聊天框正常显示气泡，但点击后报错
「打开失败：Exception：文件未缓存（可能已过期）」。100% 复现。

## 2. 根因

### 2.1 客户端 `downloadByUrl` 是唯一不带认证的请求

`lib/services/botapi_http.dart` 的 `downloadByUrl()`（约 304 行）用 Dio 发 GET
下载媒体文件，**options 不含任何认证头**。项目中所有其他 API 方法
（`auth`、`sendMessage`、`uploadFile`、`fetchHistory`）都通过 `_authHeaders`
携带 `Authorization: Bearer <token>` —— 仅此一个遗漏。

### 2.2 服务端文件 URL 指向需要认证的文件服务

服务端 `serializer.py` 的 `_media_url()` 调用 AstrBot 组件方法
（`register_to_file_service` / `get_file(allow_return_url=True)` /
`convert_to_file_path`）获取 URL。`register_to_file_service` 返回的 URL 指向
AstrBot 自带的文件服务端点，该端点要求 API 认证。

### 2.3 下载静默失败，localPath 永不被设置

`downloadByUrl` 在收到非 200 响应或 JSON content-type 时静默返回 `null`（行 328-331）。
捕获异常时也静默返回 `null`（行 349-354）。

`chat_provider.dart` 的 `_handleMedia()`（行 623-643）仅在 `localPath != null`
时才更新消息的 `localPath` 字段。`localPath` 始终为空 → 用户点击时 `file_bubble.dart`
的 `_open()` 检查 `lp` 为空 → 抛「文件未缓存」。

## 3. 修复

### 3.1 `downloadByUrl` 补上认证头

```dart
res = await dio.get<ResponseBody>(absUrl,
    options: Options(
        responseType: ResponseType.stream,
        headers: _authHeaders,       // ← 补上
    ));
```

### 3.2 `resolveMediaUrl` 不做特殊处理

`resolveMediaUrl` 只处理 URL 规范化（相对路径拼 origin），不操作 header。
因为该函数是纯函数且已有单元测试，不做改动。

### 3.3 不动服务端

服务端（`serializer.py` / `routes.py`）不做修改。修复仅限客户端。

## 4. 验证

### 4.1 单元测试

- 扩展 `test/media_url_test.dart`：新增 `downloadByUrl` 携带 auth header 的测试。
  由于 `downloadByUrl` 依赖 `dio` 网络 + `getApplicationDocumentsDirectory` 平台
  插件，真正的集成测试需要桩注入。最小可行：验证 `_authHeaders` 作为类属性存在
  且包含 `Authorization` 键。

### 4.2 端到端手测（真机）

- 用测试 token 对 `https://astrbot.zztweb.top` 发送会回复图片/文件的消息。
  预期：点击图片气泡→全屏预览；点击文件气泡→系统分享面板弹出。

## 5. 风险与回滚

- `_authHeaders` 仅含 Authorization header，不干扰文件服务其他行为
- 回滚：删除 Options 中的 `headers: _authHeaders` 一行即可

## 6. 变更清单

- `astrbot-app/lib/services/botapi_http.dart`：`downloadByUrl` 加 `headers: _authHeaders`
- `astrbot-app/test/media_url_test.dart`：扩展 auth header 测试
- `astrbot-app/CHANGELOG`（若有）：记一条 Fixed
