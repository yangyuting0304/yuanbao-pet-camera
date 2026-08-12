# 阿里云 ECS 部署指南 — 元宝拍拍 Flutter Web

> 将 `build/web` 部署到阿里云 ECS，配置 HTTPS（免费证书），iPhone Safari 可直接访问并调用相机。

---

## 前置条件

| 项目 | 你需要准备的 |
|------|-------------|
| ECS 公网 IP | 如 `47.xxx.xxx.xxx` |
| 域名 | 如 `pet.yourdomain.com`（用于 HTTPS 证书 + 访问） |
| ECS 登录方式 | root 密码或 SSH 密钥 |
| 操作系统 | 推荐 CentOS 7+ / Ubuntu 20+ / Alibaba Cloud Linux |

---

## 第 1 步：上传网站文件到 ECS

### 方式 A：用 FileZilla / WinSCP（推荐，图形界面）

1. 下载 [FileZilla Client](https://filezilla-project.org/download.php)（免费）
2. 打开 FileZilla → 文件 → 站点管理器 → 新站点：
   - **协议**：SFTP
   - **主机**：你的 ECS 公网 IP
   - **用户**：`root`
   - **密码**：你的 ECS root 密码
   - **端口**：`22`
3. 点「连接」→ 登录成功后：
   - 右侧（远程）进入 `/var/www/pet-camera/`（没有就新建）
   - 左侧（本地）打开 `F:\元宝爱拍照\pet_camera\build\web\`
   - **全选左侧所有文件 → 右键 → 上传**

### 方式 B：用 SCP 命令行（一行搞定）

在你电脑的 PowerShell / Git Bash 里执行：

```bash
scp -r F:/元宝爱拍照/pet_camera/build/web/* root@<你的ECS公网IP>:/var/www/pet-camera/
```

> ⚠️ 把 `<你的ECS公网IP>` 换成真实 IP。首次连接会提示 `yes/no`，输入 `yes` 回车，然后输密码。

### 上传完成后验证

SSH 登录到 ECS 执行：

```bash
ls -la /var/www/pet-camera/
# 应该看到 index.html、main.dart.js、assets/ 等文件
du -sh /var/www/pet-camera/
# 应该显示约 117MB
```

---

## 第 2 步：安装 Nginx

SSH 登录到 ECS 后执行：

```bash
# CentOS / Alibaba Cloud Linux
yum install -y nginx

# Ubuntu / Debian
apt update && apt install -y nginx
```

启动并设置开机自启：

```bash
systemctl start nginx
systemctl enable nginx
```

验证安装：

```bash
nginx -v
# 应输出: nginx version: nginx/1.x.x
curl http://localhost
# 应返回 nginx 欢迎页面的 HTML
```

> ⚠️ 如果 `curl localhost` 不通，检查安全组是否放行了**入方向端口 80 和 443**（见第 6 步）。

---

## 第 3 步：配置域名解析

去你的域名 DNS 管理面板（阿里云域名 → 解析设置 / 或你买域名的服务商后台），添加一条 A 记录：

| 字段 | 值 |
|------|-----|
| 记录类型 | **A** |
| 主机记录 | `pet`（或 `www` 或 `@`，看你想要什么子域名） |
| 记录值 | 你的 **ECS 公网 IP** |
| TTL | 默认（10 分钟） |

例如：如果你填主机记录为 `pet`，域名是 `example.com`，最终地址就是 `pet.example.com`

> ⚠️ DNS 生效需要 **几分钟到几十分钟**不等。可以用 `ping pet.yourdomain.com` 验证是否指向了你的 ECS IP。

---

## 第 4 步：申请免费 SSL 证书（HTTPS 必须）

### 推荐方式：阿里云免费 SSL 证书（最简单）

1. 登录 [阿里云 SSL 证书控制台](https://yundun.console.aliyun.com/?p=cas)
2. 点 **「免费证书」** → **「创建证书」**
3. 填写：
   - **域名**：`pet.yourdomain.com`（和第 3 步 DNS 记录一致）
   - **验证方式**：选 **DNS 验证**（会自动添加一条 TXT 记录，按提示去 DNS 面板加就行）
4. 提交后等签发（通常 **5–10 分钟**）
5. 签发成功后 → 点 **「下载」** → 选 **Nginx** 格式 → 下载 zip 包

### 下载解压后得到两个文件：

```
xxxxxx.pem    # 证书文件
xxxxxx.key    # 私钥文件
```

把这两个文件传到 ECS 的 `/etc/nginx/ssl/` 目录：

```bash
mkdir -p /etc/nginx/ssl/
# 用 scp 或 FileZilla 把 .pem 和 .key 传进去
```

---

## 第 5 步：配置 Nginx（HTTP + HTTPS）

在 ECS 上创建站点配置：

```bash
vi /etc/nginx/conf.d/pet-camera.conf
```

写入以下内容（**把 4 处 `pet.yourdomain.com` 替换成你的真实域名**）：

```nginx
server {
    listen 80;
    server_name pet.yourdomain.com;

    # HTTP 自动跳转 HTTPS
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name pet.yourdomain.com;

    # SSL 证书路径（替换成你实际下载的文件名）
    ssl_certificate     /etc/nginx/ssl/xxxxxx.pem;
    ssl_certificate_key /etc/nginx/ssl/xxxxxx.key;

    # 安全配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # 网站根目录
    root /var/www/pet-camera;
    index index.html;

    # Flutter Web SPA 路由支持（关键！）
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|ttf|woff2?)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # 禁止隐藏目录访问
    location ~ /\. {
        deny all;
    }
}
```

保存退出后测试配置 + 重载：

```bash
# 测试配置语法
nginx -t
# 应输出: syntax is ok / test is successful

# 重载配置
systemctl reload nginx
```

---

## 第 6 步：开放防火墙 / 安全组

### A. ECS 安全组（必须！否则外网访问不了）

登录 [阿里云 ECS 控制台](https://ecs.console.aliyun.com/) → 实例详情 → **安全组** → 配规则 → 入方向添加：

| 协议 | 端口范围 | 授权对象 | 说明 |
|------|---------|---------|------|
| TCP | **80** | 0.0.0.0/0 | HTTP（自动跳转 HTTPS） |
| TCP | **443** | 0.0.0.0/0 | HTTPS |

### B. 系统防火墙（如果有开的话）

```bash
# CentOS / firewalld
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --reload

# Ubuntu / ufw
ufw allow 'Nginx Full'
```

---

## 第 7 步：验证！

### 7.1 电脑浏览器打开

```
https://pet.yourdomain.com/
```

应该看到「元宝拍拍」完整 App 界面（马卡龙配色首页）。

### 7.2 iPhone Safari 打开

同一个链接，应该能正常渲染网页（不再弹"下载"对话框）。

### 7.3 测试相机功能

点顶栏相机图标 → iPhone Safari 应弹出相机权限请求 → 允许后可拍照 ✅

---

## 常见问题排查

| 问题 | 原因 | 解决方法 |
|------|------|----------|
| 打不开 / 连接超时 | 安全组没放行 80/443 | 第 6 步检查安全组 |
| 502 Bad Gateway | nginx 没启动或配置错误 | `systemctl status nginx` + `nginx -t` |
| 证书警告（不安全） | 证书域名和访问域名不匹配 | 确保 SSL 证书申请的域名 = 访问的域名 |
| 能打开但白屏 | Flutter Web 路由问题 | 确认配置了 `try_files $uri $uri/ /index.html;` |
| 图片全部 404 | assets 路径不对 | 确认 `/var/www/pet-camera/assets/assets/` 目录存在且有文件 |
| 相机打不开 | 不是 HTTPS | 确认地址栏有 🔒 锁标且是 `https://` 开头 |

---

## 更新部署（以后改了代码重新上线）

每次本地改完代码后：

```bash
# 1. 本地重新构建
cd F:/元宝爱拍照/pet_camera
flutter build web --release

# 2. 重新上传（只覆盖变更的文件更快）
scp -r build/web/* root@<ECS_IP>:/var/www/pet-camera/

# 3. 无需重启 nginx，静态文件直接生效
```

---

## 下一步：接 AI 美颜代理

网站跑通后，在同一台 ECS 上部署 Node.js 代理服务（`cloud_functions/ai_portrait/index.js` 已写好），步骤见 `cloud_functions/ai_portrait/README.md`。
