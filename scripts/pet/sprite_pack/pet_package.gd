class_name PetPackage
extends RefCounted
## 角色分享包(.pet):把一個角色(素材包 + 角色設定 + 積木檔,可選記憶與戰績)壓成一個檔,方便分享與備份。
## 檔案其實是 ZIP,裡面只有資料(圖片、音效、JSON),沒有任何可執行的內容:
##   manifest.json             {fileType: "slime_pet_package", packageVersion: 1, name, tag, exportedAt, includes: {state, logic}}
##   pack/…                    素材包資料夾的內容(pack.json、圖片、overlays.json、說話聲音…)
##   character/profile.json    角色設定(數值定義、狀態鏡、介面風格、性格副本、關鍵詞庫…)
##   character/logic.json      導入過的積木檔(選填)
##   character/state.json      執行狀態:數值目前的值、記憶、戰績(選填,匯出時預設不含)
## 匯入時把「不信任的檔案」當成危險輸入處理:先只讀 ZIP 的目錄(不解壓)驗證——路徑不可含 .. / 絕對路徑 / 磁碟代號 / 反斜線 / 控制字元、
## 只認 manifest.json、pack/、character/ 三處、副檔名白名單、檔案數與大小上限(單檔、總量、壓縮比,防「解壓炸彈」)、不支援 ZIP64、重複名稱與大小寫撞名一律拒絕;
## 通過才解壓到暫存資料夾,再逐一確認實際大小與宣告的一致,JSON 都要能解析成字典,最後才搬進角色庫。任何一步失敗都不會留下半成品。
## 辨識代號和角色庫裡現有的角色撞名時,匯入成一個獨立的新角色(換新的辨識代號),不會覆蓋任何現有角色。

const EXTENSION := "pet"
const FORMAT := "slime_pet_package"
const VERSION := 1
const MANIFEST := "manifest.json"
const PACK_PREFIX := "pack/"
const CHARACTER_PREFIX := "character/"
const CHARACTER_FILES: Array[String] = ["profile.json", "logic.json", "state.json"]
const MAX_PACKAGE_BYTES := 300_000_000
const MAX_FILES := 3000
const MAX_TOTAL_BYTES := 500_000_000
const MAX_FILE_BYTES := 80_000_000
const MAX_JSON_BYTES := 5_000_000
const MAX_RATIO := 200
const MAX_PATH_LENGTH := 200
const MAX_DEPTH := 8
## pack/ 裡允許的副檔名(圖片、音效、資料、說明)。
const PACK_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "json", "ogg", "wav", "mp3", "txt", "md"]
const RESERVED := ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3"]
const TEMP_ROOT := "user://pet_import_tmp"
## 角色資料夾以外、但屬於這個角色的東西(2026-10-11 補):為了讓舊版程式也讀得了新版匯出的 .pet,不新增壓縮檔裡的位置,
## 借現有的兩處帶著走,匯入時再放回原本的地方——
##  - 自訂說話聲音(user://voices/ 的音檔,見 PetVoice):放成 pack/_character_voice.<副檔名>;匯入後搬回 user://voices/ 並改寫設定檔裡的檔名。
##  - 記憶存檔的 5 格(user://memory_slots/<辨識代號>.json,見 MemorySlots):勾了「包含記憶與戰績」才帶,塞在 state.json 的 memorySlots 欄位;
##    匯入後寫回 user://memory_slots/ 並從 state.json 拿掉。
## 舊版程式匯入時這兩樣只是用不到(多一個沒人讀的音檔 / 欄位),不會壞。
const VOICE_ENTRY_BASE := "_character_voice"
const MEMORY_SLOTS_KEY := "memorySlots"


# --- 匯出 ---

## 建議的檔名(角色名稱 + .pet)。
static func suggested_name(folder: String) -> String:
	var manifest := SpriteLibrary._read_manifest(folder)
	var base := str(manifest.get("name", "")).strip_edges()
	if base == "":
		base = folder.replace("\\", "/").trim_suffix("/").get_file()
	return SpriteLibrary.folder_name_for(base) + "." + EXTENSION


## 把角色庫裡的一個角色匯出成 .pet。options:{include_state: false, include_logic: true}。
## 回傳 {ok, error, files, bytes, skipped:[不收的檔案], included:{profile, logic, state, voice, memory_slots}}。先寫成 .tmp 再改名,失敗不會留下壞檔。
static func export_package(folder: String, out_path: String, options := {}) -> Dictionary:
	var source := folder.replace("\\", "/").trim_suffix("/")
	var report := {"ok": false, "error": "", "files": 0, "bytes": 0, "skipped": [], "included": {"profile": false, "logic": false, "state": false, "voice": false, "memory_slots": false}}
	if not DirAccess.dir_exists_absolute(source):
		report["error"] = "找不到角色資料夾"
		return report
	if out_path.get_extension().to_lower() != EXTENSION:
		out_path += "." + EXTENSION
	var manifest_source := SpriteLibrary._read_manifest(source)
	var name := str(manifest_source.get("name", source.get_file())).strip_edges().left(SpriteLibrary.MAX_NAME)
	var tag := SpriteLibrary.tag_of(source)
	var want_state := bool(options.get("include_state", false))
	var want_logic := bool(options.get("include_logic", true))
	var temp_path := out_path + ".tmp"
	var packer := ZIPPacker.new()
	if packer.open(temp_path) != OK:
		report["error"] = TranslationServer.translate("無法寫入:%s") % out_path
		return report
	var state := {"failure": ""}   # lambda 只帶得走值的複本,要改的東西放進字典
	var written := {}
	var add := func(entry_name: String, bytes: PackedByteArray) -> bool:
		if written.has(entry_name.to_lower()):
			return true
		written[entry_name.to_lower()] = true
		if packer.start_file(entry_name) != OK or packer.write_file(bytes) != OK or packer.close_file() != OK:
			state["failure"] = TranslationServer.translate("寫入失敗:%s") % entry_name
			return false
		report["files"] += 1
		report["bytes"] += bytes.size()
		return true
	# 素材包
	for relative in _list_files(source, ""):
		if relative.begins_with(CharacterFiles.SUBDIR + "/") or relative.ends_with(".bak") or relative.get_basename() == VOICE_ENTRY_BASE:
			continue
		var extension := relative.get_extension().to_lower()
		if not PACK_EXTENSIONS.has(extension) or entry_problem(PACK_PREFIX + relative, true) != "":
			(report["skipped"] as Array).append(relative)
			continue
		var size := FileAccess.get_size(source.path_join(relative))
		if size > MAX_FILE_BYTES or (report["bytes"] as int) + size > MAX_TOTAL_BYTES:
			(report["skipped"] as Array).append(relative)
			continue
		if not add.call(PACK_PREFIX + relative, FileAccess.get_file_as_bytes(source.path_join(relative))):
			break
	# 角色設定(角色資料夾裡的優先,沒有就找舊位置)
	if state["failure"] == "":
		var legacy := CharacterFiles.legacy_paths(tag)
		var sources := {"profile.json": [CharacterFiles.profile_in(source), legacy[0]], "state.json": [CharacterFiles.state_in(source), legacy[1]], "logic.json": [CharacterFiles.logic_in(source), legacy[2]]}
		var wanted := {"profile.json": true, "logic.json": want_logic, "state.json": want_state}
		for file_name: String in CHARACTER_FILES:
			if not wanted[file_name]:
				continue
			for candidate: String in sources[file_name]:
				if FileAccess.file_exists(candidate) and FileAccess.get_size(candidate) <= MAX_JSON_BYTES:
					var bytes := FileAccess.get_file_as_bytes(candidate)
					if file_name == "profile.json":
						var voice := _voice_file_of(bytes)
						if voice != "" and add.call(PACK_PREFIX + VOICE_ENTRY_BASE + "." + voice.get_extension().to_lower(), FileAccess.get_file_as_bytes(PetVoice.VOICE_DIR + voice)):
							report["included"]["voice"] = true
					elif file_name == "state.json":
						var with_slots := _state_with_memory_slots(bytes, tag)
						if not with_slots.is_empty():
							bytes = with_slots
							report["included"]["memory_slots"] = true
					if not add.call(CHARACTER_PREFIX + file_name, bytes):
						break
					report["included"][file_name.trim_suffix(".json")] = true
					break
			if state["failure"] != "":
				break
	if state["failure"] == "":
		var manifest := {"fileType": FORMAT, "packageVersion": VERSION, "name": name, "tag": tag, "exportedAt": Time.get_datetime_string_from_system(),
				"includes": {"logic": bool(report["included"]["logic"]), "state": bool(report["included"]["state"]), "profile": bool(report["included"]["profile"])}}
		add.call(MANIFEST, JSON.stringify(manifest, "  ").to_utf8_buffer())
	packer.close()
	if state["failure"] != "":
		DirAccess.remove_absolute(temp_path)
		report["error"] = state["failure"]
		return report
	if FileAccess.file_exists(out_path):
		DirAccess.remove_absolute(out_path)
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(out_path)) != OK:
		DirAccess.remove_absolute(temp_path)
		report["error"] = TranslationServer.translate("無法寫入:%s") % out_path
		return report
	report["ok"] = true
	return report


## 設定檔(profile.json 的內容)用的自訂說話聲音檔名;沒有、檔名不合法、檔案不在或太大回空字串。
static func _voice_file_of(profile_bytes: PackedByteArray) -> String:
	var parsed: Variant = JSON.parse_string(profile_bytes.get_string_from_utf8())
	if not parsed is Dictionary or not parsed.get("voice") is Dictionary:
		return ""
	var file_name := str(parsed["voice"].get("file", ""))
	if not PetVoice.is_valid_file_name(file_name) or not FileAccess.file_exists(PetVoice.VOICE_DIR + file_name):
		return ""
	return file_name if FileAccess.get_size(PetVoice.VOICE_DIR + file_name) <= PetVoice.MAX_BYTES else ""


## 把這個角色的記憶存檔格子塞進 state.json 的內容;沒有存檔格子(或讀不了)回空陣列 = 照原樣放。
static func _state_with_memory_slots(state_bytes: PackedByteArray, tag: String) -> PackedByteArray:
	var slots_path := "%s%s.json" % [MemorySlots.DIR, tag.validate_filename()]
	if not FileAccess.file_exists(slots_path) or FileAccess.get_size(slots_path) > MAX_JSON_BYTES:
		return PackedByteArray()
	var slots: Variant = JSON.parse_string(FileAccess.get_file_as_string(slots_path))
	var state: Variant = JSON.parse_string(state_bytes.get_string_from_utf8())
	if not slots is Dictionary or not slots.get("slots") is Array or not state is Dictionary:
		return PackedByteArray()
	state[MEMORY_SLOTS_KEY] = slots["slots"]
	var bytes := JSON.stringify(state, "  ").to_utf8_buffer()
	return bytes if bytes.size() <= MAX_JSON_BYTES else PackedByteArray()


## 匯入後:把跟著素材包進來的說話聲音搬回 user://voices/(檔名用新的辨識代號),並改寫設定檔裡的檔名。
## 音檔要先解得開、長度大小合規才收(跟使用者自己導入聲音同一套檢查,見 PetVoice.import_file);不合格就丟掉,桌寵用內建聲音。
static func _restore_voice(folder: String, tag: String) -> void:
	for extension in PetVoice.ALLOWED_EXTENSIONS:
		var bundled := folder.path_join(VOICE_ENTRY_BASE + "." + extension)
		if not FileAccess.file_exists(bundled):
			continue
		var bytes := FileAccess.get_file_as_bytes(bundled)
		DirAccess.remove_absolute(bundled)
		var stream := PetVoice.decode(bytes, extension) if bytes.size() <= PetVoice.MAX_BYTES else null
		if stream == null or stream.get_length() > PetVoice.MAX_SECONDS:
			continue
		var file_name := "%s_%d.%s" % [tag.validate_filename().replace(" ", "_"), int(Time.get_unix_time_from_system()), extension]
		DirAccess.make_dir_recursive_absolute(PetVoice.VOICE_DIR)
		var out := FileAccess.open(PetVoice.VOICE_DIR + file_name, FileAccess.WRITE)
		if out == null:
			continue
		out.store_buffer(bytes)
		out.close()
		var profile_path := CharacterFiles.profile_in(folder)
		var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(profile_path)) if FileAccess.file_exists(profile_path) else null
		if profile is Dictionary and profile.get("voice") is Dictionary:
			profile["voice"]["file"] = file_name
			var file := FileAccess.open(profile_path, FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify(profile, "  "))
				file.close()
		return


## 匯入後:state.json 裡帶著的記憶存檔格子寫回 user://memory_slots/<辨識代號>.json(那裡已經有檔就不蓋),並從 state.json 拿掉。
## 內容不在這裡驗證:MemorySlots.read_all() 讀的時候本來就逐格驗證。
static func _restore_memory_slots(folder: String, tag: String) -> void:
	var state_path := CharacterFiles.state_in(folder)
	if not FileAccess.file_exists(state_path):
		return
	var state: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
	if not state is Dictionary or not state.has(MEMORY_SLOTS_KEY):
		return
	var slots: Variant = state[MEMORY_SLOTS_KEY]
	state.erase(MEMORY_SLOTS_KEY)
	var file := FileAccess.open(state_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(state, "  "))
		file.close()
	var slots_path := "%s%s.json" % [MemorySlots.DIR, tag.validate_filename()]
	if not slots is Array or FileAccess.file_exists(slots_path):
		return
	DirAccess.make_dir_recursive_absolute(MemorySlots.DIR)
	var out := FileAccess.open(slots_path, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"slots": (slots as Array).slice(0, MemorySlots.SLOT_COUNT)}, "\t"))
		out.close()


## 資料夾裡所有檔案的相對路徑(用 /),遞迴。
static func _list_files(root: String, relative: String) -> Array[String]:
	var result: Array[String] = []
	var current := root.path_join(relative) if relative != "" else root
	if not DirAccess.dir_exists_absolute(current):
		return result
	for file_name in DirAccess.get_files_at(current):
		result.append(file_name if relative == "" else relative + "/" + file_name)
	for sub in DirAccess.get_directories_at(current):
		result.append_array(_list_files(root, sub if relative == "" else relative + "/" + sub))
	return result


# --- 驗證 ---

## 一個壓縮檔內的路徑有沒有問題;沒問題回空字串。in_pack = true 時只檢查檔名本身(給匯出用,已經在 pack/ 底下)。
static func entry_problem(entry_name: String, in_pack := false) -> String:
	if entry_name == "" or entry_name.length() > MAX_PATH_LENGTH:
		return "路徑是空的或太長"
	if entry_name.begins_with("/") or "\\" in entry_name or ":" in entry_name:
		return "路徑不能是絕對路徑,也不能含反斜線或磁碟代號"
	for i in entry_name.length():
		var code := entry_name.unicode_at(i)
		if code < 32 or code == 127:
			return "路徑含控制字元"
	var segments := entry_name.trim_suffix("/").split("/")
	if segments.size() > MAX_DEPTH:
		return "資料夾太深"
	for segment in segments:
		if segment == "" or segment == "." or segment == ".." or segment.length() > 100:
			return "路徑含不合法的段落(空的、. 或 ..)"
		if segment.ends_with(" ") or segment.ends_with(".") or segment.begins_with(" "):
			return "檔名開頭結尾不能是空白或句點"
		for bad in ["<", ">", "\"", "|", "?", "*"]:
			if bad in segment:
				return "檔名含不能用的符號"
		if segment.get_basename().to_upper() in RESERVED:
			return "檔名是系統保留字"
	return ""


## 只讀 ZIP 的目錄(不解壓):回傳 {ok, error, entries:[{name, size, compressed, method, is_dir}]}。
## 檔案大小、數量與 ZIP64 都在這裡先擋,避免壓縮炸彈。
static func read_directory(path: String) -> Dictionary:
	var fail := func(message: String) -> Dictionary: return {"ok": false, "error": message, "entries": []}
	if not FileAccess.file_exists(path):
		return fail.call(TranslationServer.translate("找不到檔案:%s") % path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fail.call(TranslationServer.translate("讀不了檔案:%s") % path)
	var length := file.get_length()
	if length < 22:
		return fail.call("這不是有效的 .pet 檔(太小了)")
	if length > MAX_PACKAGE_BYTES:
		return fail.call(TranslationServer.translate("檔案太大了(超過 %d MB)") % (MAX_PACKAGE_BYTES / 1_000_000))
	var tail_length := mini(length, 65557)
	file.seek(length - tail_length)
	var tail := file.get_buffer(tail_length)
	var eocd := -1
	for i in range(tail.size() - 22, -1, -1):
		if tail.decode_u32(i) == 0x06054b50:
			eocd = i
			break
	if eocd < 0:
		return fail.call("這不是有效的 .pet 檔(找不到壓縮檔目錄)")
	var count := tail.decode_u16(eocd + 10)
	var directory_size := tail.decode_u32(eocd + 12)
	var directory_offset := tail.decode_u32(eocd + 16)
	if count == 0xFFFF or directory_size == 0xFFFFFFFF or directory_offset == 0xFFFFFFFF:
		return fail.call("不支援 ZIP64 格式的檔案")
	if count > MAX_FILES + 2:
		return fail.call(TranslationServer.translate("檔案數量太多了(超過 %d 個)") % MAX_FILES)
	if directory_offset + directory_size > length or directory_size > 2_000_000:
		return fail.call("這不是有效的 .pet 檔(目錄範圍不正確)")
	file.seek(directory_offset)
	var directory := file.get_buffer(directory_size)
	var entries: Array[Dictionary] = []
	var position := 0
	for i in count:
		if position + 46 > directory.size() or directory.decode_u32(position) != 0x02014b50:
			return fail.call("這不是有效的 .pet 檔(目錄項目損壞)")
		var flags := directory.decode_u16(position + 8)
		var method := directory.decode_u16(position + 10)
		var compressed := directory.decode_u32(position + 20)
		var size := directory.decode_u32(position + 24)
		var name_length := directory.decode_u16(position + 28)
		var extra_length := directory.decode_u16(position + 30)
		var comment_length := directory.decode_u16(position + 32)
		if position + 46 + name_length > directory.size():
			return fail.call("這不是有效的 .pet 檔(檔名超出範圍)")
		if compressed == 0xFFFFFFFF or size == 0xFFFFFFFF:
			return fail.call("不支援 ZIP64 格式的檔案")
		if flags & 1:
			return fail.call("不支援加密的壓縮檔")
		var entry_name := directory.slice(position + 46, position + 46 + name_length).get_string_from_utf8()
		entries.append({"name": entry_name, "size": size, "compressed": compressed, "method": method, "is_dir": entry_name.ends_with("/")})
		position += 46 + name_length + extra_length + comment_length
	return {"ok": true, "error": "", "entries": entries}


## 檢查一份 .pet(不解壓):回傳 {ok, error, manifest, files, bytes, has_state, has_logic, has_profile, entries(要解壓的檔案)}。
static func inspect(path: String) -> Dictionary:
	var result := {"ok": false, "error": "", "manifest": {}, "files": 0, "bytes": 0, "has_state": false, "has_logic": false, "has_profile": false, "entries": []}
	var directory := read_directory(path)
	if not bool(directory["ok"]):
		result["error"] = directory["error"]
		return result
	var seen := {}
	var pack_files := 0
	var total := 0
	for entry: Dictionary in directory["entries"]:
		var entry_name: String = entry["name"]
		var problem := entry_problem(entry_name)
		if problem != "":
			result["error"] = TranslationServer.translate("檔案「%s」不安全:%s") % [entry_name.left(60), TranslationServer.translate(problem)]
			return result
		if bool(entry["is_dir"]):
			continue
		if seen.has(entry_name.to_lower()):
			result["error"] = TranslationServer.translate("有重複的檔名:%s") % entry_name.left(60)
			return result
		seen[entry_name.to_lower()] = true
		var size: int = entry["size"]
		if int(entry["method"]) != 0 and int(entry["method"]) != 8:
			result["error"] = "壓縮方式不支援"
			return result
		if size > MAX_FILE_BYTES or (size > 1_000_000 and size > int(entry["compressed"]) * MAX_RATIO):
			result["error"] = TranslationServer.translate("檔案「%s」大得不合理,已拒絕") % entry_name.left(60)
			return result
		total += size
		if total > MAX_TOTAL_BYTES:
			result["error"] = TranslationServer.translate("解壓後總量太大了(超過 %d MB)") % (MAX_TOTAL_BYTES / 1_000_000)
			return result
		if entry_name == MANIFEST:
			if size > MAX_JSON_BYTES:
				result["error"] = "manifest.json 太大"
				return result
		elif entry_name.begins_with(PACK_PREFIX):
			var relative := entry_name.trim_prefix(PACK_PREFIX)
			if relative.begins_with(CharacterFiles.SUBDIR + "/") or not PACK_EXTENSIONS.has(relative.get_extension().to_lower()):
				result["error"] = TranslationServer.translate("素材包裡有不允許的檔案:%s(只接受圖片、音效、JSON 與文字檔)") % relative.left(60)
				return result
			if relative.get_extension().to_lower() == "json" and size > MAX_JSON_BYTES:
				result["error"] = TranslationServer.translate("素材包裡的 JSON 太大:%s") % relative.left(60)
				return result
			pack_files += 1
		elif entry_name.begins_with(CHARACTER_PREFIX) and CHARACTER_FILES.has(entry_name.trim_prefix(CHARACTER_PREFIX)):
			if size > MAX_JSON_BYTES:
				result["error"] = TranslationServer.translate("%s 太大") % entry_name
				return result
			result["has_" + entry_name.trim_prefix(CHARACTER_PREFIX).trim_suffix(".json")] = true
		else:
			result["error"] = TranslationServer.translate("有不認得的內容:%s(.pet 只能有 manifest.json、pack/、character/)") % entry_name.left(60)
			return result
		(result["entries"] as Array).append(entry)
	if not seen.has(MANIFEST):
		result["error"] = "這不是角色分享包(沒有 manifest.json)"
		return result
	if pack_files == 0:
		result["error"] = "這個分享包裡沒有素材(pack/ 是空的)"
		return result
	var manifest_read := _read_zip_json(path, MANIFEST)
	if not bool(manifest_read["ok"]):
		result["error"] = manifest_read["error"]
		return result
	var manifest: Dictionary = manifest_read["data"]
	if str(manifest.get("fileType", "")) != FORMAT:
		result["error"] = "這不是角色分享包(fileType 不對)"
		return result
	var version: Variant = manifest.get("packageVersion")
	if not (version is float or version is int) or int(version) < 1 or int(version) > VERSION:
		result["error"] = TranslationServer.translate("這個分享包的版本(%s)這個程式不認得,請更新程式後再試") % str(version)
		return result
	result["manifest"] = {"name": PetText.sanitize(str(manifest.get("name", "")), SpriteLibrary.MAX_NAME), "tag": str(manifest.get("tag", "")).strip_edges().left(SpriteLibrary.MAX_NAME),
			"exportedAt": str(manifest.get("exportedAt", "")).left(40)}
	result["files"] = pack_files
	result["bytes"] = total
	result["ok"] = true
	return result


static func _read_zip_json(path: String, entry_name: String) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"ok": false, "error": "讀不了這個檔案(不是有效的壓縮檔)", "data": {}}
	var bytes := reader.read_file(entry_name)
	reader.close()
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
		return {"ok": false, "error": TranslationServer.translate("%s 不是有效的 JSON") % entry_name, "data": {}}
	return {"ok": true, "error": "", "data": json.data}


# --- 匯入 ---

## 角色庫裡有沒有辨識代號和這個一樣的角色(不分大小寫);有就回那個資料夾。
static func folder_with_tag(tag: String) -> String:
	if tag.strip_edges() == "":
		return ""
	for folder in SpriteLibrary.list_packs():
		if SpriteLibrary.tag_of(folder).to_lower() == tag.to_lower():
			return folder
	return ""


## 匯入一份 .pet 成為角色庫裡的新角色。display_name = 使用者取的名字(空白 = 用分享包裡的名字);options:{include_state: true}(分享包有記憶與戰績時是否一起匯入)。
## 回傳 {ok, error, folder, tag, tag_changed, name}。
static func import_package(path: String, display_name := "", options := {}) -> Dictionary:
	var fail := func(message: String) -> Dictionary: return {"ok": false, "error": message, "folder": "", "tag": "", "tag_changed": false, "name": ""}
	var info := inspect(path)
	if not bool(info["ok"]):
		return fail.call(info["error"])
	var manifest: Dictionary = info["manifest"]
	var wanted_name := display_name.strip_edges() if display_name.strip_edges() != "" else str(manifest["name"])
	if wanted_name == "":
		wanted_name = path.get_file().get_basename()
	var problem := SpriteLibrary.name_problem(wanted_name)
	if problem != "":
		return fail.call(problem)
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return fail.call("讀不了這個檔案(不是有效的壓縮檔)")
	# ZIP 目錄與實際內容要一致:讀出來的檔名集合不能多出目錄檢查過的那些。
	var declared := {}
	for entry: Dictionary in info["entries"]:
		declared[entry["name"]] = entry
	for actual in reader.get_files():
		if not bool(actual.ends_with("/")) and not declared.has(actual):
			reader.close()
			return fail.call(TranslationServer.translate("壓縮檔內容和目錄不一致:%s") % str(actual).left(60))
	var stamp := "%d_%d" % [Time.get_ticks_msec(), randi() % 100000]
	var staging := ProjectSettings.globalize_path(TEMP_ROOT).replace("\\", "/").path_join(stamp)
	var pack_dir := staging.path_join("pack")
	var character_dir := staging.path_join("character")
	if DirAccess.make_dir_recursive_absolute(pack_dir) != OK or DirAccess.make_dir_recursive_absolute(character_dir) != OK:
		reader.close()
		return fail.call(TranslationServer.translate("無法建立資料夾:%s") % staging)
	var include_state := bool(options.get("include_state", true))
	var extract_error := ""
	for entry: Dictionary in info["entries"]:
		var entry_name: String = entry["name"]
		if entry_name == MANIFEST or (entry_name == CHARACTER_PREFIX + "state.json" and not include_state):
			continue
		var bytes := reader.read_file(entry_name)
		if bytes.size() != int(entry["size"]):
			extract_error = TranslationServer.translate("檔案「%s」的實際大小和目錄不符,已拒絕") % entry_name.left(60)
			break
		var target := staging.path_join(entry_name) if entry_name.begins_with(CHARACTER_PREFIX) else pack_dir.path_join(entry_name.trim_prefix(PACK_PREFIX))
		if entry_name.begins_with(CHARACTER_PREFIX) or entry_name.get_extension().to_lower() == "json":
			var json := JSON.new()
			if json.parse(bytes.get_string_from_utf8()) != OK or not json.data is Dictionary:
				if entry_name.begins_with(CHARACTER_PREFIX) or entry_name.trim_prefix(PACK_PREFIX) == "pack.json":
					extract_error = TranslationServer.translate("%s 不是有效的 JSON 字典,已拒絕") % entry_name
					break
		if DirAccess.make_dir_recursive_absolute(target.get_base_dir()) != OK:
			extract_error = TranslationServer.translate("無法建立資料夾:%s") % target.get_base_dir()
			break
		var out := FileAccess.open(target, FileAccess.WRITE)
		if out == null:
			extract_error = TranslationServer.translate("無法寫入:%s") % entry_name.left(60)
			break
		out.store_buffer(bytes)
		out.close()
	reader.close()
	if extract_error != "":
		SpriteLibrary._remove_folder(staging)
		return fail.call(extract_error)
	# 辨識代號:撞名(或分享包沒寫)就用新資料夾名當新的辨識代號。
	var target_folder := SpriteLibrary.unique_folder(SpriteLibrary.folder_name_for(wanted_name))
	var pack_manifest := SpriteLibrary._read_manifest(pack_dir)
	var tag := str(pack_manifest.get("tag", manifest.get("tag", ""))).strip_edges()
	var tag_changed := false
	if tag == "" or folder_with_tag(tag) != "" or tag.validate_filename() != tag:
		tag = target_folder.get_file()
		tag_changed = true
		if folder_with_tag(tag) != "":
			tag += "_" + str(randi() % 10000)
	pack_manifest["name"] = wanted_name.left(SpriteLibrary.MAX_NAME)
	pack_manifest["tag"] = tag
	if not SpriteLibrary._write_manifest(pack_dir, pack_manifest):
		SpriteLibrary._remove_folder(staging)
		return fail.call("無法寫入 pack.json")
	# 搬進角色庫:素材包整個改名成角色資料夾,角色設定放進 character/。
	if DirAccess.rename_absolute(pack_dir, target_folder) != OK:
		SpriteLibrary._remove_folder(staging)
		return fail.call(TranslationServer.translate("無法建立角色資料夾:%s") % target_folder)
	var move_error := ""
	if not DirAccess.get_files_at(character_dir).is_empty():
		DirAccess.make_dir_recursive_absolute(target_folder.path_join(CharacterFiles.SUBDIR))
		for file_name in DirAccess.get_files_at(character_dir):
			if DirAccess.rename_absolute(character_dir.path_join(file_name), target_folder.path_join(CharacterFiles.SUBDIR).path_join(file_name)) != OK:
				move_error = TranslationServer.translate("無法放入角色設定:%s") % file_name
				break
	SpriteLibrary._remove_folder(staging)
	if move_error != "":
		SpriteLibrary._remove_folder(target_folder)
		return fail.call(move_error)
	_restore_voice(target_folder, tag)
	_restore_memory_slots(target_folder, tag)
	return {"ok": true, "error": "", "folder": target_folder, "tag": tag, "tag_changed": tag_changed, "name": wanted_name}
