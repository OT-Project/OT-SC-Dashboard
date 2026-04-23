# OT-SC – Central Log Processing System

> **OT Security Central** – Forked from [Wazuh](https://wazuh.com) v4.14.4
> Một component của dự án **OT**: OT-SA (Security Appliance) + OT-SC (Security Central)
> BKCS – HUST

---

## Kiến trúc

```
┌─────────────────────────────────────────────────────┐
│                    HOST (Dev)                       │
│                                                     │
│  ┌─────────────────────────────────────────────┐    │
│  │         OT-SC-Dashboard (:5601)             │    │
│  │  ┌──────────┐ ┌────────┐ ┌────────────────┐ │    │
│  │  │  Wazuh   │ │Security│ │  OpenSearch    │ │    │
│  │  │ Plugins  │ │ Plugin │ │  Dashboards    │ │    │
│  │  └────┬─────┘ └────────┘ └────────────────┘ │    │
│  └───────┼─────────────────────────────────────┘    │
│          │                                          │
├──────────┼──────────────────────────────────────────┤
│          │          DOCKER                          │
│  ┌───────▼──────────┐    ┌───────────────────────┐  │
│  │  Wazuh Manager   │    │   Wazuh Indexer       │  │
│  │  API :55000      │    │  (OpenSearch) :9200   │  │
│  │  Agent :1514/1515│    │                       │  │
│  └──────────────────┘    └───────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Yêu cầu

| Component | Version       | Ghi chú                    |
| --------- | ------------- | -------------------------- |
| Wazuh     | 4.14.4        | Fixed, clone tag `v4.14.4` |
| Node.js   | 18.19.0       | **BẮT BUỘC** đúng version  |
| Yarn      | 1.22.x        | Classic v1, KHÔNG dùng v2+ |
| Docker    | 24.x+         | Engine + Compose v2        |
| OS        | Ubuntu 22.04+ | Hoặc distro tương đương    |

## Credentials

| Dịch vụ           | Username    | Password           | Port  |
| ----------------- | ----------- | ------------------ | ----- |
| Dashboard UI      | `admin`     | `SecretPassword`   | 5601  |
| Wazuh Manager API | `wazuh-wui` | `MyS3cr37P450r.*-` | 55000 |
| Indexer API       | `admin`     | `SecretPassword`   | 9200  |

---

## Setup từ Zero

### 1. Cài công cụ

```bash
# NVM + Node.js
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 18.19.0 && nvm alias default 18.19.0

# Yarn v1
npm install -g yarn

# Docker + các công cụ khác
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 git curl build-essential python3 jq
sudo usermod -aG docker $USER && newgrp docker
```

### 2. Clone repos

```bash
cd ~/Documents/BKCS/OT-Project/

git clone git@github.com:OT-Project/OT-SC-Dashboard.git         OT-SC-Dashboard
git clone git@github.com:OT-Project/OT-SC-Dashboard-Plugins.git OT-SC-Dashboard-Plugins
git clone git@github.com:OT-Project/OT-SC-Security-Plugin.git   OT-SC-Security-Plugin
git clone git@github.com:OT-Project/OT-SC-Docker.git            OT-SC-Docker
```

> Yêu cầu SSH key đã được add vào GitHub account có quyền truy cập `OT-Project` org.
> Dùng HTTPS thay thế nếu cần: `git clone https://github.com/OT-Project/<repo>.git`

### 3. Khởi chạy Docker Backend

```bash
cd ~/Documents/BKCS/OT-Project/OT-SC-Docker/single-node/

# docker-compose.yml đã được cấu hình sẵn không chạy service wazuh.dashboard
# (Dashboard chạy trực tiếp trên host ở bước 6)

# Tạo certificates
docker compose -f generate-indexer-certs.yml run --rm generator

# Khởi chạy
docker compose up -d
```

Verify sau ~60 giây:

```bash
# Indexer:
curl -k -u admin:SecretPassword 'https://localhost:9200/_cluster/health?pretty=true'

# Wazuh API (JWT auth):
TOKEN=$(curl -sk -u 'wazuh-wui:MyS3cr37P450r.*-' \
  -X POST 'https://localhost:55000/security/user/authenticate' \
  | jq -r '.data.token')
curl -k -H "Authorization: Bearer $TOKEN" 'https://localhost:55000/'
```

### 4. Mount plugins vào Dashboard

Các plugin (Wazuh main/core/check-updates, Security) nằm ở các repo riêng. Để sửa code tại repo gốc mà Dashboard vẫn load được, ta bind mount vào `plugins/`:

```bash
cd ~/Documents/BKCS/OT-Project/OT-SC-Dashboard
sudo ./scripts/mount-plugins.sh
```

> Cần tháo mount trước khi `yarn osd clean` hoặc reboot:
>
> ```bash
> sudo ./scripts/umount-plugins.sh
> ```

### 5. Bootstrap

```bash
cd ~/Documents/BKCS/OT-Project/OT-SC-Dashboard
nvm use
yarn osd bootstrap --single-version=ignore
```

> **⚠️ Flag `--single-version=ignore` là BẮT BUỘC.**
> Không có flag này sẽ lỗi "Multiple version ranges" vì Wazuh plugins khai báo dependency version khác với dashboard base (typescript 5.5 vs 4.0, eslint 8 vs 6...). Đây là do Wazuh dev không bao giờ bootstrap plugins chung với dashboard — họ build riêng rồi install `.zip`.

### 6. Chạy

```bash
cd ~/Documents/BKCS/OT-Project/OT-SC-Dashboard
yarn start --no-base-path
```

Đợi 3–5 phút (lần đầu compile hàng chục bundles). Truy cập: **http://localhost:5601/app/wz-home**

Đăng nhập: `admin` / `SecretPassword`

> **Cấu hình kết nối** (Dashboard → Indexer, Wazuh Plugin → Manager API) đã được commit sẵn trong repo:
>
> - `config/opensearch_dashboards.yml`
> - `data/wazuh/config/wazuh.yml`

---

## Workflow hàng ngày

```bash
# Start container
cd ~/Documents/BKCS/OT-Project/OT-SC-Docker/single-node/ && docker compose up -d

# Start yarn (mount plugins + run dev server)
cd ~/Documents/BKCS/OT-Project/OT-SC-Dashboard && sudo ./scripts/mount-plugins.sh && nvm use && yarn start --no-base-path
```

- Sửa code **client** (`public/`) → tự động re-optimize (15–60s)
- Sửa code **server** (`server/`) → phải restart `yarn start`

---

## Troubleshooting

| Lỗi                                      | Nguyên nhân                      | Giải pháp                                                 |
| ---------------------------------------- | -------------------------------- | --------------------------------------------------------- |
| "Multiple version ranges"                | Wazuh plugins ≠ dashboard deps   | `yarn osd bootstrap --single-version=ignore`              |
| "Cannot find module @osd/config-schema"  | Plugin nằm ngoài project tree    | Dùng bind mount qua `scripts/mount-plugins.sh`            |
| "Application Not Found"                  | `defaultRoute` sai               | Dùng `/app/wz-home`, không phải `/app/wazuh`              |
| "Request failed 401" (wazuh plugin)      | Sai credentials trong `wazuh.yml`| `wazuh-wui` / `MyS3cr37P450r.*-`                          |
| "no matches found" (zsh)                 | `*` và `?` là glob               | Bọc trong single quotes                                   |
| "not of type boolean"                    | `?pretty` empty string           | Dùng `?pretty=true` hoặc pipe `jq`                        |
| `EACCES` permission                      | `node_modules` cũ                | `rm -rf node_modules` và bootstrap lại                    |
| Heap out of memory                       | Thiếu RAM                        | `export NODE_OPTIONS=--max-old-space-size=4096`           |
| Plugin không load sau reboot             | Mount bị mất khi tắt máy         | Chạy lại `sudo ./scripts/mount-plugins.sh`                |

---

## Lệnh thường dùng

| Lệnh                                                       | Mô tả                                 |
| ---------------------------------------------------------- | ------------------------------------- |
| `sudo ./scripts/mount-plugins.sh`                          | Mount plugins vào Dashboard           |
| `sudo ./scripts/umount-plugins.sh`                         | Tháo mount plugins                    |
| `yarn osd bootstrap --single-version=ignore`               | Cài dependencies                      |
| `yarn osd clean`                                           | Xóa build + plugin `node_modules`     |
| `yarn start --no-base-path`                                | Chạy dev mode                         |
| `yarn build-platform --linux --skip-os-packages --release` | Build production                      |
| `docker compose up -d`                                     | Start backend                         |
| `docker compose down -v`                                   | Stop + xóa data                       |

---

## License

Wazuh: **GNU General Public License v2.0**
Các thay đổi rebrand thuộc dự án **OT** / BKCS – HUST.
