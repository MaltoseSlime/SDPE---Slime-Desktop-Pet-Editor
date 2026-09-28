class_name PetVoice
extends RefCounted
## 桌寵的自訂說話聲音(對話打字機每輸出一個字播的那一聲):使用者可以為指定桌寵導入自己的音效檔,取代內建的 speak.ogg,
## 並微調音高(做出不同角色的聲線)與音量。
##
## 檔案處理(企劃書「匯入音效檔的格式驗證:毀損退回預設與靜音,絕不讓錯誤往上拋出至引擎崩潰」):
## - 只收 ogg / wav / mp3;大小上限 MAX_BYTES;長度上限 MAX_SECONDS(說話聲是每個字一聲的短音,太長只會糊成一團)。
## - 匯入時先實際解碼驗證,失敗就拒絕並回傳原因,不動原本的聲音。
## - 通過的檔案複製到 user://voices/<辨識代號>_<時間戳>.<副檔名>(複製一份,原檔被移動/刪除也不受影響),
##   設定檔只記檔名;載入時檔名一律驗證(不含路徑分隔字元與 ..),避免別人分享的設定檔指到任意路徑。
## - 沒有自訂檔、或自訂檔壞掉,一律退回內建說話音效。

const VOICE_DIR := "user://voices/"
const ALLOWED_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]
const MAX_BYTES := 1_000_000
const MAX_SECONDS := 3.0
const PITCH_RANGE := Vector2(0.5, 2.0)


## 導入一個聲音檔給指定桌寵(同辨識代號的桌寵一起套用)。回傳 {ok: bool, message: String}。
static func import_file(pet: Node, source_path: String) -> Dictionary:
	var extension := source_path.get_extension().to_lower()
	if not ALLOWED_EXTENSIONS.has(extension):
		return {"ok": false, "message": "只支援 ogg、wav、mp3 檔案。"}
	var file := FileAccess.open(source_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "無法開啟這個檔案。"}
	if file.get_length() > MAX_BYTES:
		return {"ok": false, "message": TranslationServer.translate("檔案太大了(上限 %d KB),請將音檔修剪或壓縮後再嘗試。") % (MAX_BYTES / 1000)}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var stream := decode(bytes, extension)
	if stream == null:
		return {"ok": false, "message": "這個檔案無法解碼,可能已經毀損或格式不正確。"}
	if stream.get_length() > MAX_SECONDS:
		return {"ok": false, "message": TranslationServer.translate("音檔時間太長了(%.1f 秒,上限 %.0f 秒);請用更簡短的音效。") % [stream.get_length(), MAX_SECONDS]}
	DirAccess.make_dir_recursive_absolute(VOICE_DIR)
	var file_name := "%s_%d.%s" % [_safe_tag(pet), Time.get_unix_time_from_system(), extension]
	var target := FileAccess.open(VOICE_DIR + file_name, FileAccess.WRITE)
	if target == null:
		return {"ok": false, "message": "無法儲存音檔,請檢查磁碟空間或權限。"}
	target.store_buffer(bytes)
	target.close()
	apply_to_same_character(pet, file_name, stream)
	return {"ok": true, "message": TranslationServer.translate("已導入(%.2f 秒)。") % stream.get_length()}


## 位元組 → AudioStream;失敗回傳 null。不依賴檔案路徑,所以「使用者選的檔」與「複製後的檔」走同一套解碼。
static func decode(bytes: PackedByteArray, extension: String) -> AudioStream:
	if bytes.is_empty():
		return null
	var stream: AudioStream = null
	match extension:
		"ogg":
			stream = AudioStreamOggVorbis.load_from_buffer(bytes)
		"mp3":
			var mp3 := AudioStreamMP3.new()
			mp3.data = bytes
			stream = mp3
		"wav":
			stream = AudioStreamWAV.load_from_buffer(bytes)
	if stream == null or stream.get_length() <= 0.0:
		return null
	return stream


## 讀取已存的檔名並解碼;檔名不合法、檔案不存在或壞掉回傳 null(呼叫端退回內建聲音)。
static func load_stream(file_name: String) -> AudioStream:
	if not is_valid_file_name(file_name):
		return null
	var path := VOICE_DIR + file_name
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() > MAX_BYTES:
		return null
	return decode(bytes, file_name.get_extension().to_lower())


static func is_valid_file_name(file_name: String) -> bool:
	return file_name != "" and file_name == file_name.get_file() and not file_name.contains("..") \
			and not file_name.contains("/") and not file_name.contains("\\") \
			and ALLOWED_EXTENSIONS.has(file_name.get_extension().to_lower())


## 套用到所有同辨識代號的桌寵(同一個角色在場好幾隻時,聲音應該一致)。stream 為 null 表示清除自訂聲音。
static func apply_to_same_character(pet: Node, file_name: String, stream: AudioStream) -> void:
	for other: Node in pet.get_tree().get_nodes_in_group("pets"):
		if other == pet or _same_character(other, pet):
			other.voice_file = file_name
			other.voice_stream = stream


static func clear(pet: Node) -> void:
	apply_to_same_character(pet, "", null)


## 儲存後清理:這個角色目錄裡沒被採用的舊聲音檔(重新導入、清除後留下的)全部刪掉。
static func cleanup(pet: Node) -> void:
	var directory := DirAccess.open(VOICE_DIR)
	if directory == null:
		return
	var prefix := _safe_tag(pet) + "_"
	for file_name in directory.get_files():
		if file_name.begins_with(prefix) and file_name != pet.voice_file:
			directory.remove(file_name)


## 從設定檔的 voice 區段套用(音高/音量夾在合法範圍,檔名驗證後才載入)。
static func apply_profile(pet: Node, data: Variant) -> void:
	if not data is Dictionary:
		return
	pet.voice_pitch = clampf(_number(data.get("pitch"), pet.voice_pitch), PITCH_RANGE.x, PITCH_RANGE.y)
	pet.voice_volume = clampf(_number(data.get("volume"), pet.voice_volume), 0.0, 1.0)
	var file_name := str(data.get("file", ""))
	if file_name != pet.voice_file or pet.voice_stream == null:
		pet.voice_file = file_name if is_valid_file_name(file_name) else ""
		pet.voice_stream = load_stream(pet.voice_file) if pet.voice_file != "" else null
		if pet.voice_stream == null:
			pet.voice_file = ""


static func to_dict(pet: Node) -> Dictionary:
	return {"file": pet.voice_file, "pitch": pet.voice_pitch, "volume": pet.voice_volume}


static func _same_character(a: Node, b: Node) -> bool:
	return a.recognition_tag != "" and a.recognition_tag == b.recognition_tag


static func _safe_tag(pet: Node) -> String:
	var tag: String = pet.recognition_tag if pet.recognition_tag != "" else pet.display_name
	return tag.validate_filename().replace(" ", "_")


static func _number(value: Variant, fallback: float) -> float:
	return float(value) if value is float or value is int else fallback
