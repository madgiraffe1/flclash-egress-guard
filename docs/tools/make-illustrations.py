#!/usr/bin/env python3
"""Generates the SVG illustrations in docs/images, in English and Simplified Chinese.

    /usr/bin/python3 -I docs/tools/make-illustrations.py

Inputs: docs/tools/palette.json (colours), docs/images/app-icon.png (the real app
icon, written by render-screenshots.sh) and, when present, docs/images/logo.svg,
which is inlined into the banners. These are schematic illustrations, not
screenshots; every screenshot comes from render-screenshots.sh. Standard library only.
"""
import base64
import json
import math
import re
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[2]
IMAGES = ROOT / "docs" / "images"
C = {k: v for k, v in json.loads((ROOT / "docs/tools/palette.json").read_text()).items() if not k.startswith("_")}
ICON = base64.b64encode((IMAGES / "app-icon.png").read_bytes()).decode()
LOGO = IMAGES / "logo.svg"

SANS = ("-apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', "
        "'Microsoft YaHei', 'Noto Sans CJK SC', 'Noto Sans SC', 'Helvetica Neue', Arial, sans-serif")
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"
APP = "FlClash 出网保护"


def esc(s):
    return escape(s, {'"': "&quot;"})


def width(s, size, bold=False, mono=False):
    """Rough rendered width, good enough to lay out pills and arrows."""
    w = 0.0
    for ch in s:
        if ord(ch) >= 0x2E80:
            w += 1.0
        elif mono:
            w += 0.61
        elif ch in "il.,:;|!'’ ·()[]":
            w += 0.32
        elif ch in "mwMW":
            w += 0.86
        elif ch.isupper() or ch.isdigit():
            w += 0.64
        else:
            w += 0.55
    return w * size * (1.05 if bold else 1.0)


def text(x, y, s, size=15, weight=400, fill=None, anchor="start", mono=False, opacity=None, spacing=None):
    a = f'x="{x:g}" y="{y:g}" font-size="{size:g}" font-weight="{weight}" fill="{fill or C["ink"]}"'
    if anchor != "start":
        a += f' text-anchor="{anchor}"'
    if mono:
        a += ' class="mono"'
    if opacity is not None:
        a += f' fill-opacity="{opacity:g}"'
    if spacing is not None:
        a += f' letter-spacing="{spacing:g}"'
    return f"<text {a}>{esc(s)}</text>"


def document(w, h, label, body, defs=""):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        f'width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-label="{esc(label)}">\n'
        f"<title>{esc(label)}</title>\n<defs>\n"
        f"<style>text{{font-family:{SANS};}} .mono{{font-family:{MONO};}}"
        "@keyframes fcg-dash{to{stroke-dashoffset:-32}}"
        ".fcg-flow{animation:fcg-dash 1.4s linear infinite}"
        "@media (prefers-reduced-motion: reduce){.fcg-flow{animation:none}}</style>\n"
        f'<linearGradient id="fcg-brand" x1="0" y1="0" x2="1" y2="1">'
        f'<stop offset="0" stop-color="{C["deep"]}"/><stop offset="1" stop-color="{C["bright"]}"/></linearGradient>\n'
        f'<filter id="fcg-shadow" x="-25%" y="-25%" width="150%" height="170%">'
        f'<feDropShadow dx="0" dy="3" stdDeviation="5" flood-color="{C["ink"]}" flood-opacity=".13"/></filter>\n'
        f"{defs}</defs>\n{body}\n</svg>\n"
    )


# ---------------------------------------------------------------- icons

def app_icon(x, y, size):
    return f'<image x="{x:g}" y="{y:g}" width="{size:g}" height="{size:g}" xlink:href="data:image/png;base64,{ICON}"/>'


def laptop(cx, cy, s=1.0, stroke=None, fill="#fff", fill_opacity=1.0, base=None):
    stroke = stroke or C["ink"]
    base = base or stroke
    return (f'<g transform="translate({cx:g} {cy:g}) scale({s:g})">'
            f'<rect x="-44" y="-34" width="88" height="58" rx="7" fill="{fill}" fill-opacity="{fill_opacity:g}" '
            f'stroke="{stroke}" stroke-width="2.6"/>'
            f'<rect x="-36" y="-26" width="72" height="42" rx="3" fill="{stroke}" fill-opacity=".08"/>'
            f'<path d="M-56 28h112l-7 9h-98z" fill="{base}"/></g>')


def globe(cx, cy, r, stroke=None, fill="#fff", fill_opacity=1.0, width_=2.4):
    stroke = stroke or C["ink"]
    chord = math.sqrt(r * r - (r * 0.42) ** 2)
    return (f'<g fill="none" stroke="{stroke}" stroke-width="{width_:g}">'
            f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="{fill}" fill-opacity="{fill_opacity:g}"/>'
            f'<ellipse cx="{cx:g}" cy="{cy:g}" rx="{r * 0.44:g}" ry="{r:g}"/>'
            f'<path d="M{cx - r:g} {cy:g}h{2 * r:g}M{cx - chord:g} {cy - r * 0.42:g}h{2 * chord:g}'
            f'M{cx - chord:g} {cy + r * 0.42:g}h{2 * chord:g}"/></g>')


def router(cx, cy, s=1.0, stroke=None, led=None, fill="#fff", fill_opacity=1.0):
    stroke = stroke or C["ink"]
    led = led or C["ok"]
    return (f'<g transform="translate({cx:g} {cy:g}) scale({s:g})">'
            f'<path d="M-20 -12l-7-18M20 -12l7-18" stroke="{stroke}" stroke-width="2.6" stroke-linecap="round"/>'
            f'<rect x="-36" y="-12" width="72" height="28" rx="8" fill="{fill}" fill-opacity="{fill_opacity:g}" '
            f'stroke="{stroke}" stroke-width="2.6"/>'
            f'<circle cx="-18" cy="2" r="3" fill="{led}"/><circle cx="-6" cy="2" r="3" fill="{led}"/>'
            f'<circle cx="6" cy="2" r="3" fill="{led}"/></g>')


def lock_badge(cx, cy, r=18, color=None):
    color = color or C["warn"]
    k = r / 18
    return (f'<g transform="translate({cx:g} {cy:g}) scale({k:g})">'
            f'<circle r="18" fill="{color}" stroke="#fff" stroke-width="3"/>'
            '<path d="M-5.5 -2v-4a5.5 5.5 0 0 1 11 0v4" fill="none" stroke="#fff" stroke-width="2.6"/>'
            '<rect x="-8.5" y="-2" width="17" height="12.5" rx="2.5" fill="#fff"/></g>')


def check_badge(cx, cy, r=11, color=None, mark="#fff"):
    color = color or C["ok"]
    k = r / 11
    return (f'<g transform="translate({cx:g} {cy:g}) scale({k:g})"><circle r="11" fill="{color}" '
            f'stroke="#fff" stroke-width="2"/><path d="M-5 0.5l3.4 3.4L5.5 -4" fill="none" stroke="{mark}" '
            'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></g>')


def cross_badge(cx, cy, r=11, color=None):
    color = color or C["warn"]
    k = r / 11
    return (f'<g transform="translate({cx:g} {cy:g}) scale({k:g})"><circle r="11" fill="{color}" '
            'stroke="#fff" stroke-width="2"/><path d="M-4.2 -4.2l8.4 8.4M4.2 -4.2l-8.4 8.4" stroke="#fff" '
            'stroke-width="2.6" stroke-linecap="round"/></g>')


def tun_capsule(cx, cy, label, w=130, h=36, color=None, fill_opacity=0.14, text_fill=None, faded=False):
    color = color or C["bright"]
    op = ' opacity=".45"' if faded else ""
    return (f'<g{op}><rect x="{cx - w / 2:g}" y="{cy - h / 2:g}" width="{w:g}" height="{h:g}" rx="{h / 2:g}" '
            f'fill="{color}" fill-opacity="{fill_opacity:g}" stroke="{color}" stroke-width="2"/>'
            + text(cx, cy + 5.5, label, 15, 650, text_fill or color, "middle") + "</g>")


def zip_file(x, y, s=1.0):
    teeth = "".join(f'<rect x="{25 if i % 2 else 29:g}" y="{6 + i * 5:g}" width="6" height="3" rx="1" '
                    f'fill="{C["muted"]}"/>' for i in range(6))
    return (f'<g transform="translate({x:g} {y:g}) scale({s:g})" filter="url(#fcg-shadow)">'
            f'<path d="M8 0h32l20 20v46a8 8 0 0 1-8 8H8a8 8 0 0 1-8-8V8a8 8 0 0 1 8-8z" fill="#fff" '
            f'stroke="{C["line"]}" stroke-width="2"/>'
            f'<path d="M40 0v13a7 7 0 0 0 7 7h13" fill="none" stroke="{C["line"]}" stroke-width="2"/>{teeth}'
            f'<rect x="12" y="46" width="36" height="17" rx="4" fill="{C["bright"]}"/>'
            + text(30, 58.5, "ZIP", 11, 700, "#fff", "middle") + "</g>")


def folder(x, y, w=74, h=56, label=None):
    tab = (f'<path d="M{x:g} {y + 8:g}a8 8 0 0 1 8-8h{w * 0.3:g}l8 8h{w * 0.7 - 24:g}a8 8 0 0 1 8 8v4H{x:g}z" '
           f'fill="{C["bright"]}" fill-opacity=".75"/>')
    body = (f'<rect x="{x:g}" y="{y + 12:g}" width="{w:g}" height="{h - 12:g}" rx="8" fill="url(#fcg-brand)"/>'
            f'<rect x="{x:g}" y="{y + 12:g}" width="{w:g}" height="{h - 12:g}" rx="8" fill="#fff" fill-opacity=".10"/>')
    glyph = ""
    if label == "apps":  # the "A" pencil glyph macOS draws on Applications folders, simplified
        gx, gy = x + w / 2, y + 12 + (h - 12) / 2
        glyph = (f'<path d="M{gx - 11:g} {gy + 10:g}L{gx:g} {gy - 11:g}L{gx + 11:g} {gy + 10:g}M{gx - 6:g} {gy + 2:g}'
                 f'h12" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" '
                 'stroke-linejoin="round" stroke-opacity=".9"/>')
    return f'<g filter="url(#fcg-shadow)">{tab}{body}{glyph}</g>'


def home(cx, cy, r=30):
    return (f'<g filter="url(#fcg-shadow)"><circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="#fff" '
            f'stroke="{C["line"]}" stroke-width="2"/>'
            f'<path d="M{cx - 13:g} {cy + 1:g}L{cx:g} {cy - 11:g}L{cx + 13:g} {cy + 1:g}M{cx - 9:g} {cy - 2:g}'
            f'v13h18v-13M{cx - 3:g} {cy + 11:g}v-7h6v7" fill="none" stroke="{C["deep"]}" stroke-width="2.6" '
            'stroke-linecap="round" stroke-linejoin="round"/></g>')


def cursor(x, y, s=1.0, clicks=True):
    arcs = ""
    if clicks:  # a click ripple centred on the pointer tip
        arcs = (f'<circle r="9" fill="{C["annotation"]}" fill-opacity=".22"/>'
                f'<circle r="16" fill="none" stroke="{C["annotation"]}" stroke-opacity=".55" stroke-width="2"/>')
    return (f'<g transform="translate({x:g} {y:g}) scale({s:g})">{arcs}'
            '<path d="M0 0v24l6.5-6.2 4.6 10.2 4.2-1.9-4.6-10h9.1z" fill="#fff" '
            f'stroke="{C["ink"]}" stroke-width="2" stroke-linejoin="round"/></g>')


def gear(cx, cy, r=26, color=None):
    color = color or C["muted"]
    pts = []
    teeth = 9
    for i in range(teeth * 2):
        a0 = math.pi * 2 * i / (teeth * 2)
        rr = r if i % 2 == 0 else r * 0.80
        for da in (-0.12, 0.12):
            a = a0 + da
            pts.append(f"{cx + rr * math.cos(a):.1f},{cy + rr * math.sin(a):.1f}")
    return (f'<polygon points="{" ".join(pts)}" fill="{color}"/>'
            f'<circle cx="{cx:g}" cy="{cy:g}" r="{r * 0.36:g}" fill="#fff"/>')


def warning(cx, cy, s=1.0):
    return (f'<g transform="translate({cx:g} {cy:g}) scale({s:g})">'
            f'<path d="M0 -20L22 18H-22Z" fill="{C["warn"]}" stroke="{C["warn"]}" stroke-width="5" '
            'stroke-linejoin="round"/><path d="M0 -6v12" stroke="#fff" stroke-width="3.4" stroke-linecap="round"/>'
            '<circle cy="12" r="2.2" fill="#fff"/></g>')


def arrow(x1, y, x2, color=None, dashed=False):
    color = color or C["bright"]
    dash = ' stroke-dasharray="5 6"' if dashed else ""
    return (f'<path d="M{x1:g} {y:g}H{x2 - 9:g}" stroke="{color}" stroke-width="2.6" stroke-linecap="round"{dash}/>'
            f'<path d="M{x2 - 11:g} {y - 7:g}L{x2:g} {y:g}L{x2 - 11:g} {y + 7:g}" fill="none" stroke="{color}" '
            'stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/>')


def pill(x, y, label, size=13, fill=None, stroke=None, color=None, h=28, bold=False, mono=False):
    w = width(label, size, bold) + 26
    return (f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{h / 2:g}" fill="{fill or "#fff"}" '
            f'stroke="{stroke or C["line"]}" stroke-width="1.4"/>'
            + text(x + w / 2, y + h / 2 + size * 0.36, label, size, 650 if bold else 500, color or C["ink"],
                   "middle", mono)), w


def button(x, y, label, primary=False, size=13):
    w = width(label, size, True) + 28
    fill = C["accent"] if primary else "#EEF2F6"
    color = "#fff" if primary else C["ink"]
    return (f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="28" rx="8" fill="{fill}"/>'
            + text(x + w / 2, y + 18.5, label, size, 600, color, "middle")), w


def ring(x, y, w, h):
    return (f'<rect x="{x - 5:g}" y="{y - 5:g}" width="{w + 10:g}" height="{h + 10:g}" rx="12" fill="none" '
            f'stroke="{C["annotation"]}" stroke-width="2.6"/>')


def card(x, y, w, h, r=16, shadow=True):
    f = ' filter="url(#fcg-shadow)"' if shadow else ""
    return (f'<rect x="{x:g}" y="{y:g}" width="{w:g}" height="{h:g}" rx="{r:g}" fill="#fff" '
            f'stroke="{C["line"]}" stroke-width="1.2"{f}/>')


def step_dot(cx, cy, n, r=13):
    return (f'<circle cx="{cx:g}" cy="{cy:g}" r="{r:g}" fill="url(#fcg-brand)"/>'
            + text(cx, cy + 4.6, str(n), 13, 700, "#fff", "middle"))


def paper(w, h):
    return f'<rect x=".5" y=".5" width="{w - 1:g}" height="{h - 1:g}" rx="22" fill="{C["paper"]}" stroke="{C["line"]}"/>'


# ---------------------------------------------------------------- logo

def inline_logo(x, y, size):
    """Nests docs/images/logo.svg, with its ids namespaced so they cannot clash."""
    raw = LOGO.read_text(encoding="utf-8")
    raw = re.sub(r"<\?xml.*?\?>|<!DOCTYPE[^>]*>|<!--.*?-->", "", raw, flags=re.S)
    m = re.search(r"<svg\b([^>]*)>(.*)</svg>", raw, flags=re.S)
    if not m:
        return ""
    attrs, inner = m.group(1), m.group(2)
    vb = re.search(r'viewBox="([^"]+)"', attrs)
    if vb:
        viewbox = vb.group(1)
    else:
        w = re.search(r'width="([\d.]+)', attrs)
        h = re.search(r'height="([\d.]+)', attrs)
        viewbox = f"0 0 {w.group(1) if w else size} {h.group(1) if h else size}"
    for ident in sorted(set(re.findall(r'\bid="([^"]+)"', inner)), key=len, reverse=True):
        e = re.escape(ident)
        inner = re.sub(rf'\bid="{e}"', f'id="logo-{ident}"', inner)
        inner = re.sub(rf"url\(\s*['\"]?#{e}['\"]?\s*\)", f"url(#logo-{ident})", inner)
        inner = re.sub(rf'((?:xlink:)?href)="#{e}"', rf'\1="#logo-{ident}"', inner)
    return f'<svg x="{x:g}" y="{y:g}" width="{size:g}" height="{size:g}" viewBox="{viewbox}">{inner}</svg>'


# ---------------------------------------------------------------- strings

T = {
    "en": {
        "banner_title": "FlClash Egress Guard",
        "banner_sub": "FlClash 出网保护",
        "banner_lines": ["A menu-bar kill switch for FlClash on macOS.",
                         "FlClash drops → internet locks. LAN keeps working."],
        "chips": ["macOS 13+", "Apple silicon", "Menu-bar app", "Built-in macOS firewall"],
        "internet": "Internet", "lan": "LAN",
        "banner_label": "FlClash Egress Guard: a macOS menu-bar kill switch for FlClash",
        "ov_label": "What FlClash Egress Guard does when FlClash is connected and when it drops",
        "ov": [("FlClash connected", "Daily protection on",
                ["Apps reach the internet only through FlClash's TUN.",
                 "Anything trying to go around it is dropped."]),
               ("FlClash quit or TUN down", "Public internet locked",
                ["No silent fallback to a direct connection. LAN,",
                 "printers and localhost keep working; one click reconnects."])],
        "dl_label": "Step 1: download the zip from the latest release and double-click it",
        "dl": ["Latest release", "Download", "Double-click to unzip", "You get the app"],
        "mv_label": "Step 2: move the app into the Applications folder inside your home folder",
        "mv": ["Home folder", "Applications", "~/Applications/" + APP + ".app",
               "Finder ▸ Go ▸ Home  (⇧⌘H)", "No Applications folder? Create one with exactly that name",
               "Keep the app's name unchanged"],
        "op_label": "Step 3: open the app the first time through Privacy & Security",
        "op": ["Double-click the app", "macOS can't verify it", "Click Done", "System Settings",
               "Privacy & Security", "Open Anyway", "Enter your Mac password", "then click Open",
               "Apple could not verify", "Done", "Open",
               "On macOS 13–14 you can also Control-click the app ▸ Open ▸ Open.",
               "Allow it in Settings", "Privacy & Security ▸ Open Anyway"],
    },
    "zh-CN": {
        "banner_title": "FlClash 出网保护",
        "banner_sub": "FlClash Egress Guard",
        "banner_lines": ["macOS 菜单栏出网保护：FlClash 掉线，公网立即锁住。",
                         "局域网、打印机和本机服务照常可用。"],
        "chips": ["macOS 13+", "Apple 芯片", "菜单栏 App", "系统自带防火墙"],
        "internet": "公网", "lan": "局域网",
        "banner_label": "FlClash 出网保护：macOS 菜单栏的 FlClash 断网保护",
        "ov_label": "FlClash 出网保护在 FlClash 正常连接和掉线时分别做什么",
        "ov": [("FlClash 正常连接", "日常保护已开启",
                ["应用只能经 FlClash 的虚拟网卡上公网，",
                 "想绕开它的连接一律丢弃。"]),
               ("FlClash 退出或虚拟网卡掉线", "公网已锁住",
                ["不会悄悄改成直连。局域网、打印机和",
                 "本机服务照常可用，一键重新接通。"])],
        "dl_label": "第 1 步：从最新发布下载压缩包并双击解压",
        "dl": ["最新发布", "下载", "双击解压", "得到 App"],
        "mv_label": "第 2 步：把 App 放进个人文件夹里的「应用程序」",
        "mv": ["个人文件夹", "应用程序", "~/Applications/" + APP + ".app",
               "访达 ▸ 前往 ▸ 个人（⇧⌘H）", "没有「应用程序」文件夹？新建一个，名字写 Applications",
               "不要改 App 的名字"],
        "op_label": "第 3 步：第一次打开时，在「隐私与安全性」里允许",
        "op": ["双击打开 App", "系统提示无法验证", "先点「完成」", "系统设置",
               "隐私与安全性", "仍要打开", "输入 Mac 登录密码", "再点「打开」",
               "Apple 无法验证", "完成", "打开",
               "macOS 13–14 也可以：按住 Control 点按 App ▸ 打开 ▸ 打开。",
               "在设置里允许", "隐私与安全性 ▸ 仍要打开"],
    },
}


# ---------------------------------------------------------------- illustrations

def banner(lang):
    s = T[lang]
    W, H = 1280, 400
    logo = inline_logo(76, 138, 160) if LOGO.exists() else ""
    tx = 276 if logo else 80
    defs = (f'<linearGradient id="fcg-bg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{C["ink"]}"/>'
            f'<stop offset=".5" stop-color="{C["deep"]}"/><stop offset="1" stop-color="{C["mid"]}"/></linearGradient>'
            f'<radialGradient id="fcg-glow" cx="80%" cy="48%" r="42%"><stop offset="0" stop-color="{C["glow"]}" '
            f'stop-opacity=".26"/><stop offset="1" stop-color="{C["glow"]}" stop-opacity="0"/></radialGradient>'
            '<pattern id="fcg-grid" width="32" height="32" patternUnits="userSpaceOnUse">'
            '<path d="M32 0H0V32" fill="none" stroke="#fff" stroke-opacity=".055"/></pattern>'
            f'<clipPath id="fcg-clip"><rect width="{W}" height="{H}" rx="24"/></clipPath>')
    b = [f'<g clip-path="url(#fcg-clip)">',
         f'<rect width="{W}" height="{H}" fill="url(#fcg-bg)"/>',
         f'<rect width="{W}" height="{H}" fill="url(#fcg-grid)"/>',
         f'<rect width="{W}" height="{H}" fill="url(#fcg-glow)"/>',
         '<g fill="none" stroke="#fff" stroke-opacity=".07">'
         + "".join(f'<circle cx="1080" cy="205" r="{r}"/>' for r in (120, 185, 250, 315)) + "</g>"]
    if logo:
        b.append(logo)
    title_size = 46 if lang == "en" else 50
    b.append(text(tx, 150, s["banner_title"], title_size, 700, "#fff", spacing=-0.4))
    b.append(text(tx, 192, s["banner_sub"], 25, 600, C["glow"]))
    b.append(text(tx, 238, s["banner_lines"][0], 20, 400, "#fff", opacity=0.9))
    b.append(text(tx, 266, s["banner_lines"][1], 20, 400, "#fff", opacity=0.9))
    x = tx
    for chip in s["chips"]:
        w = width(chip, 14) + 28
        b.append(f'<rect x="{x:g}" y="292" width="{w:g}" height="30" rx="15" fill="#fff" fill-opacity=".1" '
                 'stroke="#fff" stroke-opacity=".24"/>')
        b.append(text(x + w / 2, 312, chip, 14, 500, "#fff", "middle", opacity=0.92))
        x += w + 10
    # Network art: protected route through the TUN, direct route dropped, LAN allowed.
    lx, ly = 960, 212
    gx, gy = 1205, 148
    rx_, ry_ = 1196, 300
    cap_x, cap_y = 1080, 104
    protected = f"M{lx + 34} {ly - 36}C{lx + 36} {cap_y + 6} {cap_x - 104} {cap_y} {cap_x - 66} {cap_y}" \
                f"M{cap_x + 66} {cap_y}C{cap_x + 100} {cap_y} {gx - 70} {gy - 30} {gx - 40} {gy - 8}"
    b.append(f'<path d="{protected}" fill="none" stroke="{C["glow"]}" stroke-opacity=".35" stroke-width="3"/>')
    b.append(f'<path class="fcg-flow" d="{protected}" fill="none" stroke="{C["glow"]}" stroke-width="3.2" '
             'stroke-dasharray="2 14" stroke-linecap="round"/>')
    b.append(f'<path d="M{lx + 50} {ly - 6}L{gx - 42} {gy + 14}" stroke="#fff" stroke-opacity=".34" '
             'stroke-width="2.6" stroke-dasharray="6 8"/>')
    b.append(f'<path d="M{lx + 52} {ly + 14}C{lx + 110} {ly + 40} {rx_ - 120} {ry_ - 10} {rx_ - 44} {ry_ - 2}" '
             f'fill="none" stroke="#fff" stroke-opacity=".6" stroke-width="2.6"/>')
    b.append(tun_capsule(cap_x, cap_y, "FlClash · TUN", 132, 38, C["glow"], 0.12))
    b.append(laptop(lx, ly, 1.0, "#fff", "#fff", 0.06, "#fff"))
    b.append(globe(gx, gy, 38, "#fff", "#fff", 0.06))
    b.append(router(rx_, ry_, 1.0, "#fff", C["glow"], "#fff", 0.06))
    b.append(lock_badge((lx + 50 + gx - 42) / 2, (ly - 6 + gy + 14) / 2, 18))
    b.append(check_badge(gx - 30, gy - 30, 11, C["glow"], C["ink"]))
    b.append(check_badge(rx_ - 42, ry_ - 24, 11, C["glow"], C["ink"]))
    b.append(text(gx, gy + 62, s["internet"], 14, 500, "#fff", "middle", opacity=0.72))
    b.append(text(rx_, ry_ + 42, s["lan"], 14, 500, "#fff", "middle", opacity=0.72))
    b.append("</g>")
    return document(W, H, s["banner_label"], "\n".join(b), defs)


def overview(lang):
    s = T[lang]
    W, H = 960, 380
    b = [paper(W, H)]
    for i, (title, sub, caption) in enumerate(s["ov"]):
        on = i == 0
        x0, y0, w, h = 24 + i * 468, 24, 444, 332
        b.append(card(x0, y0, w, h, 18))
        if on:
            b.append(check_badge(x0 + 38, y0 + 42, 16, C["ok"]))
        else:
            b.append(lock_badge(x0 + 38, y0 + 42, 17, C["warn"]))
        b.append(text(x0 + 66, y0 + 40, title, 19, 700))
        b.append(text(x0 + 66, y0 + 62, sub, 14, 500, C["ok"] if on else C["warn"]))
        b.append(f'<path d="M{x0 + 24} {y0 + 84}H{x0 + w - 24}" stroke="{C["line"]}"/>')
        mx, my = x0 + 76, y0 + 168
        cx, cy = x0 + 222, y0 + 112
        gx, gy = x0 + 374, y0 + 120
        rx_, ry_ = x0 + 368, y0 + 218
        # LAN route: allowed in both states.
        b.append(f'<path d="M{mx + 44} {my + 10}C{mx + 120} {my + 30} {rx_ - 110} {ry_} {rx_ - 42} {ry_}" '
                 f'fill="none" stroke="{C["ok"]}" stroke-width="2.6"/>')
        if on:
            route = f"M{mx + 30} {my - 34}C{mx + 40} {cy} {cx - 100} {cy} {cx - 62} {cy}M{cx + 62} {cy}H{gx - 36}"
            b.append(f'<path d="{route}" fill="none" stroke="{C["bright"]}" stroke-width="3"/>')
            b.append(f'<path class="fcg-flow" d="{route}" fill="none" stroke="#fff" stroke-width="3" '
                     'stroke-dasharray="2 14" stroke-linecap="round"/>')
            b.append(tun_capsule(cx, cy, "FlClash · TUN", 124, 34, C["bright"], 0.12, C["deep"]))
            b.append(check_badge(gx - 24, gy - 26, 10))
        else:
            b.append(f'<path d="M{mx + 30} {my - 34}C{mx + 40} {cy} {cx - 100} {cy} {cx - 62} {cy}" fill="none" '
                     f'stroke="{C["muted"]}" stroke-opacity=".5" stroke-width="2.6" stroke-dasharray="5 7"/>')
            b.append(tun_capsule(cx, cy, "FlClash · TUN", 124, 34, C["muted"], 0.06, C["muted"], faded=True))
            b.append(cross_badge(cx + 60, cy - 16, 10, C["muted"]))
            b.append(f'<path d="M{mx + 50} {my - 2}L{gx - 32} {gy + 18}" stroke="{C["muted"]}" '
                     'stroke-opacity=".55" stroke-width="2.6" stroke-dasharray="5 7"/>')
            b.append(lock_badge((mx + 50 + gx - 32) / 2 + 6, (my - 2 + gy + 18) / 2 + 2, 17))
        b.append(laptop(mx, my, 0.82))
        b.append(globe(gx, gy, 30))
        b.append(router(rx_, ry_, 0.82))
        b.append(check_badge(rx_ - 44, ry_ - 20, 10))
        b.append(text(mx, my + 52, "Mac", 13, 600, C["muted"], "middle"))
        b.append(text(gx, gy + 50, s["internet"], 13, 600, C["muted"], "middle"))
        b.append(text(rx_, ry_ + 36, s["lan"], 13, 600, C["muted"], "middle"))
        for j, line in enumerate(caption):
            b.append(text(x0 + 26, y0 + 290 + j * 21, line, 14.5, 400, C["ink"], opacity=0.85))
    return document(W, H, s["ov_label"], "\n".join(b))


def install_download(lang):
    s = T[lang]
    W, H = 960, 236
    b = [paper(W, H)]
    # Browser card with the release asset.
    b.append(card(32, 34, 360, 168, 14))
    b.append(f'<path d="M32 70H392" stroke="{C["line"]}"/>')
    b.append("".join(f'<circle cx="{54 + k * 16}" cy="52" r="5" fill="{C["line"]}"/>' for k in range(3)))
    b.append(f'<rect x="112" y="43" width="262" height="18" rx="9" fill="{C["paper"]}"/>')
    b.append(text(124, 56, "github.com/…/releases", 11, 500, C["muted"], mono=True))
    b.append(text(52, 98, s["dl"][0] + " · v1.1.0", 13, 600, C["muted"]))
    b.append(f'<rect x="52" y="112" width="320" height="64" rx="10" fill="{C["paper"]}" stroke="{C["line"]}"/>')
    b.append(zip_file(64, 120, 0.62))
    b.append(text(110, 140, "FlClash-Egress-Guard-", 13, 600, C["ink"], mono=True))
    b.append(text(110, 158, "macOS-arm64.zip", 13, 600, C["ink"], mono=True))
    b.append(f'<circle cx="346" cy="144" r="16" fill="{C["accent"]}"/>'
             '<path d="M346 135v15M339.5 144l6.5 6.5 6.5-6.5" fill="none" stroke="#fff" stroke-width="2.6" '
             'stroke-linecap="round" stroke-linejoin="round"/>')
    b.append(ring(330, 128, 32, 32))
    b.append(text(212, 224, s["dl"][1], 13, 600, C["muted"], "middle"))
    # Zip → double-click → app.
    b.append(arrow(414, 118, 486))
    b.append(zip_file(512, 72, 1.0))
    b.append(cursor(554, 104, 1.05))
    b.append(text(544, 186, s["dl"][2], 14, 600, C["ink"], "middle"))
    b.append(text(544, 206, "FlClash-Egress-Guard-macOS-arm64.zip", 11, 500, C["muted"], "middle", mono=True))
    b.append(arrow(636, 118, 708))
    b.append(f'<g filter="url(#fcg-shadow)">{app_icon(760, 58, 96)}</g>')
    b.append(text(808, 186, s["dl"][3], 14, 600, C["ink"], "middle"))
    b.append(text(808, 206, APP + ".app", 12.5, 600, C["muted"], "middle"))
    return document(W, H, s["dl_label"], "\n".join(b))


def install_move(lang):
    s = T[lang]
    W, H = 960, 250
    b = [paper(W, H)]
    # Breadcrumb: Home › Applications › app
    b.append(card(32, 30, 896, 128, 16))
    b.append(home(98, 86, 30))
    b.append(text(98, 140, s["mv"][0], 13.5, 600, C["ink"], "middle"))
    b.append(arrow(150, 86, 214))
    b.append(folder(236, 58, 76, 58, "apps"))
    b.append(text(274, 140, s["mv"][1], 13.5, 600, C["ink"], "middle"))
    b.append(arrow(336, 86, 400))
    b.append(f'<g filter="url(#fcg-shadow)">{app_icon(424, 50, 72)}</g>')
    b.append(check_badge(494, 56, 12))
    b.append(text(460, 140, APP + ".app", 13.5, 600, C["ink"], "middle"))
    path = s["mv"][2]
    pw = width(path, 14, mono=True) + 32
    b.append(f'<rect x="{560:g}" y="68" width="{pw:g}" height="36" rx="10" fill="{C["paper"]}" stroke="{C["line"]}"/>')
    b.append(text(576, 91, path, 14, 600, C["deep"], mono=True))
    # Tips.
    x = 32
    for k, tip in enumerate(s["mv"][3:]):
        g, w = pill(x, 182, tip, 13, "#fff", C["line"], C["ink"], 32)
        b.append(f'<g>{g}</g>')
        x += w + 12
    return document(W, H, s["mv_label"], "\n".join(b))


def install_open(lang):
    s = T[lang]
    o = s["op"]
    W, H = 960, 300
    b = [paper(W, H)]
    cw, ch, top = 204, 196, 30
    xs = [24 + k * (cw + 26) for k in range(4)]
    for k, x0 in enumerate(xs):
        b.append(card(x0, top, cw, ch, 14))
        b.append(step_dot(x0 + 24, top + 24, k + 1, 12))
        if k < 3:
            b.append(arrow(x0 + cw + 4, top + ch / 2, x0 + cw + 24))
    # 1. Double-click the app.
    x0 = xs[0]
    b.append(f'<g filter="url(#fcg-shadow)">{app_icon(x0 + 66, top + 46, 72)}</g>')
    b.append(cursor(x0 + 120, top + 96, 1.0))
    b.append(text(x0 + cw / 2, top + 160, o[0], 14, 650, C["ink"], "middle"))
    # 2. Blocked: click Done.
    x0 = xs[1]
    b.append(f'<rect x="{x0 + 22}" y="{top + 42}" width="{cw - 44}" height="112" rx="12" fill="{C["paper"]}" '
             f'stroke="{C["line"]}"/>')
    b.append(warning(x0 + cw / 2, top + 72, 0.7))
    b.append(text(x0 + cw / 2, top + 106, o[8] + " …", 11.5, 500, C["muted"], "middle"))
    g, bw = button(0, 0, o[9], primary=True, size=12)
    bx = x0 + cw / 2 - bw / 2
    b.append(f'<g transform="translate({bx:g} {top + 114})">{g}</g>')
    b.append(ring(bx, top + 114, bw, 28))
    b.append(text(x0 + cw / 2, top + 168, o[1], 14, 650, C["ink"], "middle"))
    b.append(text(x0 + cw / 2, top + 186, o[2], 12.5, 500, C["muted"], "middle"))
    # 3. System Settings › Privacy & Security › Open Anyway.
    x0 = xs[2]
    b.append(gear(x0 + 46, top + 70, 17))
    b.append(text(x0 + 72, top + 66, o[3], 12.5, 500, C["muted"]))
    b.append(text(x0 + 72, top + 84, "› " + o[4], 13, 650, C["ink"]))
    g, bw = button(0, 0, o[5], primary=False, size=12.5)
    bx = x0 + cw / 2 - bw / 2
    b.append(f'<g transform="translate({bx:g} {top + 106})">{g}</g>')
    b.append(ring(bx, top + 106, bw, 28))
    b.append(text(x0 + cw / 2, top + 168, o[12], 14, 650, C["ink"], "middle"))
    b.append(text(x0 + cw / 2, top + 186, o[13], 12.5, 500, C["muted"], "middle"))
    # 4. Password, then Open.
    x0 = xs[3]
    b.append(f'<rect x="{x0 + 30}" y="{top + 56}" width="{cw - 60}" height="30" rx="8" fill="#fff" '
             f'stroke="{C["line"]}" stroke-width="1.4"/>')
    b.append("".join(f'<circle cx="{x0 + 50 + k * 14}" cy="{top + 71}" r="4" fill="{C["ink"]}"/>' for k in range(6)))
    g, bw = button(0, 0, o[10], primary=True, size=12.5)
    bx = x0 + cw / 2 - bw / 2
    b.append(f'<g transform="translate({bx:g} {top + 106})">{g}</g>')
    b.append(ring(bx, top + 106, bw, 28))
    b.append(text(x0 + cw / 2, top + 168, o[6], 14, 650, C["ink"], "middle"))
    b.append(text(x0 + cw / 2, top + 186, o[7], 12.5, 500, C["muted"], "middle"))
    # Footnote for macOS 13–14.
    b.append(text(W / 2, top + ch + 46, o[11], 13.5, 500, C["muted"], "middle"))
    return document(W, H, s["op_label"], "\n".join(b))


def main():
    outputs = {"banner": banner, "overview": overview, "install-download": install_download,
               "install-move": install_move, "install-open": install_open}
    for lang in T:
        suffix = "" if lang == "en" else "." + lang
        for name, build in outputs.items():
            path = IMAGES / f"{name}{suffix}.svg"
            path.write_text(build(lang), encoding="utf-8")
            print("wrote", path.relative_to(ROOT))


if __name__ == "__main__":
    main()
