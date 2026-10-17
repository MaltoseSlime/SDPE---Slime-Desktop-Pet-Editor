class_name TagRename
extends RefCounted
## 2026-10-18 使用者要求:角色庫「變更辨識代號…」。辨識代號是其他桌寵認得這個角色的依據(好惡、⭐/🚫、遇見時的台詞、
## 對牠的好感度、積木裡指定牠的欄位都記代號),所以改代號時把這些引用一起改過去,改完大家照樣認得牠:
##  - 自己的 pack.json tag、自己積木檔的 recognitionTag。
##  - 角色庫每個角色(含自己)、庫外角色(user://profiles、user://logic)的檔案:交互行為的 characters / pet_prefs、
##    pet_favors、積木檔裡指到桌寵的欄位與 knownCharacters。
##  - 桌面上正在跑的桌寵:改記憶體裡的同一批資料再存檔(不然牠們之後存檔會把舊代號寫回去)。
## 限制:這個角色不能在桌面上、精靈圖編輯器不能開著它(同改名);桌寵管理視窗要先關(它存著「不儲存離開」用的快照,會把改動還原回去)。
## 改不到的:記憶槽備份(舊的存檔快照)、網頁積木編輯器瀏覽器裡存的角色名單、別人電腦上的角色。

const MAX_LENGTH := 40
const RESERVED: Array[String] = ["SELF", "user", "ALL"]
## 積木裡 TAG 欄位不一定是桌寵(閒聊情境、家具標籤):這些積木的 TAG 不動。
const NON_PET_TAG_TYPES: Array[String] = ["chat", "furniture", "keyword"]
const PET_FIELDS: Array[String] = ["A_TAG", "B_TAG", "TARGET", "SPEAKER", "WITH", "FROM"]


## 新代號有沒有問題;沒問題回空字串。
static func problem(folder: String, new_tag: String, tree: SceneTree) -> String:
	var tag := new_tag.strip_edges()
	if tag == "":
		return "代號不能是空的"
	if tag.length() > MAX_LENGTH:
		return TranslationServer.translate("代號太長了(最多 %d 個字)") % MAX_LENGTH
	if tag != tag.validate_filename() or tag.contains(",") or tag.begins_with("_") or tag.begins_with("."):
		return "代號不能有 , : / \\ ? * \" | % < > 這些符號,也不能用底線或點開頭"
	if tag in RESERVED:
		return TranslationServer.translate("「%s」是系統保留的代號,請換一個") % tag
	var old := SpriteLibrary.tag_of(folder)
	if tag == old:
		return "跟現在的代號一樣"
	if PetReferences.known_pets(tree).has(tag) or FileAccess.file_exists("user://profiles/%s.json" % tag):
		return TranslationServer.translate("已經有角色用「%s」這個代號了") % tag
	return ""


## 不能改的原因(角色在桌面上、編輯器開著、桌寵管理開著);可以改回空字串。
static func blocked_reason(folder: String, tree: SceneTree) -> String:
	var normalized := folder.replace("\\", "/").trim_suffix("/")
	for pet: Node in tree.get_nodes_in_group("pets"):
		if CharacterFiles.folder_of(pet) == normalized:
			return "桌面上還有這個角色,請先在系統匣把它移除"
	for window: Node in tree.get_nodes_in_group("floating_windows"):
		if window is ManagerWindow:
			return "請先關掉桌寵管理視窗"
		if window is PackEditorWindow and (window as PackEditorWindow)._model.has_pack() and ((window as PackEditorWindow)._model.root.replace("\\", "/").trim_suffix("/") + "/").begins_with(normalized + "/"):
			return "精靈圖編輯器正開著它,請先關掉編輯器(或切到別的角色)"
	return ""


## 改代號。回傳 {ok, error, files(改了幾個檔), pets(改了幾隻桌面上的桌寵)}。
static func apply(folder: String, new_tag: String, tree: SceneTree) -> Dictionary:
	var source := folder.replace("\\", "/").trim_suffix("/")
	var tag := new_tag.strip_edges()
	var error := blocked_reason(source, tree)
	if error == "":
		error = problem(source, tag, tree)
	if error != "":
		return {"ok": false, "error": error, "files": 0, "pets": 0}
	var old := SpriteLibrary.tag_of(source)
	var manifest := SpriteLibrary._read_manifest(source)
	manifest["tag"] = tag
	if not SpriteLibrary._write_manifest(source, manifest):
		return {"ok": false, "error": "無法寫入 pack.json", "files": 0, "pets": 0}
	# 桌面上的桌寵用到的檔案由記憶體版本存回去,不另外改檔。
	var live_files := {}
	var live_count := 0
	for pet: Node in tree.get_nodes_in_group("pets"):
		if not is_instance_valid(pet) or pet.is_queued_for_deletion():
			continue
		live_files[PetProfile.profile_path(pet)] = true
		live_files[PetRoster.logic_path(pet.recognition_tag, CharacterFiles.folder_of(pet))] = true
		if _retarget_live(pet, old, tag):
			live_count += 1
	var files := 0
	var profiles: Array[String] = []
	var logics: Array[String] = []
	for pack in SpriteLibrary.list_packs():
		profiles.append(CharacterFiles.profile_in(pack))
		logics.append(CharacterFiles.logic_in(pack))
	for name in DirAccess.get_files_at("user://profiles"):
		if name.ends_with(".json") and not name.ends_with("_state.json") and not name.begins_with("_"):
			profiles.append("user://profiles".path_join(name))
	for name in DirAccess.get_files_at("user://logic"):
		if name.ends_with(".logic.json"):
			logics.append("user://logic".path_join(name))
	for path in profiles:
		if not live_files.has(path) and _retarget_profile_file(path, old, tag):
			files += 1
	var own_logic := CharacterFiles.logic_in(source)
	for path in logics:
		if not live_files.has(path) and _retarget_logic_file(path, old, tag, path == own_logic):
			files += 1
	return {"ok": true, "error": "", "files": files, "pets": live_count}


## 交互行為規則裡指到 old 的(遇見台詞、好惡)改成 new;回傳改了幾處。顯示名稱不動。
static func retarget_rules(rules: Dictionary, old: String, new: String) -> int:
	var count := 0
	for section: String in ["characters", "pet_prefs"]:
		var key := "target" if section == "pet_prefs" else "tag"
		var entries: Variant = rules.get(section, [])
		if not entries is Array:
			continue
		for entry: Variant in entries:
			if entry is Dictionary and str((entry as Dictionary).get(key, "")) == old:
				(entry as Dictionary)[key] = new
				count += 1
	return count


## 好感度表的鍵 old → new(新代號本來就沒人用,不會撞)。
static func retarget_favors(favors: Dictionary, old: String, new: String) -> int:
	if not favors.has(old):
		return 0
	favors[new] = favors[old]
	favors.erase(old)
	return 1


## 一顆積木(連同底下)裡指到桌寵 old 的欄位改成 new;回傳改了幾處。
static func retarget_block(block: Dictionary, old: String, new: String) -> int:
	var changed := [PetReferences.retarget(block, "pet", old, new)]
	LensChecker._walk(block, func(inner: Dictionary) -> void:
		if not inner.get("fields") is Dictionary:
			return
		var fields: Dictionary = inner["fields"]
		var type := str(inner.get("type", ""))
		var names: Array[String] = PET_FIELDS.duplicate()
		if not NON_PET_TAG_TYPES.any(func(word: String) -> bool: return type.contains(word)):
			names.append("TAG")
		for field in names:
			if str(fields.get(field, "")).strip_edges() == old:
				fields[field] = new
				changed[0] += 1)
	return changed[0]


## 積木檔資料(Blockly 匯出格式)裡的引用;own = 這是改代號那個角色自己的檔(recognitionTag 也改)。
static func retarget_logic_data(data: Dictionary, old: String, new: String, own := false) -> int:
	var count := 0
	if own and str(data.get("recognitionTag", "")) == old:
		data["recognitionTag"] = new
		count += 1
	var workspace: Variant = data.get("workspaceState", {})
	var blocks: Variant = []
	if workspace is Dictionary:
		blocks = (workspace as Dictionary).get("blocks", [])
		if blocks is Dictionary:
			blocks = (blocks as Dictionary).get("blocks", [])
	if blocks is Array:
		for block: Variant in blocks:
			if block is Dictionary:
				count += retarget_block(block, old, new)
	var roster: Variant = data.get("knownCharacters")
	if roster is Array:
		for entry: Variant in roster:
			if entry is Dictionary and str((entry as Dictionary).get("recognitionTag", "")) == old:
				(entry as Dictionary)["recognitionTag"] = new
				count += 1
	return count


static func _retarget_live(pet: Node, old: String, new: String) -> bool:
	var changed := false
	var rules: Dictionary = (pet.interaction_rules as Dictionary).duplicate(true)
	if retarget_rules(rules, old, new) > 0:
		pet.set_interaction_rules(rules)
		changed = true
	if retarget_favors(pet.pet_favors, old, new) > 0:
		changed = true
	var logic: Variant = pet.get("logic")
	if logic != null:
		var count := 0
		for block: Variant in logic._top_blocks:
			if block is Dictionary:
				count += retarget_block(block, old, new)
		var known: Dictionary = logic._known_characters
		if known.has(old):
			var entry: Dictionary = known[old]
			entry["recognitionTag"] = new
			known.erase(old)
			known[new] = entry
			count += 1
		if count > 0:
			logic._reregister_all()
			logic.save_user_only_file(PetRoster.logic_path(pet.recognition_tag, CharacterFiles.folder_of(pet)))
			changed = true
	if changed:
		PetProfile.save_pet(pet)
	return changed


static func _retarget_profile_file(path: String, old: String, new: String) -> bool:
	var data := _read(path)
	if data.is_empty():
		return false
	var count := 0
	if data.get("interaction") is Dictionary:
		count += retarget_rules(data["interaction"], old, new)
	if data.get("pet_favors") is Dictionary:
		count += retarget_favors(data["pet_favors"], old, new)
	return count > 0 and _write(path, data)


static func _retarget_logic_file(path: String, old: String, new: String, own: bool) -> bool:
	var data := _read(path)
	return not data.is_empty() and retarget_logic_data(data, old, new, own) > 0 and _write(path, data)


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	return true
