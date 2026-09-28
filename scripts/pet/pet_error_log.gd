class_name PetErrorLog
extends RefCounted
## 錯誤紀錄檔:桌寵的積木失控(死循環、事件被過度頻繁觸發…)被安全機制處理時,把原因寫在這裡讓使用者排查。
## 位置:user://logs/pet_errors.log(Windows:%APPDATA%\Godot\app_userdata\<專案名>\logs\;系統匣「開啟錯誤紀錄資料夾」可直接打開)。
## 超過 MAX_BYTES 就把舊檔改名成 pet_errors.old.log(只留一份舊檔),不會無限長大。永遠不往外拋錯。

const DIR := "user://logs"
const FILE_NAME := "pet_errors.log"
const OLD_FILE_NAME := "pet_errors.old.log"
const MAX_BYTES := 512 * 1024


static func file_path() -> String:
	return "%s/%s" % [DIR, FILE_NAME]


static func folder_global() -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	return ProjectSettings.globalize_path(DIR)


## 寫一行紀錄。source = 哪隻桌寵/哪個模組,message = 發生了什麼、怎麼處理的。
static func write(source: String, message: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := file_path()
	if FileAccess.file_exists(path):
		var size := 0
		var probe := FileAccess.open(path, FileAccess.READ)
		if probe != null:
			size = probe.get_length()
			probe.close()
		if size > MAX_BYTES:
			DirAccess.rename_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path("%s/%s" % [DIR, OLD_FILE_NAME]))
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line("[%s] [%s] %s" % [Time.get_datetime_string_from_system(false, true), source, message.replace("\n", " ")])
	file.close()
