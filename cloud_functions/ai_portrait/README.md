# AI 美颜代理部署指南（阿里云 ECS / 函数计算）

代理作用：服务端持有千问 API Key，浏览器只调本服务；源图先传腾讯云 COS 拿公网 URL（千问图生图要求输入图为公网可访问 URL），再调 `wanx2.1-imageedit` 生成美颜图，结果转 base64 回前端。

> 千问 `wanx2.1-imageedit` 免费额度：**500 张 / 激活后 180 天**，正好用于 Demo。

## 一、准备

```bash
cd cloud_functions/ai_portrait
npm install
cp .env.example .env   # 填入真实密钥（.env 已被 .gitignore 忽略）
```

`.env` 必填项：
- `DASHSCOPE_API_KEY`：千问/百炼 API Key
- `TENCENT_COS_SECRET_ID` / `TENCENT_COS_SECRET_KEY` / `TENCENT_COS_BUCKET` / `TENCENT_COS_REGION`：腾讯云 COS（复用你已有的云存储当临时图床）

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

## 三、部署到阿里云函数计算 FC（免备案 HTTPS，可选）

FC HTTP 触发器自带 `*.fc.aliyuncs.com` 域名、无需备案，最省心。适配要点：FC 的 HTTP 触发事件结构与 Express 不同，但**核心逻辑可复用**。最简做法是用 FC 的「自定义运行时 / 容器」直接跑这个 Express 服务（监听 `0.0.0.0:$PORT`），不写 FC 专用 handler。部署后在触发器拿到 HTTPS 地址，作为 `AI_PROXY_URL`。

## 四、安全提醒

- `ALLOW_ORIGIN` 建议设为你的 COS 站点域名，不要长期用 `*`。
- `.env` 切勿提交进仓库（已忽略）。
- COS 临时图在返回结果后即删除，不会长期留存用户照片。
- 千问免费额度有限，正式上线建议配置计费告警。
