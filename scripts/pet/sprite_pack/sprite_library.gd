class_name SpriteLibrary
extends RefCounted
## 專案統一存放精靈(sprite)素材包的資料夾:user://sprites/<角色名>/(Windows:%APPDATA%\Godot\app_userdata\<專案名>\sprites\)。
## 精靈圖編輯器的「新建資料夾…」與「從資料夾匯入…」都把素材包放在這裡,之後的角色庫也從這裡列出角色。
## 命名:使用者替資料夾取的名字**同時是資料夾名、角色顯示名稱(pack.json 的 name)與預設辨識代號(pack.json 沒寫 tag 時用資料夾名)**——
## 一個名字管三件事,使用者不用重複輸入;之後想分開(例如辨識代號改成英文)直接改 pack.json 的 tag / name。

const ROOT := "user://sprites"
## 匯入資料夾的大小上限(檔案數、總位元組),避免不小心把整個磁碟複製進來。
const MAX_COPY_FILES := 3000
const MAX_COPY_BYTES := 500_000_000
const MAX_NAME := 40
## 角色庫的預設角色(使用者指定:活動桌寵用 Mal、靜止桌寵用 Still)。第一次(設定檔 [library] 沒有對應的旗標)從專案素材複製進來一次;之後使用者刪掉也不會再自己長回來。
## source 資料夾是「完整的素材包」(圖檔、pack.json、選用的 character/profile.json 角色設定),整份照原樣複製(不含 state.json、.bak);靜止桌寵的資料夾裡還沒有圖時不會裝(等有圖再裝)。
const DEFAULT_CHARACTER := "Mal"
const DEFAULT_CHARACTER_SOURCE := "res://assets/sample_pets/Mal/"
const DEFAULT_CHARACTERS: Array[Dictionary] = [
	{"name": "Mal", "source": "res://assets/default_characters/active/Mal/", "flag": "default_installed"},
	{"name": "Still", "source": "res://assets/default_characters/still/Still/", "flag": "default_installed_still"},
]
## 角色種類:active = 活動桌寵(會走動,適合有 spritesheet 的角色)、still = 靜止桌寵(固定貼在行動區底部、會呼吸,適合固定立繪)。存在 pack.json 的 "kind"。
const KINDS: Array[String] = ["active", "still"]


## 第一次(旗標還沒設)把預設的活動桌寵 Mal 裝進 sprite 資料夾。專案素材裡有完整的預設素材包(assets/default_characters/active/Mal,連軸心與角色設定)就整份複製;
## 沒有就退回舊做法:只複製 assets/sample_pets/Mal 朝右的 _r_ 幀(引擎慣例朝右,左右由程式翻)並寫最小的 pack.json。
## 已經有同名資料夾就不動(視為使用者自己的),一樣記下「裝過了」。回傳新裝的資料夾路徑;沒裝(裝過了、已有同名、複製失敗)回空字串。
static func ensure_default_character() -> String:
	var config := ConfigFile.new()
	config.load(AppSettings.SETTINGS_PATH)
	var entry := DEFAULT_CHARACTERS[0]
	if bool(config.get_value("library", str(entry["flag"]), false)):
		return ""
	var installed := _install_default(entry, config)
	if installed != "" or DirAccess.dir_exists_absolute(root_dir().path_join(DEFAULT_CHARACTER)):
		return installed
	return _install_legacy_mal(config)


## 兩個預設角色(Mal、Still)都檢查一次,回傳這次新裝的資料夾路徑。
static func ensure_default_characters() -> Array[String]:
	var installed: Array[String] = []
	var mal := ensure_default_character()
	if mal != "":
		installed.append(mal)
	var config := ConfigFile.new()
	config.load(AppSettings.SETTINGS_PATH)
	var entry := DEFAULT_CHARACTERS[1]
	if not bool(config.get_value("library", str(entry["flag"]), false)):
		var path := _install_default(entry, config)
		if path != "":
			installed.append(path)
	return installed


## 把預設素材包 entry.source 整份複製成 sprite 資料夾裡的 entry.name。來源沒有圖(還沒放)回空字串、不記旗標;已有同名資料夾記旗標不動它。
static func _install_default(entry: Dictionary, config: ConfigFile) -> String:
	var source := str(entry["source"])
	var target := root_dir().path_join(str(entry["name"]))
	if DirAccess.dir_exists_absolute(target):
		_mark_default_installed(config, str(entry["flag"]))
		return ""
	var files := _default_source_files(source, "")
	var has_image := false
	for relative: String in files:
		if relative.get_extension().to_lower() == "png":
			has_image = true
	if not has_image:
		return ""
	DirAccess.make_dir_recursive_absolute(target)
	for relative: String in files:
		var to := target.path_join(relative)
		DirAccess.make_dir_recursive_absolute(to.get_base_dir())
		var ok := false
		if relative.get_extension().to_lower() == "png":
			var texture := load(source + relative) as Texture2D
			ok = texture != null and texture.get_image().save_png(to) == OK
		else:
			var file := FileAccess.open(source + relative, FileAccess.READ)
			var out := FileAccess.open(to, FileAccess.WRITE) if file != null else null
			if out != null:
				out.store_buffer(file.get_buffer(file.get_length()))
				out.close()
				ok = true
		if not ok:
			_remove_folder(target)
			return ""
	_mark_default_installed(config, str(entry["flag"]))
	return target


## 預設素材包資料夾裡所有要複製的檔案(相對路徑,遞迴;略過 .import / .remap 附檔、state.json、.bak、說明用的 .txt)。
static func _default_source_files(source: String, sub: String) -> Array[String]:
	var found: Array[String] = []
	var here := source + sub
	for file_name in DirAccess.get_files_at(here):
		var clean := file_name.trim_suffix(".import").trim_suffix(".remap")
		if clean.ends_with(".bak") or clean == "state.json" or clean.get_extension().to_lower() == "txt":
			continue
		var relative := sub + clean
		if not found.has(relative):
			found.append(relative)
	for dir_name in DirAccess.get_directories_at(here):
		found.append_array(_default_source_files(source, sub + dir_name + "/"))
	return found


static func _install_legacy_mal(config: ConfigFile) -> String:
	var target := root_dir().path_join(DEFAULT_CHARACTER)
	var names := {}
	for file_name in DirAccess.get_files_at(DEFAULT_CHARACTER_SOURCE):
		var clean := file_name.trim_suffix(".import").trim_suffix(".remap")
		if clean.ends_with(".png") and "_r_" in clean:
			names[clean] = true
	if names.is_empty():
		return ""
	DirAccess.make_dir_recursive_absolute(target)
	for clean: String in names:
		var texture := load(DEFAULT_CHARACTER_SOURCE + clean) as Texture2D
		if texture == null or texture.get_image().save_png(target.path_join(clean)) != OK:
			_remove_folder(target)
			return ""
	var manifest := FileAccess.open(target.path_join("pack.json"), FileAccess.WRITE)
	if manifest == null:
		_remove_folder(target)
		return ""
	manifest.store_string(JSON.stringify({"name": DEFAULT_CHARACTER, "tag": "mal", "fps": 6}, "  ") + "\n")
	manifest.close()
	_mark_default_installed(config, "default_installed")
	return target


static func _mark_default_installed(config: ConfigFile, flag := "default_installed") -> void:
	config.set_value("library", flag, true)
	config.save(AppSettings.SETTINGS_PATH)

## 遞迴刪掉一個資料夾(只在裝預設角色失敗時清半成品用)。
static func _remove_folder(path: String) -> void:
	# 防呆(2026-09-21 事故:空字串被當成專案根目錄,整個專案被遞迴刪光):只允許刪 user:// 底下的資料夾,空路徑、相對路徑、專案資料夾一律拒絕。
	var clean := path.replace("\\", "/").trim_suffix("/")
	var user_root := ProjectSettings.globalize_path("user://").replace("\\", "/").trim_suffix("/")
	if clean == "" or not (clean.begins_with("user://") or clean.begins_with(user_root + "/")):
		push_warning("_remove_folder 拒絕刪除:%s" % path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for dir_name in DirAccess.get_directories_at(path):
		_remove_folder(path.path_join(dir_name))
	DirAccess.remove_absolute(path)


## sprite 根資料夾的完整路徑(用 / 分隔);不存在就建立。
static func root_dir() -> String:
	DirAccess.make_dir_recursive_absolute(ROOT)
	return ProjectSettings.globalize_path(ROOT).replace("\\", "/").trim_suffix("/")


## 使用者輸入的名字 → 資料夾名:去掉不能出現在檔名的字元、頭尾的空白與點、限制長度。清完是空的代表名字無效。
static func folder_name_for(display_name: String) -> String:
	var cleaned := display_name.strip_edges().validate_filename().strip_edges().trim_prefix(".").trim_suffix(".").strip_edges().left(MAX_NAME)
	return cleaned.strip_edges()


## 名字有沒有問題(空的、清完變空、Windows 保留字);沒問題回空字串,有問題回原因。
static func name_problem(display_name: String) -> String:
	if display_name.strip_edges() == "":
		return "名字不能是空的"
	var folder := folder_name_for(display_name)
	if folder == "" or folder.replace("_", "").replace(".", "").replace(" ", "") == "":
		return "名字裡沒有可以當資料夾名的字(不能只有符號或底線)"
	if folder.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3"]:
		return TranslationServer.translate("「%s」是系統保留的名字,請換一個") % folder
	return ""


## 資料夾名已經有人用就加序號(名字、名字_2、名字_3…)。回傳完整路徑(還不存在)。
static func unique_folder(folder: String) -> String:
	var base := root_dir().path_join(folder)
	var candidate := base
	var counter := 2
	while DirAccess.dir_exists_absolute(candidate):
		candidate = "%s_%d" % [base, counter]
		counter += 1
	return candidate


## 這個路徑在不在 sprite 根資料夾底下(已經在裡面的資料夾不需要再複製)。
static func is_inside(path: String) -> bool:
	var normalized := path.replace("\\", "/").trim_suffix("/")
	return normalized.begins_with(root_dir() + "/")


## 新建一個空的素材包資料夾(只有 pack.json:{"name": 名字, "kind": 角色種類 active / still})。回傳 {ok, folder, error}。
static func create_pack(display_name: String, kind := "active") -> Dictionary:
	var problem := name_problem(display_name)
	if problem != "":
		return {"ok": false, "folder": "", "error": problem}
	var folder := unique_folder(folder_name_for(display_name))
	if DirAccess.make_dir_recursive_absolute(folder) != OK:
		return {"ok": false, "folder": "", "error": TranslationServer.translate("無法建立資料夾:%s") % folder}
	var file := FileAccess.open(folder.path_join("pack.json"), FileAccess.WRITE)
	if file == null:
		return {"ok": false, "folder": folder, "error": "無法寫入 pack.json"}
	file.store_string(JSON.stringify({"name": display_name.strip_edges().left(MAX_NAME), "kind": kind if KINDS.has(kind) else "active"}, "  ") + "\n")
	file.close()
	return {"ok": true, "folder": folder, "error": ""}


## 把外面的素材包資料夾複製一份進 sprite 根資料夾(原資料夾不動)。display_name 是使用者取的名字(空白 = 沿用原資料夾名)。
## 已經在根資料夾裡的直接回傳原路徑、不複製。回傳 {ok, folder, error, copied}。
static func import_folder(source: String, display_name := "") -> Dictionary:
	var from := source.strip_edges().replace("\\", "/").trim_suffix("/")
	if from == "" or not DirAccess.dir_exists_absolute(from):
		return {"ok": false, "folder": "", "error": TranslationServer.translate("找不到資料夾:%s") % source, "copied": false}
	if is_inside(from):
		return {"ok": true, "folder": from, "error": "", "copied": false}
	var root := root_dir()
	if root == from or root.begins_with(from + "/"):
		return {"ok": false, "folder": "", "error": "不能匯入包含 sprite 資料夾本身的資料夾", "copied": false}
	var wanted := display_name if display_name.strip_edges() != "" else from.get_file()
	var problem := name_problem(wanted)
	if problem != "":
		return {"ok": false, "folder": "", "error": problem, "copied": false}
	var stats := {"files": 0, "bytes": 0}
	var scan_error := _scan(from, stats)
	if scan_error != "":
		return {"ok": false, "folder": "", "error": scan_error, "copied": false}
	var target := unique_folder(folder_name_for(wanted))
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return {"ok": false, "folder": "", "error": TranslationServer.translate("無法建立資料夾:%s") % target, "copied": false}
	var error := copy_tree(from, target)
	if error != "":
		return {"ok": false, "folder": target, "error": error, "copied": true}
	return {"ok": true, "folder": target, "error": "", "copied": true}


## 遞迴複製資料夾(略過 .bak 備份檔)。成功回空字串。
static func copy_tree(from: String, to: String) -> String:
	var dir := DirAccess.open(from)
	if dir == null:
		return TranslationServer.translate("讀不了資料夾:%s") % from
	for file_name in dir.get_files():
		if file_name.ends_with(".bak"):
			continue
		if DirAccess.copy_absolute(from.path_join(file_name), to.path_join(file_name)) != OK:
			return TranslationServer.translate("複製失敗:%s") % file_name
	for sub in dir.get_directories():
		if DirAccess.make_dir_recursive_absolute(to.path_join(sub)) != OK:
			return TranslationServer.translate("無法建立資料夾:%s") % sub
		var error := copy_tree(from.path_join(sub), to.path_join(sub))
		if error != "":
			return error
	return ""


static func _scan(folder: String, stats: Dictionary) -> String:
	var dir := DirAccess.open(folder)
	if dir == null:
		return TranslationServer.translate("讀不了資料夾:%s") % folder
	for file_name in dir.get_files():
		stats["files"] += 1
		stats["bytes"] += FileAccess.get_size(folder.path_join(file_name)) if FileAccess.file_exists(folder.path_join(file_name)) else 0
		if stats["files"] > MAX_COPY_FILES:
			return TranslationServer.translate("這個資料夾的檔案太多了(超過 %d 個),看起來不是素材包") % MAX_COPY_FILES
		if stats["bytes"] > MAX_COPY_BYTES:
			return TranslationServer.translate("這個資料夾太大了(超過 %d MB),看起來不是素材包") % (MAX_COPY_BYTES / 1_000_000)
	for sub in dir.get_directories():
		var error := _scan(folder.path_join(sub), stats)
		if error != "":
			return error
	return ""


# --- 角色管理:改名、複製、刪除(搬到備份資料夾) ---

const BACKUP_ROOT := "user://backup"


static func backup_root_dir() -> String:
	DirAccess.make_dir_recursive_absolute(BACKUP_ROOT)
	return ProjectSettings.globalize_path(BACKUP_ROOT).replace("\\", "/").trim_suffix("/")


static func _read_manifest(folder: String) -> Dictionary:
	var path := folder.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write_manifest(folder: String, manifest: Dictionary) -> bool:
	var file := FileAccess.open(folder.path_join("pack.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(manifest, "  ") + "\n")
	file.close()
	return true


## 這個素材包的辨識代號:pack.json 寫的 tag,沒寫就是資料夾名(角色設定檔就是用它當檔名)。
static func tag_of(folder: String) -> String:
	var tag := str(_read_manifest(folder).get("tag", "")).strip_edges()
	return tag if tag != "" else folder.replace("\\", "/").trim_suffix("/").get_file()


## tag_of() 的反查:給辨識代號,找目前這個代號對應的角色顯示名稱(找不到回傳空字串)。掃過所有角色庫資料夾,
## 給「匯出積木檔時自動把互動分頁引用到的角色寫進 knownCharacters」這類需要「代號 → 目前顯示名稱」的地方用。
static func display_name_of_tag(tag: String) -> String:
	if tag == "":
		return ""
	for folder in list_packs():
		if tag_of(folder) == tag:
			return str(_read_manifest(folder).get("name", folder.get_file()))
	return ""


## 這個角色在素材包之外的設定檔(角色設定、狀態、導入的積木檔),存在的才列。
static func related_files(folder: String) -> Array[String]:
	var tag := tag_of(folder).validate_filename()
	var found: Array[String] = []
	for path: String in ["user://profiles/%s.json" % tag, "user://profiles/%s_state.json" % tag, "user://logic/%s.logic.json" % tag]:
		if FileAccess.file_exists(path):
			found.append(path)
	return found


## 重新命名:資料夾改名、pack.json 的 name 改成新名字。**辨識代號不變**(pack.json 沒寫 tag 時先把舊資料夾名寫成 tag),
## 這樣角色設定檔、積木檔、桌面名單都還認得它。新名字和別的資料夾撞名會拒絕。回傳 {ok, folder, error}。
static func rename_pack(folder: String, new_name: String) -> Dictionary:
	var problem := name_problem(new_name)
	if problem != "":
		return {"ok": false, "folder": folder, "error": problem}
	var source := folder.replace("\\", "/").trim_suffix("/")
	if not is_inside(source) or not DirAccess.dir_exists_absolute(source):
		return {"ok": false, "folder": folder, "error": "找不到角色資料夾"}
	var wanted := folder_name_for(new_name)
	var target := root_dir().path_join(wanted)
	if target != source and DirAccess.dir_exists_absolute(target):
		return {"ok": false, "folder": folder, "error": TranslationServer.translate("已經有叫「%s」的角色了") % wanted}
	var manifest := _read_manifest(source)
	if str(manifest.get("tag", "")).strip_edges() == "":
		manifest["tag"] = source.get_file()
	manifest["name"] = new_name.strip_edges().left(MAX_NAME)
	if not _write_manifest(source, manifest):
		return {"ok": false, "folder": folder, "error": "無法寫入 pack.json"}
	if target != source and DirAccess.rename_absolute(source, target) != OK:
		return {"ok": false, "folder": folder, "error": "無法把資料夾改名(是不是有程式正開著它?)"}
	return {"ok": true, "folder": target, "error": ""}


## 複製成新角色:整個素材包資料夾複製一份(不含 .bak),新角色有自己的辨識代號(= 新資料夾名),不帶原角色的設定檔與記憶。
static func copy_pack(folder: String, new_name: String) -> Dictionary:
	var problem := name_problem(new_name)
	if problem != "":
		return {"ok": false, "folder": "", "error": problem}
	var source := folder.replace("\\", "/").trim_suffix("/")
	if not DirAccess.dir_exists_absolute(source):
		return {"ok": false, "folder": "", "error": "找不到角色資料夾"}
	var target := unique_folder(folder_name_for(new_name))
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return {"ok": false, "folder": "", "error": TranslationServer.translate("無法建立資料夾:%s") % target}
	var error := copy_tree(source, target)
	if error != "":
		_remove_folder(target)
		return {"ok": false, "folder": "", "error": error}
	# 新角色不帶原角色的設定、狀態與積木檔(character/)。
	_remove_folder(target.path_join(CharacterFiles.SUBDIR))
	var manifest := _read_manifest(target)
	manifest["name"] = new_name.strip_edges().left(MAX_NAME)
	manifest["tag"] = target.get_file()
	_write_manifest(target, manifest)
	return {"ok": true, "folder": target, "error": ""}


## 刪除角色 = 搬到備份資料夾 user://backup/<名字>_<時間>/pack/(整個素材包),並把角色設定檔、狀態、積木檔複製到同一個備份的 character/ 裡
## (原本的設定檔留在原地,以後同辨識代號的角色回來還接得上)。不會真的刪掉任何東西。回傳 {ok, backup, copied(複製了幾個設定檔), error}。
static func delete_pack(folder: String) -> Dictionary:
	var source := folder.replace("\\", "/").trim_suffix("/")
	if not is_inside(source) or not DirAccess.dir_exists_absolute(source):
		return {"ok": false, "backup": "", "copied": 0, "error": "找不到角色資料夾"}
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var backup := backup_root_dir().path_join("%s_%s" % [source.get_file(), stamp])
	var counter := 2
	while DirAccess.dir_exists_absolute(backup):
		backup = backup_root_dir().path_join("%s_%s_%d" % [source.get_file(), stamp, counter])
		counter += 1
	DirAccess.make_dir_recursive_absolute(backup.path_join("character"))
	var copied := 0
	for path in related_files(source):
		if DirAccess.copy_absolute(path, backup.path_join("character").path_join(path.get_file())) == OK:
			copied += 1
	if DirAccess.rename_absolute(source, backup.path_join("pack")) != OK:
		return {"ok": false, "backup": backup, "copied": copied, "error": "無法把資料夾搬到備份(是不是有程式正開著它?)"}
	return {"ok": true, "backup": backup, "copied": copied, "error": ""}


## sprite 根資料夾裡的所有素材包資料夾(完整路徑,依名字排序)。
static func list_packs() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root_dir())
	if dir == null:
		return result
	var names: Array[String] = []
	for sub in dir.get_directories():
		names.append(sub)
	names.sort()
	for sub in names:
		result.append(root_dir().path_join(sub))
	return result
