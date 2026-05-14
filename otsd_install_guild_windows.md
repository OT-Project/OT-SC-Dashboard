# OTSD – Central Log Processing System (Windows / WSL2)

> **OT Security Central** – Forked from [Wazuh](https://wazuh.com) v4.14.4
> Một component của dự án **OT**: OT-SA (Security Appliance) + OTSD (Security Central)
> BKCS – HUST
>
> Tài liệu thiết lập môi trường dev trên **Windows 10/11 + WSL2 Ubuntu 24.04 + Docker Desktop (WSL backend)**.
> Phần Git workflow (clone, branch, PR, rebase…) giống hệt bản Linux — xem `ot_sc_install_guide.md` mục **Quản lý Git**.

>Lưu ý: Đây là tài liệu dùng 1 lần (trừ phần workflow hàng ngày)

---

## Kiến trúc

```
┌──────────────────────────────────────────────────────────────┐
│                       WINDOWS HOST                           │
│                                                              │
│  Browser ──────────────────────────────► http://localhost:5601 │
│                                            ▲                 │
│  ┌──────────────────────────────────────┐  │                  │
│  │  Docker Desktop (WSL2 backend)       │  │ (port forward    │
│  │  ─ tự share daemon vào distro Ubuntu │  │  qua WSL2 NAT)   │
│  └──────────────────────────────────────┘  │                  │
│                                            │                  │
│  ┌─────────────────────────────────────────┴──────────────┐  │
│  │           WSL2 — Ubuntu-24.04 (distro)                 │  │
│  │                                                        │  │
│  │  ┌────────────────────────────────────────────────┐    │  │
│  │  │         OTSD-Dashboard (yarn start :5601)     │    │  │
│  │  │  Wazuh plugins + Security plugin + OSD core    │    │  │
│  │  └────────────────────┬───────────────────────────┘    │  │
│  │                       │                                │  │
│  │   ┌───────────────────▼─────────────────────────┐      │  │
│  │   │  Docker containers (qua Docker Desktop)      │     │  │
│  │   │  ┌─────────────┐  ┌───────────────────────┐  │     │  │
│  │   │  │Wazuh Manager│  │  Wazuh Indexer        │  │     │  │
│  │   │  │API :55000   │  │ (OpenSearch) :9200    │  │     │  │
│  │   │  └─────────────┘  └───────────────────────┘  │     │  │
│  │   └─────────────────────────────────────────────┘     │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

WSL2 share network namespace ra Windows host, nên `localhost:5601`, `localhost:9200`, `localhost:55000` từ browser Windows hit thẳng vào dashboard / container trong WSL.

## Yêu cầu

| Component        | Version       | Ghi chú                                              |
| ---------------- | ------------- | ---------------------------------------------------- |
| Windows          | 10 22H2 / 11  | Cần WSL2 (WSL1 KHÔNG hoạt động với Docker)           |
| WSL distro       | Ubuntu-24.04  | Cài qua `wsl --install -d Ubuntu-24.04`              |
| Docker Desktop   | 4.x mới nhất  | Bật WSL2 backend + integration vào distro Ubuntu     |
| Wazuh            | 4.14.4        | Fixed, clone tag `v4.14.4`                           |
| Node.js          | 18.19.0       | **BẮT BUỘC** đúng version (cài trong WSL, không phải Windows) |
| Yarn             | 1.22.x        | Classic v1, KHÔNG dùng v2+                           |
| RAM              | ≥ 16GB host   | Phân ≥ 8GB cho WSL (xem `.wslconfig` bên dưới)       |
| Ổ cứng           | ≥ 30GB free   | Cho WSL vhdx + Docker images + node_modules          |

> ⚠️ **Đặt code Ở ĐÂU?** Bắt buộc đặt code trong **filesystem của WSL** (vd: `~/projects/` = `/home/<user>/projects/`), **KHÔNG đặt trong `/mnt/c/Users/...`** (= Windows filesystem mount qua 9P). Lý do:
> - I/O qua 9P chậm gấp 10–30 lần (yarn bootstrap có thể từ 8 phút → 90 phút).
> - File watcher của `@osd/optimizer` không nhận event inotify từ NTFS → hot-reload chết.
> - Permission bit của Linux không map đúng → `chmod +x scripts/*.sh` không có hiệu lực.

## Credentials

Giống hệt bản Linux:

| Dịch vụ           | Username    | Password           | Port  |
| ----------------- | ----------- | ------------------ | ----- |
| Dashboard UI      | `kc`        | `1`                | 5601  |
| Wazuh Manager API | `wazuh-wui` | `MyS3cr37P450r.*-` | 55000 |
| Indexer API       | `admin`     | `SecretPassword`   | 9200  |

---

## Setup từ Zero

### 0. Cài WSL2 + Ubuntu 24.04 (trên PowerShell Windows, chạy as Administrator)

```powershell
# Bật WSL feature + Virtual Machine Platform (nếu máy mới chưa có)
wsl --install

# Cập nhật WSL kernel + đặt default version 2
wsl --update
wsl --set-default-version 2

# Cài Ubuntu 24.04
wsl --install -d Ubuntu-24.04

# Sau khi distro khởi động lần đầu, tạo user + password Linux.
```

Kiểm tra:

```powershell
wsl --list --verbose
# NAME            STATE           VERSION
# Ubuntu-24.04    Running         2
```

### 0.1. Cấu hình tài nguyên WSL (Windows host)

Tạo file `C:\Users\<bạn>\.wslconfig` (không có extension, viết bằng Notepad / VSCode):

```ini
[wsl2]
memory=10GB          # cấp 10GB RAM cho WSL VM (chỉnh theo RAM máy)
swap=4GB
localhostForwarding=true

# Bật mirrored networking nếu Windows 11 22H2+ — giúp container expose port mượt hơn
# networkingMode=mirrored
```

Apply config:

```powershell
wsl --shutdown
# Sau đó mở lại Ubuntu — WSL VM khởi động với config mới.
```

> Nếu không set `memory`, WSL sẽ chiếm tối đa 50% RAM máy mặc định — `yarn osd bootstrap` rất ngốn RAM, không cần giới hạn quá thấp.

### 0.2. Cài Docker Desktop (Windows host)

1. Tải **Docker Desktop for Windows** từ <https://www.docker.com/products/docker-desktop>.
2. Khi cài, tick **"Use WSL 2 instead of Hyper-V"** (default ở bản mới).
3. Sau khi cài xong, mở Docker Desktop:
   - **Settings → General**: tick **Use the WSL 2 based engine**.
   - **Settings → Resources → WSL Integration**:
     - Bật **Enable integration with my default WSL distro**.
     - Bật toggle cho **Ubuntu-24.04**.
   - Bấm **Apply & Restart**.

Verify (mở terminal Ubuntu trong WSL):

```bash
docker version
# Client + Server đều có dòng "Docker Desktop ..."

docker compose version
# Docker Compose version v2.x.x

# Test chạy container
docker run --rm hello-world
```

Nếu báo `Cannot connect to the Docker daemon` → vào Docker Desktop Settings, đảm bảo distro Ubuntu-24.04 được enabled trong WSL Integration.

> Daemon Docker chạy trong distro riêng `docker-desktop` của Docker Desktop, không phải trong Ubuntu-24.04. Distro Ubuntu chỉ có CLI client được forward qua. Vì vậy KHÔNG cần (và đừng) cài `docker-ce` engine bằng `apt` trong Ubuntu — sẽ xung đột.

### 1. Cài công cụ (trong terminal Ubuntu-24.04 / WSL)

Lưu ý: tất cả các lệnh dưới đây đều được chạy trong WSL.

```bash
# Cập nhật + công cụ cơ bản
sudo apt update
sudo apt install -y git curl build-essential python3 jq unzip

# NVM + Node.js (cài trong WSL, KHÔNG cài Node trên Windows rồi share qua)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc       # hoặc ~/.zshrc nếu dùng zsh

# Verify NVM version
nvm --version
# 0.39.7
```

> Nếu sau này dùng terminal mới mà `nvm` không tìm thấy → `source ~/.nvm/nvm.sh` hoặc đảm bảo block init NVM đã được append vào `~/.bashrc` / `~/.zshrc`. 

### 2. Clone repos

**Đặt trong WSL filesystem**, ví dụ `~/projects/otsd/`:

```bash
mkdir -p ~/projects/otsd && cd ~/projects/otsd

# SSH (recommend — xem mục Git để setup SSH key)
git clone git@github.com:OT-Project/OTSD-Dashboard.git OTSD-Dashboard

git clone git@github.com:OT-Project/OTSD-Dashboard-Plugins.git OTSD-Dashboard-Plugins

git clone git@github.com:OT-Project/OTSD-Security-Plugin.git OTSD-Security-Plugin

git clone git@github.com:OT-Project/OTSD-Docker.git OTSD-Docker

# Hoặc HTTPS
git clone https://github.com/OT-Project/OTSD-Dashboard.git OTSD-Dashboard

git clone https://github.com/OT-Project/OTSD-Dashboard-Plugins.git OTSD-Dashboard-Plugins

git clone https://github.com/OT-Project/OTSD-Security-Plugin.git OTSD-Security-Plugin

git clone https://github.com/OT-Project/OTSD-Docker.git OTSD-Docker
```

Kiểm tra đường dẫn — phải KHÔNG bắt đầu bằng `/mnt/c/`:

```bash
pwd
# /home/<user>/projects/otsd      ✅
# /mnt/c/Users/.../otsd           ❌ SAI — chuyển sang ~/projects/
```

> Nếu muốn mở code bằng VSCode trên Windows: dùng extension **WSL** (`ms-vscode-remote.remote-wsl`), sau đó từ terminal WSL chạy `code .`. VSCode sẽ chạy server trong WSL, edit file trực tiếp trên ext4 — không qua 9P.

### 3. Chuẩn bị `vm.max_map_count` cho Indexer (OpenSearch)

OpenSearch cần `vm.max_map_count ≥ 262144`. Trên Linux native chỉ cần `sysctl`. Trên WSL2 cần sửa **trong distro Ubuntu** (vì Docker Desktop dùng namespace riêng nhưng kernel chung của WSL VM):

```bash
# Test giá trị hiện tại
sysctl vm.max_map_count

# Set tạm thời cho session hiện tại
sudo sysctl -w vm.max_map_count=262144

# Set vĩnh viễn (apply mỗi lần WSL khởi động)
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
```

Sau khi `wsl --shutdown` rồi mở lại, kiểm tra giá trị đã giữ.

> Một số bản WSL2 cũ không tự đọc `/etc/sysctl.conf` lúc boot — nếu vậy thêm vào `/etc/wsl.conf`:
> ```ini
> [boot]
> command="sysctl -w vm.max_map_count=262144"
> ```
> Cần WSL ≥ 0.67 (Win11) hoặc store version.

### 4. Khởi chạy Docker Backend

```bash
cd ~/projects/otsd/OTSD-Docker/single-node/

# docker-compose.yml đã được cấu hình sẵn không chạy service wazuh.dashboard
# (Dashboard chạy trực tiếp trên host WSL ở bước 7)

# Tạo certificates
docker compose -f generate-indexer-certs.yml run --rm generator

# Khởi chạy
docker compose up -d
```

Verify sau ~60 giây (giống bản Linux):

```bash
# Indexer:
curl -k -u admin:SecretPassword 'https://localhost:9200/_cluster/health?pretty=true'
# status: "green"

# Wazuh API (JWT auth):
TOKEN=$(curl -sk -u 'wazuh-wui:MyS3cr37P450r.*-' \
  -X POST 'https://localhost:55000/security/user/authenticate' \
  | jq -r '.data.token')

curl -k -H "Authorization: Bearer $TOKEN" 'https://localhost:55000/'
# {"data": {"title": "Wazuh API REST", "api_version": "4.14.4", ...}, "error": 0} 
```

Trên Windows browser cũng có thể test trực tiếp:
- <https://localhost:9200> (chấp nhận self-signed cert) — login `admin` / `SecretPassword`.

> Nếu container start nhưng `wazuh.indexer` chết liền (`exited (137)`) → thiếu RAM cho WSL, tăng `memory=` trong `.wslconfig` rồi `wsl --shutdown`.
> Nếu indexer log `max virtual memory areas vm.max_map_count [65530] is too low` → quay lại bước 3.

### 5. Mount plugins vào Dashboard

```bash
cd ~/projects/otsd/OTSD-Dashboard
sudo ./scripts/mount-plugins.sh
```

> ⚠️ Bind mount `mount --bind` chỉ hoạt động trong filesystem Linux (ext4 của WSL). Đây là lý do nữa **phải đặt code trong `~/projects/`** — `mount --bind` không hoạt động trên `/mnt/c/`.
>
> Bind mount sẽ mất sau khi `wsl --shutdown` hoặc reboot Windows. Mỗi lần khởi động WSL phải chạy lại `sudo ./scripts/mount-plugins.sh` trước khi `yarn start`.

Trước khi `yarn osd clean` hoặc shutdown WSL:

```bash
sudo ./scripts/umount-plugins.sh
```

### 6. Bootstrap

```bash
cd ~/projects/otsd/OTSD-Dashboard
nvm install                                        # Now using node v18.19.0
nvm use                                            # Now using node v18.19.0 (npm v10.2.3)

# Yarn classic v1
npm install -g yarn
yarn -v                # 1.22.x

yarn osd bootstrap --single-version=ignore           # ~5–15 phút, 100% CPU
```

> Bước này **rất ngốn RAM**. Nếu WSL chỉ cấp 4GB sẽ OOM ở giữa chừng → tăng `memory=` trong `.wslconfig`, restart WSL, chạy lại.
>
> Flag `--single-version=ignore` BẮT BUỘC — xem giải thích trong bản Linux.

### 7. Chạy

```bash
cd ~/projects/otsd/OTSD-Dashboard
yarn start --no-base-path

# [info][listening] Server running at http://0.0.0.0:5601
```

**QUAN TRỌNG: Đợi 15 phút (lần đầu compile bundles) cho đến khi xuất hiện thông báo**
>[success][@osd/optimizer] XX bundles compiled successfully after YYY sec, watching for changes

Trên **browser Windows**, truy cập:

**<http://localhost:5601/app/wz-home>**

Login: `kc` / `1`

> WSL2 forward port `:5601` từ distro ra Windows tự động qua relay. Nếu localhost không vào được:
> - Kiểm tra port có thực sự mở trong WSL: `ss -tlnp | grep 5601` trong terminal Ubuntu.
> - Một số máy Windows có Hyper-V Windows Firewall block — tắt tạm hoặc add rule cho `vEthernet (WSL)`.
> - Trên Windows 11, có thể bật `networkingMode=mirrored` trong `.wslconfig` để dùng chung network stack với Windows (ổn định hơn).
> - Trường hợp xấu nhất: lấy IP của WSL bằng `ip addr show eth0` rồi truy cập trực tiếp `http://<wsl-ip>:5601`.

---

## Workflow hàng ngày

Sau khi reboot Windows hoặc `wsl --shutdown`, sequence khởi động:

```bash
# (Tự động) Docker Desktop start cùng Windows nếu đã tick "Start on login".
# Mở terminal Ubuntu-24.04 (WSL)

# 1. Verify Docker đã sẵn sàng
docker ps                                # nếu lỗi → mở Docker Desktop, chờ icon xanh

# 2. Start containers
cd ~/projects/otsd/OTSD-Docker/single-node/
docker compose up -d

# 3. Mount plugins + start dashboard
cd ~/projects/otsd/OTSD-Dashboard
sudo ./scripts/mount-plugins.sh
nvm use
yarn start --no-base-path
```

- Sửa code **client** (`public/`) → tự động re-optimize (15–60s), refresh trình duyệt Windows là thấy.
- Sửa code **server** (`server/`) → Ctrl+C rồi `yarn start` lại.

> File watcher: vì code nằm trong ext4 của WSL, inotify hoạt động bình thường — `public/` hot-reload mượt như Linux native. Đây là lợi ích chính của việc KHÔNG đặt code trong `/mnt/c/`.

### Tắt máy / cuối ngày

```bash
# Trong WSL Ubuntu:
cd ~/projects/otsd/OTSD-Docker/single-node/ && docker compose down
cd ~/projects/otsd/OTSD-Dashboard && sudo ./scripts/umount-plugins.sh
```

Sau đó từ PowerShell (tuỳ chọn — giải phóng RAM cho Windows):

```powershell
wsl --shutdown
```

---

## Quản lý Git

Giống hệt bản Linux. Xem `ot_sc_install_guide.md` mục **Quản lý Git (cho dev mới)** — quy ước commit, branch name, workflow PR vào `dev`, rebase, cheatsheet.

Lưu ý duy nhất cho WSL: SSH key tạo bên trong WSL (`~/.ssh/id_ed25519`) **độc lập** với SSH key trên Windows (`C:\Users\<bạn>\.ssh\id_ed25519`). Phải `ssh-keygen` trong WSL và add key đó vào GitHub — đừng tưởng dùng được key của Windows.

```bash
# Trong WSL terminal
ssh-keygen
cat ~/.ssh/id_ed25519.pub          # copy → paste vào GitHub Settings → SSH and GPG keys
ssh -T git@github.com              # test
```

> Nếu muốn share 1 key giữa Windows và WSL, có thể symlink `~/.ssh` của WSL trỏ vào `/mnt/c/Users/<bạn>/.ssh/`, nhưng phải `chmod 600` cho `id_ed25519` — quyền trên `/mnt/c/` thường không đủ strict, ssh sẽ từ chối load key. Khuyên dùng key riêng cho WSL, đơn giản và an toàn hơn.

---

## Troubleshooting (riêng WSL)

| Lỗi                                                  | Nguyên nhân                                  | Giải pháp                                                       |
| ---------------------------------------------------- | -------------------------------------------- | --------------------------------------------------------------- |
| `Cannot connect to the Docker daemon`                | WSL Integration tắt cho distro Ubuntu        | Docker Desktop → Settings → Resources → WSL Integration → bật toggle |
| `yarn bootstrap` cực chậm (>30 phút)                 | Code nằm trong `/mnt/c/` (9P filesystem)     | Chuyển code sang `~/projects/`, clone lại                       |
| Hot-reload không hoạt động khi sửa `public/`         | inotify không xuyên qua 9P                   | Code phải ở ext4 (`~/`), không phải `/mnt/c/`                   |
| `wazuh.indexer exited (137)`                         | OOM trong WSL                                | Tăng `memory=` trong `.wslconfig`, `wsl --shutdown`              |
| `vm.max_map_count [65530] is too low`                | sysctl chưa apply                            | Bước 3 — `sysctl -w` + `/etc/wsl.conf` `[boot] command=`         |
| `localhost:5601` không vào được từ Windows browser   | WSL2 port forward bị Firewall block          | Tắt Windows Defender Firewall tạm, hoặc bật `networkingMode=mirrored` |
| `mount --bind ... operation not permitted`           | Đang ở `/mnt/c/`                             | Bind mount chỉ chạy trên ext4 — chuyển sang `~/projects/`        |
| `Permission denied (publickey)` khi `git push`       | Dùng nhầm SSH key của Windows                | `ssh-keygen` trong WSL, add public key trong WSL vào GitHub      |
| `EACCES: permission denied, scandir ...node_modules` | Bootstrap chạy với sudo trước đó            | `sudo rm -rf node_modules` rồi bootstrap lại KHÔNG sudo          |
| Bind mount mất sau khi mở lại WSL                    | `wsl --shutdown` reset mount namespace       | Bình thường — chạy lại `sudo ./scripts/mount-plugins.sh`         |
| Container chạy được nhưng RAM Windows tụt mạnh       | WSL VM ăn nhiều hơn `memory=` set            | Cần restart WSL để config mới apply; hoặc check `vmmem` trong Task Manager |
| `wsl --install` báo "Virtual Machine Platform missing" | Chưa bật feature Windows                  | PowerShell admin: `dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart` rồi reboot |

Các lỗi khác (Wazuh-specific, plugin not loaded, multiple version ranges...) giống bản Linux — xem table troubleshooting trong `ot_sc_install_guide.md`.

---

## Lệnh thường dùng (WSL)

| Lệnh                                                       | Mô tả                                       |
| ---------------------------------------------------------- | ------------------------------------------- |
| `wsl --shutdown` (PowerShell)                              | Tắt toàn bộ WSL VM, giải phóng RAM          |
| `wsl --list --verbose` (PowerShell)                        | List distro, version, state                 |
| `wsl --terminate Ubuntu-24.04` (PowerShell)                | Tắt riêng 1 distro                          |
| `explorer.exe .` (WSL terminal)                            | Mở thư mục hiện tại trong Windows Explorer  |
| `code .` (WSL terminal)                                    | Mở VSCode trong WSL Remote mode             |
| `ip addr show eth0`                                        | Lấy IP của WSL distro                       |
| `ss -tlnp \| grep 5601`                                    | Kiểm tra port 5601 đang LISTEN              |
| `sudo ./scripts/mount-plugins.sh`                          | Mount plugins (phải chạy lại mỗi lần WSL start) |
| `sudo ./scripts/umount-plugins.sh`                         | Tháo mount plugins                          |
| `yarn osd bootstrap --single-version=ignore`               | Cài deps                                    |
| `yarn osd clean`                                           | Xóa build + plugin `node_modules`           |
| `yarn start --no-base-path`                                | Chạy dev mode                               |
| `docker compose up -d`                                     | Start backend                               |
| `docker compose down -v`                                   | Stop + xóa data                             |

---

## Khác biệt cốt lõi so với bản Linux native

| Khía cạnh        | Linux native (Mint/Ubuntu)    | WSL2 + Docker Desktop                                  |
| ---------------- | ----------------------------- | ------------------------------------------------------ |
| Docker engine    | `docker-ce` cài qua apt       | Docker Desktop daemon, forward CLI vào distro          |
| Filesystem code  | Bất kỳ thư mục nào            | **BẮT BUỘC** ext4 của WSL (`~/projects/`)              |
| `vm.max_map_count` | `sysctl.conf` đơn giản      | `sysctl.conf` + `/etc/wsl.conf` `[boot]` để persist    |
| Bind mount       | Persistent qua reboot         | Mất sau `wsl --shutdown` — phải mount lại              |
| RAM management   | Linux quản lý trực tiếp       | Giới hạn qua `.wslconfig` `memory=`                    |
| Browser access   | Cùng máy, trực tiếp           | Browser Windows → port forward qua WSL2 NAT            |
| SSH key Git      | `~/.ssh/`                     | Key riêng trong WSL, không share với Windows           |
| File watcher     | inotify trực tiếp             | Chỉ work khi code ở ext4 (KHÔNG ở `/mnt/c/`)           |
| Performance      | Bare metal                    | ~95% bare metal nếu setup đúng, ~10% nếu code ở `/mnt/c/` |
