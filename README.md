# uplink

手机把任务送上服务器。Linux 上的 Cursor Agent 负责改代码、改配置、跑 git。

GitHub 仓库名：**`uplink`**。Flutter 包名同样是 `uplink`。

```
手机 App（Uplink）
    ↓ HTTPS / 鉴权
FastAPI 后端
    ↓
Cursor CLI（agent -p --force）
    ↓
本地仓库 / 配置文件 / git / GitHub
```

## 克隆

```bash
git clone https://github.com/<你的用户名>/uplink.git
cd uplink
```

不要提交 `.env`、AWS 密钥 `.pem`、`CURSOR_API_KEY`。仓库请建为 **Private**。

## 能做什么

- 发一句任务，服务器上的 Agent 改工作区里的代码或配置
- 从手机上传文件，再让 Agent「处理刚上传的 xxx」
- 看实时日志
- 点按钮执行白名单 git：`pull --ff-only` / `commit` / `push`

系统级配置（nginx、systemd）不要直接交给模型。把配置文件放进工作区，或以后再加白名单脚本。

## 1. 服务器后端

需要：Python 3.10+、git、[Cursor CLI](https://cursor.com/docs/cli/overview)

```bash
curl https://cursor.com/install -fsS | bash
export CURSOR_API_KEY=你的key
agent status
```

```bash
cd server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

编辑 `server/.env`：

- `APP_TOKEN`：手机登录口令，至少 16 位
- `WORKSPACE`：Agent 只能改这个目录，建议指向一个 git 仓库
- `CURSOR_API_KEY`：Cursor Dashboard 的 API Key

```bash
cd server
python -m uvicorn app.main:app --host 0.0.0.0 --port 8787
```

浏览器打开 `http://服务器IP:8787/api/health`，看到 `ok: true` 即可。

Linux 长期运行可用 `uplink.service`。先改里面的路径，再：

```bash
sudo cp uplink.service /etc/systemd/system/
sudo systemctl enable --now uplink
```

生产环境请前面加 HTTPS（Caddy / nginx），不要把口令裸奔公网。

## 2. 手机端

```bash
cd mobile
flutter pub get
flutter run
```

也可以先 `flutter run -d chrome`。

登录页填写：

- 服务器地址：`http://服务器IP:8787`
- 口令：和 `APP_TOKEN` 相同

Android 模拟器访问电脑用 `http://10.0.2.2:8787`。

## 建议的第一轮验证

1. `WORKSPACE` 指到一个测试 git 仓库
2. 手机发：「在仓库里新建 hello-from-phone.md，写一行今天的日期」
3. 看日志里出现写入文件
4. 打开 Git 页，提交，再 push（服务器要先配好 SSH 或 PAT）

## 安全

- 只给登录用户；外网必须 HTTPS
- 更好再套 VPN 或 IP 白名单
- `WORKSPACE` 不要设成 `/`
- GitHub 用细粒度 token / deploy key
- 推送前看日志，不要盲改生产配置
