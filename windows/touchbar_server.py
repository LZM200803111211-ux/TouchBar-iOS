# -*- coding: utf-8 -*-
"""Windows 端：蓝牙连 iPhone，收按键、推状态。

装依赖：pip install -r requirements.txt
运行：  python touchbar_server.py
"""
import asyncio
import ctypes
import json
import os
import socket
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import psutil
from bleak import BleakClient, BleakScanner

SVC = "8E1A0001-7D3B-4F2A-9C61-0A2B3C4D5E6F"
CMD = "8E1A0002-7D3B-4F2A-9C61-0A2B3C4D5E6F"
STAT = "8E1A0003-7D3B-4F2A-9C61-0A2B3C4D5E6F"
NAME = "iPhoneTouchBar"

COVER_PORT = 8765
COVER_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cover.jpg")
_cover_seen = [""]        # 上一次的标题，用来判断换歌

u32 = ctypes.windll.user32
KU = 0x0002

VK = {
    "prev": 0xB1, "next": 0xB0, "play": 0xB3, "stop": 0xB2,
    "shot": 0x2C, "undo": 0x5A, "redo": 0x59,
    "copy": 0x43, "cut": 0x58, "paste": 0x56,
    "pgup": 0x21, "pgdn": 0x22, "mute": 0xAD,
}


def tap(vk, alt=False):
    if alt:
        u32.keybd_event(0x12, 0, 0, 0)
    u32.keybd_event(vk, 0, 0, 0)
    u32.keybd_event(vk, 0, KU, 0)
    if alt:
        u32.keybd_event(0x12, 0, KU, 0)


def set_volume(pct):
    try:
        from ctypes import cast, POINTER
        from comtypes import CLSCTX_ALL
        from pycaw.pycaw import AudioUtilities, IAudioEndpointVolume
        dev = AudioUtilities.GetSpeakers()
        itf = dev.Activate(IAudioEndpointVolume._iid_, CLSCTX_ALL, None)
        vol = cast(itf, POINTER(IAudioEndpointVolume))
        vol.SetMasterVolumeLevelScalar(max(0.0, min(1.0, pct / 100.0)), None)
    except Exception:
        step = 0xAF if pct > 50 else 0xAE
        for _ in range(max(1, abs(pct - 50) // 2)):
            u32.keybd_event(step, 0, 0, 0)
            u32.keybd_event(step, 0, KU, 0)


def set_brightness(pct):
    try:
        subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "(Get-WmiObject -Namespace root/wmi -Class WmiMonitorBrightnessMethods)"
             ".WmiSetBrightness(1,%d)" % max(0, min(100, pct))],
            capture_output=True, timeout=8)
    except Exception:
        pass


def run(cmd):
    print("  ->", cmd)
    if cmd in VK:
        tap(VK[cmd]); return
    if cmd.startswith("volset:"):
        set_volume(int(cmd.split(":")[1])); return
    if cmd.startswith("briset:"):
        set_brightness(int(cmd.split(":")[1])); return
    if cmd == "muteMic":
        tap(VK["mute"]); return
    if cmd == "alttab":
        tap(0x09, alt=True); return
    if cmd == "showdesk":
        u32.keybd_event(0x5B, 0, 0, 0); u32.keybd_event(0x44, 0, 0, 0)
        u32.keybd_event(0x44, 0, KU, 0); u32.keybd_event(0x5B, 0, KU, 0); return
    if cmd == "lock":
        u32.LockWorkStation(); return
    if cmd == "sleep":
        subprocess.run(["rundll32.exe", "powrprof.dll,SetSuspendState", "0,1,0"]); return
    if cmd == "recycle":
        os.startfile("shell:RecycleBinFolder"); return
    if cmd == "music":
        os.startfile("mswindowsmusic:"); return
    if cmd == "wechat":
        subprocess.Popen(["cmd", "/c", "start", "", "weixin://"]); return
    if cmd == "browser":
        os.startfile("https://papercloud.top"); return


def gpu_percent():
    try:
        out = subprocess.run(
            ["nvidia-smi", "--query-gpu=utilization.gpu",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=3).stdout.strip().splitlines()
        return float(out[0]) if out else 0.0
    except Exception:
        return 0.0


MEDIA_PS = (
    "try {"
    " $m=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]"
    "::RequestAsync().GetAwaiter().GetResult();"
    " $s=$m.GetCurrentSession();"
    " if ($s) {"
    "  $p=$s.TryGetMediaPropertiesAsync().GetAwaiter().GetResult();"
    "  $i=$s.GetPlaybackInfo();"
    "  @{title=$p.Title;artist=$p.Artist;playing=($i.PlaybackStatus -eq 4)}"
    " | ConvertTo-Json -Compress"
    " } else { '{\"title\":\"\",\"artist\":\"\",\"playing\":false}' }"
    "} catch { '{\"title\":\"\",\"artist\":\"\",\"playing\":false}' }"
)


COVER_PS = (
    "try {"
    " $m=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]"
    "::RequestAsync().GetAwaiter().GetResult();"
    " $s=$m.GetCurrentSession(); if (-not $s) { exit 1 };"
    " $p=$s.TryGetMediaPropertiesAsync().GetAwaiter().GetResult();"
    " $ref=$p.Thumbnail; if (-not $ref) { exit 1 };"
    " $st=$ref.OpenReadAsync().GetAwaiter().GetResult();"
    " $size=[uint32]$st.Size;"
    " $buf=New-Object byte[] $size;"
    " $dr=[Windows.Storage.Streams.DataReader,Windows.Storage,ContentType=WindowsRuntime]"
    "::new($st);"
    " $dr.LoadAsync($size).GetAwaiter().GetResult() | Out-Null;"
    " $dr.ReadBytes($buf);"
    " [IO.File]::WriteAllBytes($env:TB_COVER, $buf)"
    "} catch { exit 1 }"
)


def grab_cover(title):
    """换歌了才重新抽，避免每次都跑 PowerShell。"""
    if not title or title == _cover_seen[0]:
        return
    _cover_seen[0] = title
    try:
        env = dict(os.environ)
        env["TB_COVER"] = COVER_FILE
        subprocess.run(["powershell", "-NoProfile", "-Command", COVER_PS],
                       capture_output=True, env=env, timeout=10)
        print("  封面已更新" if os.path.isfile(COVER_FILE) else "  没取到封面")
    except Exception as e:
        print("  封面失败:", e)


def lan_ip():
    try:
        sk = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sk.connect(("8.8.8.8", 80))
        ip = sk.getsockname()[0]
        sk.close()
        return ip
    except Exception:
        return "127.0.0.1"


class CoverHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if os.path.isfile(COVER_FILE):
                data = open(COVER_FILE, "rb").read()
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Content-Length", str(len(data)))
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                self.wfile.write(data)
            else:
                self.send_response(404)
                self.end_headers()
        except Exception:
            pass

    def log_message(self, *a):
        pass


def start_cover_server():
    try:
        srv = ThreadingHTTPServer(("0.0.0.0", COVER_PORT), CoverHandler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        print("  封面服务: http://%s:%d/cover.jpg" % (lan_ip(), COVER_PORT))
    except Exception as e:
        print("  封面服务启动失败:", e)


_last = [time.time() - 99, "", "", False]


def now_playing():
    try:
        r = subprocess.run(
            ["powershell", "-NoProfile", "-Command", MEDIA_PS],
            capture_output=True, text=True, timeout=6).stdout.strip()
        d = json.loads(r) if r.startswith("{") else {}
        return d.get("title", ""), d.get("artist", ""), bool(d.get("playing"))
    except Exception:
        return "", "", False


def snapshot():
    if time.time() - _last[0] > 2:
        t, a, p = now_playing()
        _last[0], _last[1], _last[2], _last[3] = time.time(), t, a, p
    if _last[1]:
        grab_cover(_last[1])
    vm = psutil.virtual_memory()
    n = int(time.time() // 3)          # 每 3 秒换一个版本号，促使手机重取
    return {
        "title": _last[1], "artist": _last[2], "playing": _last[3],
        "cover": "http://%s:%d/cover.jpg?v=%d" % (lan_ip(), COVER_PORT, n)
                 if os.path.isfile(COVER_FILE) else "",
        "cpu": round(psutil.cpu_percent(interval=None), 1),
        "gpu": round(gpu_percent(), 1),
        "ram": round(vm.percent, 1),
        "ramText": "%.1f/%.0fG" % (vm.used / 1e9, vm.total / 1e9),
    }


def on_cmd(_, data: bytearray):
    try:
        run(data.decode("utf-8", "replace"))
    except Exception as e:
        print("  执行出错:", e)


async def push_loop(cli):
    psutil.cpu_percent(None)
    while True:
        if not cli.is_connected:
            return
        try:
            await cli.write_gatt_char(
                STAT, json.dumps(snapshot()).encode("utf-8"), response=False)
        except Exception as e:
            print("  推送失败:", e)
            return
        await asyncio.sleep(1.5)


async def main():
    print("=" * 54)
    print("  TouchBar - Windows")
    print("=" * 54)
    start_cover_server()
    print("  扫描 iPhone…")
    dev = None
    while dev is None:
        for d in await BleakScanner.discover(timeout=4.0):
            if (d.name or "") == NAME:
                dev = d
                break
        if dev is None:
            print("    没找到，继续…")
    print("  找到", dev.name, dev.address)

    while True:
        try:
            async with BleakClient(dev.address) as cli:
                print("  已连接")
                await cli.start_notify(CMD, on_cmd)
                await push_loop(cli)
                print("  断开，重连…")
        except Exception as e:
            print("  连接失败:", e)
            await asyncio.sleep(2)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        sys.exit(0)
