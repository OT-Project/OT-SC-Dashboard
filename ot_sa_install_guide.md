# OT-SC – Central Log Processing System

> **OT Security Central** – Forked from [Wazuh](https://wazuh.com) v4.14.4
> Một component của dự án **OT**: OT-SA (Security Appliance) + OT-SC (Security Central)
> BKCS – HUST
>
> Đây là tài liệu thiết lập môi trường dev trên máy cá nhân

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
| Ổ cứng    |               | 20GB                       |

## Credentials

| Dịch vụ           | Username    | Password           | Port  |
| ----------------- | ----------- | ------------------ | ----- |
| Dashboard UI      | `kc`        | `1`                | 5601  |
| Wazuh Manager API | `wazuh-wui` | `MyS3cr37P450r.*-` | 55000 |
| Indexer API       | `admin`     | `SecretPassword`   | 9200  |

> Dashboard UI và Indexer API là cùng một credential store (Security Plugin của OpenSearch). User `kc` là tài khoản dev cho login web, được thêm vào `internal_users.yml` với `backend_role: admin`. User `admin` vẫn giữ nguyên vì `wazuh.manager` container dùng nó để đẩy data qua filebeat — không xóa.

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

# Docker
https://docs.docker.com/engine/


# Các công cụ khác
sudo apt update
sudo apt install -y git curl build-essential python3 jq

```

### 2. Clone repos

```bash
# HTTPS
git clone https://github.com/OT-Project/OT-SC-Dashboard.git OT-SC-Dashboard
git clone https://github.com/OT-Project/OT-SC-Dashboard-Plugins.git OT-SC-Dashboard-Plugins
git clone https://github.com/OT-Project/OT-SC-Security-Plugin.git OT-SC-Security-Plugin
git clone https://github.com/OT-Project/OT-SC-Docker.git OT-SC-Docker

# SSH
git clone git@github.com:OT-Project/OT-SC-Dashboard.git OT-SC-Dashboard
git clone git@github.com:OT-Project/OT-SC-Dashboard-Plugins.git OT-SC-Dashboard-Plugins
git clone git@github.com:OT-Project/OT-SC-Security-Plugin.git OT-SC-Security-Plugin
git clone git@github.com:OT-Project/OT-SC-Docker.git OT-SC-Docker

```

### 3. Khởi chạy Docker Backend

```bash
cd OT-SC-Docker/single-node/

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

# {
#   "cluster_name" : "wazuh-cluster",
#   "status" : "green",
#   "timed_out" : false,
#   "number_of_nodes" : 1,
#   "number_of_data_nodes" : 1,
#   "discovered_master" : true,
#   "discovered_cluster_manager" : true,
#   "active_primary_shards" : 20,
#   "active_shards" : 20,
#   "relocating_shards" : 0,
#   "initializing_shards" : 0,
#   "unassigned_shards" : 0,
#   "delayed_unassigned_shards" : 0,
#   "number_of_pending_tasks" : 0,
#   "number_of_in_flight_fetch" : 0,
#   "task_max_waiting_in_queue_millis" : 0,
#   "active_shards_percent_as_number" : 100.0
# }

# Wazuh API (JWT auth):
TOKEN=$(curl -sk -u 'wazuh-wui:MyS3cr37P450r.*-' \
  -X POST 'https://localhost:55000/security/user/authenticate' \
  | jq -r '.data.token')

curl -k -H "Authorization: Bearer $TOKEN" 'https://localhost:55000/'

# {"data": {"title": "Wazuh API REST", "api_version": "4.14.4", "revision": "rc2", "license_name": "GPL 2.0", "license_url": "https://github.com/wazuh/wazuh/blob/v4.14.4/LICENSE", "hostname": "wazuh.manager", "timestamp": "2026-05-11T15:31:10Z"}, "error": 0}% 
```

Xong bước khởi tạo Backend cho Wazuh.

### 4. Mount plugins vào Dashboard

Các plugin (Wazuh main/core/check-updates, Security) nằm ở các repo riêng. Để sửa code tại repo gốc mà Dashboard vẫn load được, ta bind mount vào `plugins/`:

```bash
cd OT-SC-Dashboard
sudo ./scripts/mount-plugins.sh
```

> Lưu ý: Cần unmount trước khi chạy `yarn osd clean` hoặc reboot:
>
> ```bash
> sudo ./scripts/umount-plugins.sh
> ```

### 5. Bootstrap

```bash
cd OT-SC-Dashboard
nvm use # Now using node v18.19.0 (npm v10.2.3) - Cần chính xác Node version v18.19.0
yarn osd bootstrap --single-version=ignore # Lệnh này sẽ chạy tốn nhiều tài nguyên CPU (100% all cores), chỉ chạy 1 lần lần đầu.

#  succ [@osd/optimizer] bootstrap complete
#  info [@osd/plugin-helpers] running [osd:bootstrap] script
#  succ [@osd/plugin-helpers] bootstrap complete
#  info [opensearch-dashboards] running [osd:bootstrap] script
#  succ [opensearch-dashboards] bootstrap complete
#  Done in 499.52s.

```

> **⚠️ Flag `--single-version=ignore` là BẮT BUỘC.**
> Không có flag này sẽ lỗi "Multiple version ranges" vì Wazuh plugins khai báo dependency version khác với dashboard base (typescript 5.5 vs 4.0, eslint 8 vs 6...). Đây là do Wazuh dev không bao giờ bootstrap plugins chung với dashboard — họ build riêng rồi install `.zip`.

### 6. Chạy

```bash
cd OT-SC-Dashboard
yarn start --no-base-path

# [info][listening] Server running at http://0.0.0.0:5601
```

Đợi 3–5 phút (lần đầu compile hàng chục bundles). Truy cập: **http://localhost:5601/app/wz-home**

Đăng nhập: `kc` / `1`

> **Cấu hình kết nối** (Dashboard → Indexer, Wazuh Plugin → Manager API) đã được commit sẵn trong repo:
>
> - `config/opensearch_dashboards.yml`
> - `data/wazuh/config/wazuh.yml`

---

## Workflow hàng ngày

```bash
# Start container
cd OT-SC-Docker/single-node/ && docker compose up -d

# Start yarn (mount plugins + run dev server)
cd OT-SC-Dashboard && sudo ./scripts/mount-plugins.sh && nvm use && yarn start --no-base-path
```

- Sửa code **client** (`public/`) → tự động re-optimize (15–60s), refresh trình duyệt là thấy
- Sửa code **server** (`server/`) → phải Ctrl+C rồi `yarn start` lại

> `public/` và `server/` không phải một thư mục cụ thể — đây là **quy ước cấu trúc plugin của OpenSearch Dashboards** (kế thừa từ Kibana). Mỗi plugin có 2 thư mục con cùng tên:
>
> ```
> OT-SC-Dashboard-Plugins/plugins/
> ├── main/                 ← Wazuh main plugin
> │   ├── public/           ← React UI (chạy trên browser)
> │   └── server/           ← API routes Node.js (chạy trong OSD process)
> ├── wazuh-core/
> │   ├── public/
> │   └── server/
> └── wazuh-check-updates/
>     ├── public/
>     └── server/
>
> OT-SC-Security-Plugin/
> ├── public/                ← UI của Security plugin
> └── server/                ← Backend của Security plugin
> ```
>
> Cộng thêm `OT-SC-Dashboard/src/plugins/*/{public,server}/` cho các plugin built-in của OSD.
>
> **Lý do hot-reload khác nhau**: `public/` đi qua bundler watcher (`@osd/optimizer`) — đổi file thì rebuild bundle, browser tải lại. `server/` chạy trực tiếp trong Node main process của `yarn start`, không có watcher restart tự động.

---

## Quản lý Git (cho dev mới)

> Section này dành cho dev **chưa từng làm dự án có nhiều người dùng Git**. Nếu bạn đã quen với feature branch + Pull Request thì có thể nhảy xuống mục cheatsheet ở cuối.

### 0. Khái niệm 30 giây

- **Repository (repo)**: thư mục code có lịch sử thay đổi được Git theo dõi. Dự án OT có **4 repo** trên GitHub (Dashboard, Plugins, Security, Docker).
- **Commit**: một bản snapshot có message mô tả thay đổi. Là đơn vị nhỏ nhất của lịch sử.
- **Branch**: nhánh phát triển song song, để code feature/fix mà không ảnh hưởng người khác.
- **Remote (`origin`)**: bản repo trên server (GitHub). `push` = đẩy lên, `pull` = kéo về.
- **Pull Request (PR)**: yêu cầu merge branch của bạn vào branch tích hợp (`dev`), kèm code review từ đồng nghiệp.

### 0.1. Mô hình 3 nhánh dài hạn của dự án

```
feature/X ──PR──► dev ──phase done──► staging ──project end──► main
fix/Y     ──PR──┘    (integration)    (pre-release)         (release final)
```

| Nhánh       | Vai trò                                                                                       | Ai được push? |
| ----------- | --------------------------------------------------------------------------------------------- | ------------- |
| `main`      | **Nhánh gốc / release final** — chỉ nhận merge khi kết thúc dự án (hoặc release lớn).         | Maintainer    |
| `staging`   | **Pre-release / QA** — nhận từ `dev` sau khi xong 1 phase lớn, để test tích hợp trước khi lên main. | Maintainer    |
| `dev`       | **Nhánh tích hợp hàng ngày** — nơi feature/fix được merge sau code review. Daily work base.   | Qua PR        |
| `feature/*` `fix/*` `chore/*` ... | **Branch ngắn hạn** — tạo từ `dev`, làm xong PR vào `dev`, xóa sau merge. | Owner branch  |

→ **Daily work của dev**: luôn checkout từ `dev`, PR ngược vào `dev`. KHÔNG đụng vào `staging` hay `main`.

### 1. Setup lần đầu (mỗi máy chỉ làm 1 lần)

**1.1. Định danh — Git cần biết bạn là ai để gắn vào commit**

```bash
git config --global user.name "Nguyen Van A"
git config --global user.email "a.nv@soict.hust.edu.vn"
git config --global init.defaultBranch main      # default branch khi `git init` là main (dùng cho repo mới tự tạo)
git config --global pull.rebase true             # `git pull` mặc định rebase, history sạch hơn
```

**1.2. SSH key — để GitHub xác thực máy bạn (không cần gõ password mỗi lần push)**

```bash
# Tạo key
ssh-keygen
# Enter 3 lần (chấp nhận path mặc định ~/.ssh/id_ed25519, không passphrase)

# Hiện public key để copy
cat ~/.ssh/id_ed25519.pub
```

Copy toàn bộ output (bắt đầu bằng `ssh-ed25519 AAAA...`) → vào [GitHub Settings → SSH and GPG keys](https://github.com/settings/keys) → **New SSH key** → paste → Save.

**1.3. Test kết nối**

```bash
ssh -T git@github.com
# Lần đầu sẽ hỏi "Are you sure you want to continue connecting" → yes
# Output đúng: "Hi <username>! You've successfully authenticated..."
```

Nếu thấy `Permission denied (publickey)` → key chưa add đúng vào GitHub hoặc add nhầm account.

### 2. Quy ước commit message

Dùng **Conventional Commits** — format đã chuẩn hóa, sau này dùng để auto-generate changelog.

```
<type>(<scope>): <subject>

[optional body, wrap 72 chars, giải thích WHY]

[optional footer: Refs: #123]
```

**Types**:

| Type       | Khi nào dùng                                          |
| ---------- | ----------------------------------------------------- |
| `feat`     | Thêm tính năng mới                                    |
| `fix`      | Sửa bug                                               |
| `docs`     | Sửa documentation (README, guide, comment...)         |
| `style`    | Format code, không đổi logic (whitespace, prettier)   |
| `refactor` | Tái cấu trúc code, không đổi behavior                 |
| `test`     | Thêm/sửa test                                         |
| `chore`    | Cập nhật build config, deps, file linh tinh           |
| `perf`     | Tối ưu performance                                    |
| `ci`       | Sửa GitHub Actions, CI config                         |

**Quy tắc subject** (dòng đầu tiên):
- ≤ 50 ký tự
- Imperative mood (mệnh lệnh): `add`, `fix`, `update` — KHÔNG `added`, `fixed`, `updates`
- Lowercase sau dấu `:` — `feat(auth): add login flow` ✅, `feat(auth): Add login flow` ❌
- Không có dấu `.` cuối câu

**Atomicity** — 1 commit = 1 thay đổi logic. Không gộp 5 việc khác nhau vào 1 commit. Ví dụ tốt:

```
feat(dashboard): add agent grouping by site

Allows operators to filter agents by physical site location.
Site is read from the agent's manager group config.

Refs: #42
```

Ví dụ tệ: `update stuff`, `wip`, `fix bug`, `final version`.

### 3. Quy ước branch name

```
<type>/<short-kebab-case-desc>
```

| Branch name                  | Dùng cho                              |
| ---------------------------- | ------------------------------------- |
| `feature/agent-grouping`     | Feature mới                           |
| `fix/login-401-error`        | Bug fix                               |
| `refactor/extract-api-client`| Tái cấu trúc                          |
| `chore/upgrade-node-18`      | Config, deps, file linh tinh          |
| `docs/install-guide-git`     | Cập nhật doc                          |

Quy tắc: kebab-case, tiếng Anh, ngắn nhưng đủ rõ. Không dùng tên cá nhân (`feature/nva-stuff`).

### 4. Workflow hàng ngày — Feature branch + PR vào `dev`

> Nhắc lại: daily work base là `dev`, KHÔNG phải `main`. `main`/`staging` do maintainer quản lý.

**Bước 1**: Sync `dev` về mới nhất

```bash
git checkout dev
git pull --rebase origin dev
```

**Bước 2**: Tạo branch mới TỪ `dev`

```bash
git checkout -b feature/agent-grouping
```

**Bước 3**: Code → commit (nhiều commit nhỏ atomic, không phải 1 commit khổng lồ)

```bash
git status                    # xem file nào đã đổi
git diff                      # xem nội dung thay đổi
git add path/to/file.ts       # stage từng file (đừng dùng `git add .` mù quáng)
git commit -m "feat(plugins): add site filter to agent list endpoint"

# Code tiếp, commit tiếp
git add another/file.tsx
git commit -m "feat(plugins): render site filter dropdown in UI"
```

**Bước 4**: Push branch lên GitHub

```bash
git push -u origin feature/agent-grouping
# Lần đầu push 1 branch mới cần `-u` để track. Sau đó chỉ cần `git push`.
```

**Bước 5**: Mở PR trên GitHub

- Vào repo trên GitHub → tab **Pull requests** → **New pull request**
- **Base: `dev`** (KHÔNG phải `main`), Compare: `feature/agent-grouping`
- Title: theo format commit (`feat(plugins): add agent grouping by site`)
- Description: mô tả WHY (vấn đề đang giải quyết), screenshot nếu là UI, link issue/ticket
- **Request review** từ ít nhất 1 đồng nghiệp

**Bước 6**: Reviewer comment → bạn sửa → push tiếp

```bash
# Sửa theo comment
git add file.ts
git commit -m "fix(plugins): handle empty site list"
git push          # branch đã track sẵn ở bước 4
```

PR sẽ tự cập nhật. Reviewer xem lại → approve → merge.

**Bước 7**: Sau khi PR được merge, dọn dẹp local

```bash
git checkout dev
git pull
git branch -d feature/agent-grouping     # xóa branch local
```

### 5. Khi branch của bạn bị "lag" so với `dev`

**Tình huống**: Sáng bạn checkout `dev` rồi tạo branch `feature/X` từ đó. Đến chiều, đồng nghiệp đã merge 2 PR khác vào `dev` → `dev` trên GitHub đã có commit mới. Branch `feature/X` của bạn **vẫn đang dựa trên `dev` cũ** lúc sáng:

```
Trước khi sync:

origin/dev:    A───B───C───D───E───F        ← dev mới nhất (có 2 commit mới: E, F)
                       │
                       └─X1───X2            ← feature/X của bạn (base ở C)
```

Nếu để như vậy đến lúc mở PR, code của bạn có thể đụng độ (conflict) với E và F. **Rebase** giúp "dịch chuyển base" của `feature/X` từ commit cũ (C) sang commit mới nhất của `dev` (F):

```
Sau khi rebase:

origin/dev:    A───B───C───D───E───F
                                   │
                                   └─X1'───X2'   ← feature/X giờ base ở F
```

Hiểu nôm na: rebase = **"giả vờ như tôi mới tạo branch feature/X từ `dev` ngay bây giờ rồi commit lại X1, X2 từ đầu"**. Lịch sử branch của bạn vẫn đầy đủ 2 commit X1, X2 — chỉ là chúng được "đặt lại" lên trên `dev` mới nhất. (Lưu ý: X1, X2 sau rebase có hash khác X1', X2' — Git tạo bản sao mới, đó là lý do phải force push ở bước cuối.)

**Lệnh chạy**:

```bash
git checkout feature/X            # đảm bảo đang ở branch của mình
git fetch origin                  # tải info `dev` mới về (không đổi code local)
git rebase origin/dev             # dịch base của feature/X lên commit mới nhất của dev
```

**Nếu có conflict** — xảy ra khi commit của bạn (X1/X2) và commit mới trên dev (E/F) cùng sửa 1 chỗ:

```bash
# Git sẽ pause, in ra "CONFLICT: Merge conflict in <file>"
git status                        # liệt kê file conflict (có chữ "both modified")

# Mở file conflict trong VSCode → bạn sẽ thấy marker:
# <<<<<<< HEAD            ← version đang có trên dev (E/F)
# code của dev
# =======
# code của bạn (X1/X2)
# >>>>>>> X1 (commit message)
#
# → Quyết định giữ version nào (hoặc gộp cả 2) → XÓA HẾT 3 dòng marker

git add <file-đã-resolve>         # đánh dấu đã fix conflict
git rebase --continue             # tiếp tục rebase commit kế tiếp

# Nếu Git phát hiện tiếp conflict ở commit sau → lặp lại quy trình trên.

# Nếu rối quá muốn quay đầu:
git rebase --abort                # về lại trạng thái trước khi `git rebase`
```

**Sau khi rebase xong, push lại lên GitHub**:

```bash
git push --force-with-lease
```

> ⚠ Vì sao cần force push? Branch `feature/X` của bạn trên GitHub vẫn còn X1, X2 cũ (hash cũ). Sau rebase, local của bạn có X1', X2' (hash mới). Git sẽ từ chối `git push` thường vì "lịch sử khác nhau". `--force-with-lease` ghi đè hợp lệ.
>
> Phải dùng `--force-with-lease`, KHÔNG dùng `--force` plain. Khác biệt: `--force-with-lease` kiểm tra "nếu trong lúc tôi rebase mà có ai push thêm lên branch này, hãy dừng lại" — tránh đè mất commit của teammate (nếu là branch chung). `--force` thì đè bất chấp, mất commit không recovery được.

> 💡 **Khi nào nên rebase?**
> - Trước khi mở PR đầu tiên (để PR sạch, dễ review)
> - Khi PR đang chờ review mà `dev` đã đi xa
> - Khi GitHub báo "This branch is out-of-date with the base branch"
>
> **Khi nào KHÔNG rebase?**
> - Branch của bạn đang share với người khác (vd: 2 dev cùng làm 1 feature) — rebase sẽ làm vỡ branch của họ. Trường hợp này dùng `git merge origin/dev` thay vì rebase.

### 6. Multi-repo feature (đụng nhiều repo cùng lúc)

Ví dụ: thêm tính năng "agent grouping" cần sửa cả `OT-SC-Dashboard-Plugins` (API backend) lẫn `OT-SC-Security-Plugin` (UI).

**Cách làm**:

1. Tạo branch **cùng tên** ở mỗi repo: `feature/agent-grouping`
2. Mở PR riêng cho từng repo
3. Trong PR description, **link chéo** sang PR còn lại:
   ```
   Phần API: OT-Project/OT-SC-Dashboard-Plugins#15
   Phần UI:  OT-Project/OT-SC-Security-Plugin#8
   ```
4. Tất cả PR đều base vào `dev` của repo tương ứng.
5. Merge theo thứ tự **backend trước, frontend sau** — để khi UI merge vào `dev` thì API đã có endpoint sẵn ở `dev` repo backend.

### 7. Cheatsheet — lệnh dùng hàng ngày

| Lệnh                                    | Mô tả                                            |
| --------------------------------------- | ------------------------------------------------ |
| `git status`                            | Xem file đã đổi, đã stage, đang ở branch nào     |
| `git diff`                              | Xem thay đổi chưa stage                          |
| `git diff --staged`                     | Xem thay đổi đã stage                            |
| `git log --oneline -20`                 | Xem 20 commit gần nhất, mỗi commit 1 dòng        |
| `git log --oneline --graph --all`       | Xem cây branch dạng đồ họa                       |
| `git show <hash>`                       | Xem nội dung 1 commit cụ thể                     |
| `git branch -a`                         | List tất cả branch (local + remote)              |
| `git checkout <branch>`                 | Chuyển branch                                    |
| `git checkout -b <branch>`              | Tạo branch mới + chuyển sang                     |
| `git restore <file>`                    | Discard thay đổi 1 file (chưa stage)             |
| `git restore --staged <file>`           | Unstage file (vẫn giữ thay đổi)                  |
| `git stash` / `git stash pop`           | Tạm cất việc đang dở / lấy lại                   |
| `git fetch --prune`                     | Cập nhật info remote, xóa branch remote đã chết  |
| `git reflog`                            | Xem lịch sử HEAD — cứu commit "bị mất"           |

### 8. KHÔNG làm những điều sau

- ❌ **Không push trực tiếp lên `main`, `staging`, `dev`** — luôn qua PR. Đặc biệt `main` và `staging` chỉ maintainer mới được merge.
- ❌ **Không `git push --force` lên branch chung (`main` / `staging` / `dev`)** — rewrite history công khai → mất commit của đồng nghiệp. Chỉ `--force-with-lease` được phép trên branch cá nhân của chính bạn.
- ❌ **Không commit `.env`, password, private key**, file `>10MB` (binary, data dump). Nếu lỡ commit → báo ngay senior, KHÔNG tự ý `git push --force` để "xóa", vì commit cũ vẫn còn trong reflog/PR và có thể đã clone về máy người khác.
- ❌ **Không commit `node_modules/`, `data/`, file build** — `.gitignore` đã loại trừ sẵn, đừng `git add -f` để cố push lên.
- ❌ **Không gộp 10 thay đổi linh tinh vào 1 commit `update stuff`** — sau này debug không truy được nguyên nhân.
- ❌ **Không sửa code trực tiếp trên `dev`** — luôn `git checkout -b feature/X` từ `dev`, code ở branch riêng, PR vào `dev`.
- ❌ **Không tạo feature branch từ `staging` hay `main`** — sai base, sẽ lệch lịch sử so với `dev`. Luôn `git checkout dev` trước khi `git checkout -b`.

### 9. Khi bị stuck — escape hatch

| Tình huống                                            | Lệnh                                                  |
| ----------------------------------------------------- | ----------------------------------------------------- |
| Lỡ commit lên nhầm branch                             | `git reset --soft HEAD~1` → checkout branch đúng → commit lại |
| Muốn xóa hết thay đổi local, đồng bộ y hệt remote     | `git fetch && git reset --hard origin/dev` (⚠ mất hết uncommitted) |
| Tìm commit bị "mất" sau khi reset/rebase nhầm         | `git reflog` → tìm hash → `git reset --hard <hash>`   |
| Branch quá lệch `dev`, rebase ngợp conflict           | Tạo branch mới từ `dev`, cherry-pick các commit cần thiết qua |

**Quy tắc vàng**: trước khi chạy lệnh có `--force`, `--hard`, `reset` → **hỏi senior**. Đây là các lệnh có thể mất việc không recovery được.

### 10. Phụ lục: setup 3 nhánh dài hạn (cho người maintain repo)

4 repo OT-Project hiện đang dùng `master` đơn lẻ (GitHub default cũ, chưa có `dev`/`staging`). Bước này làm 1 lần cho mỗi repo, do maintainer thực hiện.

**Bước A**: Rename `master` → `main`

```bash
cd OT-SC-Dashboard
git checkout master
git pull
git branch -m master main           # rename local
git push -u origin main             # push branch main mới lên GitHub
```

**Bước B**: Tạo `dev` và `staging` từ `main`

```bash
git checkout -b dev
git push -u origin dev

git checkout -b staging main
git push -u origin staging

git checkout dev                    # quay về dev, base của daily work
```

**Bước C**: Trên GitHub UI

1. **Settings → Branches → Default branch** → đổi sang `dev` (để PR mới mặc định base `dev`).
2. **Settings → Branches → Branch protection rules** → thêm rule cho `main` và `staging`:
   - ✅ Require pull request before merging
   - ✅ Require approvals (≥1)
   - ✅ Restrict who can push (chỉ maintainer)
   - ✅ Do not allow force pushes
3. Xóa remote `master`:
   ```bash
   git push origin --delete master
   git remote set-head origin -a
   ```

**Bước D**: Các dev khác sync máy local

```bash
git fetch --prune
git branch -m master main           # nếu local còn branch master cũ
git branch -u origin/dev dev        # track dev
git checkout dev
git pull
```

Làm theo Bước A–C cho cả 4 repo (`OT-SC-Dashboard`, `OT-SC-Dashboard-Plugins`, `OT-SC-Security-Plugin`, `OT-SC-Docker`). Sau khi xong, mọi dev đều base trên `dev` để làm việc.

### 11. Quy trình promote `dev` → `staging` → `main` (cho maintainer)

| Sự kiện                               | Hành động                                                                                  |
| ------------------------------------- | ------------------------------------------------------------------------------------------ |
| Hoàn thành 1 phase lớn (vd: sprint end) | Mở PR `dev` → `staging`. Title: `release: phase N — <tên phase>`. QA test trên staging.    |
| QA pass, release final                | Mở PR `staging` → `main`. Tag version: `git tag -a v0.X.0 -m "..."` → `git push --tags`.   |
| Hotfix khẩn cấp lên production       | Branch `hotfix/X` từ `main` → PR vào `main` → sau đó cherry-pick ngược về `staging` và `dev`. |

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