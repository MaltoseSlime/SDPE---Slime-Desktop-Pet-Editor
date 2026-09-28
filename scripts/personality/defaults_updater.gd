class_name DefaultsUpdater
extends RefCounted
## 新版本的預設內容更新:內建性格(參數、狀態鏡、數值定義、對話池、反應事件)改版之後,問使用者要不要「追加」到既有桌寵上。
## 原則(和 PersonalityApplier 一致,不覆蓋使用者的東西):
##  - 使用者自己建的狀態鏡 / 數值定義、性格加入後被使用者改過的:不動。
##  - 沒被使用者改過的性格加入項目:換成新版內容。
##  - 參數:只更新「使用者沒手動調過」的(目前值 = 上次套用的值 / 預設值);手動調過的保留,想同步到新版要在「性格」分頁按「重設此性格副本」。
##  - 對話池與反應事件:沒改過的性格副本本來就跟著共用的性格檔走(見 PersonalityApplier.personality_of),這裡只需要重建事件層。
##  - 以前就有、後來被使用者刪掉的項目(defaults_seen)不會加回來。
##  - 使用者改過的性格副本整份不動(它已經是使用者自己的版本)。
## 怎麼知道「有更新」:內建性格檔內容 + REVISION 算出一個簽章(signature);每隻桌寵記著自己上次更新到哪個簽章(Pet.defaults_signature,存在設定檔的 "defaults" 區塊)。
## 新放出來的桌寵一開始就是最新的;舊設定檔沒有這個欄位 = 需要更新。改了內建性格檔簽章就會自己變,不用手動改版本號;
## REVISION 只在「引擎內建、不在性格檔裡」的預設有變動時才要加一(例如 BASELINE_LENSES 增加項目)。

## 內建預設的手動版本號:見上面說明。
const REVISION := 1
## 引擎的行為會用到、所有桌寵都該有的狀態鏡(名稱)。桌寵缺其中的項目,更新時從 BASELINE_SOURCE 這份性格補上(當成使用者自己的,之後換性格不會被移除)。
const BASELINE_LENSES: Array[String] = ["疲憊", "生氣", "開心", "悲傷", "緊張", "悠哉", "奔跑"]
const BASELINE_SOURCE := "calm"
## 使用者選了「這一版不要再問」時,記在 settings.cfg 的 [app] defaults_ack(那一版的簽章)。
const ACK_SECTION := "app"
const ACK_KEY := "defaults_ack"

static var _signature_cache := ""


## 目前內建預設內容的簽章(內建性格檔的內容 + REVISION)。
static func signature() -> String:
	if _signature_cache != "":
		return _signature_cache
	var parts: PackedStringArray = ["rev%d" % REVISION]
	var files := Array(DirAccess.get_files_at(PersonalityFile.PRESET_DIR))
	files.sort()
	for file_name: String in files:
		if file_name.ends_with(PersonalityFile.EXTENSION):
			parts.append(file_name + "\n" + FileAccess.get_file_as_string(PersonalityFile.PRESET_DIR + file_name))
	_signature_cache = "\n".join(parts).sha256_text().left(16)
	return _signature_cache


## 這隻桌寵的預設內容是不是舊版(需要更新)。
static func needs_update(pet: Node) -> bool:
	return str(pet.defaults_signature) != signature()


## 標成最新版,並把目前有的狀態鏡、數值定義名稱記進 defaults_seen(之後被使用者刪掉的不會加回來)。
static func mark_current(pet: Node) -> void:
	pet.defaults_signature = signature()
	remember_names(pet)


## 把目前有的項目名稱記起來(存檔時也會呼叫,所以「以前有過、後來刪掉」的看得出來)。
static func remember_names(pet: Node) -> void:
	var seen := seen_of(pet)
	for lens: PetStateLens in pet.state_lenses:
		if not (seen["lenses"] as Array).has(lens.lens_name):
			(seen["lenses"] as Array).append(lens.lens_name)
	for def: PetValueDef in pet.value_defs:
		if not (seen["valueDefs"] as Array).has(def.key):
			(seen["valueDefs"] as Array).append(def.key)


static func seen_of(pet: Node) -> Dictionary:
	var seen: Dictionary = pet.defaults_seen
	for section: String in ["lenses", "valueDefs"]:
		if not seen.get(section) is Array:
			seen[section] = []
	pet.defaults_seen = seen
	return seen


## 存檔用({signature, seen})。
static func to_data(pet: Node) -> Dictionary:
	remember_names(pet)
	return {"signature": str(pet.defaults_signature), "seen": pet.defaults_seen.duplicate(true)}


## 從設定檔還原(逐項驗證;沒有這個區塊 = 舊設定檔,簽章維持空,代表需要更新)。
static func restore(pet: Node, data: Variant) -> void:
	pet.defaults_signature = ""
	pet.defaults_seen = {"lenses": [], "valueDefs": []}
	if not data is Dictionary:
		return
	if data.get("signature") is String:
		pet.defaults_signature = str(data["signature"]).left(64)
	if data.get("seen") is Dictionary:
		for section: String in ["lenses", "valueDefs"]:
			if (data["seen"] as Dictionary).get(section) is Array:
				for entry: Variant in (data["seen"] as Dictionary)[section]:
					if entry is String and (pet.defaults_seen[section] as Array).size() < 500:
						(pet.defaults_seen[section] as Array).append(str(entry).left(60))


## 更新一隻桌寵(不存檔,呼叫的人決定什麼時候存)。回傳 {lines:[給使用者看的報告], changed:更新了幾項}。
static func update_pet(pet: Node) -> Dictionary:
	var lines: Array[String] = []
	var changed := 0
	var wanted := {}
	var choices: Dictionary = PersonalityApplier.state_of(pet)["choices"]
	for section: String in PersonalityApplier.SECTIONS:
		if str(choices.get(section, "")) != "":
			wanted[section] = str(choices[section])
	var skip := seen_of(pet).duplicate(true)
	# 「以前就有」只該擋使用者刪掉的:現在還在的照常比對更新,所以 skip 只放 seen 裡目前不存在的名稱。
	for section: String in ["lenses", "valueDefs"]:
		var present: Array[String] = []
		for item: Variant in PersonalityApplier._existing(pet, section):
			present.append(PersonalityApplier._name_of(item, section))
		skip[section] = (skip[section] as Array).filter(func(item_name: String) -> bool: return not present.has(item_name))
	if not wanted.is_empty():
		var result := PersonalityApplier.apply(pet, wanted, {"skip_names": skip})
		lines.append_array(result["lines"])
		var plan: Dictionary = result["plan"]
		for step: Dictionary in plan["params"]:
			if ["apply", "revert"].has(str(step["action"])):
				changed += 1   # keep(保留你改過的)、same、release 都不算更新
		for section: String in ["valueDefs", "lenses"]:
			for step: Dictionary in plan["defs"][section]:
				if ["add", "replace", "remove"].has(str(step["action"])):
					changed += 1
	for line: String in _add_baseline(pet, skip["lenses"]):
		lines.append(line)
		changed += 1
	PersonalityApplier.rebuild_layer(pet)
	mark_current(pet)
	return {"lines": lines, "changed": changed}


## 缺的引擎必備狀態鏡從 BASELINE_SOURCE 補上(以前有過的、被刪掉的不補)。
static func _add_baseline(pet: Node, skip_names: Array) -> Array[String]:
	var lines: Array[String] = []
	var source := PersonalityFile.find(BASELINE_SOURCE)
	if source.is_empty():
		return lines
	var added := false
	for entry: Dictionary in (source["personality"] as Dictionary).get("lenses", []):
		var lens_name := str(entry.get("name", ""))
		if not BASELINE_LENSES.has(lens_name) or pet.has_lens(lens_name) or skip_names.has(lens_name):
			continue
		var lens: PetStateLens = PetProfile.lens_from_dict(entry)
		if lens == null:
			continue
		lens.source = ""   # 當成使用者自己的:之後換性格不會被自動移除
		pet.state_lenses.append(lens)
		lines.append(TranslationServer.translate("狀態鏡「%s」:新增(桌寵的基本反應會用到)") % lens_name)
		added = true
	if added:
		pet.reapply_lenses()
	return lines


# --- 全部桌寵 / 開機詢問 ---

## 目前場上需要更新的桌寵。
static func outdated_pets(tree: SceneTree) -> Array:
	return tree.get_nodes_in_group("pets").filter(func(pet: Node) -> bool: return not pet.is_queued_for_deletion() and needs_update(pet))


## 使用者選了「這一版不要再問」。
static func acknowledge(settings_path: String) -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(ACK_SECTION, ACK_KEY, signature())
	config.save(settings_path)


static func acknowledged(settings_path: String) -> bool:
	var config := ConfigFile.new()
	return config.load(settings_path) == OK and str(config.get_value(ACK_SECTION, ACK_KEY, "")) == signature()
