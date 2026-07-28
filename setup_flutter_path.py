"""把 Flutter 的 bin 目录加入当前用户的 PATH（持久化到注册表）。

运行方式（任选其一）：
  1) 双击本文件（若系统已关联 .py）
  2) 终端里执行：python setup_flutter_path.py
  3) 或者在 Python REPL 里：exec(open("setup_flutter_path.py").read())

运行后请【关闭所有终端窗口】，重新打开一个，再执行：
  flutter --version
看到 Flutter 3.44.7 即配置成功。
"""
import winreg

FLUTTER_BIN = r"F:\tool\flutter_windows_3.44.7-stable\flutter\bin"


def main():
    key = winreg.OpenKey(
        winreg.HKEY_CURRENT_USER, r"Environment", 0,
        winreg.KEY_READ | winreg.KEY_WRITE,
    )
    try:
        current, _ = winreg.QueryValueEx(key, "Path")
    except FileNotFoundError:
        current = ""

    if FLUTTER_BIN.lower() in current.lower():
        print(f"[跳过] 已在 PATH 中: {FLUTTER_BIN}")
    else:
        new_path = current.rstrip(";") + ";" + FLUTTER_BIN if current else FLUTTER_BIN
        winreg.SetValueEx(key, "Path", 0, winreg.REG_EXPAND_SZ, new_path)
        print(f"[已添加] {FLUTTER_BIN}")
        print("请关闭所有终端窗口，重新打开一个再验证 flutter --version。")
    winreg.CloseKey(key)


if __name__ == "__main__":
    main()
