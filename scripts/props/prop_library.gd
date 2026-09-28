class_name PropLibrary
extends RefCounted
## 物品欄:所有小道具定義的存放與管理。一個道具一個資料夾 user://props/<id>/(prop.json + 縮圖/桌面貼圖),
## 刪除是搬到 user://backup/props/<id>_<時間>/(不直接刪,和角色庫一致)。內建模板(食物、金錢、洗滌用品、玩具、逗貓棒)是「可複製的起點」。
## 圖片一律由使用者匯入(見 import_image);沒有圖片的道具在桌面上用程式畫替代圖示,不附任何圖像素材。

const IMAGE_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp"]
const MAX_IMAGE_BYTES := 8_000_000
const MAX_IMAGE_SIDE := 2048
const MAX_PROPS := 200
## 測試用:非空就改用這個資料夾當物品欄根目錄(不動使用者真正的資料)。
static var root_override := ""

## 內建模板(企劃書「內建小道具模板」):id → 欄位(用 PropDef.from_dict 的格式)。
const TEMPLATES := {
	"food": {"label": "食物", "data": {"toss": true, "rub": false, "defaultReaction": "pickup", "disableNegative": true,
			"valueBindings": [], "useAnim": "shake", "useShakes": 3, "template": "食物"}},
	"money": {"label": "金錢", "data": {"toss": true, "rub": false, "defaultReaction": "none",
			"valueBindings": [{"scope": "global", "key": "金幣", "delta": 1}], "useAnim": "float_up", "template": "金錢"}},
	"soap": {"label": "洗滌用品", "data": {"toss": false, "rub": true, "defaultReaction": "none", "effect": "foam", "effectAfter": "sparkle", "template": "洗滌用品"}},
	"toy": {"label": "玩具", "data": {"toss": true, "rub": true, "defaultReaction": "none", "template": "玩具"}},
	"ball": {"label": "球", "data": {"toss": false, "rub": false, "defaultReaction": "none", "shape": "ball", "template": "球"}},
	"teaser": {"label": "逗貓棒", "data": {"toss": false, "rub": true, "defaultReaction": "none", "attractWhileDragging": true, "template": "逗貓棒"}},
}


static func root_dir() -> String:
	return root_override if root_override != "" else "user://props"


static func folder_of(id: String) -> String:
	return root_dir().path_join(id)


static func backup_root() -> String:
	return "user://backup/props" if root_override == "" else root_override.path_join("_backup")


## 所有道具:依使用者排的順序(見 move_in_order),沒排過的接在後面依名稱排;壞掉的資料夾略過。
static func list() -> Array[PropDef]:
	var result: Array[PropDef] = []
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
		if result.size() >= MAX_PROPS:
			break
	var order := saved_order()
	result.sort_custom(func(a: PropDef, b: PropDef) -> bool:
		var ia := order.find(a.id)
		var ib := order.find(b.id)
		if ia >= 0 and ib >= 0:
			return ia < ib
		if ia >= 0 or ib >= 0:
			return ia >= 0
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)
	return result


## 使用者排的順序(道具 id 陣列),存在物品欄根目錄的 _order.json;沒有就是空的。
static func saved_order() -> Array:
	var path := root_dir().path_join("_order.json")
	if not FileAccess.file_exists(path):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (parsed as Array).map(func(v: Variant) -> String: return str(v)) if parsed is Array else []


## 把道具 id 往前(delta < 0)或往後(delta > 0)移;回傳有沒有真的移動。物品欄視窗、道具欄與網頁 Schema 都照這個順序。
static func move_in_order(id: String, delta: int) -> bool:
	var ids: Array = list().map(func(d: PropDef) -> String: return d.id)
	var from := ids.find(id)
	var to := clampi(from + delta, 0, ids.size() - 1)
	if from < 0 or to == from:
		return false
	ids.remove_at(from)
	ids.insert(to, id)
	DirAccess.make_dir_recursive_absolute(root_dir())
	var file := FileAccess.open(root_dir().path_join("_order.json"), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(ids) + "\n")
	file.close()
	return true


static func find_by_name(display_name: String) -> PropDef:
	for def in list():
		if def.display_name == display_name:
			return def
	return null


static func load_def(id: String) -> PropDef:
	var path := folder_of(id).path_join("prop.json")
	if not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null   # 壞掉的檔案略過,不讓清單壞掉
	return PropDef.from_dict(json.data, id)


## 存檔(新道具用 unique_id 取一個不重複的資料夾名稱)。回傳 "" = 成功,否則是錯誤說明。
static func save_def(def: PropDef) -> String:
	if def.display_name == "":
		return tr_("名稱不能是空的。")
	if def.id == "":
		def.id = unique_id(def.display_name)
	DirAccess.make_dir_recursive_absolute(folder_of(def.id))
	var file := FileAccess.open(folder_of(def.id).path_join("prop.json"), FileAccess.WRITE)
	if file == null:
		return tr_("無法寫入道具資料夾。")
	file.store_string(JSON.stringify(def.to_dict(), "  ") + "\n")
	file.close()
	return ""


## 這個顯示名稱對應的、還沒被用掉的資料夾名稱(重複就加 _2、_3…)。
static func unique_id(display_name: String) -> String:
	var base := PropDef.safe_id(display_name)
	var candidate := base
	var n := 2
	while DirAccess.dir_exists_absolute(folder_of(candidate)):
		candidate = "%s_%d" % [base, n]
		n += 1
	return candidate


## 名稱有沒有被別的道具用了(改名檢查用;except_id 是自己)。
static func name_taken(display_name: String, except_id := "") -> bool:
	for def in list():
		if def.display_name == display_name and def.id != except_id:
			return true
	return false


## 從內建模板做一個新道具並存檔。名稱重複就自動加編號;回傳新道具,失敗回 null。
static func create_from_template(template_id: String, display_name := "") -> PropDef:
	if not TEMPLATES.has(template_id):
		return null
	var entry: Dictionary = TEMPLATES[template_id]
	var wanted := PropDef.clean_name(display_name if display_name != "" else str(entry["label"]))
	var final_name := wanted
	var n := 2
	while name_taken(final_name):
		final_name = "%s %d" % [wanted, n]
		n += 1
	var data: Dictionary = (entry["data"] as Dictionary).duplicate(true)
	data["name"] = final_name
	var def := PropDef.from_dict(data, "")
	if def == null or save_def(def) != "":
		return null
	return def


## 刪除 = 整個資料夾搬到備份(不直接刪)。回傳 "" 或錯誤說明。
static func delete_def(id: String) -> String:
	var source := folder_of(id)
	if not DirAccess.dir_exists_absolute(source):
		return tr_("找不到這個道具。")
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var target := backup_root().path_join("%s_%s" % [id, stamp])
	DirAccess.make_dir_recursive_absolute(backup_root())
	if DirAccess.rename_absolute(source, target) != OK:
		return tr_("無法把道具搬到備份資料夾。")
	return ""


## 匯入圖片到道具資料夾(slot = "thumbnail" 或 "desktop"):驗證副檔名、大小、能不能讀、長寬,存成 <slot>.png(統一格式)。
## 回傳 "" = 成功(並更新 def 的欄位,呼叫端記得 save_def),否則是錯誤說明,原本的圖不動。
static func import_image(def: PropDef, slot: String, source_path: String) -> String:
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
	var file_name := "%s.png" % ("thumbnail" if slot == "thumbnail" else "desktop")
	DirAccess.make_dir_recursive_absolute(folder_of(def.id))
	if image.save_png(folder_of(def.id).path_join(file_name)) != OK:
		return tr_("無法儲存圖片。")
	if slot == "thumbnail":
		def.thumbnail = file_name
	else:
		def.desktop_texture = file_name
	return ""


## 道具的圖:which = "desktop"(桌面貼圖,沒有就沿用縮圖)或 "thumbnail";沒有圖回 null。
static func texture_of(def: PropDef, which := "desktop") -> Texture2D:
	var file_name := def.desktop_texture if which == "desktop" and def.desktop_texture != "" else def.thumbnail
	if file_name == "":
		var sprite := load_sprite(def)   # 沒有簡單版的圖:用進階貼圖預設狀態的第一幀當縮圖 / 貼圖
		return sprite.get_frame_texture(&"default_0", 0) if sprite != null else null
	var path := folder_of(def.id).path_join(file_name)
	if not FileAccess.file_exists(path):
		return null
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


## 進階貼圖(狀態動畫)的素材包資料夾:道具資料夾裡的 sprite/,用精靈圖編輯器的道具區編輯;動作槽 default(預設)、used(被使用)、drag(拖曳中)。
static func sprite_folder(id: String) -> String:
	return folder_of(id).path_join("sprite")


const SPRITE_STATES: Array[String] = ["default", "used", "drag"]
static var _sprite_cache: Dictionary = {}


## sprite/ 裡有沒有圖片(任何一層資料夾裡的 png / jpg / webp)。
static func has_sprite(def: PropDef) -> bool:
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


## 載入進階貼圖(SpriteFrames,動畫名 default_0 / used_0 / drag_0);沒有或讀不出來回 null。依資料夾內容快取,編輯器存檔後下一次載入就是新的。
## 預設狀態循環播放,被使用與拖曳中的動畫不自己循環(由 PropItem 依播放方式控制次數或循環)。
static func load_sprite(def: PropDef) -> SpriteFrames:
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
	if not frames.has_animation(&"default_0"):
		return null
	for animation: StringName in frames.get_animation_names():
		frames.set_animation_loop(animation, str(animation) == "default_0")
	_sprite_cache[folder] = {"stamp": stamp, "frames": frames}
	return frames


## static 函式裡不能用 tr():走 TranslationServer。
static func tr_(message: String) -> String:
	return TranslationServer.translate(message)
