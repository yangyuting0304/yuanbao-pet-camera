# 毛孩美颜 · FireRed 图像编辑代理（部署教程）

这个 Node 服务是「毛孩美颜」页面里 **AI 编辑** 能力的后端。它代替前端持有 ModelScope API Key，
避免 key 泄露到 Flutter Web 客户端，同时把源图上传到腾讯云 COS 拿到公网 URL（FireRed 模型只接受 `image_url`）。

---

## 一、上传文件到 ECS

把整个 `firered_edit/` 文件夹上传到 ECS（和现有 `ai_portrait/` 代理放一起，例如 `/www/wwwroot/120.24.240.129/cloud_functions/firered_edit/`）。

## 二、安装依赖

在 ECS 终端进入该目录执行：

```bash
cd /www/wwwroot/120.24.240.129/cloud_functions/firered_edit
npm install
```

> 若没有 npm，先在宝塔「软件商店」装 Node.js 项目环境（建议 Node 18+）。

## 三、配置环境变量

复制 `.env.example` 为 `.env`，填入真实值：

```bash
cp .env.example .env
vim .env   # 填入 MODELSCOPE_API_KEY、COS_SECRET_ID、COS_SECRET_KEY 等
```

| 变量 | 说明 | 去哪找 |
|------|------|--------|
| `MODELSCOPE_API_KEY` | ModelScope 访问令牌 | modelscope.cn 控制台 → 访问令牌 |
| `COS_SECRET_ID` / `COS_SECRET_KEY` | 腾讯云 API 密钥 | 腾讯云控制台 → 访问管理 → API密钥管理（或你本地 `SecretKey.csv`） |
| `COS_BUCKET` | COS 桶名 | 默认 `pet-camera-1322296918` |
| `COS_REGION` | 桶所在地域 | 默认 `ap-guangzhou` |
| `PORT` | 服务监听端口 | 默认 `3000` |

⚠️ **安全**：你之前在对话里贴出的 `ms-613d078d-...` 已经暴露，**请务必去 ModelScope 控制台重新生成一个新 key，旧的直接删除**，并在 `.env` 里用新 key。`.env` 文件不要提交到任何公开仓库。

## 四、启动服务（PM2 保活）

```bash
npm install -g pm2
pm2 start index.js --name firered-edit
pm2 save
```

验证是否起来：

```bash
curl http://localhost:3000/health
# 返回 {"ok":true} 即正常
```

## 五、宝塔配置反向代理（让公网能访问）

1. 宝塔 → 网站 → 你的站点（如 `120.24.240.129` 或你的域名）→ **反向代理** → 添加
2. 代理名称：`firered-edit`
3. 目标 URL：`http://127.0.0.1:3000`
4. 发送域名：留空或填你的域名
5. 保存

代理后，接口地址为：`https://你的域名/api/v1/firered-edit`（或 `http://120.24.240.129/api/v1/firered-edit`）。

> 若用 IP 直接访问，注意浏览器/ModelScope 对混合内容（http）的限制；建议配一个域名 + HTTPS（宝塔可免费申请证书）。

## 六、前端构建时注入代理地址

在本地构建 Flutter Web 时加上 `--dart-define`：

```bash
flutter build web --base-href=/yuanbao-pet-camera/ --release \
  --dart-define=FIERED_PROXY_URL=https://你的域名/api/v1/firered-edit
```

- 配了 `FIERED_PROXY_URL`：点「AI 编辑」→ 选图 → 选/写 prompt → 生成，走真实 AI。
- **没配**（演示模式）：页面正常可跑，但结果会回显源图并提示「未接入 AI 服务」。

## 七、排错

| 现象 | 可能原因 | 处理 |
|------|----------|------|
| 前端提示「代理返回错误：4xx」 | 请求体缺字段 | 检查前端是否传了 `imageBase64` 和 `prompt` |
| 代理日志 `ModelScope submit failed: 400 image_url is required` | COS 上传失败或 URL 不可公开访问 | 确认 COS 桶/地域正确、对象已公开读、网络能出公网 |
| 代理日志 `generation FAILED` | prompt 触发模型安全策略或源图不符 | 换更温和的 prompt（英文描述），换一张清晰猫图 |
| 生成很久才出 / 超时 | FireRed 任务排队 | 代理轮询上限 36×5s≈3min，前端超时 180s；高峰期耐心等 |
| 前端一直 demo 回显 | 没注入 `FIERED_PROXY_URL` | 重新构建并加 `--dart-define=FIERED_PROXY_URL=...` |

---

## 接口契约

**请求** `POST /api/v1/firered-edit`
```json
{ "imageBase64": "<源图 base64，可带/不带 data URI 前缀>", "prompt": "Add a pink bow on the cat" }
```

**成功** `200`
```json
{ "imageBase64": "<结果图 base64>" }
```
（FireRed 单次返回一张含多个变体的图，前端整张展示）

**失败** `400 / 500`
```json
{ "error": "错误描述" }
```
