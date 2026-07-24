# Pandora — 统一容器化部署平台

> 造船厂：所有项目从构建到部署的完整容器化方案，基于 Docker Compose + Caddy + Woodpecker CI/CD。

---

## 目录结构

```
pandora/
│
├── core/                                    # ═══ 核心基础服务 ═══
│   ├── docker-compose.yml                   #     Caddy + PHP-FPM + MySQL + Redis + DPanel + Woodpecker
│   ├── Caddyfile                            #     统一网关配置（所有站点在此管理）
│   ├── Dockerfile.php74                     #     PHP 7.4 FPM 镜像
│   ├── Dockerfile.php83                     #     PHP 8.3 FPM 镜像
│   ├── .env                                 #     环境变量
│   ├── mysql/
│   │   ├── conf.d/                          #     自定义配置
│   │   └── init/                            #     初始化 SQL
│   ├── redis/
│   │   └── redis.conf
│   └── woodpecker/                          #     CI/CD 服务
│
├── apps/                                    # ═══ 业务项目 ═══
│   ├── personal/                            # ── 个人项目 ──
│   │   ├── docker-compose.yml               #     个人项目编排
│   │   ├── demo-php74/public/               #     PHP 7.4 Demo（纯源码，无容器）
│   │   ├── demo-php83/public/               #     PHP 8.3 Demo（纯源码，无容器）
│   │   └── ...
│   ├── company-a/                           # ── A公司项目 ──
│   │   ├── docker-compose.yml
│   │   └── ...
│   ├── company-b/                           # ── B公司项目 ──
│   ├── outsource-a/                         # ── 外包A ──
│   └── outsource-b/                         # ── 外包B ──
│
├── shared/                                  # ═══ 跨项目共享 ═══
│   ├── docker/
│   │   ├── php-fpm.Dockerfile               #     PHP 8.1 模板
│   │   └── hyperf.Dockerfile                #     Hyperf 镜像
│   └── scripts/deploy.sh
│
├── docker-compose.yml                       # ═══ 顶层入口（include 所有分组） ═══
├── Makefile
└── README.md
```

---

## 设计理念

| 原则 | 说明 |
|------|------|
| **基础服务集中管理** | Caddy、MySQL、Redis、FPM 统一放 `core/`，一次部署长期运行 |
| **PHP 版本即容器** | FPM 项目不建独立容器——每个 PHP 大版本一个容器，所有同版项目共享 |
| **Caddy 统一网关** | `core/Caddyfile` 管理全部站点，3 行配置一个域名，`caddy reload` 热重载 |
| **源码与容器分离** | `apps/` 只放项目源码，FPM 和 Caddy 通过 volume 挂载共用 |

### 核心架构

```
                         caddy (:80/:443)
                              │
         ┌────────────────────┼────────────────────┐
         ▼                    ▼                    ▼
      php74                 php83              静态/反代
   (PHP-FPM 7.4)        (PHP-FPM 8.3)       (Hyperf 等)
         │                    │
         └──────────┬─────────┘
                    │
             mysql (:3306)
             redis (:6379)

    所有容器加入 pandora-net（bridge），容器名直连。
    apps/ 源码同时挂载到 Caddy 和所有 FPM 容器，路径一致。
```

---

## 快速开始

```bash
# 1. 启动核心服务
cd core && docker compose up -d

# 2. 访问 Demo 站点（需配 hosts: 127.0.0.1 php74.local.pandora）
open http://php74.local.pandora   # PHP 7.4 phpinfo
open http://php83.local.pandora   # PHP 8.3 phpinfo

# 3. 管理面板
open http://localhost:8807         # DPanel — Docker 可视化管理
open http://localhost:8000         # Woodpecker — CI/CD 管理
```

---

## 添加项目

### FPM 项目（Laravel / ThinkPHP / Yii2）

只需放源码 + 在 `Caddyfile` 加 4 行：

```bash
# 1. 创建项目目录，放源码
mkdir -p apps/personal/my-blog/public
echo '<?php phpinfo();' > apps/personal/my-blog/public/index.php

# 2. 编辑 core/Caddyfile，在 :80 {} 块内添加：
#    @myblog host myblog.local.pandora
#    handle @myblog {
#        root * /var/www/apps/personal/my-blog/public
#        php_fastcgi php83:9000
#    }

# 3. 热重载 Caddy
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# 4. 访问
open http://myblog.local.pandora
```

### 伪静态（Laravel / ThinkPHP）

只需在 `php_fastcgi` 后加 `try_files`：

```caddyfile
php_fastcgi php83:9000 {
    try_files {path} /index.php?{query}
}
```

### Hyperf / Swoole 项目（自带 HTTP Server）

项目需要自己的 `docker-compose.yml`，Caddy 只需一行反代：

```caddyfile
handle @hyperf {
    reverse_proxy hyperf-backend:9501
}
```

### 前端静态项目

```caddyfile
handle @static {
    root * /var/www/apps/personal/static-site
    file_server
}
```

---

## 服务一览

| 服务 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| Caddy | `caddy` | 80, 443 | 统一网关，`Caddyfile` 管理站点 |
| PHP 7.4 | `php74` | 9000（内部） | FPM，挂载 `../apps` |
| PHP 8.3 | `php83` | 9000（内部） | FPM，挂载 `../apps` |
| MySQL | `mysql` | 3306 | `mysql:8.0`，自动建库 |
| Redis | `redis` | 6379 | `redis:7-alpine` |
| DPanel | `dpanel` | 8807 | Docker 可视化管理 |
| Woodpecker Server | `woodpecker-server` | 8000 | CI/CD 管理端 |
| Woodpecker Agent | `woodpecker-agent` | — | CI 执行器 |
| Nginx Proxy Manager | `nginx-proxy-manager` | 8180（备用） | 仅 `--profile production` 启动 |

---

## 常用命令

```bash
# 核心服务
cd core
docker compose up -d                    # 启动全部
docker compose up -d caddy php83 mysql  # 指定服务
docker compose ps                       # 查看状态
docker compose logs -f caddy            # 查看日志

# 重载 Caddy 配置（修改 Caddyfile 后）
docker exec caddy caddy reload --config /etc/caddy/Caddyfile

# 按分组启动
docker compose -f apps/personal/docker-compose.yml up -d

# 进入容器
docker exec -it mysql mysql -u root -p
docker exec -it redis redis-cli
docker exec -it php83 sh
```

---

## 网络

所有容器加入 `pandora-net`（bridge），容器名即 hostname：

```
Caddyfile 中写 php83:9000 → 自动解析到 pandora-php83 容器
项目 .env 中写 DB_HOST=mysql → 自动解析到 pandora-mysql 容器
```

---

## 环境变量

主要配置集中在 `core/.env`：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码 | `pandora123` |
| `MYSQL_DATABASE` | 默认数据库 | `pandora` |
| `REDIS_PASSWORD` | Redis 密码 | `pandora123` |
| `WOODPECKER_HOST` | CI 访问地址 | `http://localhost:8000` |
| `WOODPECKER_AGENT_SECRET` | CI 通信密钥 | 请修改 |
| `DPANEL_PORT` | DPanel 面板端口 | `8807` |

---

## 线上部署

本地用 Caddy，线上可选切到 Nginx Proxy Manager：

```bash
# 线上启动 NPM（需先停掉 caddy 释放 80/443）
docker compose stop caddy
cd core && docker compose --profile production up -d nginx-proxy-manager
```

NPM 管理界面：`http://<host>:8181`，默认账号 `admin@example.com` / `changeme`。

---

## 更多

- [Caddy 站点配置详解](core/README.md)（伪静态、HTTPS、前后端分离等）
- CI/CD 流程见各项目 `.woodpecker.yml`
