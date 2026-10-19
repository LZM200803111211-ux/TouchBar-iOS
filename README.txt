iPhone 7 当 MacBook 触控条用（Windows 版）
==========================================

【原理】
  iPhone 用蓝牙广播一个服务，Windows 用 bleak 去连它。
  iPhone 上点一下图标 -> 通过蓝牙把指令字符串发过去 -> Windows 执行。

【电脑端】
  1. 装 Python 3.8+
  2. 进 windows\ 目录，双击「启动.bat」
  3. 看到「正在扫描…」就等手机

【手机端】
  1. GitHub push 后 Actions 自动编译，下载 artifact 里的 TouchBar.ipa
  2. 越狱设备：用 TrollStore / AppSync 直接装（未签名）
     或自签：Sideloadly / AltStore
  3. 打开 App，横屏，等左上角变绿「已连接 Windows」
  4. 点图标即可

【界面】
  6 列平铺，不滚动，24 个按键一屏放下。
  按下会变成金色高亮 + 轻震动。

【能不能加键】
  改 TouchBar/Actions.swift 里的 DEFAULT_KEYS，
  再在 windows/touchbar_server.py 的 run() 里加对应处理即可。
