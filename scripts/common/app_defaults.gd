class_name AppDefaults
extends RefCounted
## 隨遊戲發行的「預設值」:開發者自己調好的全局設定(assets/defaults/settings.cfg)與全域數值(assets/defaults/_global.json)。
## 規則(只補、不覆蓋):使用者的 settings.cfg 裡**沒有**的項目才從預設檔補上;使用者已經有的值一律不動。全域數值檔使用者沒有才複製。
## 什麼時候補:第一次啟動,以及之後每次版本號(專案設定的版本)變了——這樣新版本新增的設定項目,老使用者也拿得到開發者調好的預設值。
## 紀錄存在 settings.cfg 的 [app]:last_version(上次啟動時的版本號)。預設檔用 tools/snapshot_defaults.gd 從開發者目前的設定產生。

const SETTINGS_SOURCE := "res://assets/defaults/settings.cfg"
const GLOBAL_SOURCE := "res://assets/defaults/_global.json"
const GLOBAL_TARGET := "user://profiles/_global.json"


## 開機呼叫一次。回傳 {first_run, previous, current, added}:previous 是上次的版本號(第一次 = 空字串),added 是這次補進去的設定項目數。
static func apply() -> Dictionary:
	var current := CreditsData.version()
	var config := ConfigFile.new()
	var existed := config.load(AppSettings.SETTINGS_PATH) == OK
	var previous := str(config.get_value("app", "last_version", ""))
	var result := {"first_run": previous == "" and not existed, "previous": previous, "current": current, "added": 0}
	if previous == current:
		return result
	var defaults := ConfigFile.new()
	if defaults.load(SETTINGS_SOURCE) == OK:
		for section in defaults.get_sections():
			for key in defaults.get_section_keys(section):
				if not config.has_section_key(section, key):
					config.set_value(section, key, defaults.get_value(section, key))
					result["added"] += 1
	config.set_value("app", "last_version", current)
	config.save(AppSettings.SETTINGS_PATH)
	if FileAccess.file_exists(GLOBAL_SOURCE) and not FileAccess.file_exists(GLOBAL_TARGET):
		DirAccess.make_dir_recursive_absolute(GLOBAL_TARGET.get_base_dir())
		var text := FileAccess.get_file_as_string(GLOBAL_SOURCE)
		var out := FileAccess.open(GLOBAL_TARGET, FileAccess.WRITE)
		if out != null:
			out.store_string(text)
			out.close()
	return result
