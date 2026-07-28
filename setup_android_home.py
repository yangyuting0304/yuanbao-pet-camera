"""设置 ANDROID_HOME 环境变量（用户级，永久生效）。

运行：python setup_android_home.py
运行后请【关闭所有终端】，重新打开 Android Studio，向导会自动把 SDK 装到 F:\\tool\\AndroidSDK。
"""
import winreg

ANDROID_HOME = r"F:\tool\AndroidSDK"


def main():
    key = winreg.OpenKey(
        winreg.HKEY_CURRENT_USER, r"Environment", 0,
        winreg.KEY_READ | winreg.KEY_WRITE,
    )
    try:
        current, _ = winreg.QueryValueEx(key, "ANDROID_HOME")
    except FileNotFoundError:
        current = ""

    if current.lower() == ANDROID_HOME.lower():
        print(f"[跳过] ANDROID_HOME 已是: {ANDROID_HOME}")
    else:
        winreg.SetValueEx(key, "ANDROID_HOME", 0, winreg.REG_SZ, ANDROID_HOME)
        print(f"[已设置] ANDROID_HOME = {ANDROID_HOME}")
        print("请关闭 Android Studio 及所有终端，重新打开 Android Studio 使变量生效。")
    winreg.CloseKey(key)


if __name__ == "__main__":
    main()
