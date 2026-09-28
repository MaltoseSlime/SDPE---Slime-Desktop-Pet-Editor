class_name AutoStart
extends RefCounted
## 開機(登入 Windows)時自動啟動這個程式:寫一個機碼在「目前使用者」層級的開機清單(HKCU\...\Run),不需要系統管理員權限、不用建捷徑檔案。
## 用登錄檔本身當「目前有沒有開」的依據(不是另外存一個布林值在 settings.cfg),這樣使用者自己去登錄編輯器手動刪掉時,設定畫面也會照實顯示成「關閉」。
## 只在匯出後的 exe 有意義:在 Godot 編輯器裡執行時 OS.get_executable_path() 是編輯器本身的路徑,開了這個開關只會讓 Windows 開機時打開 Godot 編輯器。
## 全局設定的勾選框預設是關閉的(見 docs 與 app_settings_tab.gd)。

const REG_KEY := "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
const VALUE_NAME := "SlimeDesktopPetEditor"

## 測試用:非 null 時完全不呼叫系統的 reg.exe,改讀寫這個字典(模擬登錄檔,key = VALUE_NAME,value = 執行檔路徑或不存在)。
## 絕對不能讓自動測試真的去改開發機的登錄檔,所以每個實際會呼叫 reg.exe 的函式都先檢查這個。
static var test_registry: Variant = null


static func supported() -> bool:
	return OS.get_name() == "Windows"


## 目前是不是已經在開機清單裡。查詢失敗(找不到這個值、reg.exe 出問題)一律當作沒開,不拋錯。
static func is_enabled() -> bool:
	if test_registry != null:
		return (test_registry as Dictionary).has(VALUE_NAME)
	if not supported():
		return false
	var output := []
	var code := OS.execute("reg", ["query", REG_KEY, "/v", VALUE_NAME], output, true)
	return code == 0


## 開啟或關閉。回傳空字串 = 成功,否則是失敗原因(給狀態列顯示)。
static func set_enabled(enabled: bool) -> String:
	if test_registry != null:
		if enabled:
			(test_registry as Dictionary)[VALUE_NAME] = OS.get_executable_path()
		else:
			(test_registry as Dictionary).erase(VALUE_NAME)
		return ""
	if not supported():
		return "只支援 Windows"
	if enabled:
		var exe := OS.get_executable_path()
		if exe == "":
			return "找不到執行檔路徑"
		var output := []
		var code := OS.execute("reg", ["add", REG_KEY, "/v", VALUE_NAME, "/t", "REG_SZ", "/d", exe, "/f"], output, true)
		return "" if code == 0 else TranslationServer.translate("寫入登錄檔失敗:%s") % "\n".join(PackedStringArray(output))
	# 關閉:值本來就不存在時 reg delete 會回非 0(找不到機碼或值),當成已經是關閉狀態,不算失敗。
	var delete_output := []
	OS.execute("reg", ["delete", REG_KEY, "/v", VALUE_NAME, "/f"], delete_output, true)
	return ""
