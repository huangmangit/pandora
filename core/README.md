# Core — 核心基础服务

> 所有项目共享的底层基础设施，一版本一容器，一次部署长期运行。

---

## 服务清单

| 服务 | 镜像 | 端口 | 容器名 |
|------|------|------|--------|
| Caddy | `caddy:alpine` | 80, 443 | `caddy` |
| PHP 7.4 | 自构建 (`Dockerfile.php74`) | — | `php74` |
| PHP 8.3 | 自构建 (`Dockerfile.php83`) | — | `php83` |
| MySQL | `mysql:8.0` | 3306 | `mysql` |
| Redis | `redis:7-alpine` | 6379 | `redis` |
| DPanel | `dpanel/dpanel:latest` | 8807 | `dpanel` |
| Woodpecker Server | `woodpeckerci/woodpecker-server:latest` | 8000 | `woodpecker-server` |
| Woodpecker Agent | `woodpeckerci/woodpecker-agent:latest` | — | `woodpecker-agent` |
| Nginx Proxy Manager | `jc21/nginx-proxy-manager:latest` | 8180/8443/8181 | `nginx-proxy-manager` (production profile) |

---

## 架构

```
                          caddy (:80/:443)
                               │
          ┌────────────────────┼────────────────────┐
          ▼                    ▼                    ▼
       php74                 php83              静态/反代
       (PHP-FPM 7.4)         (PHP-FPM 8.3)         ...
          │                    │
          └──────────┬─────────┘
                     │
              mysql (:3306)
              redis (:6379)

   所有容器加入 pandora-net（bridge），容器名直连。
   apps/ 源码同时挂载到 Caddy 和所有 FPM 容器（只读），路径一致。
```

---

## 环境变量（`.env`）

| 变量 | 服务 | 说明 | 默认值 |
|------|------|------|--------|
| `MYSQL_ROOT_PASSWORD` | MySQL | root 密码 | `pandora123` |
| `MYSQL_DATABASE` | MySQL | 默认数据库 | `pandora` |
| `REDIS_PASSWORD` | Redis | 认证密码 | `pandora123` |
| `WOODPECKER_HOST` | Server | 对外地址 | `http://localhost:8000` |
| `WOODPECKER_GITEA_URL` | Server | Git 服务地址 | `http://gitea:3000` |
| `WOODPECKER_AGENT_SECRET` | Server+Agent | 通信密钥 | `change-me-to-random-string` |
| `WOODPECKER_ADMIN` | Server | 管理员 | `admin` |
| `DPANEL_PORT` | DPanel | 面板端口 | `8807` |
| `NPM_HTTP_PORT` | NPM | HTTP（备用） | `8180` |
| `NPM_HTTPS_PORT` | NPM | HTTPS（备用） | `8443` |
| `NPM_ADMIN_PORT` | NPM | 管理界面 | `8181` |

---

## Caddy 站点配置

所有站点配置集中在 `core/Caddyfile`，修改后执行 `caddy reload` 即可生效，无需重启容器。

### 配置文件结构

```caddyfile
{
    auto_https off          # 本地开发关闭自动 HTTPS
}

:80 {
    # 站点1
    @site1 host site1.local.pandora
    handle @site1 {
        root * /var/www/apps/personal/site1/public
        php_fastcgi php74:9000
    }

    # 站点2
    @site2 host site2.local.pandora
    handle @site2 {
        root * /var/www/apps/personal/site2/public
        php_fastcgi php83:9000
    }
}
```

### 添加 PHP 站点（FPM 模式）

假设要添加一个 PHP 8.3 项目 `my-app`，源码在 `apps/personal/my-app/public/`：

**步骤 1** — 在 `Caddyfile` 的 `:80 {}` 块内添加：

```caddyfile
    @myapp host myapp.local.pandora
    handle @myapp {
        root * /var/www/apps/personal/my-app/public
        php_fastcgi php83:9000
    }
```

**步骤 2** — 重载 Caddy：

```bash
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**步骤 3** — 浏览器访问（需配 hosts 指向 `127.0.0.1`）：

```
http://myapp.local.pandora
```

### 关键说明

| 要点 | 说明 |
|------|------|
| **域名匹配** | `@name host <domain>` 定义一个 host 匹配器 |
| **root 路径** | Caddy 和 FPM 都挂载了 `../apps:/var/www/apps`，路径从 `<project>/public` 开始 |
| **php_fastcgi** | `php74:9000` 或 `php83:9000`，按项目需要的 PHP 版本选 |
| **配置生效** | `caddy reload` 热重载，不停机 |

### 其他站点类型

**静态站点**：

```caddyfile
    @static host static.local.pandora
    handle @static {
        root * /var/www/apps/personal/static-site
        file_server
    }
```

**反向代理**（如 Hyperf Swoole 项目）：

```caddyfile
    @hyperf host hyperf.local.pandora
    handle @hyperf {
        reverse_proxy hyperf-backend:9501
    }
```

**前后端分离**（前端静态 + 后端 FPM）：

```caddyfile
    @split host split.local.pandora
    handle @split {
        handle_path /api/* {
            php_fastcgi php83:9000
        }
        handle {
            root * /var/www/apps/personal/split/frontend
            file_server
        }
    }
```

### 伪静态（URL Rewrite）

所有请求重写到 `index.php`，Laravel、ThinkPHP 等框架通用。核心是用 `php_fastcgi` 的 `try_files` 子指令代替手写 rewrite 规则。

**Laravel**：

```caddyfile
    @laravel host laravel.local.pandora
    handle @laravel {
        root * /var/www/apps/personal/laravel/public
        php_fastcgi php83:9000 {
            try_files {path} /index.php?{query}
        }
    }
```

**ThinkPHP**：

```caddyfile
    @thinkphp host thinkphp.local.pandora
    handle @thinkphp {
        root * /var/www/apps/personal/thinkphp/public
        php_fastcgi php83:9000 {
            try_files {path} /index.php?{query}
        }
    }
```

**无 public 目录的项目**（老版 ThinkPHP 等入口在根目录）：

```caddyfile
    @oldtp host oldtp.local.pandora
    handle @oldtp {
        root * /var/www/apps/personal/oldtp
        php_fastcgi php74:9000 {
            try_files {path} /index.php?{query}
        }
    }
```

| 框架 | 入口文件 | root 路径 | 规律 |
|------|---------|-----------|------|
| Laravel | `public/index.php` | `<project>/public` | `try_files {path} /index.php?{query}` |
| ThinkPHP 6+ | `public/index.php` | `<project>/public` | 同上 |
| ThinkPHP 3/5 | `index.php` | `<project>` | 同上，root 少一层 |

> **原理**：`try_files {path} /index.php?{query}` 先尝试请求的实际文件路径，不存在则 Fallback 到 `index.php?{query}`，完全替代 nginx 的 `try_files $uri $uri/ /index.php?$query_string`。

### 线上开启 HTTPS

把 `auto_https off` 改为 `auto_https on` 或直接删除该行（默认开启），Caddy 自动从 Let's Encrypt 签发证书。

> **注意**：`auto_https on` 时不要用 `:80` 块，直接写域名即可（Caddy 会自动处理 HTTP→HTTPS 重定向）。

---

## PHP FPM 容器

每个 PHP 大版本一个容器，通过 `./Dockerfile.php7x` 构建，扩展统一管理：

| 版本 | Dockerfile | 扩展 |
|------|-----------|------|
| 7.4 | `Dockerfile.php74` | pdo_mysql, mbstring, gd, zip, exif, pcntl, bcmath + Composer |
| 8.3 | `Dockerfile.php83` | 同上 + linux-headers |

所有 FPM 容器挂载 `../apps:/var/www/apps:ro`（只读），源码在宿主机编辑即可。

**新增 PHP 版本**：

1. 创建 `core/Dockerfile.php8x`
2. 在 `docker-compose.yml` 添加服务（复制 php83 那段，改名字）
3. 构建并加入 `pandora-net`

---

## MySQL & Redis

- **MySQL 8.0** — 自定义配置见 `mysql/conf.d/custom.cnf`，初始化 SQL 放 `mysql/init/`（仅首次启动执行）
- **Redis 7** — 配置见 `redis/redis.conf`，默认密码 + AOF 持久化 + 128MB 上限

连接方式（同网络容器）：

```
host=mysql, port=3306, user=root, password=${MYSQL_ROOT_PASSWORD}
host=redis, port=6379, password=${REDIS_PASSWORD}
```

---

## DPanel — Docker 管理面板

访问 `http://<host>:8807`，可视化管理容器、镜像、网络、数据卷。

---

## Nginx Proxy Manager（备用）

仅 `production` profile 启动，用于线上环境替代 Caddy：

```bash
docker compose --profile production up -d nginx-proxy-manager
```

---

## 使用方法

```bash
# 启动全部
cd core && docker compose up -d

# 单独启动
docker compose up -d caddy php74 php83 mysql redis

# 查看状态
docker compose ps

# 日志
docker compose logs -f caddy
docker compose logs -f php74

# 重载 Caddy 配置（修改 Caddyfile 后）
docker exec caddy caddy reload --config /etc/caddy/Caddyfile
```

---

## 数据持久化

| 卷名 | 用途 |
|------|------|
| `core_mysql-data` | MySQL 数据 |
| `core_redis-data` | Redis 持久化 |
| `core_caddy-data` | Caddy 证书/配置 |
| `core_woodpecker-data` | Woodpecker 数据 |
| `core_dpanel-data` | DPanel 配置 |
| `core_npm-data` | NPM 配置 |
| `core_npm-letsencrypt` | NPM SSL 证书 |

---

## 添加新项目完整流程

以添加一个 PHP 8.3 的 `blog` 项目为例：

```bash
# 1. 创建项目目录和入口文件
mkdir -p apps/personal/blog/public
echo '<?php phpinfo();' > apps/personal/blog/public/index.php

# 2. 在 core/Caddyfile 的 :80 {} 块内添加
#    @blog host blog.local.pandora
#    handle @blog {
#        root * /var/www/apps/personal/blog/public
#        php_fastcgi php83:9000
#    }

# 3. 重载 Caddy
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# 4. 本地 hosts 添加（如需要）
#    127.0.0.1 blog.local.pandora

# 5. 浏览器访问 http://blog.local.pandora
```
