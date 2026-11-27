"""ccauth for Windows: a Tk front end for the ccauth command-line tool.

Every action runs `ccauth ...`; the window reads `ccauth state` (JSON) to draw itself.
Packaged with PyInstaller next to ccauth.exe (see .github/workflows/release.yml).
"""

import json
import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from tkinter import messagebox, ttk
from tkinter.scrolledtext import ScrolledText

HERE = os.path.dirname(os.path.abspath(sys.executable if getattr(sys, "frozen", False) else __file__))


def cli():
    exe = os.path.join(HERE, "ccauth.exe")
    if os.path.exists(exe):
        return [exe]
    script = os.path.join(HERE, "..", "ccauth")
    return [sys.executable, script]


def run_cli(args, stdin_text=None, timeout=600):
    env = dict(os.environ, PYTHONIOENCODING="utf-8", PYTHONUTF8="1")
    env.setdefault("CCAUTH_LANG", "zh")
    flags = 0x08000000 if os.name == "nt" else 0  # CREATE_NO_WINDOW
    try:
        r = subprocess.run(cli() + [str(a) for a in args], input=(stdin_text + "\n") if stdin_text else "",
                           capture_output=True, timeout=timeout, env=env, creationflags=flags)
    except Exception as e:  # noqa: BLE001
        return 1, f"无法运行 ccauth：{e}"
    out = (r.stdout or b"").decode("utf-8", "replace") + (r.stderr or b"").decode("utf-8", "replace")
    return r.returncode, out.strip()


def money(v):
    return "—" if v is None else f"${v:.2f}"


def short(ts):
    return (ts or "")[:16].replace("T", " ")


class App:
    def __init__(self, root, selftest=False):
        self.root = root
        self.state = None
        self.quota = {}
        self.q = queue.Queue()
        root.title("ccauth")
        root.geometry("980x680")
        root.minsize(820, 560)
        style = ttk.Style()
        if "vista" in style.theme_names():
            style.theme_use("vista")
        style.configure("Treeview", rowheight=26)

        top = ttk.Frame(root, padding=(10, 8))
        top.pack(fill="x")
        self.title = ttk.Label(top, text="ccauth", font=("Segoe UI", 13, "bold"))
        self.title.pack(side="left")
        self.busy = ttk.Label(top, text="")
        self.busy.pack(side="left", padx=12)
        ttk.Button(top, text="刷新", command=self.refresh).pack(side="right")

        self.nb = ttk.Notebook(root)
        self.nb.pack(fill="both", expand=True, padx=10)
        self.build_relays()
        self.build_checkin()
        self.claude = self.build_accounts("Claude 账号", [], "切换后重启 claude，正在运行的会话仍用旧账号。")
        self.gemini = self.build_accounts("Gemini CLI 账号", ["gemini"], "切换后重启 gemini。")
        self.build_mac_only()

        out = ttk.Frame(root, padding=(10, 6))
        out.pack(fill="x")
        self.out = ScrolledText(out, height=6, font=("Consolas", 9), wrap="word")
        self.out.pack(fill="x")
        self.out.insert("end", "操作结果会显示在这里。")
        self.out.configure(state="disabled")

        root.after(100, self.poll)
        self.refresh()
        self.selftest_ok = None
        if selftest:
            root.after(12000, self.finish_selftest)

    # ---- plumbing ----

    def background(self, fn, *a):
        threading.Thread(target=lambda: self.q.put(fn(*a)), daemon=True).start()

    def poll(self):
        try:
            while True:
                cb = self.q.get_nowait()
                if callable(cb):
                    cb()
        except queue.Empty:
            pass
        self.root.after(100, self.poll)

    def show(self, ok, text):
        self.out.configure(state="normal")
        self.out.delete("1.0", "end")
        self.out.insert("end", ("完成\n" if ok else "失败\n") + (text or "（没有输出）"))
        self.out.configure(state="disabled")

    def run(self, args, stdin_text=None, confirm=None):
        if confirm and not messagebox.askyesno("ccauth", confirm):
            return
        self.busy.configure(text="执行中…")

        def work():
            code, text = run_cli(args, stdin_text)
            return lambda: (self.show(code == 0, text), self.refresh())
        self.background(work)

    def refresh(self):
        def work():
            code, text = run_cli(["state"], timeout=60)
            return lambda: self.apply_state(code, text)
        self.background(work)

    def apply_state(self, code, text):
        self.busy.configure(text="")
        if code != 0:
            self.show(False, text)
            return
        try:
            self.state = json.loads(text)
        except ValueError:
            self.show(False, "无法解析 ccauth state：\n" + text[:800])
            return
        self.title.configure(text=f"ccauth {self.state.get('version', '')}")
        self.fill_relays()
        self.fill_checkin()
        self.fill_accounts(self.claude, self.state["claude"])
        self.fill_accounts(self.gemini, self.state["gemini"])

    def finish_selftest(self):
        self.selftest_ok = self.state is not None
        print("selftest", "ok" if self.selftest_ok else "failed: state not loaded", flush=True)
        self.root.destroy()

    @staticmethod
    def selected(tree):
        sel = tree.selection()
        return tree.item(sel[0], "values")[0] if sel else None

    @staticmethod
    def entry(parent, label, width=24, show=None):
        ttk.Label(parent, text=label).pack(side="left", padx=(8, 4))
        e = ttk.Entry(parent, width=width, show=show or "")
        e.pack(side="left")
        return e

    # ---- relays ----

    def build_relays(self):
        f = ttk.Frame(self.nb, padding=10)
        self.nb.add(f, text="中转站与余额")
        cols = ("名字", "地址", "key", "余额", "已用", "可用模型")
        self.relay_tree = ttk.Treeview(f, columns=cols, show="headings", height=8)
        for c, w in zip(cols, (110, 220, 70, 80, 80, 360)):
            self.relay_tree.heading(c, text=c)
            self.relay_tree.column(c, width=w, anchor="w")
        self.relay_tree.pack(fill="both", expand=True)
        b = ttk.Frame(f)
        b.pack(fill="x", pady=8)
        ttk.Button(b, text="查询余额", command=self.load_quota).pack(side="left")
        ttk.Button(b, text="更新可用模型", command=lambda: self.run(["agy", "models"])).pack(side="left", padx=6)
        ttk.Button(b, text="删除所选", command=lambda: self.selected(self.relay_tree) and self.run(
            ["agy", "rm", self.selected(self.relay_tree)],
            confirm=f"删除中转站 {self.selected(self.relay_tree)}？")).pack(side="left", padx=6)
        add = ttk.LabelFrame(f, text="新增中转站（保存时自动读取该站的 Gemini 模型列表）", padding=8)
        add.pack(fill="x")
        self.n_name = self.entry(add, "名字", 14)
        self.n_url = self.entry(add, "地址", 30)
        self.n_key = self.entry(add, "API key", 30, show="•")
        ttk.Button(add, text="保存", command=lambda: (
            self.run(["agy", "add", self.n_name.get(), "--url", self.n_url.get(), "--key", self.n_key.get()]),
            self.n_key.delete(0, "end"))).pack(side="left", padx=8)

    def load_quota(self):
        self.busy.configure(text="查询余额…")

        def work():
            code, text = run_cli(["agy", "quota", "--json"])
            def done():
                self.busy.configure(text="")
                try:
                    self.quota = json.loads(text) if code == 0 else {}
                except ValueError:
                    self.quota = {}
                if code != 0:
                    self.show(False, text)
                self.fill_relays()
            return done
        self.background(work)

    def fill_relays(self):
        t = self.relay_tree
        t.delete(*t.get_children())
        for p in self.state["agy"]["providers"]:
            q = self.quota.get(p["name"]) or {}
            left = "查询失败" if q.get("error") else money(q.get("left")) if q else "未查询"
            t.insert("", "end", values=(p["name"], p.get("url") or "", "…" + p.get("key_tail", ""), left,
                                        money(q.get("used")) if q and not q.get("error") else "—",
                                        "，".join(p.get("models") or [])))
        names = [p["name"] for p in self.state["agy"]["providers"]]
        self.lg_relay.configure(values=names)
        if names and not self.lg_relay.get():
            self.lg_relay.set(names[0])

    # ---- check-in ----

    def build_checkin(self):
        f = ttk.Frame(self.nb, padding=10)
        self.nb.add(f, text="每日签到")
        top = ttk.Frame(f)
        top.pack(fill="x")
        self.sched = tk.BooleanVar()
        ttk.Checkbutton(top, text="自动签到（每天 00:10 与 12:10，任务计划程序）", variable=self.sched,
                        command=lambda: self.run(["agy", "checkin", "--install" if self.sched.get() else "--uninstall"])
                        ).pack(side="left")
        ttk.Button(top, text="立即签到", command=lambda: self.run(["agy", "checkin"])).pack(side="right")
        cols = ("账户", "今天", "签到奖励", "签到后余额", "时间")
        self.ck_tree = ttk.Treeview(f, columns=cols, show="headings", height=7)
        for c, w in zip(cols, (140, 260, 90, 100, 140)):
            self.ck_tree.heading(c, text=c)
            self.ck_tree.column(c, width=w, anchor="w")
        self.ck_tree.pack(fill="both", expand=True, pady=8)
        lg = ttk.LabelFrame(f, text="登录 NewAPI 账户（站内有签到按钮的中转站）", padding=8)
        lg.pack(fill="x")
        ttk.Label(lg, text="中转站").pack(side="left", padx=(8, 4))
        self.lg_relay = ttk.Combobox(lg, width=14, state="readonly")
        self.lg_relay.pack(side="left")
        self.lg_user = self.entry(lg, "用户名", 18)
        self.lg_pw = self.entry(lg, "密码", 18, show="•")
        ttk.Button(lg, text="登录并保存", command=lambda: (
            self.run(["agy", "login", self.lg_relay.get(), self.lg_user.get()], self.lg_pw.get()),
            self.lg_pw.delete(0, "end"))).pack(side="left", padx=8)
        st = ttk.LabelFrame(f, text="添加登录即签到的站点（如 Agent Router）", padding=8)
        st.pack(fill="x", pady=(8, 0))
        r1 = ttk.Frame(st)
        r1.pack(fill="x")
        self.s_name = self.entry(r1, "名字", 12)
        self.s_url = self.entry(r1, "地址", 28)
        self.s_user = self.entry(r1, "用户名或邮箱", 22)
        r2 = ttk.Frame(st)
        r2.pack(fill="x", pady=(6, 0))
        self.s_uid = self.entry(r2, "用户 ID（可空）", 10)
        self.s_tok = self.entry(r2, "系统访问令牌（可空）", 26)
        self.s_pw = self.entry(r2, "密码", 16, show="•")
        ttk.Button(r2, text="保存", command=lambda: (
            self.run(["agy", "site", self.s_name.get(), self.s_url.get(), self.s_user.get(),
                      self.s_uid.get(), self.s_tok.get()], self.s_pw.get()),
            self.s_pw.delete(0, "end"))).pack(side="left", padx=8)

    def fill_checkin(self):
        ck = self.state["checkin"]
        self.sched.set(bool(ck.get("scheduled")))
        t = self.ck_tree
        t.delete(*t.get_children())
        import datetime
        today = datetime.date.today().isoformat()
        names = set(ck["records"]) | {s["name"] for s in self.state["agy"]["sites"]} | \
            {p["name"] for p in self.state["agy"]["providers"] if p.get("account")}
        for n in sorted(names):
            r = ck["records"].get(n) or {}
            if r.get("status") == "error":
                day = "失败 " + (r.get("error") or "")
            elif r.get("status") == "wait":
                day = "暂无可领"
            elif r.get("date") == today:
                day = "已签"
            else:
                day = "未签"
            aw = r.get("awarded")
            t.insert("", "end", values=(n, day, "—" if aw is None else f"+${aw:.2f}", money(r.get("balance")),
                                        short(r.get("at"))))

    # ---- accounts ----

    def build_accounts(self, title, prefix, note):
        f = ttk.Frame(self.nb, padding=10)
        self.nb.add(f, text=title)
        cur = ttk.Label(f, text="当前账号：")
        cur.pack(anchor="w")
        ttk.Label(f, text=note, foreground="#666").pack(anchor="w", pady=(2, 6))
        cols = ("名字", "账号", "保存时间", "当前")
        tree = ttk.Treeview(f, columns=cols, show="headings", height=8)
        for c, w in zip(cols, (120, 300, 160, 60)):
            tree.heading(c, text=c)
            tree.column(c, width=w, anchor="w")
        tree.pack(fill="both", expand=True)
        b = ttk.Frame(f)
        b.pack(fill="x", pady=8)

        def act(verb, confirm, extra=()):
            n = self.selected(tree)
            if n:
                self.run(prefix + [verb, n] + list(extra), confirm=confirm.format(n=n))
        ttk.Button(b, text="切换到所选", command=lambda: act("use", "切换到 {n}？")).pack(side="left")
        ttk.Button(b, text="用当前账号覆盖所选", command=lambda: act("save", "用当前登录的账号覆盖 {n}？", ["--force"])
                   ).pack(side="left", padx=6)
        ttk.Button(b, text="删除所选", command=lambda: act("rm", "删除 {n}？")).pack(side="left")
        sv = ttk.LabelFrame(f, text="把当前登录的账号保存为", padding=8)
        sv.pack(fill="x")
        name = self.entry(sv, "名字", 18)
        ttk.Button(sv, text="保存", command=lambda: self.run(prefix + ["save", name.get()])).pack(side="left", padx=8)
        return {"tree": tree, "cur": cur}

    def fill_accounts(self, w, data):
        w["cur"].configure(text="当前账号：" + (data.get("current") or "未登录"))
        t = w["tree"]
        t.delete(*t.get_children())
        for p in data["profiles"]:
            t.insert("", "end", values=(p["name"], p.get("email") or "", short(p.get("savedAt")),
                                        "✓" if p.get("current") else ""))

    def build_mac_only(self):
        f = ttk.Frame(self.nb, padding=16)
        self.nb.add(f, text="Antigravity / Codex")
        ttk.Label(f, justify="left", text=(
            "Antigravity 第三方模式与 Codex 分流依赖 macOS 的后台服务，只在 macOS 版提供。\n\n"
            "Windows 上可用：Claude 与 Gemini CLI 多账号、中转站管理与余额、每日签到（任务计划程序）。")
        ).pack(anchor="w")


def main():
    root = tk.Tk()
    app = App(root, selftest="--selftest" in sys.argv)
    root.mainloop()
    if app.selftest_ok is False:
        sys.exit(1)


if __name__ == "__main__":
    main()
