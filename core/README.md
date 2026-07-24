# Core — 核心基础服务

> 所有业务项目共享的底层基础设施，一次部署长期运行，很少变动。

---

## 架构概览

```
┌──────────────────────────────────────────────────────────────────┐
│                         core/                                     │
│                                                                   │
│   ┌──────────┐  ┌──────────┐  ┌───────────────────────┐          │
│   │  MySQL   │  │  Redis   │  │ Nginx Proxy Manager   │          │
│   │  :3306   │  │  :6379   │  │  :80 / :443 / :81     │          │
│   └────┬─────┘  └────┬─────┘  │  (Web UI 管理反代)     │          │
│        │             │        └───────────┬───────────┘          │
│        │             │                    │  反代到 apps/        │
│        │             │                    │  下所有项目           │
│        └──────┬──────┘                    │                      │
│               │                           │                      │
│        ┌──────┴──────┐           ┌───────┴───────┐  ┌──────────┐ │
│        │ pandora-net │           │  Woodpecker   │  │  DPanel  │ │
│        │  (bridge)   │           │  CI/CD :8000  │  │  :8807   │ │
│        └─────────────┘           └───────────────┘  └──────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## 服务清单

| 服务 | 镜像 | 端口 | 容器名 |
|------|------|------|--------|
| MySQL | `mysql:8.0` | 3306 | `pandora-mysql` |
| Redis | `redis:7-alpine` | 6379 | `pandora-redis` |
| Nginx Proxy Manager | `jc21/nginx-proxy-manager:latest` | 80, 443, 81 | `pandora-npm` |
| Woodpecker Server | `woodpeckerci/woodpecker-server:latest` | 8000 | `pandora-woodpecker-server` |
| Woodpecker Agent | `woodpeckerci/woodpecker-agent:latest` | — | `pandora-woodpecker-agent` |
| DPanel | `dpanel/dpanel:latest` | 8807 | `pandora-dpanel` |

---

## 环境变量（`.env`）

所有核心服务的配置集中在 `core/.env`，修改后重启生效。

| 变量 | 服务 | 说明 | 默认值 |
|------|------|------|--------|
| `MYSQL_ROOT_PASSWORD` | MySQL | root 密码，**生产环境务必修改** | `pandora123` |
| `MYSQL_DATABASE` | MySQL | 初始化时创建的默认数据库 | `pandora` |
| `REDIS_PASSWORD` | Redis | Redis 认证密码 | `pandora123` |
| `WOODPECKER_HOST` | Server | Woodpecker 对外访问地址 | `http://localhost:8000` |
| `WOODPECKER_GITEA_URL` | Server | Gitea / Git 服务地址 | `http://gitea:3000` |
| `WOODPECKER_AGENT_SECRET` | Server + Agent | Agent 通信密钥，**务必改为随机字符串** | `change-me-to-random-string` |
| `WOODPECKER_ADMIN` | Server | 管理员用户名 | `admin` |
| `DPANEL_PORT` | DPanel | 面板访问端口（宿主机） | `8807` |
| `NPM_ADMIN_PORT` | Proxy Manager | 管理界面端口 | `81` |

> **安全提示**：首次部署前，请至少修改 `MYSQL_ROOT_PASSWORD`、`REDIS_PASSWORD` 和 `WOODPECKER_AGENT_SECRET` 三项。

---

## 各服务详解

### 1. MySQL — 关系型数据库

| 属性 | 值 |
|------|-----|
| 镜像 | `mysql:8.0` |
| 内部端口 | 3306 |
| 对外端口 | 3306 |
| 数据卷 | `mysql-data` → `/var/lib/mysql` |
| 配置挂载 | `mysql/conf.d/` → `/etc/mysql/conf.d/`（只读） |
| 初始化脚本 | `mysql/init/` → `/docker-entrypoint-initdb.d/`（只读） |
| 健康检查 | `mysqladmin ping` / 10s 间隔 / 5s 超时 / 5 次重试 |

**自定义配置** (`mysql/conf.d/custom.cnf`)：

```ini
[mysqld]
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci
default-time-zone    = '+08:00'
max_connections      = 200
innodb_buffer_pool_size = 256M
```

**初始化脚本** (`mysql/init/01-init.sql`)：

容器首次启动时自动执行，为各 demo 项目预建数据库。新增项目时在此目录添加 `.sql` 文件即可，已存在的数据库不会被覆盖。

**连接方式**：

```bash
# 宿主机
mysql -h 127.0.0.1 -P 3306 -u root -p

# 同网络其他容器：直接用容器名
# host=mysql, port=3306, user=root, password=${MYSQL_ROOT_PASSWORD}
```

---

### 2. Redis — 缓存 & 队列

| 属性 | 值 |
|------|-----|
| 镜像 | `redis:7-alpine` |
| 内部端口 | 6379 |
| 对外端口 | 6379 |
| 数据卷 | `redis-data` → `/data` |
| 配置挂载 | `redis/redis.conf` → `/usr/local/etc/redis/redis.conf`（只读） |
| 启动命令 | `redis-server /usr/local/etc/redis/redis.conf` |
| 健康检查 | `redis-cli ping` / 10s 间隔 / 5s 超时 / 5 次重试 |

**自定义配置** (`redis/redis.conf`)：

```conf
port 6379
bind 0.0.0.0
requirepass pandora123
maxmemory 128mb
maxmemory-policy allkeys-lru
save 300 10
save 60 10000
dir /data
appendonly yes
```

**连接方式**：

```bash
# 宿主机
redis-cli -h 127.0.0.1 -p 6379 -a pandora123

# 同网络其他容器
# host=redis, port=6379, password=${REDIS_PASSWORD}
```

---

### 3. Nginx Proxy Manager — Web UI 统一网关

| 属性 | 值 |
|------|-----|
| 镜像 | `jc21/nginx-proxy-manager:latest` |
| 对外端口 | 80 (HTTP), 443 (HTTPS), `${NPM_ADMIN_PORT:-81}` (管理界面) |
| 数据卷 | `npm-data` → `/data`、`npm-letsencrypt` → `/etc/letsencrypt` |

**工作原理**：

Nginx Proxy Manager 是 Pandora 的唯一流量入口，接管全部 80/443 请求，通过 Web UI 管理所有反代规则。业务项目容器加入 `pandora-net` 后，NPM 可直接用容器名反代。

**添加新项目**（Web UI 操作，无需手写配置文件）：

1. 访问管理界面 `http://<host>:81`（默认账号 `admin@example.com` / 密码 `changeme`）
2. 点击 **Proxy Hosts → Add Proxy Host**
3. 填写 Domain Names（如 `blog.local.pandora`）、Forward Hostname（如 `demo-blog-frontend`）、Forward Port（`80`）
4. 保存即生效，无需重启

**FPM 项目如何配置**：

NPM 默认使用 HTTP 反代，PHP-FPM 需要通过 Advanced 选项卡添加 FastCGI 配置。以 Yii2 前后端分离为例：

- 前端（静态）：直接 Proxy Host → `demo-blog-frontend:80`
- 后端（FPM）：同一个 Proxy Host，在 Advanced 中粘贴：

```nginx
location /api {
    fastcgi_pass demo-blog-backend:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME /var/www/html/web$fastcgi_script_name;
    include fastcgi_params;
}
```

> Hyperf 项目自带 Swoole HTTP Server，直接用 NPM 默认 HTTP 反代即可，无需 Advanced。

**SSL 证书**：支持一键 Let's Encrypt 自动签发和续期，Web UI 操作即可。
### 4. DPanel — Docker 可视化管理

| 属性 | 值 |
|------|-----|
| 镜像 | `dpanel/dpanel:latest` |
| 对外端口 | `${DPANEL_PORT:-8807}` → `8080` |
| 数据卷 | `dpanel-data` → `/dpanel` |
| Socket 挂载 | `/var/run/docker.sock` (读写) |

**功能**：浏览器中管理所有 Docker 容器、镜像、网络、数据卷，提供可视化 Compose 编排界面。

> **端口说明**：DPanel 容器内部监听 8080，仅映射到宿主机 `${DPANEL_PORT}`（默认 8807），不占用 80/443，避免与 Nginx Gateway 冲突。

```bash
# 访问面板
open http://<host>:8807
```

> 首次访问根据界面提示完成初始化即可。

---

### 5. Woodpecker — CI/CD 流水线

| 组件 | 镜像 | 端口 | 说明 |
|------|------|------|------|
| Server | `woodpeckerci/woodpecker-server:latest` | 8000 | Web 管理端，接收 Webhook，调度任务 |
| Agent | `woodpeckerci/woodpecker-agent:latest` | — | 执行 CI 任务，需挂载 `docker.sock` |

**Agent 必须能访问 Docker**：挂载了 `/var/run/docker.sock`，用于在宿主机上运行 CI 容器。如果宿主机没有 Docker 或权限不足，Agent 无法工作。

**独立启动 Woodpecker**：

```bash
# 如果只需 CI/CD 而不依赖 core 内其他服务
docker compose -f core/woodpecker/docker-compose.yml up -d
```

`core/woodpecker/docker-compose.yml` 使用 `external: true` 接入 `pandora-net`，与主编排共用同一网络。

**首次访问**：

1. 启动后访问 `http://<host>:8000`
2. 使用 `WOODPECKER_ADMIN` 指定的用户名登录
3. 在 Gitea/GitHub 中配置 Webhook 指向 Woodpecker
4. 在项目中创建 `.woodpecker.yml` 即可触发 CI

---

## 使用方法

### 启动 & 停止

```bash
# 启动所有核心服务
docker compose -f core/docker-compose.yml up -d

# 或通过 Makefile
make core-up

# 启动单个服务
docker compose -f core/docker-compose.yml up -d mysql

# 仅重新构建并重启（配置变更后）
docker compose -f core/docker-compose.yml up -d --force-recreate

# 停止
docker compose -f core/docker-compose.yml down
make core-down
```

### 查看状态 & 日志

```bash
# 服务状态
docker compose -f core/docker-compose.yml ps

# 所有日志
docker compose -f core/docker-compose.yml logs -f

# 单服务日志
docker compose -f core/docker-compose.yml logs -f mysql
docker compose -f core/docker-compose.yml logs -f nginx-proxy-manager

# 通过 Makefile
make logs-core
```

### 进入容器调试

```bash
docker exec -it pandora-mysql mysql -u root -p
docker exec -it pandora-redis redis-cli -a pandora123
docker exec -it pandora-npm sh
```

---

## 数据持久化

核心服务创建了以下 Docker 命名卷，`docker compose down` 不会删除：

| 卷名 | 用途 | 挂载点 |
|------|------|--------|
| `core_mysql-data` | MySQL 数据文件 | `/var/lib/mysql` |
| `core_redis-data` | Redis RDB/AOF | `/data` |
| `core_woodpecker-data` | Woodpecker 数据库 | `/var/lib/woodpecker` |
| `core_dpanel-data` | DPanel 配置数据 | `/dpanel` |
| `core_npm-data` | Proxy Manager 配置 | `/data` |
| `core_npm-letsencrypt` | SSL 证书 | `/etc/letsencrypt` |

> 卷名前缀 `core_` 由 Compose 项目名自动生成。如需清理数据：
> ```bash
> docker compose -f core/docker-compose.yml down -v
> ```

---

## 网络

所有核心服务加入 `pandora-net` bridge 网络（主编排自动创建，woodpecker 子编排通过 `external: true` 接入）。

业务项目（`apps/`）的 `docker-compose.yml` 也声明 `pandora-net: external: true`，因此可以**直接用容器名**访问核心服务：

```
mysql            # 不是 localhost，是容器名
redis            # 不是 127.0.0.1，是容器名
pandora-npm
woodpecker-server
```

---

## 常见问题

### Q: 端口被占用？

修改 `core/docker-compose.yml` 中的 `ports` 映射，例如：

```yaml
ports:
  - "3307:3306"   # MySQL 映射到宿主机的 3307
```

### Q: Woodpecker 无法连接到 Gitea？

确保 `WOODPECKER_GITEA_URL` 中的地址在容器内可达。如果 Gitea 也在 Docker 中且同网络，用容器名；如果在宿主机，用 `host.docker.internal`。

### Q: 添加初始化 SQL 后不生效？

MySQL 的 `/docker-entrypoint-initdb.d/` 只在**数据库数据目录为空时**执行。如果数据已存在，需手动导入：

```bash
docker exec -i pandora-mysql mysql -u root -p${MYSQL_ROOT_PASSWORD} < new-script.sql
```
