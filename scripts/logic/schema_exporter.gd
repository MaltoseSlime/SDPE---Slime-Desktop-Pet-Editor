class_name SchemaExporter
extends RefCounted
## Schema 導出器(主企劃書第四章模組 C 流程一):把 Godot 端一隻桌寵的資料整理成 HTML 積木編輯器
## 讀得懂的 JSON(結構見 docs/html_side_progress/Godot端回覆給HTML端.md 第一節(範例:docs/html_side_progress/test_pack/*.schema.json))。
## 動作清單 = 13 個系統動作 + 該桌寵素材裡多出來的自訂動作(動畫名稱去掉尾端 _數字);
## 狀態鏡、小道具、特效、音效等系統完成前先導出空陣列。

const SCHEMA_VERSION := "1.1"
const SYSTEM_ACTIONS: Array[String] = ["idle", "walk", "run", "rise", "fall", "land", "downward", "fly", "sit", "lay", "drag", "sleep", "gather", "enter", "leave", "interact", "dance", "climb_wall", "climb_ceiling"]
const TOGGLES: Array[String] = ["run", "跟隨"]


static func build(pet: Node) -> Dictionary:
	var global_values: Dictionary = pet.get_node("/root/DesktopShellState").global_values
	var style: PetUiStyle = pet.ui_style
	return {
		"schemaVersion": SCHEMA_VERSION,
		"pet": {
			"recognitionTag": pet.recognition_tag,
			"displayName": pet.display_name,
			"palette": {
				"background": _hex(style.background),
				"border": _hex(style.border),
				"text": _hex(style.text),
				"option": _hex(style.option),
			},
			# 關鍵詞庫(台詞裡的 {keyword} / {kw:N}),網頁預覽用它顯示示範文字。
			"keywords": Array(pet.keywords),
			"userKeywords": Array(pet.user_keywords),
			# 思考泡泡(對話積木 BUBBLE = thought)的獨立配色,網頁預覽用。
			"thoughtPalette": {
				"background": _hex(style.thought_background),
				"border": _hex(style.thought_border),
				"text": _hex(style.thought_text),
				"option": _hex(style.thought_option),
			},
			"uiScale": int(style.scale_factor() * 100.0),
			"defaultFont": style.default_font,
			"fontScale": int(style.font_scale_factor() * 100.0),
			"availableFonts": UiFonts.FONT_NAMES.duplicate(),
			# 桌寵語系(見「介面與自動行為 > 字體與對話」):"" = 預設(原始語言);翻譯內容本身由 HTML 端製作,
			# Godot 端只負責記住這隻角色目前選哪個代碼、給哪些代碼可選。
			"dialogueLocale": pet.dialogue_locale,
			"availableLocales": AppSettings.available_languages().keys(),
			# 固定不動的角色(移動模式=固定,例如半身立繪):HTML 端據此對移動類積木加提示。
			"fixed": int(pet.move_mode) == Pet.MoveMode.FIXED,
		},
		"actions": _collect_actions(pet),
		"stateLenses": _collect_lenses(pet),
		"toggles": TOGGLES.duplicate(),
		"props": PropLibrary.list().map(func(def: PropDef) -> Dictionary: return def.schema_entry()),
		"effects": PetEffects.catalog_entries(),
		"sounds": SoundManager.BUILTIN_SOUNDS.duplicate(),
		"localValues": _collect_keys(pet.value_defs, pet.local_values, false),
		"globalValues": _collect_keys(pet.get_node("/root/DesktopShellState").global_value_defs, global_values, true),
		"flags": pet.flags.keys(),
		"valueDefs": _collect_value_defs(pet),
		# 使用者輸入給桌寵的文字變數名稱(稱呼、抽籤結果…),給 {text:名稱} 與 cond_text_set 的下拉選單用。
		"textValues": pet.text_values.keys(),
	}


static func save(pet: Node, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(build(pet), "  "))
	return OK


## 選用欄位 valueDefs:每個宣告過的數值 {name, scope, default, min?, max?};沒有上/下限的就省略該鍵。
static func _collect_value_defs(pet: Node) -> Array:
	var defs: Array = []
	var all: Array = pet.value_defs.duplicate()
	all.append_array(pet.get_node("/root/DesktopShellState").global_value_defs)
	for def: PetValueDef in all:
		var entry := {"name": def.key, "scope": "global" if def.is_global else "local", "default": def.default_value}
		if def.min_value > -1.0e8:
			entry["min"] = def.min_value
		if def.has_max():
			entry["max"] = def.max_value
		defs.append(entry)
	return defs


## #RRGGBBAA(大寫,帶 Alpha),與 HTML 端 Schema 範例格式一致。
static func _hex(color: Color) -> String:
	return "#" + color.to_html(true).to_upper()


## 宣告過的數值名稱在前(依宣告順序),再補上執行中實際出現過、但沒宣告的名稱。
static func _collect_keys(defs: Array, store: Dictionary, global: bool) -> Array:
	var keys: Array = []
	for def: PetValueDef in defs:
		if def.is_global == global and not keys.has(def.key):
			keys.append(def.key)
	for key in store.keys():
		if not keys.has(key):
			keys.append(key)
	return keys


static func _collect_lenses(pet: Node) -> Array:
	var lenses: Array = []
	for lens: PetStateLens in pet.state_lenses:
		lenses.append({"name": lens.lens_name, "nature": Array(lens.nature)})
	return lenses


static func _has_lens_prefix(pet: Node, animation: String) -> bool:
	for lens: PetStateLens in pet.state_lenses:
		if lens.prefix != "" and animation.begins_with(lens.prefix):
			return true
	return false


## 這隻桌寵的動作清單(13 個系統動作 + 素材裡的自訂動作),Schema 與測試者視窗共用。
static func collect_actions(pet: Node) -> Array:
	return _collect_actions(pet)


static func _collect_actions(pet: Node) -> Array:
	var actions: Array = SYSTEM_ACTIONS.duplicate()
	var frames: SpriteFrames = pet.get_node("VisualRoot/AnimatedSprite2D").sprite_frames
	if frames == null:
		return actions
	for animation in frames.get_animation_names():
		var base := String(animation)
		# 眨眼/說話子差分(_bl/_sp)與狀態鏡前綴差分(tired_idle_0)是既有動作的變體,不是獨立的動作名稱。
		if base.ends_with("_bl") or base.ends_with("_sp") or "_bl_f" in base or _has_lens_prefix(pet, base):
			continue
		var split := base.rfind("_")
		if split > 0 and base.substr(split + 1).is_valid_int():
			base = base.substr(0, split)
		if not actions.has(base):
			actions.append(base)
	return actions
