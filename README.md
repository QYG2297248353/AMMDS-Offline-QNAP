# AMMDS for QNAP

AMMDS（Adult Movie MetaData Scraper）的 QNAP NAS QPKG 安装包项目。基于 QNAP QDK 构建，支持 x86_64 和 arm_64 两种 CPU 架构。

## 支持的架构

| 架构 | 目录 | 说明 |
|------|------|------|
| x86_64 | `x86_64/` | Intel / AMD 64 位 NAS |
| arm_64 | `arm_64/` | ARM 64 位 NAS |

## 项目结构

```
AMMDS-QNAP/
├── .github/workflows/       # GitHub Actions 工作流
│   └── release-qnap.yml     # 构建与发布 QPKG 包
├── x86_64/                  # x86_64 架构专属文件
│   └── ammds                # 64 位 x86 二进制（CI 动态下载）
├── arm_64/                  # ARM 64 架构专属文件
│   └── ammds                # 64 位 ARM 二进制（CI 动态下载）
├── shared/                  # 所有架构共享文件
│   └── AMMDS.sh             # 服务启停控制脚本
├── config/                  # 配置文件
│   └── ammds.env            # 运行环境变量
├── icons/                   # 应用图标
│   ├── ICON.PNG
│   └── ICON_256.PNG
├── qpkg.cfg                 # QPKG 包核心配置
├── package_routines         # 安装 / 卸载流程脚本
├── build_sign.csv           # QNAP 代码签名配置
└── .gitignore
```

## 构建方式

### 自动构建（推荐）

通过 GitHub Actions 工作流手动触发：

1. 进入仓库的 **Actions** 页面
2. 选择 **Build and Publish QPKG Package** 工作流
3. 点击 **Run workflow**，输入镜像标签（如 `v1.6.58`）
4. 触发后自动完成以下步骤：
   - 从 [AMMDS-Docker](https://github.com/QYG2297248353/AMMDS-Docker) 下载对应架构的 `ammds` 二进制
   - 安装 QDK v2.5.3
   - 分别构建 x86_64 和 arm_64 的 `.qpkg` 安装包
   - 上传发布资产到 GitHub Release

### 本地构建

需要安装 [QNAP QDK](https://github.com/qnap-dev/QDK)：

```bash
# 安装 QDK
wget https://github.com/qnap-dev/QDK/releases/download/v2.5.3/qdk_2.5.3_amd64.deb
sudo apt install -y ./qdk_2.5.3_amd64.deb

# 准备二进制文件
# 将 amd64 的 ammds 放入 x86_64/ammds
# 将 arm64 的 ammds 放入 arm_64/ammds

# 构建 x86_64 QPKG
qbuild --root . --build-arch x86_64 --build-version "1.0.0"

# 构建 arm_64 QPKG
qbuild --root . --build-arch arm_64 --build-version "1.0.0"
```

构建产物位于 `build/` 目录下，文件名为 `*_x86_64.qpkg` 和 `*_arm_64.qpkg`。

## 安装说明

1. 下载对应架构的 `.qpkg` 文件
2. 登录 QNAP NAS 管理界面，打开 **App Center**
3. 点击右上角 **手动安装**，选择下载的 `.qpkg` 文件
4. 按照提示完成安装

应用安装后默认监听端口 **9523**，服务由 `AMMDS.sh` 控制启停。

## 配置说明

### qpkg.cfg

QPKG 包元信息配置，关键配置项：

| 配置项 | 值 | 说明 |
|--------|-----|------|
| QPKG_NAME | ammds | 包名称 |
| QPKG_DISPLAY_NAME | AMMDS | 显示名称 |
| QPKG_VER | 1.6.60 | 版本号（CI 自动更新） |
| QPKG_AUTHOR | 新疆萌森软件开发工作室 | 作者 |
| QTS_MINI_VERSION | 5.0.0 | 最低 QTS 版本要求 |
| QPKG_SERVICE_PROGRAM | AMMDS.sh | 服务控制脚本 |
| QPKG_WEB_PORT | 9523 | Web 界面端口 |

### config/ammds.env

运行时环境变量：

```env
AMMDS_SERVER_PORT=9523
ADMIN_USER=ammds
ADMIN_PASS=ammds
AMMDS_SYSTEM_MODE=full
AMMDS_MAX_FILE_SIZE=10GB
AMMDS_MAX_REQUEST_SIZE=50GB
```

安装后可通过修改 `/share/CACHEDEV1_DATA/.qpkg/AMMDS/config/ammds.env` 调整配置。

## 发布流程

1. 在 [AMMDS-Docker](https://github.com/QYG2297248353/AMMDS-Docker) 仓库创建 Release（tag 格式 `vX.Y.Z`），上传 `ammds-amd64-backend.tar.gz` 和 `ammds-arm64-backend.tar.gz`
2. 在本仓库手动触发 **Build and Publish QPKG Package** 工作流，输入相同的 tag
3. 等待构建完成，`.qpkg` 包将自动上传到对应的 GitHub Release

## 许可证

本项目由 **新疆萌森软件开发工作室** 维护。
