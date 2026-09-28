class_name ClickThrough
extends RefCounted
## 讓一個 Godot 視窗「看得見、但滑鼠完全穿透到後面的程式」(給螢火蟲、之後的家具這類純裝飾用)。
##
## Godot 的 Window.mouse_passthrough 在 Windows 只是回 HTTRANSPARENT,這只會穿給「同一個程式」的視窗,別的程式的視窗照樣被擋住;
## 而主視窗靠穿透多邊形(視窗形狀)決定哪裡點得到,形狀 = 可見範圍,做不到「看得見又點得穿」。
## 所以另外開一個裝飾專用視窗,再用系統呼叫把它的擴充樣式加上 WS_EX_LAYERED | WS_EX_TRANSPARENT(整個視窗滑鼠穿透,連別的程式也是)。
## GDScript 沒有系統呼叫,這裡開一個 PowerShell 一次性行程(Add-Type 編一小段 C#)去做,不用任何額外檔案;成功會在 user:// 寫一個結果檔(內容 OK)。
## 視窗被 hide() 再 show() 會重建原生視窗、樣式就沒了(要重新套用),所以裝飾視窗建立後就一直開著。
## 用法:var job := ClickThrough.start(window)  →  之後每影格 ClickThrough.poll(job):true = 成功、false = 失敗、null = 還在做。

const POWERSHELL := "powershell.exe"
const SCRIPT_TEMPLATE := """
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class CT {
  [DllImport("user32.dll", EntryPoint="GetWindowLongPtrW")] public static extern IntPtr GetLong(IntPtr h, int i);
  [DllImport("user32.dll", EntryPoint="SetWindowLongPtrW")] public static extern IntPtr SetLong(IntPtr h, int i, IntPtr v);
  [DllImport("user32.dll")] public static extern bool SetLayeredWindowAttributes(IntPtr h, uint key, byte alpha, uint flags);
  public static void Apply(long handle) {
    IntPtr h = new IntPtr(handle);
    long ex = GetLong(h, -20).ToInt64();
    SetLong(h, -20, new IntPtr(ex | 0x80000L | 0x20L));
    %s
  }
}
'@
[CT]::Apply(%d)
Set-Content -Path '%s' -Value 'OK'
"""
## SetLayeredWindowAttributes 的變體(測試用,見 start 的 layered_alpha):空字串 = 不呼叫。
const LAYERED_CALL := "SetLayeredWindowAttributes(h, 0, 255, 2);"


## 開始套用;回傳 {pid, result}(給 poll);不是 Windows、沒有原生視窗代碼、開不了行程時回空字典。call_layered 是測試用(是否再呼叫 SetLayeredWindowAttributes)。
static func start(window: Window, call_layered := true) -> Dictionary:
	if OS.get_name() != "Windows" or DisplayServer.get_name() == "headless":
		return {}
	var handle := DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
	if handle == 0:
		return {}
	var result_path := ProjectSettings.globalize_path("user://click_through_%d.txt" % handle)
	if FileAccess.file_exists(result_path):
		DirAccess.remove_absolute(result_path)
	var script := SCRIPT_TEMPLATE % [LAYERED_CALL if call_layered else "", handle, result_path]
	var encoded := Marshalls.raw_to_base64(script.to_utf16_buffer())
	var pid := OS.create_process(POWERSHELL, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encoded], false)
	if pid <= 0:
		return {}
	return {"pid": pid, "result": result_path}


## 檢查一次:null = 還沒結束、true = 成功、false = 失敗(行程結束了但沒有結果檔)。
static func poll(job: Dictionary) -> Variant:
	if job.is_empty():
		return false
	var result_path: String = job["result"]
	if FileAccess.file_exists(result_path):
		var ok := FileAccess.get_file_as_string(result_path).contains("OK")
		DirAccess.remove_absolute(result_path)
		return ok
	if not OS.is_process_running(int(job["pid"])):
		return false
	return null
