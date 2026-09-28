class_name FurnitureLibrary
extends RefCounted
## 家具庫:所有家具定義的存放與管理。一個家具一個資料夾 user://furniture/<id>/(furniture.json + 縮圖 + sprite/),
## 刪除是搬到 user://backup/furniture/<id>_<時間>/(不直接刪,和角色庫、道具一致)。

const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const MAX_IMAGE_BYTES := 8_000_000
const MAX_IMAGE_SIDE := 2048
const MAX_FURNITURE := 200
## 測試用:非空就改用這個資料夾當家具庫根目錄(不動使用者真正的資料)。
static var root_override := ""

## 內建模板(可複製的起點):id → 欄位(用 FurnitureDef.from_dict 的格式)。
const TEMPLATES := {
	"lamp": {"label": "檯燈", "data": {"condition": {"type": "time_range", "start": 1080, "end": 360}, "template": "檯燈"}},
	"disco": {"label": "迪斯可燈", "data": {"condition": {"type": "pet_action", "action": "dance"}, "template": "迪斯可燈"}},
	"plain": {"label": "純裝飾", "data": {"condition": {"type": "always"}, "template": "純裝飾"}},
}


static func root_dir() -> String:
	return root_override if root_override != "" else "user://furniture"


static func folder_of(id: String) -> String:
	return root_dir().path_join(id)


static func backup_root() -> String:
	return "user://backup/furniture" if root_override == "" else root_override.path_join("_backup")


## 所有家具,依名稱排序;壞掉的資料夾略過。
static func list() -> Array[FurnitureDef]:
	var result: Array[FurnitureDef] = []
	var dir := DirAccess.open(root_dir())
	if dir == null:
		return result
	var folders := Array(dir.get_directories())
	folders.sort()
	for folder: String in folders:
		if folder.begins_with("_"):
			continue
		var def := load_def(folder)
		if def != null:
			result.append(def)
		if result.size() >= MAX_FURNITURE:
			break
	result.sort_custom(func(a: FurnitureDef, b: FurnitureDef) -> bool: return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return result


static func find_by_name(display_name: String) -> FurnitureDef:
	for def in list():
		if def.display_name == display_name:
			return def
	return null


static func load_def(id: String) -> FurnitureDef:
	var path := folder_of(id).path_join("furniture.json")
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return FurnitureDef.from_dict(json.data, id)


## 存檔(新家具用 unique_id 取一個不重複的資料夾名稱)。回傳 "" = 成功,否則是錯誤說明。
static func save_def(def: FurnitureDef) -> String:
	if def.display_name == "":
		return tr_("名稱不能是空的。")
	if def.id == "":
		def.id = unique_id(def.display_name)
	DirAccess.make_dir_recursive_absolute(folder_of(def.id))
	var file := FileAccess.open(folder_of(def.id).path_join("furniture.json"), FileAccess.WRITE)
	if file == null:
		return tr_("無法寫入家具資料夾。")
	file.store_string(JSON.stringify(def.to_dict(), "  ") + "\n")
	file.close()
	return ""


static func unique_id(display_name: String) -> String:
	var base := FurnitureDef.safe_id(display_name)
	var candidate := base
	var n := 2
	while DirAccess.dir_exists_absolute(folder_of(candidate)):
		candidate = "%s_%d" % [base, n]
		n += 1
	return candidate


static func name_taken(display_name: String, except_id := "") -> bool:
	for def in list():
		if def.display_name == display_name and def.id != except_id:
			return true
	return false


## 從內建模板做一個新家具並存檔。名稱重複就自動加編號;回傳新家具,失敗回 null。
static func create_from_template(template_id: String, display_name := "") -> FurnitureDef:
	if not TEMPLATES.has(template_id):
		return null
	var entry: Dictionary = TEMPLATES[template_id]
	var wanted := FurnitureDef.clean_name(display_name if display_name != "" else str(entry["label"]))
	var final_name := wanted
	var n := 2
	while name_taken(final_name):
		final_name = "%s %d" % [wanted, n]
		n += 1
	var data: Dictionary = (entry["data"] as Dictionary).duplicate(true)
	data["name"] = final_name
	var def := FurnitureDef.from_dict(data, "")
	if def == null or save_def(def) != "":
		return null
	return def


## 刪除 = 整個資料夾搬到備份(不直接刪)。回傳 "" 或錯誤說明。
static func delete_def(id: String) -> String:
	var source := folder_of(id)
	if not DirAccess.dir_exists_absolute(source):
		return tr_("找不到這件家具。")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var target := backup_root().path_join("%s_%s" % [id, stamp])
	DirAccess.make_dir_recursive_absolute(backup_root())
	if DirAccess.rename_absolute(source, target) != OK:
		return tr_("無法把家具搬到備份資料夾。")
	return ""


## 匯入縮圖(存成 thumbnail.png,統一格式)。回傳 "" = 成功(並更新 def.thumbnail,呼叫端記得 save_def),否則是錯誤說明。
static func import_thumbnail(def: FurnitureDef, source_path: String) -> String:
	if def.id == "":
		return tr_("請先存檔再匯入圖片。")
	if not IMAGE_EXTENSIONS.has(source_path.get_extension().to_lower()):
		return tr_("只支援 png、jpg、webp 圖片。")
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return tr_("無法開啟這個檔案。")
	if file.get_length() > MAX_IMAGE_BYTES:
		return tr_("圖片檔案太大(上限 8 MB)。")
	var image := Image.load_from_file(source_path)
	if image == null or image.is_empty() or image.get_width() <= 0 or image.get_height() <= 0:
		return tr_("圖片毀損或格式不對。")
	if image.get_width() > MAX_IMAGE_SIDE or image.get_height() > MAX_IMAGE_SIDE:
		return tr_("圖片太大(長寬上限 2048)。")
	DirAccess.make_dir_recursive_absolute(folder_of(def.id))
	if image.save_png(folder_of(def.id).path_join("thumbnail.png")) != OK:
		return tr_("無法儲存圖片。")
	def.thumbnail = "thumbnail.png"
	return ""


static func texture_of(def: FurnitureDef) -> Texture2D:
	if def.thumbnail == "":
		var sprite := load_sprite(def)
		return sprite.get_frame_texture(&"normal_0", 0) if sprite != null and sprite.has_animation(&"normal_0") else null
	var path := folder_of(def.id).path_join(def.thumbnail)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


## 進階貼圖(狀態動畫)的素材包資料夾:家具資料夾裡的 sprite/,用精靈圖編輯器的家具區編輯;動作槽見檔頭(normal / conditional / interacted)。
static func sprite_folder(id: String) -> String:
	return folder_of(id).path_join("sprite")


const SPRITE_STATES: Array[String] = ["normal", "conditional", "interacted"]
static var _sprite_cache: Dictionary = {}


static func has_sprite(def: FurnitureDef) -> bool:
	return def != null and def.id != "" and _folder_has_images(sprite_folder(def.id), 0)


static func _folder_has_images(path: String, depth: int) -> bool:
	if depth > 2 or not DirAccess.dir_exists_absolute(path):
		return false
	for file_name in DirAccess.get_files_at(path):
		if IMAGE_EXTENSIONS.has(file_name.get_extension().to_lower()):
			return true
	for sub in DirAccess.get_directories_at(path):
		if _folder_has_images(path.path_join(sub), depth + 1):
			return true
	return false


static func _folder_stamp(path: String) -> int:
	var total := 0
	for file_name in DirAccess.get_files_at(path):
		total += FileAccess.get_modified_time(path.path_join(file_name)) + file_name.hash() % 1000
	for sub in DirAccess.get_directories_at(path):
		total += _folder_stamp(path.path_join(sub))
	return total


## 載入進階貼圖(SpriteFrames,動畫名 normal_0 / conditional_0 / interacted_0);沒有或讀不出來回 null。
## normal 與 conditional 一直循環播放(裝飾用);interacted 這批還沒有播放邏輯接上,先不循環。依資料夾內容快取。
static func load_sprite(def: FurnitureDef) -> SpriteFrames:
	if not has_sprite(def):
		return null
	var folder := sprite_folder(def.id)
	var stamp := _folder_stamp(folder)
	var cached: Variant = _sprite_cache.get(folder)
	if cached is Dictionary and int(cached["stamp"]) == stamp:
		return cached["frames"]
	var loaded := SpritePackLoader.load_pack(folder)
	if not bool(loaded["ok"]):
		return null
	var frames: SpriteFrames = loaded["frames"]
	if not frames.has_animation(&"normal_0"):
		return null
	for animation: StringName in frames.get_animation_names():
		frames.set_animation_loop(animation, str(animation) in ["normal_0", "conditional_0"])
	_sprite_cache[folder] = {"stamp": stamp, "frames": frames}
	return frames


static func tr_(message: String) -> String:
	return TranslationServer.translate(message)
