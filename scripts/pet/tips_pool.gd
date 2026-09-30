class_name TipsPool
extends RefCounted
## 健談桌寵閒聊引用的「小提示」詞條池:對話文字裡用 {tips} 插入(見 LogicInterpreter._placeholder_text,
## 跟 {pick:甲|乙|丙} 一樣是隨機挑一則,只是這個池子存在獨立的文件、不是寫死在對話句子裡)。
## 內容存在 res://content/tips_pool.json 的 "tips" 陣列,每則是 {zh_TW, en} 一組(跟性格檔的
## dialogueTranslations 同一個精神,只是這裡沒有原文/翻譯之分,兩個語系都是平起平坐的欄位);開發者自己填,
## 這個池子不分性格、不分桌寵,場上所有引用 {tips} 的句子共用同一份。en 目前留白(2026-10-01:第一版先只寫
## 中文,英文之後再補,pick() 會在 en 缺席時自動退回 zh_TW,不會插入空字串或英文原文夾雜的怪句子)。
## 池子是空的(檔案不存在、陣列是空的、或整批都沒有可用文字)時,{tips} 就插入空字串,不會出錯。

const PATH := "res://content/tips_pool.json"
## 每筆 {zh_TW, en}(en 可以是空字串,pick() 會自動退回 zh_TW)。
static var _cache: Array[Dictionary] = []
static var _loaded := false


## 目前的提示清單(第一次呼叫時讀檔、之後用快取;檔案不存在或格式不對就回傳空陣列)。
static func list() -> Array[Dictionary]:
	if not _loaded:
		_cache = _load()
		_loaded = true
	return _cache


## 依語系隨機挑一則(locale 用跟 Pet.speak_tr()/LogicInterpreter._resolve_text 同一套代號,例如 "zh_TW"/"en";
## 前綴比對就好,"en_US" 也算 "en")。這個語系沒填就退回 zh_TW;池子整個是空的就回空字串。
static func pick(locale: String) -> String:
	var entries := list()
	if entries.is_empty():
		return ""
	var entry: Dictionary = entries[randi() % entries.size()]
	var wanted := locale.to_lower().replace("-", "_")
	if wanted.begins_with("zh"):
		return str(entry.get("zh_TW", ""))
	var text := str(entry.get(wanted, entry.get(wanted.split("_")[0], "")))
	return text if text != "" else str(entry.get("zh_TW", ""))


static func _load() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(PATH):
		return result
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not (parsed.get("tips") is Array):
		return result
	for entry: Variant in (parsed["tips"] as Array):
		if not entry is Dictionary:
			continue
		var zh := str((entry as Dictionary).get("zh_TW", "")).strip_edges()
		var en := str((entry as Dictionary).get("en", "")).strip_edges()
		if zh != "" or en != "":
			result.append({"zh_TW": zh, "en": en})
	return result


## 測試,或使用者存檔後想立刻生效時用:清掉快取,下次 list()/pick() 重新讀檔。
static func reload() -> void:
	_loaded = false
