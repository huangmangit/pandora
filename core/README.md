# Core — 核心基础服务

> 所有项目共享的底层基础设施，一版本一容器，一次部署长期运行。

---

## 服务清单

| 服务 | 镜像 | 端口 | 容器名 |
|------|------|------|--------|
| **Caddy** | `caddy:2-alpine` | 80, 443 | `caddy` |
| OpenResty | `uusec/openresty-manager:2.4.2` | 80, 443, 8808 | `openresty` |
| PHP 7.4 | 自构建 (`Dockerfile.php74`) | — | `php74` |
| PHP 8.3 | 自构建 (`Dockerfile.php83`) | — | `php83` |
| MySQL | `mysql:8.0` | 3306 | `mysql` |
| Redis | `redis:7-alpine` | 6379 | `redis` |
| DPanel | `dpanel/dpanel:latest` | 8807 | `dpanel` |
| Woodpecker Server | `woodpeckerci/woodpecker-server:latest` | 8000 | `woodpecker-server` |
| Woodpecker Agent | `woodpeckerci/woodpecker-agent:latest` | — | `woodpecker-agent` |

---

## 架构

```
  本地开发 (Caddy)              线上生产 (OpenResty)
  ┌─────────────────┐       ┌─────────────────────────┐
  │  caddy (:80)    │       │  openresty (:80/:443)   │
  │  sites/*.caddy  │       │  (Web UI: :8808)        │
  └───────┬─────────┘       └───────────┬─────────────┘
          │                             │
          └──────────┬──────────────────┘
                     │
         ┌───────────┼───────────┐
         ▼           ▼           ▼
      php74        php83      静态/反代
   (FPM 7.4)    (FPM 8.3)   (Hyperf 等)
         │           │
         └─────┬─────┘
               │
        mysql (:3306)
        redis (:6379)

  所有容器加入 1panel-network（bridge），容器名直连。
  apps/ 源码同时挂载到 caddy 和所有 FPM 容器，路径一致。
```

---

## 环境变量（`.env`）

| 变量 | 服务 | 说明 | 默认值 |
|------|------|------|--------|
| `CADDY_HTTP_PORT` | Caddy | HTTP 端口 | `80` |
| `CADDY_HTTPS_PORT` | Caddy | HTTPS 端口 | `443` |
| `MYSQL_ROOT_PASSWORD` | MySQL | root 密码 | `pandora123` |
| `MYSQL_DATABASE` | MySQL | 默认数据库 | `pandora` |
| `REDIS_PASSWORD` | Redis | 认证密码 | `pandora123` |
| `WOODPECKER_HOST` | Server | 对外地址 | `http://localhost:8000` |
| `WOODPECKER_GITEA_URL` | Server | Git 服务地址 | `http://gitea:3000` |
| `WOODPECKER_AGENT_SECRET` | Server+Agent | 通信密钥 | `change-me-to-random-string` |
| `WOODPECKER_ADMIN` | Server | 管理员 | `admin` |
| `DPANEL_PORT` | DPanel | 面板端口 | `8807` |
| `OPENRESTY_MANAGER_PORT` | OpenResty | 管理界面端口 | `8808` |

---

## Caddy — 本地开发网关（推荐）

> Caddy 2 是本地开发环境的主力 Web 服务器。自动 HTTPS、Caddyfile 配置简洁、PHP-FPM 原生支持，非常适合本地快速搭建站点。
>
> 线上生产环境使用 **OpenResty**（1Panel 管理面板），Caddy 专为本地开发设计。

### 访问

| 入口 | 地址 |
|------|------|
| **HTTP** | `http://localhost` (端口由 `CADDY_HTTP_PORT` 控制，默认 80) |
| **HTTPS** | `https://localhost` (端口由 `CADDY_HTTPS_PORT` 控制，默认 443) |

> 本地开发已关闭自动 HTTPS（`auto_https off`），直接 HTTP 访问即可，无需配置证书。

### 启动 / 停止

```bash
# 启动 Caddy
docker compose up -d caddy

# 重载配置（修改站点后）
docker compose restart caddy

# 查看日志
docker compose logs -f caddy

# 停止
docker compose stop caddy
```

### 目录结构

```
core/caddy/
├── Caddyfile                  # 主配置（全局设置 + 导入 sites/）
├── sites/                     # 站点配置目录
│   ├── _template.caddy.example   # 站点配置模板（保留，不改名）
│   └── myapp.caddy            # 你的站点配置（以 .caddy 结尾）
├── data/                      # 证书、日志等运行时数据（已 gitignore）
├── config/                    # Caddy 配置存储
└── .gitignore
```

### 添加 PHP 站点（核心流程）

以添加一个 Yii2 项目 `my-shop` 到 PHP 8.3 为例：

#### 第 1 步：确保 PHP-FPM 容器运行

```bash
docker compose up -d php83
# 确认容器名为 php83，Caddy 通过 php83:9000 连接
```

#### 第 2 步：创建站点配置文件

在 `core/caddy/sites/` 下创建 `myshop.caddy`（文件名即站点标识）：

```caddy
# 站点: my-shop
# PHP: 8.3
myshop.local.pandora {
    root * /var/www/apps/personal/my-shop/public

    # PHP-FPM 连接（容器名:9000）
    php_fastcgi php83:9000

    # 静态文件直接返回
    file_server

    # Yii2 / Laravel / ThinkPHP 伪静态
    @notStatic {
        not file
    }
    rewrite @notStatic /index.php
}
```

> **路径规则**: Caddy 挂载了 `../apps:/var/www/apps`，站点根目录写 `/var/www/apps/<company>/<project>/public`

#### 第 3 步：添加 hosts

编辑 `C:\Windows\System32\drivers\etc\hosts`（管理员权限）：

```
127.0.0.1 myshop.local.pandora
```

#### 第 4 步：重载 Caddy

```bash
cd core && docker compose restart caddy
```

#### 第 5 步：打开浏览器

```
http://myshop.local.pandora
```

### 站点配置速查

#### 普通 PHP 项目

```caddy
myapp.local.pandora {
    root * /var/www/apps/personal/my-app/public
    php_fastcgi php83:9000
    file_server
}
```

#### Laravel / Yii2 / ThinkPHP（伪静态）

```caddy
myapp.local.pandora {
    root * /var/www/apps/personal/my-app/public
    php_fastcgi php83:9000
    file_server

    @notStatic { not file }
    rewrite @notStatic /index.php
}
```

#### PHP 7.4 项目

将 `php_fastcgi php83:9000` 改为 `php_fastcgi php74:9000` 即可。

#### 静态站点

```caddy
docs.local.pandora {
    root * /var/www/apps/personal/docsify
    file_server
}
```

#### 反向代理（Hyperf / Webman / Go 服务）

```caddy
api.local.pandora {
    reverse_proxy maxadmin-api:8787
}
```

#### 多域名指向同站点

```caddy
myapp.local.pandora, www.myapp.local.pandora {
    root * /var/www/apps/personal/my-app/public
    php_fastcgi php83:9000
    file_server
}
```

#### 自定义 HTTP 响应头

```caddy
myapp.local.pandora {
    root * /var/www/apps/personal/my-app/public
    php_fastcgi php83:9000
    file_server

    header Access-Control-Allow-Origin "*"
}
```

### 环境变量

在 `.env` 中可修改 Caddy 的监听端口：

```bash
# 如果 80 端口冲突，改为 8080
CADDY_HTTP_PORT=8080
CADDY_HTTPS_PORT=8443
```

### 常见问题

**Q: 修改 Caddyfile 后没生效？**  
A: 必须 restart（不是 reload）：`docker compose restart caddy`

**Q: 访问站点 502 Bad Gateway？**  
A: 检查 PHP-FPM 容器是否在运行：`docker compose ps php83`。确保 php_fastcgi 指向了正确的容器名（`php83:9000` 或 `php74:9000`）。

**Q: 访问站点 404？**  
A: 检查 root 路径是否正确。进入 Caddy 容器验证：`docker exec caddy ls /var/www/apps/personal/`

**Q: 80 端口被占用？**  
A: 修改 `.env` 中 `CADDY_HTTP_PORT=8080`，然后 `docker compose up -d caddy`

---
## OpenResty — 统一网关

基于 OpenResty（Nginx + Lua）的 Web 管理面板，浏览器中可视化管理站点、证书、反代规则。

### 访问

| 入口 | 地址 |
|------|------|
| **管理界面** | `https://localhost:8808` |
| **HTTP** | `http://localhost:80` |
| **HTTPS** | `https://localhost:443` |

> 管理界面走 HTTPS 自签名证书，浏览器提示不安全时点「继续访问」即可。

### 添加 PHP 站点（FPM 模式）

以添加一个 PHP 8.3 项目 `my-app` 为例：

1. 确保源码放在 `apps/personal/my-app/public/`，入口文件为 `index.php`
2. 打开管理界面 `https://localhost:8808`，登录
3. 进入 **站点管理** → **添加站点**
4. 填写域名 `myapp.local.pandora`
5. 配置 **PHP 解析**：
   - 目标地址：`php83`
   - 端口：`9000`

如果站点需要伪静态（Laravel / ThinkPHP），在站点配置中开启 URL 重写即可。

> openresty 挂载了 `../apps:/var/www/apps`，站点根目录填 `/var/www/apps/personal/<project>/public`

### 其他站点类型

**静态站点**：站点管理中选「静态文件」模式，指定 root 目录即可。

**反向代理**（如 Hyperf Swoole 项目）：站点管理中选「反向代理」，目标 `hyperf-backend:9501`。

**SSL 证书**：管理界面支持一键 Let's Encrypt 签发，或上传自有证书。

---

## PHP FPM 容器

每个 PHP 大版本一个容器，通过 `./Dockerfile.php7x` 构建：

| 版本 | Dockerfile | 扩展 |
|------|-----------|------|
| 7.4 | `Dockerfile.php74` | pdo_mysql, mbstring, gd, zip, exif, pcntl, bcmath + Composer |
| 8.3 | `Dockerfile.php83` | 同上 + linux-headers |

所有 FPM 容器挂载 `../apps:/var/www/apps:ro`，源码在宿主机编辑即可。

**新增 PHP 版本**：

1. 创建 `core/Dockerfile.php8x`
2. 在 `docker-compose.yml` 添加服务（复制 php83 那段，改名字）
3. `docker compose up -d --build php8x`

---

## MySQL & Redis

- **MySQL 8.0** — 自定义配置见 `mysql/conf.d/custom.cnf`，初始化 SQL 放 `mysql/init/`（仅首次启动执行）
- **Redis 7** — 配置见 `redis/redis.conf`

同网络容器连接方式：

```
host=mysql, port=3306, user=root, password=${MYSQL_ROOT_PASSWORD}
host=redis, port=6379, password=${REDIS_PASSWORD}
```

---

## DPanel — Docker 管理

访问 `http://localhost:8807`，可视化管理容器、镜像、网络、数据卷。

---

## 使用方法

```bash
# 首次：创建共享网络（仅一次）
docker network create 1panel-network

# 启动全部核心服务
cd core && docker compose up -d

# 只启动本地开发所需服务（Caddy + PHP + DB）
docker compose up -d caddy php74 php83 mysql redis

# 查看状态
docker compose ps

# 日志
docker compose logs -f caddy

# 重载 Caddy（修改站点配置后）
docker compose restart caddy
```

---

## 添加新项目（完整流程）

### 本地开发（Caddy，推荐）

```bash
# 1. 创建项目目录
mkdir -p apps/personal/my-app/public
echo '<?php phpinfo();' > apps/personal/my-app/public/index.php

# 2. 创建站点配置文件 core/caddy/sites/myapp.caddy
#    参考上方「添加 PHP 站点（核心流程）」部分

# 3. 添加 hosts: 127.0.0.1 myapp.local.pandora

# 4. 重载 Caddy
cd core && docker compose restart caddy

# 5. 打开 http://myapp.local.pandora
```

### 线上生产（OpenResty）

```bash
# 1. 创建项目目录
mkdir -p apps/personal/my-app/public
echo '<?php phpinfo();' > apps/personal/my-app/public/index.php

# 2. 打开 https://localhost:8808 → 站点管理 → 添加站点
#    - 域名：myapp.local.pandora
#    - PHP 解析 → 目标：php83:9000
#    - 根目录：/var/www/apps/personal/my-app/public
#    - （如需要）开启 URL 重写（伪静态）

# 3. 配置 hosts 后访问
#    127.0.0.1 myapp.local.pandora
#    open http://myapp.local.pandora
```

---

## 数据持久化

| 卷名 | 用途 |
|------|------|
| `core_mysql-data` | MySQL 数据 |
| `core_redis-data` | Redis 持久化 |
| `core_woodpecker-data` | Woodpecker 数据 |
| `core_dpanel-data` | DPanel 配置 |
