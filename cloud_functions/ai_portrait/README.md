# AI 写真代理部署指南（阿里云 ECS / 函数计算）

代理作用：服务端持有百炼/千问 API Key，浏览器只调本服务，避免 key 泄露并绕过 CORS。默认走 `wan2.7-image-pro`（multimodal-generation，base64 内联图，无需 COS），兼容旧版 `wanx2.1-imageedit`。

## 架构说明（如何换模型）

**前端协议固定不变**：前端只发 `POST /api/beautify { styleId, imageBase64 }`，后端永远返回 `{ imageBase64 }`。模型差异全部收敛在后端适配器里。

```
lib/adapter.js           适配器注册中心 —— 换模型只改这里
lib/models/dashscope.js  DashScope/百炼 适配器（wan2.7 新格式 + wanx2.1 旧格式）
prompts.js               风格提示词映射（styleId -> prompt）
index.js                 HTTP 层 + 统一协议（不关心具体模型）
```

### 换模型三步

1. **新建适配器文件**（如 `lib/models/openai.js`），实现统一接口：
   ```js
   // 输入：{ sourceBytes: Buffer, prompt: string, options?: object }
   // 输出：{ imageBytes: Buffer, imageUrl?: string, cleanup?: () => Promise<void> }
   function createOpenAiAdapter(env) {
     async function generate({ sourceBytes, prompt, options }) { /* ... */ }
     return { generate, model: 'gpt-image', format: '...' };
   }
   module.exports = { createOpenAiAdapter };
   ```
2. **在 `lib/adapter.js` 注册**：
   ```js
   const { createOpenAiAdapter } = require('./models/openai');
   const ADAPTERS = { dashscope: createDashScopeAdapter, 'gpt-image': createOpenAiAdapter };
   ```
3. **切换**：部署时设环境变量 `MODEL=gpt-image` 即可，前端与 `index.js` 零改动。

> 约定：`generate()` 必须返回结果图 `imageBytes`（Buffer），由 `index.js` 统一 base64 返回给前端。这样无论底层模型返回 URL / base64 / 其他结构，前端感知到的协议永远一致。

## 一、准备

```bash
cd cloud_functions/ai_portrait
npm install
cp .env.example .env   # 填入真实密钥（.env 已被 .gitignore 忽略）
```

`.env` 必填项：
- `DASHSCOPE_API_KEY`：百炼/千问 API Key
- （可选）`MODEL`：模型名，默认 `wan2.7-image-pro`。配置了 `MAAS_BASE_URL` 或模型名含 `wan2.7` 时走 base64 内联（无需 COS）；否则走旧版 `wanx2.1-imageedit`，此时需要 COS：
- （旧版可选）`TENCENT_COS_SECRET_ID` / `TENCENT_COS_SECRET_KEY` / `TENCENT_COS_BUCKET` / `TENCENT_COS_REGION`：腾讯云 COS（旧版 wanx2.1 当临时图床）

本地自测：
```bash
node index.js
curl -X POST http://localhost:3000/api/beautify \
  -H 'Content-Type: application/json' \
  -d '{"styleId":"oil","imageBase64":"<jpg base64>"}'
```

## 二、部署到阿里云 ECS（你有现成 ECS）

### 1. 进程托管（systemd，开机自启）
`/etc/systemd/system/ai-portrait.service`：
```
[Unit]
Description=AI Portrait Proxy
After=network.target

[Service]
WorkingDirectory=/opt/ai-portrait
ExecStart=/usr/bin/node /opt/ai-portrait/index.js
Restart=always
EnvironmentFile=/opt/ai-portrait/.env

[Install]
WantedBy=multi-user.target
```
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now ai-portrait
```

### 2. HTTPS（浏览器才肯调）
ECS 上的 API 必须 HTTPS。两种免备案方式：

- **方式 A（推荐，免备案）**：用**阿里云 API 网关**或**函数计算 FC** 暴露 HTTPS 端点（自带 `*.aliyuncs.com` 域名，无需备案）。把本目录代码原样部署到 FC 即可，见第三节。
- **方式 B（绑自己域名）**：在 ECS 前放 nginx 反代 + 免费证书（阿里云 DV 证书或 Let's Encrypt），域名需**已备案**。

nginx 示例（方式 B）：
```
server {
  listen 443 ssl;
  server_name api.your-domain.com;
  ssl_certificate     /path/fullchain.pem;
  ssl_certificate_key /path/privkey.pem;
  location / {
    proxy_pass http://127.0.0.1:3000;
    proxy_set_header Host $host;
  }
}
```

> 无论哪种，最终给前端的 `AI_PROXY_URL` 必须是 `https://.../api/beautify`。

## 三、通用 COS 上传（「我的创作」云存储）

前端保存生成结果（图片 / 视频）时，会先调用本服务的 `POST /api/upload`：
- 请求体：`{ dataBase64, ext?, contentType? }`
- 服务端用 `TENCENT_COS_*` 凭证上传到 `works/` 目录（对象级公开读），返回 `{ url }`
- 凭证只存在服务端，绝不下发到前端；未配置 COS 时该接口返回 500，前端会降级为仅本地保存

`json` body 上限 80mb（覆盖成片视频 base64）。前端上传代理复用 `AI_VIDEO_PROXY_URL` / `AI_PROXY_URL` 解析出根域名。

## 四、部署到阿里云函数计算 FC（免备案 HTTPS，可选）

FC HTTP 触发器自带 `*.fc.aliyuncs.com` 域名、无需备案，最省心。适配要点：FC 的 HTTP 触发事件结构与 Express 不同，但**核心逻辑可复用**。最简做法是用 FC 的「自定义运行时 / 容器」直接跑这个 Express 服务（监听 `0.0.0.0:$PORT`），不写 FC 专用 handler。部署后在触发器拿到 HTTPS 地址，作为 `AI_PROXY_URL`。

## 五、安全提醒

- `ALLOW_ORIGIN` 建议设为你的 COS 站点域名，不要长期用 `*`。
- `.env` 切勿提交进仓库（已忽略）。
- COS 临时图在返回结果后即删除，不会长期留存用户照片。
- 千问免费额度有限，正式上线建议配置计费告警。
