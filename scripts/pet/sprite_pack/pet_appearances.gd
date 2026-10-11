class_name PetAppearances
extends RefCounted
## 外觀(整套行走圖的差分,2026-10-11 使用者回饋:想替桌寵畫一整套萬聖節外觀,不頂掉原本的圖、也不用克隆另一隻):
## 每套外觀是角色資料夾底下的一份獨立素材包 <角色資料夾>/appearances/<外觀資料夾>/(自己的圖、pack.json、overlays.json),
## 桌寵同時只載入一套,所以像素上限(SpritePackLoader.MAX_TOTAL_PIXELS)各算各的,不會吃掉原本那套的額度。
## 判定框、光源、配件、持有錨點、縮放都是各套自己的設定;外觀沒有的動作退回那套外觀自己的 idle,所以一套外觀至少要有 idle。
## 外觀的辨識代號 = 外觀資料夾名(建立後不變,存檔記的是它);顯示名稱 = 那份 pack.json 的 name,積木兩種寫法都認。
## 舊版本看不懂 appearances/:掃描素材包時這個資料夾裡沒有直接放圖、也沒有數字子資料夾,會被略過;.pet 匯出匯入照一般素材包檔案帶著走。

const SUBDIR := "appearances"
const MAX_APPEARANCES := 32
## 積木/選單裡代表「預設外觀」(角色資料夾本身那套圖)的寫法。
const DEFAULT_WORDS: Array[String] = ["", "預設", "預設外觀", "default"]


static func _normalize(folder: String) -> String:
	return folder.replace("\\", "/").trim_suffix("/")


static func root_of(pack_folder: String) -> String:
	return _normalize(pack_folder).path_join(SUBDIR)


static func folder_of(pack_folder: String, id: String) -> String:
	return root_of(pack_folder).path_join(id)


## 這個資料夾是不是某個角色的外觀資料夾;是的話回 {pack(角色資料夾), id},不是回空字典。
static func owner_of(folder: String) -> Dictionary:
	var normalized := _normalize(folder)
	var parent := normalized.get_base_dir()
	if parent.get_file() != SUBDIR or normalized.get_file() == "":
		return {}
	return {"pack": parent.get_base_dir(), "id": normalized.get_file()}


## 這個角色的所有外觀(依資料夾名排序):[{id, name, folder}]。
static func list(pack_folder: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var root := root_of(pack_folder)
	if pack_folder == "" or not DirAccess.dir_exists_absolute(root):
		return result
	var ids: Array[String] = []
	for sub in DirAccess.get_directories_at(root):
		ids.append(sub)
	ids.sort()
	for id in ids:
		if result.size() >= MAX_APPEARANCES:
			break
		var folder := root.path_join(id)
		var display := str(SpriteLibrary._read_manifest(folder).get("name", "")).strip_edges()
		result.append({"id": id, "name": display if display != "" else id, "folder": folder})
	return result


## 積木/選單寫的外觀名稱 → 外觀代號。"" = 預設外觀;找不到回 null。先比代號,再比顯示名稱(不分大小寫)。
static func resolve(pack_folder: String, wanted: String) -> Variant:
	var key := wanted.strip_edges().to_lower()
	if DEFAULT_WORDS.has(key):
		return ""
	var entries := list(pack_folder)
	for entry in entries:
		if str(entry["id"]).to_lower() == key:
			return str(entry["id"])
	for entry in entries:
		if str(entry["name"]).to_lower() == key:
			return str(entry["id"])
	return null


static func name_of(pack_folder: String, id: String) -> String:
	if id == "":
		return "預設外觀"
	for entry in list(pack_folder):
		if entry["id"] == id:
			return str(entry["name"])
	return id


## 名字有沒有問題(空的、不能當資料夾名、跟「預設」撞名、已經有同名外觀);沒問題回空字串。except_id = 改名時自己那一套。
static func name_problem(pack_folder: String, display_name: String, except_id := "") -> String:
	var problem := SpriteLibrary.name_problem(display_name)
	if problem != "":
		return problem
	var key := display_name.strip_edges().to_lower()
	if DEFAULT_WORDS.has(key):
		return "這個名字保留給預設外觀,請換一個"
	for entry in list(pack_folder):
		if entry["id"] != except_id and (str(entry["name"]).to_lower() == key or str(entry["id"]).to_lower() == key):
			return TranslationServer.translate("已經有叫「%s」的外觀了") % display_name.strip_edges()
	return ""


## 新增一套外觀。copy_default = true:把預設外觀整套複製過來當底(圖、動作設定、判定框、光源、配件),再去換圖;
## false:空白的,自己匯入圖(至少要有 idle 才能切換過去)。回傳 {ok, id, folder, error}。
static func create(pack_folder: String, display_name: String, copy_default := true) -> Dictionary:
	var source := _normalize(pack_folder)
	if not SpriteLibrary.is_inside(source) or not DirAccess.dir_exists_absolute(source):
		return {"ok": false, "id": "", "folder": "", "error": "找不到角色資料夾"}
	var problem := name_problem(source, display_name)
	if problem != "":
		return {"ok": false, "id": "", "folder": "", "error": problem}
	if list(source).size() >= MAX_APPEARANCES:
		return {"ok": false, "id": "", "folder": "", "error": TranslationServer.translate("一個角色最多 %d 套外觀") % MAX_APPEARANCES}
	var id := SpriteLibrary.folder_name_for(display_name)
	# 純數字的資料夾名會被素材包掃描當成「表情階段」資料夾(見 SpritePackLoader._scan),加個前綴避開。
	if id.is_valid_int():
		id = "a_" + id
	var base_id := id
	var counter := 2
	while DirAccess.dir_exists_absolute(folder_of(source, id)):
		id = "%s_%d" % [base_id, counter]
		counter += 1
	var target := folder_of(source, id)
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return {"ok": false, "id": "", "folder": "", "error": TranslationServer.translate("無法建立資料夾:%s") % target}
	var base_manifest := SpriteLibrary._read_manifest(source)
	var manifest := {}
	if copy_default:
		var error := _copy_default(source, target)
		if error != "":
			SpriteLibrary._remove_folder(target)
			return {"ok": false, "id": "", "folder": "", "error": error}
		manifest = SpriteLibrary._read_manifest(target)
	manifest["name"] = display_name.strip_edges().left(SpriteLibrary.MAX_NAME)
	manifest["kind"] = str(base_manifest.get("kind", "active"))
	manifest.erase("tag")   # 外觀沒有自己的辨識代號,跟著角色走
	if not SpriteLibrary._write_manifest(target, manifest):
		SpriteLibrary._remove_folder(target)
		return {"ok": false, "id": "", "folder": "", "error": "無法寫入 pack.json"}
	return {"ok": true, "id": id, "folder": target, "error": ""}


## 把預設外觀(角色資料夾本身)複製進外觀資料夾:不含角色設定(character/)、其他外觀(appearances/)與 .bak。
static func _copy_default(source: String, target: String) -> String:
	var dir := DirAccess.open(source)
	if dir == null:
		return TranslationServer.translate("讀不了資料夾:%s") % source
	for file_name in dir.get_files():
		if file_name.ends_with(".bak"):
			continue
		if DirAccess.copy_absolute(source.path_join(file_name), target.path_join(file_name)) != OK:
			return TranslationServer.translate("複製失敗:%s") % file_name
	for sub in dir.get_directories():
		if sub == SUBDIR or sub == CharacterFiles.SUBDIR:
			continue
		if DirAccess.make_dir_recursive_absolute(target.path_join(sub)) != OK:
			return TranslationServer.translate("無法建立資料夾:%s") % sub
		var error := SpriteLibrary.copy_tree(source.path_join(sub), target.path_join(sub))
		if error != "":
			return error
	return ""


## 改顯示名稱(資料夾名 = 代號不變,已存的「目前外觀」還接得上;積木寫建立時的名字 = 代號,也還認得)。回傳錯誤文字,空字串 = 成功。
static func rename(pack_folder: String, id: String, new_name: String) -> String:
	var folder := folder_of(pack_folder, id)
	if id == "" or not DirAccess.dir_exists_absolute(folder):
		return "找不到這套外觀"
	var problem := name_problem(pack_folder, new_name, id)
	if problem != "":
		return problem
	var manifest := SpriteLibrary._read_manifest(folder)
	manifest["name"] = new_name.strip_edges().left(SpriteLibrary.MAX_NAME)
	return "" if SpriteLibrary._write_manifest(folder, manifest) else "無法寫入 pack.json"


## 刪除 = 搬到備份資料夾 user://backup/<角色>_外觀_<代號>_<時間>/(不會真的刪掉)。回傳 {ok, backup, error}。
static func delete(pack_folder: String, id: String) -> Dictionary:
	var folder := folder_of(pack_folder, id)
	if id == "" or not SpriteLibrary.is_inside(folder) or not DirAccess.dir_exists_absolute(folder):
		return {"ok": false, "backup": "", "error": "找不到這套外觀"}
	var stamp := Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_")
	var base := SpriteLibrary.backup_root_dir().path_join("%s_appearance_%s_%s" % [_normalize(pack_folder).get_file(), id, stamp])
	var backup := base
	var counter := 2
	while DirAccess.dir_exists_absolute(backup):
		backup = "%s_%d" % [base, counter]
		counter += 1
	if DirAccess.rename_absolute(folder, backup) != OK:
		return {"ok": false, "backup": "", "error": "無法把資料夾搬到備份(是不是有程式正開著它?)"}
	return {"ok": true, "backup": backup, "error": ""}


## 預設外觀素材包的「版本戳記」(pack.json 的修改時間;精靈圖編輯器每次存檔都會重寫它)。
static func base_stamp(pack_folder: String) -> int:
	var path := _normalize(pack_folder).path_join("pack.json")
	return int(FileAccess.get_modified_time(path)) if FileAccess.file_exists(path) else 0


## 這個角色上次存的外觀,而且「可以只讀外觀那一套就生成」:回 {id, folder, base_scale, base_flipped};不行回空字典
## (沒存過、存的是預設外觀、那套外觀不在了、狀態檔沒有預設外觀的縮放記錄、預設外觀的 pack.json 之後又被改過)。
static func saved_look(pack_folder: String) -> Dictionary:
	var path := CharacterFiles.state_in(_normalize(pack_folder))
	if not FileAccess.file_exists(path) or FileAccess.get_size(path) > 1_000_000:
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("appearance") is String or not data.get("appearance_base") is Dictionary:
		return {}
	var id := str(data["appearance"])
	var base: Dictionary = data["appearance_base"]
	var scale: Variant = base.get("scale")
	if id == "" or id != id.validate_filename() or id.begins_with(".") or not (scale is float or scale is int) or float(scale) <= 0.0 or not is_finite(float(scale)):
		return {}
	var folder := folder_of(pack_folder, id)
	if not DirAccess.dir_exists_absolute(folder) or int(base.get("stamp", -1)) != base_stamp(pack_folder):
		return {}
	return {"id": id, "folder": folder, "base_scale": float(scale), "base_flipped": bool(base.get("flipped", false))}


## 這套外觀能不能用(讀得出來、而且有自己的 idle);不能用回原因,能用回空字串。pack = SpritePackLoader.load_pack 的結果。
static func problem_of(pack: Dictionary) -> String:
	if not bool(pack.get("ok", false)):
		var report: Array = pack.get("report", [])
		return str(report[0]) if not report.is_empty() else "讀不出素材"
	if bool((pack["frames"] as SpriteFrames).get_meta("idle_missing", false)):
		return "這套外觀沒有待機(idle)動作;一套外觀至少要有 idle"
	return ""
