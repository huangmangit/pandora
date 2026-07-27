# 潘多拉魔盒 — 统一容器化部署平台

> 一个管理所有项目的"总控台"。

## 初衷

在日常开发中，我们常常同时维护多个项目——个人练手项目、公司正式项目、外包项目——它们分布在不同的目录下，使用不同的 PHP 版本，各自启动一堆 Docker 容器。切换项目时要停一组、起一组，端口冲突、网络隔离、配置散落一地。

Pandora 的目标是把这些散乱的容器全部收拢到一个地方：

- **基础设施集中**：MySQL、Redis、网关这些底层服务只需部署一次，所有项目共享
- **PHP 版本统一管理**：每个大版本（7.4 / 8.3）只跑一个 FPM 容器，项目不再需要自己的 PHP 容器，纯源码放进去就行
- **站点 Web UI 管理**：通过 OpenResty 在浏览器中管理域名、SSL、反代、PHP 解析，不用再手写 nginx 配置
- **按主体分组**：`apps/` 下按 personal / company-a / outsource-b 等项目归属分组，权限和关注点清晰分离

目前已适配：

- ✅ PHP FPM 模式（7.4 / 8.3），入口文件 → OpenResty 反代 → FPM 容器处理
- ✅ Swoole / Hyperf 模式（自带 HTTP Server），OpenResty 直接反代
- ✅ 所有核心容器一键启动，分组编排独立启停
- ✅ Woodpecker CI/CD 流水线（待接入项目）

技术栈：Docker Compose + OpenResty (Nginx + Lua) + PHP-FPM + MySQL + Redis + Woodpecker。

---

## 目录结构

```
pandora/
│
├── core/                                    # ═══ 核心基础服务 ═══
│   ├── docker-compose.yml                   #     所有核心容器编排
│   ├── .env                                 #     环境变量
│   ├── Dockerfile.php74                     #     PHP 7.4 FPM 镜像
│   ├── Dockerfile.php83                     #     PHP 8.3 FPM 镜像
│   ├── openresty/                           #     OpenResty 配置 & 证书（自动生成）
│   │   ├── conf/                            #     nginx 配置
│   │   │   ├── conf.d/                      #     站点配置
│   │   │   ├── sites/                       #     站点数据
│   │   │   └── certs/                       #     SSL 证书
│   │   ├── data/                            #     面板数据 & CA
│   │   └── acme/                            #     Let's Encrypt
│   ├── mysql/
│   │   ├── conf.d/                          #     自定义配置
│   │   └── init/                            #     初始化 SQL
│   ├── redis/
│   │   └── redis.conf
│   └── woodpecker/                          #     CI/CD 服务
│
├── apps/                                    # ═══ 业务项目 ═══
│   ├── personal/                            # ── 个人项目 ──
│   │   ├── docker-compose.yml               #     分组编排
│   │   ├── demo-php74/public/               #     PHP 7.4 Demo（纯源码）
│   │   ├── demo-php83/public/               #     PHP 8.3 Demo（纯源码）
│   │   ├── demo-blog/                       #     Yii2 博客 Demo
│   │   └── demo-portfolio/                  #     Hyperf 作品集 Demo
│   ├── company-a/                           # ── A公司项目 ──
│   │   ├── docker-compose.yml
│   │   └── demo-admin/                      #     Yii2 后台管理 Demo
│   ├── company-b/                           # ── B公司项目 ──
│   │   └── ...
│   ├── outsource-a/                         # ── 外包A ──
│   │   ├── docker-compose.yml
│   │   └── demo-landing/                    #     Yii2 落地页 Demo
│   └── outsource-b/                         # ── 外包B ──
│       └── ...
│
├── docker-compose.yml                       # ═══ 顶层入口 ═══
├── Makefile
└── README.md
```
│
├── docker-compose.yml                       # ═══ 顶层入口（include 所有分组） ═══
├── Makefile
└── README.md
```

---

## 设计理念

| 原则 | 说明 |
|------|------|
| **基础服务集中管理** | OpenResty、MySQL、Redis、FPM 统一放 `core/`，一次部署长期运行 |
| **PHP 版本即容器** | FPM 项目不建独立容器——每个 PHP 大版本一个容器，所有同版项目共享 |
| **OpenResty 统一网关** | Web UI 管理全部站点，域名/SSL/反代/PHP 解析一站式配置 |
| **源码与容器分离** | `apps/` 只放项目源码，FPM 和 OpenResty 通过 volume 挂载共用 |

### 核心架构

```
                         openresty (:80/:443)
                         (Web UI: https://:8808)
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
    apps/ 源码同时挂载到 OpenResty 和所有 FPM 容器，路径一致。
```

---

## 快速开始

```bash
# 0. 首次使用需创建共享网络（仅一次）
docker network create pandora-net

# 1. 启动核心服务
cd core && docker compose up -d

# 2. 访问 Demo 站点（需配 hosts: 127.0.0.1 php74.local.pandora）
open http://php74.local.pandora   # PHP 7.4 phpinfo
open http://php83.local.pandora   # PHP 8.3 phpinfo

# 3. 管理面板
open https://localhost:8808          # OpenResty — 站点管理
open http://localhost:8807           # DPanel — Docker 管理
open http://localhost:8000         # Woodpecker — CI/CD 管理
```

---

## 添加项目

### FPM 项目（Laravel / ThinkPHP / Yii2）

只需放源码，然后通过 Web UI 配置站点：

```bash
# 1. 创建项目目录，放源码
mkdir -p apps/personal/my-blog/public
echo '<?php phpinfo();' > apps/personal/my-blog/public/index.php

# 2. 打开 https://localhost:8808 → 站点管理 → 添加站点
#    - 域名：myblog.local.pandora
#    - PHP 解析：php83:9000
#    - 根目录：/var/www/apps/personal/my-blog/public
#    - 开启 URL 重写（如需要伪静态）

# 3. 访问
open http://myblog.local.pandora
```

### 伪静态（Laravel / ThinkPHP）

Web UI 中站点配置页开启「URL 重写」即可，无需手写规则。等效于 nginx 的 `try_files $uri $uri/ /index.php?$query_string`。

### Hyperf / Swoole 项目（自带 HTTP Server）

项目需要自己的 `docker-compose.yml`，在 openresty 中配置反代：

Web UI → 站点管理 → 添加站点 → 选「反向代理」→ 目标 `hyperf-backend:9501`

### 前端静态项目

Web UI → 站点管理 → 添加站点 → 选「静态文件」→ 指定 root 目录

---

## 服务一览

| 服务 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| OpenResty | `openresty` | 80, 443, 8808 | 统一网关 + Web UI 管理站点 |
| PHP 7.4 | `php74` | 9000（内部） | FPM，挂载 `../apps` |
| PHP 8.3 | `php83` | 9000（内部） | FPM，挂载 `../apps` |
| MySQL | `mysql` | 3306 | `mysql:8.0`，自动建库 |
| Redis | `redis` | 6379 | `redis:7-alpine` |
| DPanel | `dpanel` | 8807 | Docker 可视化管理 |
| Woodpecker Server | `woodpecker-server` | 8000 | CI/CD 管理端 |
| Woodpecker Agent | `woodpecker-agent` | — | CI 执行器 |

---

## 常用命令

```bash
# 核心服务
cd core
docker compose up -d                    # 启动全部
docker compose up -d openresty php83 mysql  # 指定服务
docker compose ps                       # 查看状态
docker compose logs -f openresty # 查看日志

# 重载配置（或用 Web UI 中的重载按钮）
docker exec openresty nginx -s reload

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
php83:9000  → 自动解析到 php83 容器
DB_HOST=mysql → 自动解析到 mysql 容器
```

> 网络在 `core/docker-compose.yml` 中声明为 `external: true`，需要**手动创建**（仅一次）：
>
> ```bash
> docker network create pandora-net
> ```

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

---

## 更多

- [站点管理指南](core/README.md)（如何通过 Web UI 添加站点、配置 PHP、SSL、伪静态）
- CI/CD 流程见各项目 `.woodpecker.yml`
