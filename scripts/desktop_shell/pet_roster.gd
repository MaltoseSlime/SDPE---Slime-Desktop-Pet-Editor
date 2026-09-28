class_name PetRoster
extends RefCounted
## 場上桌寵名單的存讀(開機自動召喚)與角色積木檔的保存。
## - 名單存在 user://settings.cfg 的 [roster] entries:每項是「怎麼重新放出這隻」的描述,
##   {kind:"sample", tag, name}(內建範例 Mal / Buddy)、{kind:"still", which:"A"|"B"}(半身立繪)、{kind:"pack", path}(素材包資料夾)。
##   讀進來一律逐欄驗證,不認得的項目直接丟掉;最多 MAX_ENTRIES 隻。
## - 使用者導入過的積木檔複製一份到 user://logic/<辨識代號>.logic.json,之後這個角色每次生成都會自動載入它
##   (原檔搬走、刪掉也不受影響)。
## - 無頭模式(自動測試)不讀不寫,免得測試把使用者的桌面配置弄亂。

const SETTINGS_PATH := "user://settings.cfg"
const LOGIC_DIR := "user://logic"
const MAX_ENTRIES := 20
const KINDS: Array[String] = ["sample", "still", "pack"]


## 自動測試可以設成 true 來驗證存讀(測試要自己備份/還原設定檔)。
static var force_enabled := false


static func enabled() -> bool:
	return force_enabled or DisplayServer.get_name() != "headless"


static func save(entries: Array) -> void:
	if not enabled():
		return
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	config.set_value("roster", "entries", entries.slice(0, MAX_ENTRIES))
	config.save(SETTINGS_PATH)


## 讀名單並驗證。沒有、壞掉、無頭模式都回空陣列。
static func load_entries() -> Array:
	var result: Array = []
	if not enabled():
		return result
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return result
	var raw: Variant = config.get_value("roster", "entries", [])
	if not raw is Array:
		return result
	for item: Variant in raw:
		if result.size() >= MAX_ENTRIES:
			break
		var entry := sanitize_entry(item)
		if not entry.is_empty():
			result.append(entry)
	return result


static func sanitize_entry(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var kind := str(item.get("kind", ""))
	if not KINDS.has(kind):
		return {}
	match kind:
		"sample":
			var tag := str(item.get("tag", "")).strip_edges()
			if tag == "" or tag.length() > 40:
				return {}
			return _with_placement({"kind": kind, "tag": tag, "name": str(item.get("name", tag)).strip_edges().left(40)}, item)
		"still":
			var which := str(item.get("which", ""))
			return {"kind": kind, "which": which} if which in ["A", "B"] else {}
		"pack":
			var path := str(item.get("path", "")).strip_edges()
			return _with_placement({"kind": kind, "path": path}, item) if path != "" and path.length() < 1024 else {}
	return {}


## 還原用的選用欄位:上次的移動模式 mode(0~4)與在行動區裡的水平位置 x(0~1 的比例,行動區改大小也對得上)。壞值直接不帶。
static func _with_placement(entry: Dictionary, item: Dictionary) -> Dictionary:
	var mode: Variant = item.get("mode")
	if (mode is int or mode is float) and int(mode) >= 0 and int(mode) <= 4:
		entry["mode"] = int(mode)
	var x: Variant = item.get("x")
	if (x is int or x is float) and not is_nan(float(x)):
		entry["x"] = clampf(float(x), 0.0, 1.0)
	return entry


## 保存的積木檔位置:folder 是角色庫裡的角色資料夾(見 CharacterFiles.folder_of)就放在它的 character/logic.json,否則 user://logic/<辨識代號>.logic.json。
static func logic_path(tag: String, folder := "") -> String:
	if folder != "":
		return CharacterFiles.logic_in(folder)
	return "%s/%s.logic.json" % [LOGIC_DIR, tag.validate_filename()]


## 把導入成功的積木檔複製一份保存(受大小上限保護)。回傳是否成功。
static func store_logic(tag: String, source_path: String, folder := "") -> bool:
	if not enabled() or tag.strip_edges() == "":
		return false
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null or source.get_length() > 4_000_000:
		return false
	var target_path := logic_path(tag, folder)
	DirAccess.make_dir_recursive_absolute(target_path.get_base_dir())
	var target := FileAccess.open(target_path, FileAccess.WRITE)
	if target == null:
		return false
	target.store_buffer(source.get_buffer(source.get_length()))
	return true
