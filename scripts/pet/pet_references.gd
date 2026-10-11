class_name PetReferences
extends RefCounted
## 角色資料裡「指向別的東西」的引用(2026-10-11 使用者要求):.pet 匯到別台電腦後,交互行為與事件積木指到的
## 桌寵 / 道具在那邊不一定有。這裡只負責判斷「指得到嗎」與「改指到別的」,畫面怎麼呈現由各視窗決定:
##  - 桌寵(用辨識代號指):角色庫裡沒有、桌面上也沒有 → 那一條設定 / 事件暫時隱藏並當作停用。資料原封不動,
##    之後使用者匯入那隻桌寵(辨識代號相同)就自動恢復;也可以手動改指到別的桌寵。
##  - 道具(用顯示名稱指):物品欄裡沒有同名的 → 顯示成「(空)」,可以重新連結到現有的道具。
##  - 家具:積木只用「家具標籤」找家具,沒有指定哪一件,場上沒有符合的就自然沒有對象,不用處理。
## 「認得的桌寵」= 角色庫裡的每個角色 + 目前在桌面上的桌寵(範例桌寵、庫外素材包不在角色庫裡)。

const EMPTY_LABEL := "(空)"
## 事件積木本身(帽子)用來指桌寵的欄位。
const PET_FIELDS: Array[String] = ["A_TAG", "B_TAG"]
## 積木裡 TAG 欄位指的是桌寵的類型(其他積木的 TAG 是閒聊標籤、家具標籤,不能動)。
const PET_TAG_BLOCKS: Array[String] = ["toggle_follow_start", "action_set_pet_affinity"]


## 認得的桌寵:{辨識代號: 顯示名稱}。
static func known_pets(tree: SceneTree) -> Dictionary:
	var known := {}
	for folder in SpriteLibrary.list_packs():
		var manifest := SpriteLibrary._read_manifest(folder)
		var tag := str(manifest.get("tag", "")).strip_edges()
		if tag == "":
			tag = folder.replace("\\", "/").trim_suffix("/").get_file()
		known[tag] = str(manifest.get("name", folder.get_file()))
	if tree != null:
		for pet: Node in tree.get_nodes_in_group("pets"):
			var tag := str(pet.recognition_tag) if is_instance_valid(pet) else ""
			if tag != "" and not known.has(tag):
				known[tag] = str(pet.display_name)
	return known


## 物品欄裡現有道具的顯示名稱:{名稱: true}。
static func known_props() -> Dictionary:
	var known := {}
	for def in PropLibrary.list():
		known[def.display_name] = true
	return known


static func split_tags(raw: Variant) -> Array[String]:
	var tags: Array[String] = []
	for part in str(raw).replace("、", ",").replace(" ", ",").split(",", false):
		if part.strip_edges() != "":
			tags.append(part.strip_edges())
	return tags


static func _is_self(tag: String, self_tag: String) -> bool:
	return tag == "" or tag.to_upper() == "SELF" or tag == self_tag


## 這顆事件積木(只看帽子自己的欄位,不看底下的內容)指到、但不認得的桌寵辨識代號。
## A / B 欄位指不到就算;「對象清單」(TAGS)要整份都指不到才算——清單裡還有認得的桌寵時事件仍然有用。
static func missing_pets(hat: Dictionary, known: Dictionary, self_tag: String) -> Array[String]:
	var missing: Array[String] = []
	if not str(hat.get("type", "")).begins_with("event_"):
		return missing
	var fields: Dictionary = hat.get("fields", {})
	for field in PET_FIELDS:
		var tag := str(fields.get(field, "")).strip_edges()
		if not _is_self(tag, self_tag) and not known.has(tag) and not missing.has(tag):
			missing.append(tag)
	var listed := split_tags(fields.get("TAGS", ""))
	if not listed.is_empty() and listed.all(func(tag: String) -> bool: return not _is_self(tag, self_tag) and not known.has(tag)):
		for tag in listed:
			if not missing.has(tag):
				missing.append(tag)
	return missing


## 這顆道具事件指到、但物品欄沒有的道具名稱(空白 = 任何道具,不算)。
static func missing_props(hat: Dictionary, known: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	if not str(hat.get("type", "")).begins_with("event_prop_"):
		return missing
	var prop := str((hat.get("fields", {}) as Dictionary).get("PROP", "")).strip_edges()
	if prop != "" and not known.has(prop):
		missing.append(prop)
	return missing


## 把這顆事件(連同底下所有積木)裡指向 old_ref 的地方改指到 new_ref。kind = "pet"(辨識代號)/ "prop"(道具名稱)。
## 直接改傳進來的字典,回傳改了幾處。
static func retarget(hat: Dictionary, kind: String, old_ref: String, new_ref: String) -> int:
	var changed := [0]
	if old_ref == "" or new_ref == "" or old_ref == new_ref:
		return 0
	LensChecker._walk(hat, func(block: Dictionary) -> void:
		if not block.get("fields") is Dictionary:
			return
		var fields: Dictionary = block["fields"]
		if kind == "prop":
			if str(fields.get("PROP", "")).strip_edges() == old_ref:
				fields["PROP"] = new_ref
				changed[0] += 1
			return
		var names: Array[String] = ["A_TAG", "B_TAG", "TARGET"]
		if PET_TAG_BLOCKS.has(str(block.get("type", ""))):
			names.append("TAG")
		for field in names:
			if str(fields.get(field, "")).strip_edges() == old_ref:
				fields[field] = new_ref
				changed[0] += 1
		var listed := split_tags(fields.get("TAGS", ""))
		if listed.has(old_ref):
			var replaced: Array[String] = []
			for tag in listed:
				var next := new_ref if tag == old_ref else tag
				if not replaced.has(next):
					replaced.append(next)
			fields["TAGS"] = ",".join(PackedStringArray(replaced))
			changed[0] += 1)
	return changed[0]


## 交互行為(InteractionRules)裡的引用改指:section = "characters"(遇見某角色說的話)/ "pet_prefs"(對某桌寵的好惡)/
## "props"(道具反應)。改傳進來的字典,回傳錯誤文字(空字串 = 成功)。改完要再過一次 InteractionRules.clean()
## (Pet.set_interaction_rules 會做):指到已經有設定的角色時,兩邊的台詞會併在一起。
static func retarget_rules(rules: Dictionary, section: String, old_ref: String, new_ref: String, new_name := "") -> String:
	if old_ref == "" or new_ref == "" or old_ref == new_ref:
		return "沒有可以改的對象"
	var key := "prop" if section == "props" else ("target" if section == "pet_prefs" else "tag")
	var entries: Array = rules.get(section, [])
	if section == "pet_prefs":
		for entry: Dictionary in entries:
			if str(entry.get(key, "")) == new_ref:
				return "那隻桌寵已經有設定好惡了"
	var found := false
	for entry: Dictionary in entries:
		if str(entry.get(key, "")) == old_ref:
			entry[key] = new_ref
			if section != "props":
				entry["name"] = new_name if new_name != "" else new_ref
			found = true
	return "" if found else "找不到要重新指向的項目"
