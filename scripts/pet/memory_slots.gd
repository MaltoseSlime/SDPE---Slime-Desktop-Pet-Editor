class_name MemorySlots
extends RefCounted
## 記憶存檔:每個角色(辨識代號)有 5 格,可以把目前的記憶(局部數值、事件 Flag、使用者輸入的文字)存進去,之後再讀回來。
## 存在 user://memory_slots/<辨識代號>.json;同辨識代號的複製品共用同一組 5 格。讀取時逐項驗證(型別、數量、字數),壞掉的項目略過。
## 不含:狀態鏡(啟用中的狀態鏡不算記憶)、全域數值(所有桌寵共用)。

const DIR := "user://memory_slots/"
const SLOT_COUNT := 5
const MAX_ENTRIES := 500
const MAX_TEXT := 400
const MAX_NAME := 30


static func _path(pet: Node) -> String:
	var tag: String = str(pet.recognition_tag) if str(pet.recognition_tag) != "" else str(pet.display_name)
	return "%s%s.json" % [DIR, tag.validate_filename()]


## 目前這隻桌寵的記憶快照(存進格子的內容)。slot_name 是使用者取的名字(可空)。
static func snapshot(pet: Node, slot_name := "") -> Dictionary:
	return {
		"name": slot_name.strip_edges().left(MAX_NAME),
		"time": Time.get_datetime_string_from_system(false, true),
		"values": pet.local_values.duplicate(true),
		"flags": pet.flags.duplicate(true),
		"texts": pet.text_values.duplicate(true),
	}


## 讀出 5 格(沒有檔案或壞掉的格子 = 空字典)。回傳長度一定是 SLOT_COUNT。
static func read_all(pet: Node) -> Array:
	var slots: Array = []
	for i in SLOT_COUNT:
		slots.append({})
	var path := _path(pet)
	if not FileAccess.file_exists(path):
		return slots
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or not (parsed as Dictionary).get("slots") is Array:
		return slots
	var stored: Array = parsed["slots"]
	for i in mini(stored.size(), SLOT_COUNT):
		slots[i] = clean(stored[i])
	return slots


## 驗證並整理一格的內容;不合格回空字典。數值只收數字、Flag 只收布林/數字/文字、文字只收字串。
static func clean(raw: Variant) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var result := {"name": str(raw.get("name", "")).strip_edges().left(MAX_NAME), "time": str(raw.get("time", "")).left(30), "values": {}, "flags": {}, "texts": {}}
	var counted := 0
	for section: String in ["values", "flags", "texts"]:
		var table: Variant = raw.get(section)
		if not table is Dictionary:
			continue
		for key: Variant in table:
			if counted >= MAX_ENTRIES:
				break
			var value: Variant = table[key]
			var ok := false
			match section:
				"values":
					ok = value is float or value is int
				"flags":
					ok = value is bool or value is float or value is int or value is String
				"texts":
					ok = value is String
			if ok:
				result[section][str(key).left(80)] = str(value).left(MAX_TEXT) if value is String else value
				counted += 1
	if (result["values"] as Dictionary).is_empty() and (result["flags"] as Dictionary).is_empty() and (result["texts"] as Dictionary).is_empty() and str(raw.get("time", "")) == "":
		return {}
	return result


## 寫一格。回傳成功與否。
static func write_slot(pet: Node, index: int, data: Dictionary) -> bool:
	if index < 0 or index >= SLOT_COUNT:
		return false
	var slots := read_all(pet)
	slots[index] = data
	return _write_all(pet, slots)


static func clear_slot(pet: Node, index: int) -> bool:
	return write_slot(pet, index, {})


static func _write_all(pet: Node, slots: Array) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	var file := FileAccess.open(_path(pet), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"slots": slots}, "\t"))
	return true


## 把一格的內容讀回這隻桌寵(整組取代目前的局部數值、Flag、文字)。回傳讀回前的記憶(給「復原」用)。
static func apply(pet: Node, data: Dictionary) -> Dictionary:
	var before := {"values": pet.local_values.duplicate(true), "flags": pet.flags.duplicate(true), "texts": pet.text_values.duplicate(true), "lenses": []}
	pet.restore_memory({"values": data.get("values", {}), "flags": data.get("flags", {}), "texts": data.get("texts", {})})
	return before


static func summary(data: Dictionary) -> String:
	if data.is_empty():
		return "(空)"
	var label := "「%s」" % str(data["name"]) if str(data.get("name", "")) != "" else ""
	return TranslationServer.translate("%s%s  ·  數值 %d、Flag %d、文字 %d") % [label, str(data.get("time", "")).replace("T", " "), (data["values"] as Dictionary).size(), (data["flags"] as Dictionary).size(), (data["texts"] as Dictionary).size()]
