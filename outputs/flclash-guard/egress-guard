#!/usr/bin/python3 -I
"""macOS PF guard for FlClash, with optional locked-at-boot registration."""

import contextlib
import dataclasses
import fcntl
import grp
import ipaddress
import json
import os
from pathlib import Path
import plistlib
import pwd
import re
import select
import socket
import stat
import subprocess
import sys
import tempfile
import time
import uuid


GUI = "/Applications/FlClash.app/Contents/MacOS/FlClash"
CORE = GUI + "Core"
GROUP = "_flclashguard"
DB = Path("/private/var/db/flclash-egress-guard")
ANCHOR = "com.apple/000.flclash-egress-guard"
PFCTL = "/sbin/pfctl"
ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}
SCRIPT = Path(__file__).resolve()
BOOT_LABEL = "local.flclash-egress-guard"
BOOT_DIR = Path("/Library/Application Support/FlClashEgressGuard")
BOOT_PLIST = Path("/Library/LaunchDaemons") / (BOOT_LABEL + ".plist")
BOOT_CONF = Path("/etc/pf.conf")
BOOT_POLICY = Path("/etc/pf.anchors") / BOOT_LABEL
BOOT_MARK = b"FlClash Egress Guard boot installation v1\n"
HOOK = r'^anchor "com\.apple/\*"\s*(?:all)?\s*$'
LOCAL4 = tuple(map(ipaddress.ip_network, (
    "127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16",
    "169.254.0.0/16", "224.0.0.0/24", "255.255.255.255/32")))
LOCAL6 = tuple(map(ipaddress.ip_network, (
    "::1/128", "fc00::/7", "fe80::/10", "ff01::/16", "ff02::/16")))


class GuardError(Exception):
    pass


def require(ok, message):
    if not ok:
        raise GuardError(message)


def command(args, data=None, check=True):
    # PF, ifconfig and route output may contain addresses. Keep all of it private.
    p = subprocess.run(args, input=data, text=True, capture_output=True, env=ENV,
                       timeout=15, cwd="/")
    if check and p.returncode:
        raise GuardError(f"{Path(args[0]).name} 操作失败（退出码 {p.returncode}）。")
    return p


def pf(*args, data=None):
    return command([PFCTL, *args], data).stdout


def json_read(name):
    path = DB / name
    return json.loads(path.read_text()) if path.exists() else None


def json_save(name, data):
    with tempfile.NamedTemporaryFile(mode="w", dir=DB, delete=False) as f:
        json.dump(data, f)
        temp = f.name
    os.replace(temp, DB / name)


@contextlib.contextmanager
def locked():
    with (DB / "lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield lock


def boot_id():
    return command(["/usr/sbin/sysctl", "-n", "kern.bootsessionuuid"]).stdout.strip()


def session_clock():
    # Apple's Python 3.9 time.monotonic() has a process-local origin. The
    # controller, watcher and status reader need one clock for this deadline.
    return time.clock_gettime(time.CLOCK_MONOTONIC)


def session(boot):
    data = json_read("pf.json")
    return data if data and data["boot"] == boot else None


def group_record():
    r = command(["/usr/bin/dscl", "-plist", ".", "-read", "/Groups/" + GROUP],
                check=False)
    if r.returncode:
        if "RecordNotFound" in (r.stderr + r.stdout):
            return None
        raise GuardError("本地目录服务无法读取专用组。")
    record = plistlib.loads(r.stdout.encode())
    return {k.split(":")[-1]: v for k, v in record.items()}


def group_id(create=False):
    expected = json_read("group.json")
    record = group_record()
    if record is None and create:
        try:
            grp.getgrnam(GROUP)
        except KeyError:
            pass
        else:
            raise GuardError("已有同名目录组，不能用作本机专用组。")
        expected = expected or {"uuid": str(uuid.uuid4()).upper()}
        json_save("group.json", expected)
        command(["/usr/sbin/dseditgroup", "-q", "-o", "create", "-n", ".",
                 "-g", expected["uuid"], "-r", "FlClash egress guard", GROUP])
        record = group_record()
    require(record and expected and record.get("GeneratedUID", [""])[0].upper()
            == expected["uuid"], "专用组尚未就绪，或同名组不属于本工具。")
    require(not any(member for k in ("GroupMembership", "GroupMembers", "NestedGroups")
                    for member in record.get(k, []) if member.strip()), "专用组中有成员，请复核。")
    gid = int(record["PrimaryGroupID"][0])
    require(gid > 0 and gid not in (20, 80), "专用组身份有误。")
    return gid


@dataclasses.dataclass(frozen=True)
class Process:
    pid: int
    ppid: int
    ruid: int
    euid: int
    rgid: int
    egid: int
    path: str


def processes():
    cols = "pid=,ppid=,ruid=,uid=,rgid=,gid=,state=,comm="
    rows = command(["/bin/ps", "-axo", cols]).stdout.splitlines()
    parsed = []
    for row in rows:
        fields = row.split(None, 7)
        # A zombie still appears with its former GID but has already released its sockets.
        if len(fields) == 8 and not fields[6].startswith("Z"):
            parsed.append(Process(*map(int, fields[:6]), fields[7]))
    return parsed


def gui_owner():
    uid = os.stat("/dev/console").st_uid
    require(uid != 0, "请在已登录桌面的本机终端运行。")
    return uid


def pair(gid, rows):
    guis = [p for p in rows if p.path == GUI]
    cores = [p for p in rows if p.path == CORE]
    require(len(guis) == len(cores) == 1, "需要一个正在运行的 FlClash 及其核心。")
    ui, core = guis[0], cores[0]
    require(core.ppid == ui.pid and ui.euid == ui.ruid == core.ruid == gui_owner()
            and core.euid == 0, "当前核心的父进程或身份不符合预期。")
    if gid is not None:
        require(ui.egid == core.egid == gid, "当前 FlClash 未用专用组启动。")
        require(not any(p.euid == 0 and p.egid == gid and p.pid != core.pid for p in rows),
                "另一个特权进程也取得了专用有效组，需要核对。")
    return core


def tunnel(pid):
    rows = command(["/usr/sbin/netstat", "-anv", "-f", "system"]).stdout.splitlines()
    units = set()
    for row in rows:
        f = row.split()
        if (len(f) >= 6 and f[0] == "kctl" and f[-1] == "com.apple.net.utun_control"
                and f"FlClashCore:{pid}" in f and f[-3].isdigit()):
            units.add(int(f[-3]))
    require(len(units) == 1 and min(units) > 0, "核心没有可确认归属的唯一 TUN。")
    nic = f"utun{units.pop() - 1}"
    cfg = command(["/sbin/ifconfig", nic]).stdout
    require(re.search(r"flags=\d+<[^>]*\bUP\b", cfg), "核心的 TUN 未启用。")
    sources = []
    for family, value in re.findall(r"^\s*(inet6?)\s+(\S+)", cfg, re.M):
        addr = ipaddress.ip_address(value.split("%")[0])
        if not (addr.is_link_local or addr.is_loopback or addr.is_unspecified):
            sources.append((family, str(addr)))
    require(sources, "核心 TUN 没有可用源地址。")
    return nic, tuple(sorted(set(sources)))


def owned_path(gid):
    core = pair(gid, processes())
    nic, sources = tunnel(core.pid)
    # Read the local routing table. This sends no packet.
    probe_routes = [("-inet", "1.1.1.1"), ("-inet", "9.9.9.9")]
    if any(f == "inet6" for f, _ in sources):
        probe_routes.append(("-inet6", "2606:4700:4700::1111"))
    for family, destination in probe_routes:
        r = command(["/sbin/route", "-n", "get", family, destination], check=False)
        if not r.returncode and re.search(r"^\s*interface:\s*" + nic + r"\s*$",
                                         r.stdout, re.M):
            return core.pid, nic, sources
    raise GuardError("本机路由表没有把探测目标指向核心持有的 TUN。")


def render(template, gid=None, path=None):
    tun_rules, core_rule = [], ""
    if path:
        _, nic, sources = path
        for family, addr in sources:
            tun_rules.append(f"pass out quick on {nic} {family} from {addr} to any "
                             'flags any no state label "fcg-tun"')
        core_rule = (f"pass out quick proto {{ tcp, udp }} all user 0 group {int(gid)} "
                     'flags any no state label "fcg-core"')
    return template.replace("@TUN_PASSES@", "\n".join(tun_rules)).replace("@CORE_PASS@", core_rule)


def parse_rules(text):
    pf("-n", "-R", "-a", ANCHOR, "-f", "-", data=text)


def install_rules(text):
    pf("-R", "-a", ANCHOR, "-f", "-", data=text)


def read_rules(anchor=ANCHOR, view="-sr"):
    args = (["-a", anchor] if anchor else []) + [view]
    r = command([PFCTL, *args], check=False)
    if r.returncode and "DIOCGETRULES: Invalid argument" in r.stderr and not r.stdout.strip():
        return ""
    require(not r.returncode, "无法读取 pf 规则。")
    return r.stdout


def pf_on():
    return bool(re.search(r"^Status:\s+Enabled\b", pf("-si"), re.M))


def local_state(line):
    # Recognise plain local↔local states. An unrecognised (e.g. NAT) state
    # stays untouched and prevents a misleading activation.
    fields = line.split()
    for arrow in ("->", "<-"):
        if arrow not in fields:
            continue
        i = fields.index(arrow)
        if i < 1 or i + 1 >= len(fields) or "(" in line:
            return False
        for endpoint in (fields[i - 1], fields[i + 1]):
            m = re.fullmatch(r"\[([^]]+)\](?::\d+)?", endpoint)
            raw = m[1] if m else endpoint
            if not m and raw.count(":") == 1 and "." in raw:
                raw = raw.split(":")[0]
            try:
                ip = ipaddress.ip_address(raw.split("%")[0])
            except ValueError:
                return False
            if not any(ip in net for net in (LOCAL4 if ip.version == 4 else LOCAL6)):
                return False
        return True
    return False


def filter_anchors():
    parents = [""]
    for parent in parents:
        args = ["-a", parent] if parent else []
        for row in pf(*args, "-s", "Anchors").splitlines():
            name = row.strip().lstrip("/")
            require(re.fullmatch(r"[\w./-]+", name), "无法识别已有 anchor 名称。")
            if parent and not name.startswith(parent + "/"):
                name = parent + "/" + name
            if name not in parents:
                parents.append(name)
    return parents


def check_layout():
    require(re.search(HOOK, pf("-sr"), re.M), "运行中的 pf 缺少系统 anchor 挂点。")
    interfaces = pf("-v", "-s", "Interfaces").splitlines()
    require(not any("(skip)" in l and l.split()[0] != "lo0" for l in interfaces),
            "有其他接口被设置为跳过 pf；当前规则无法保证封锁。")
    # Other active outbound policy could precede the hook, create a floating
    # state, or be unintentionally overridden by an allow rule in this anchor.
    for anchor in filter_anchors():
        if anchor == ANCHOR:
            continue
        for line in read_rules(anchor).splitlines():
            rule = line.lstrip()
            if re.match(r"^(?:pass|block)\b", rule):
                if re.match(r"^block(?: (?:drop|return\S*))? in\b", rule):
                    continue
                if rule.startswith("pass in ") and "no state" in rule:
                    continue
                raise GuardError("发现其他活动过滤规则，需核对顺序；没有覆盖或清除它。")
        for line in read_rules(anchor, "-sn").splitlines():
            require(not re.match(r"^\s*(?:nat|rdr|binat)\s", line),
                    "发现其他活动的地址转换，需核对它创建的状态。")
    require(all(local_state(l) for l in pf("-ss").splitlines() if l.strip()),
            "已有非局域网或无法归类的 pf 连接状态；本工具不会清除它。")


def boot_stanza():
    return (f'\n# FlClash Egress Guard (boot)\n'
            f'load anchor "{ANCHOR}" from "{BOOT_POLICY}"\n').encode()


def registration_boot():
    mark = BOOT_DIR / "installation"
    if not BOOT_DIR.is_symlink() and mark.is_file():
        record = mark.read_bytes()
        if record.startswith(BOOT_MARK):
            return record[len(BOOT_MARK):].decode().strip()
    return None


def boot_owned():
    return bool(registration_boot())


def boot_registered():
    return (boot_owned() and BOOT_PLIST.is_file() and BOOT_POLICY.is_file()
            and boot_stanza() in BOOT_CONF.read_bytes())


def boot_policy(template):
    return render(template).replace('label "fcg-deny"', 'label "fcg-boot-deny"')


def boot_rules_loaded(rules):
    return ('label "fcg-boot-deny"' in rules and 'label "fcg-core"' not in rules
            and 'label "fcg-tun"' not in rules)


@contextlib.contextmanager
def settings_lock():
    # The anchors directory exists before installation and survives full rollback.
    fd = os.open(BOOT_POLICY.parent, os.O_RDONLY)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield fd
    finally:
        os.close(fd)


def write_file(path, data, mode, before_replace=None, owner=(0, 0)):
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        staging = Path(f.name)
        try:
            f.write(data)
            f.flush()
            if os.geteuid() == 0:
                os.fchown(f.fileno(), *owner)
            os.fchmod(f.fileno(), mode)
            os.fsync(f.fileno())
            if before_replace:
                before_replace(staging)
            os.replace(staging, path)
        finally:
            staging.unlink(missing_ok=True)


def change_boot_conf(old, new, validate):
    info = BOOT_CONF.stat()

    def check(staged):
        if validate:
            command([PFCTL, "-n", "-f", str(staged)])
        require(BOOT_CONF.read_bytes() == old, "系统 pf 配置刚被更改，请重试。")

    write_file(BOOT_CONF, new, stat.S_IMODE(info.st_mode), check, (info.st_uid, info.st_gid))


def boot_job():
    return plistlib.dumps({
        "Label": BOOT_LABEL,
        "ProgramArguments": ["/usr/bin/python3", "-I", "-B", str(BOOT_DIR / "egress-guard"), "boot-arm"],
        "RunAtLoad": True, "KeepAlive": {"SuccessfulExit": False}, "ThrottleInterval": 2,
    })


def job_loaded():
    return command(["/bin/launchctl", "print", "system/" + BOOT_LABEL], check=False).returncode == 0


def stop_boot_registration():
    config = BOOT_CONF.read_bytes()
    stanza = boot_stanza()
    if stanza in config:
        change_boot_conf(config, config.replace(stanza, b"", 1), validate=False)
    require(not any(BOOT_POLICY.as_posix().encode() in line.split(b"#", 1)[0]
                    for line in BOOT_CONF.read_bytes().splitlines()),
            "系统 pf 配置仍引用开机规则文件，请核对后再移除。")
    if job_loaded():
        command(["/bin/launchctl", "bootout", "system/" + BOOT_LABEL])


def remove_boot_files():
    for path in (BOOT_PLIST, BOOT_POLICY, BOOT_DIR / "egress-guard", BOOT_DIR / "policy.pf",
                 BOOT_DIR / "installation"):
        path.unlink(missing_ok=True)
    BOOT_DIR.rmdir()


def sync_panel_login(required=False):
    uid = os.stat("/dev/console").st_uid
    if uid <= 0:
        return
    if SCRIPT.parent.name == "Resources" and SCRIPT.parents[1].name == "Contents":
        helper = SCRIPT.with_name("guard-guide")
    else:
        helper = Path(pwd.getpwuid(uid).pw_dir) / "Applications/FlClash 出网保护.app/Contents/Resources/guard-guide"
    if not helper.is_file():
        return  # Standalone Terminal installation without the menu-bar app.
    # Only the desktop user executes the app's code and owns the LaunchAgent.
    try:
        r = command(["/bin/launchctl", "asuser", str(uid), "/usr/bin/sudo", "-H", "-u", "#" + str(uid),
                     "--", "/usr/bin/python3", "-I", "-B", str(helper), "--app", "sync-login"], check=False)
        ok = r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        ok = False
    if not ok:
        if required:
            raise GuardError("防火墙开机项已登记，菜单栏登录项尚未同步，请在 App 内补全。")
        print("出网设置已恢复，菜单栏登录项仍待清理。")


def configure_boot():
    if boot_registered():
        sync_panel_login(required=True)
        print("开机保护已经设置。登录后双击「开启日常保护.command」即可接通 FlClash。")
        return
    require(not boot_owned(), "上一次开机设置尚未完成。先用「恢复上网.command」清理，再重试。")
    require(not any(os.path.lexists(p) for p in (BOOT_DIR, BOOT_POLICY, BOOT_PLIST))
            and not job_loaded(), "同名系统文件或启动项已存在，请核对。")
    config = BOOT_CONF.read_bytes()
    require(re.search(HOOK, config.decode(), re.M) and ANCHOR.encode() not in config
            and BOOT_LABEL.encode() not in config, "系统 pf 配置缺少预期挂点，或已有同名规则。")
    require(not BOOT_CONF.is_symlink(), "系统 pf 配置是符号链接，需要先核对。")
    disabled = command(["/bin/launchctl", "print-disabled", "system"]).stdout
    require(not re.search(r'"' + re.escape(BOOT_LABEL) + r'"\s*=>\s*(?:true|disabled)', disabled),
            "系统已单独禁用这个启动项，请先核对后台项目设置。")
    existing = read_rules().strip()
    require(not existing or (session(boot_id()) and 'label "fcg-deny"' in existing),
            "同名活动 anchor 已在使用。")
    check_layout()
    template = SCRIPT.with_name("policy.pf").read_bytes()
    closed = boot_policy(template.decode())
    parse_rules(closed)
    BOOT_DIR.mkdir(mode=0o755)
    try:
        if os.geteuid() == 0:
            os.chown(BOOT_DIR, 0, 0)
        BOOT_DIR.chmod(0o755)
        write_file(BOOT_DIR / "installation", BOOT_MARK + boot_id().encode() + b"\n", 0o644)
        write_file(BOOT_DIR / "egress-guard", SCRIPT.read_bytes(), 0o755)
        write_file(BOOT_DIR / "policy.pf", template, 0o644)
        write_file(BOOT_POLICY, closed.encode(), 0o644)
        change_boot_conf(config, config + boot_stanza(), validate=True)
        write_file(BOOT_PLIST, boot_job(), 0o644)
    except BaseException:
        if boot_stanza() in BOOT_CONF.read_bytes():
            stop_boot_registration()
        remove_boot_files()
        raise
    sync_panel_login(required=True)
    print("已设置开机保护，下次开机自动锁住公网。登录后可以接通 FlClash。")


def acquire_pf(s):
    if not s.get("token"):
        ref = command([PFCTL, "-E"], check=False)
        match = re.search(r"\bToken\s*:\s*(\d+)", ref.stdout + ref.stderr)
        require(match, "无法取得本工具的 pf 启用引用。")
        s["token"] = match[1]
        json_save("pf.json", s)
        require(not ref.returncode, "取得 pf 引用时发生错误。")
    require(pf_on(), "pf 未在运行。")


def arm_boot():
    # Apple loads the closed anchor from pf.conf. launchd retries if that
    # loader is still starting. Only the user's daily action may open egress.
    if not boot_registered():
        return
    boot = boot_id()
    if registration_boot() == boot:
        return  # Scheduling next boot must not interrupt the installation session.
    DB.mkdir(mode=0o700, exist_ok=True)
    with locked():
        rules = read_rules()
        require(re.search(HOOK, pf("-sr"), re.M), "等待系统载入 pf 主挂点。")
        previous = session(boot)
        if previous and 'label "fcg-deny"' in rules:
            acquire_pf(previous)
            return
        require(boot_rules_loaded(rules), "等待系统载入开机阻断规则。")
        s = dict(previous or {}, boot=boot, serial=str(uuid.uuid4()), pid=None, tun=None,
                 mode="locked", reason="开机保护", deadline=None)
        json_save("pf.json", s)
        acquire_pf(s)
        check_layout()
        s["boot_confirmed"] = True
        json_save("pf.json", s)


def cancel_boot():
    if not boot_owned():
        sync_panel_login()
        print("开机保护未设置。")
        return
    if boot_rules_loaded(read_rules()):
        if pf_on():
            # Keep today's lock and its PF reference when removing future boots.
            enable((BOOT_DIR / "policy.pf").read_text(), lock_only=True)
        else:
            pf("-a", ANCHOR, "-F", "rules")
    stop_boot_registration()
    remove_boot_files()
    sync_panel_login()
    print("已取消开机保护。本次已开启的保护仍然有效。")


def run_gui(uid, gid):
    """Executed by launchctl asuser in the logged-in user's bootstrap domain."""
    require(os.geteuid() == 0 and uid == gui_owner() and gid == group_id(),
            "GUI 启动身份不正确。")
    user = pwd.getpwuid(uid)
    os.initgroups(user.pw_name, user.pw_gid)
    os.setgid(user.pw_gid)
    os.setegid(gid)
    os.setuid(uid)
    require(os.getuid() == os.geteuid() == uid and os.getegid() == gid, "降权失败。")
    env = dict(ENV, HOME=user.pw_dir, USER=user.pw_name, LOGNAME=user.pw_name,
               SHELL=user.pw_shell)
    env.pop("LC_ALL")
    env["TMPDIR"] = command(["/usr/bin/getconf", "DARWIN_USER_TEMP_DIR"]).stdout.strip()
    os.chdir(user.pw_dir)
    os.umask(0o022)
    os.execve(GUI, [GUI], env)


def start(desktop_uid=None):
    uid = gui_owner()
    requester = os.environ.get("SUDO_UID") if desktop_uid is None else desktop_uid
    require(requester == str(uid), "请从当前登录的 Mac 桌面启动 FlClash。")
    require(not any(p.path in (GUI, CORE) for p in processes()),
            "FlClash 正在运行。切换启动身份需要你先手动退出。")
    DB.mkdir(mode=0o700, exist_ok=True)
    with locked():
        require(not any(p.path in (GUI, CORE) for p in processes()), "FlClash 已经在运行。")
        rules = read_rules()
        require(pf_on() and re.search(HOOK, pf("-sr"), re.M) and
                ((session(boot_id()) and 'label "fcg-deny"' in rules)
                 or (boot_rules_loaded(rules) and boot_registered()))
                and 'label "fcg-core"' not in rules, "请先用 lock 锁住公网，再启动 FlClash。")
        gid = group_id(create=True)
        with open(os.devnull, "rb+") as null:
            child = subprocess.Popen(
                ["/bin/launchctl", "asuser", str(uid), "/usr/bin/python3", "-I", "-B",
                 str(SCRIPT), "_gui", str(uid), str(gid)], env=ENV, cwd="/",
                start_new_session=True, stdin=null, stdout=null, stderr=null)
        for _ in range(40):
            if any(p.path == GUI and p.euid == uid and p.egid == gid for p in processes()):
                print("FlClash 已在当前桌面以专用有效组启动。")
                return
            if child.poll() is not None:
                break
            time.sleep(.2)
        raise GuardError("尚未确认 GUI 已用专用组启动；可用 status 查看。")


def disable_locked(s, owned_boot=False):
    if not s:
        rules = read_rules().strip()
        if rules and owned_boot and boot_rules_loaded(rules):
            pf("-a", ANCHOR, "-F", "rules")
        else:
            require(not rules, "发现未登记的同名 anchor，请先核对。")
        return
    if read_rules().strip():
        pf("-a", ANCHOR, "-F", "rules")
    if s.get("token"):
        r = command([PFCTL, "-X", s["token"]], check=False)
        if r.returncode:
            refs = pf("-s", "References")
            require(not re.search(r"\b" + s["token"] + r"\b", refs),
                    "本工具的 pf 引用仍在；可再次运行 disable。")
    (DB / "pf.json").unlink(missing_ok=True)


def close_public(s, locked_rules, reason):
    install_rules(locked_rules)
    s.update(mode="locked", deadline=None, reason=reason)
    json_save("pf.json", s)


def watch(boot, serial, gid, original, locked_rules):
    # Only this live session is watched. No launchd job and no automatic reopen.
    pid = original[0]
    # macOS kqueue has close(), but does not implement the context-manager protocol.
    with contextlib.closing(select.kqueue()) as queue:
        try:
            queue.control([select.kevent(pid, filter=select.KQ_FILTER_PROC,
                          flags=select.KQ_EV_ADD | select.KQ_EV_ONESHOT,
                          fflags=select.KQ_NOTE_EXIT)], 0, 0)
        except OSError:
            pass  # The first reconciliation also detects an already-exited core.
        # enable() holds this lock until it has published the connected state.
        with locked():
            s = session(boot)
            if not s or s["serial"] != serial or s["mode"] != "connected":
                return
        while DB.is_dir():
            events = queue.control(None, 1, 1.0)
            # Reconciliation may call several system tools. Do not hold the
            # recovery lock during those calls.
            s = session(boot)
            if not s or s["serial"] != serial:
                return
            healthy = False
            if s["mode"] != "locked" and not events:
                try:
                    healthy = owned_path(gid) == original
                except (GuardError, OSError, subprocess.SubprocessError, ValueError):
                    pass
            with locked():
                s = session(boot)
                if not s or s["serial"] != serial:
                    return
                if s.get("deadline") and session_clock() >= s["deadline"]:
                    close_public(s, locked_rules, "试用时间已到")
                    return
                if s["mode"] == "locked":
                    return
                if not healthy:
                    close_public(s, locked_rules, "核心已退出" if events else "核心或虚拟网卡状态改变")
                    return


def spawn_watcher(lock, boot, serial, gid, path, locked_rules, settings_fd=None):
    pid = os.fork()
    if pid:
        return pid
    # Do not unlock the parent's shared open-file description after fork.
    os.close(lock.fileno())
    if settings_fd is not None:
        os.close(settings_fd)
    try:
        os.setsid()
        os.chdir("/")
        with open(os.devnull, "rb+") as null:
            for fd in (0, 1, 2):
                os.dup2(null.fileno(), fd)
        watch(boot, serial, gid, path, locked_rules)
    except BaseException:
        # If observation fails, withdraw the public exception when possible.
        try:
            with locked():
                s = session(boot)
                if s and s["serial"] == serial:
                    close_public(s, locked_rules, "退出监视器发生错误")
        except BaseException:
            pass
    finally:
        os._exit(0)


def enable(template, trial=False, lock_only=False, settings_fd=None):
    if lock_only and not DB.is_dir():
        rules = read_rules().strip()
        require(not rules or (boot_rules_loaded(rules) and boot_registered()),
                "同名 anchor 已在使用；不会覆盖。")
        check_layout()
        DB.mkdir(mode=0o700, exist_ok=True)
    require(DB.is_dir(), "先用 lock 锁住公网，再手动切换 FlClash 的启动身份。")
    boot = boot_id()
    with locked() as lock:
        gid = None if lock_only else group_id()
        path = None if lock_only else owned_path(gid)
        connected = render(template, gid, path)
        closed = render(template)
        parse_rules(connected)
        parse_rules(closed)
        previous = session(boot)
        existing = read_rules().strip()
        from_boot = boot_rules_loaded(existing) and boot_registered()
        require(previous or not existing or from_boot, "同名 anchor 已在使用；不会覆盖。")
        if previous and existing:
            require('label "fcg-deny"' in existing or from_boot, "同名 anchor 内容与记录不一致。")
        check_layout()
        serial = str(uuid.uuid4())
        s = dict(previous or {}, boot=boot, serial=serial,
                 pid=path[0] if path else None, tun=path[1] if path else None,
                 mode="locked", reason="手动锁定", deadline=(session_clock() + 180 if trial else None))
        # Persist ownership before mutation, so the offline disable command can
        # always remove an interrupted activation.
        json_save("pf.json", s)
        try:
            install_rules(closed)
            acquire_pf(s)
            check_layout()
            if lock_only:
                require('label "fcg-deny"' in read_rules(), "未能读回公网阻断规则。")
                print("公网已锁定。可以手动切换 FlClash，也可用 disable 恢复出网。")
                return
            require(owned_path(gid) == path, "加载过程中核心或 TUN 已变化。")
            watcher = spawn_watcher(lock, boot, serial, gid, path, closed, settings_fd)
            install_rules(connected)
            require('label "fcg-core"' in read_rules(), "未能读回核心出口规则。")
            s.update(mode="connected", watcher=watcher, reason=None)
            json_save("pf.json", s)
        except BaseException:
            if from_boot:
                close_public(s, boot_policy(template), "开机保护")
            elif not previous:
                disable_locked(s)
            else:
                close_public(s, closed, "试用启动未完成")
            raise
    print("保护规则已装载。请按说明验收。")
    if trial:
        print("本次为限时试用，180 秒后锁住公网；再次执行 enable 可转为持续保护。")
    return boot, serial


def disable(rollback=False):
    owned_boot = boot_owned()
    if owned_boot:
        stop_boot_registration()
    if DB.exists():
        with locked():
            disable_locked(session(boot_id()), owned_boot)
    else:
        disable_locked(None, owned_boot)
    if owned_boot:
        remove_boot_files()
        print("开机保护已移除。")
    sync_panel_login()
    print("本工具的出网限制已解除。")
    if not rollback or not DB.exists():
        return
    with locked():
        if json_read("group.json") and group_record() is not None:
            gid = group_id()
            require(not any(gid in (p.egid, p.rgid) for p in processes()),
                    "出网已恢复。请手动退出以专用组启动的 FlClash，再运行 rollback 删除组。")
            command(["/usr/sbin/dseditgroup", "-q", "-o", "delete", "-n", ".", GROUP])
        for item in ("group.json", "pf.json", "lock"):
            (DB / item).unlink(missing_ok=True)
        DB.rmdir()
        print("专用组和本工具的系统记录已清理，可从原图标启动 FlClash。")


def report_boot_lock(registered, running, rules):
    if not (registered and boot_rules_loaded(rules)):
        return False
    if not running:
        print("开机规则已载入，等待防火墙启用。")
        return True
    try:
        check_layout()
        print("公网出口已锁定（开机保护）。")
    except GuardError:
        print("开机规则已载入，活动规则或接口未通过核对。")
    return True


def status():
    registered = boot_registered()
    if registered:
        print("开机保护已设置。")
    elif boot_owned():
        print("开机保护设置不完整，可用「恢复上网.command」清理。")
    else:
        print("开机保护未设置。")
    rows = processes()
    for p in rows:
        if p.path in (GUI, CORE):
            print(f"{Path(p.path).name}    PID {p.pid}    有效 UID {p.euid}    有效 GID {p.egid}")
    if os.geteuid() != 0:
        print("运行 sudo ./egress-guard status 可读取内核 pf 状态。")
        return
    boot = boot_id()
    if registered:
        if registration_boot() == boot:
            print("等待下次开机验收。")
        elif (session(boot) or {}).get("boot_confirmed"):
            print("本次开机启动项已确认过公网锁定。")
        else:
            print("尚未读到本次开机启动项的锁定记录。")
    if not DB.is_dir():
        running, rules = pf_on(), read_rules().strip()
        print("系统 pf " + ("已启用" if running else "已停用"))
        if not report_boot_lock(registered, running, rules):
            print("本工具尚未安装。" if not rules else "存在未登记的同名 anchor。")
        return
    with locked():
        running, rules = pf_on(), read_rules()
        print("系统 pf " + ("已启用" if running else "已停用"))
        s = session(boot)
        if report_boot_lock(registered, running, rules):
            return
        if not s:
            print("本工具已停用。" if not rules else "存在未登记的同名 anchor。")
        elif not running or 'label "fcg-deny"' not in rules:
            print("保护异常，内核中缺少有效阻断。")
        elif s["mode"] == "locked" and 'label "fcg-core"' not in rules:
            print("公网出口已锁定；局域网和回环例外仍有效。")
            if s.get("reason"):
                print("锁定原因  " + s["reason"])
        else:
            try:
                os.kill(s["watcher"], 0)
                path = owned_path(group_id())
                require(path[:2] == (s["pid"], s["tun"]) and 'label "fcg-core"' in rules,
                        "核心或规则已变化。")
                print(f"保护已装载，核心使用 {s['tun']}。")
            except (KeyError, GuardError, OSError):
                print("保护需要复核，进程、TUN 或监视器状态与记录不一致。")
        if s and s.get("deadline"):
            print(f"限时试用剩余 {max(0, int(s['deadline'] - session_clock()))} 秒。")


def main():
    require(sys.platform == "darwin", "仅适用于 macOS。")
    args = sys.argv[1:]
    if len(args) == 3 and args[0] == "_gui":
        run_gui(int(args[1]), int(args[2]))
        return
    # A macOS administrator dialog supplies the UI caller's UID. Terminal
    # callers continue to use the invoking user recorded by sudo.
    desktop_uid = None
    if len(args) == 2 and args[0] == "start" and args[1].isdecimal():
        desktop_uid = args[1]
        args = args[:1]
    names = ("preview", "check", "status", "lock", "start", "trial", "enable", "disable", "rollback",
             "boot-on", "boot-off", "boot-arm")
    require(len(args) == 1 and args[0] in names, "用法：egress-guard " + " | ".join(names))
    action = args[0]
    if action == "status":
        status()
    elif action in ("preview", "check"):
        template = SCRIPT.with_name("policy.pf").read_text()
        path = owned_path(None)
        # Placeholder GID never reaches the live loader.
        parse_rules(render(template, 39999, path))
        parse_rules(render(template))
        print(f"通过：当前核心持有 {path[1]}；联网和锁定两套规则均通过 pfctl -n。")
        if action == "check":
            require(os.geteuid() == 0, "读取活动的 pf 规则和状态需要 sudo。")
            rules = read_rules().strip()
            require(not rules or session(boot_id()) or (boot_rules_loaded(rules) and boot_registered()),
                    "同名 anchor 已在使用。")
            check_layout()
            print("通过：已只读核对活动挂点、已有规则、跳过的接口和连接状态。")
    else:
        require(os.geteuid() == 0, "此操作需要本机终端的 sudo。")
        os.umask(0o077)
        with settings_lock() as settings_fd:
            if action == "boot-on":
                configure_boot()
            elif action == "boot-off":
                cancel_boot()
            elif action == "boot-arm":
                require(SCRIPT == BOOT_DIR / "egress-guard", "请由已安装的开机服务执行。")
                arm_boot()
            elif action == "start":
                start(desktop_uid)
            elif action in ("lock", "trial", "enable"):
                enable(SCRIPT.with_name("policy.pf").read_text(), trial=(action == "trial"),
                       lock_only=(action == "lock"), settings_fd=settings_fd)
            else:
                disable(rollback=(action == "rollback"))


if __name__ == "__main__":
    try:
        main()
    except (GuardError, OSError, ValueError, subprocess.SubprocessError) as exc:
        # Never print OS/subprocess diagnostics containing routes or endpoints.
        print(str(exc) if isinstance(exc, GuardError) else "系统操作未完成。",
              file=sys.stderr)
        sys.exit(1)
