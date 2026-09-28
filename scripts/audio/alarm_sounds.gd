class_name AlarmSounds
extends RefCounted
## 使用者自己上傳/匯入的提醒音效(桌寵計時器鈴聲用):不綁定特定桌寵,全局設定「音效」分頁匯入一次,
## 任何桌寵的「計時提醒音效」右鍵選單都選得到,跟內建音效(SoundManager.BUILTIN_SOUNDS)並列。
## 檔案處理原則比照 PetVoice(自訂說話聲音):只收 ogg/wav/mp3、大小與長度上限、匯入時先實際解碼驗證,
## 壞掉的檔案一律拒絕,不動音效庫;解碼直接借用 PetVoice.decode(),兩邊格式驗證邏輯不用重複一份。

const ALARM_DIR := "user://alarm_sounds/"
const ALLOWED_EXTENSIONS: Array[String] = ["ogg", "wav", "mp3"]
const MAX_BYTES := 2_000_000
## 提醒音效比說話聲(PetVoice,3 秒)長一點沒關係,但太長的鈴聲用起來很吵,一樣夾個上限。
const MAX_SECONDS := 10.0


## 匯入一個音效檔進共用的提醒音效庫。回傳 {ok, message, file_name(成功時)}。
static func import_file(source_path: String) -> Dictionary:
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
	var stream := PetVoice.decode(bytes, extension)
	if stream == null:
		return {"ok": false, "message": "這個檔案無法解碼,可能已經毀損或格式不正確。"}
	if stream.get_length() > MAX_SECONDS:
		return {"ok": false, "message": TranslationServer.translate("音檔時間太長了(%.1f 秒,上限 %.0f 秒);請用更簡短的音效。") % [stream.get_length(), MAX_SECONDS]}
	DirAccess.make_dir_recursive_absolute(ALARM_DIR)
	var stem := source_path.get_file().get_basename().validate_filename().replace(" ", "_")
	var file_name := "%s_%d.%s" % [stem if stem != "" else "音效", Time.get_unix_time_from_system(), extension]
	var target := FileAccess.open(ALARM_DIR + file_name, FileAccess.WRITE)
	if target == null:
		return {"ok": false, "message": "無法儲存音檔,請檢查磁碟空間或權限。"}
	target.store_buffer(bytes)
	target.close()
	return {"ok": true, "message": TranslationServer.translate("已加入提醒音效庫(%.2f 秒)。") % stream.get_length(), "file_name": file_name}


## 音效庫裡目前的檔名清單(排序過)。
static func list() -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(ALARM_DIR)
	if dir == null:
		return result
	for file_name in dir.get_files():
		if is_valid_file_name(file_name):
			result.append(file_name)
	result.sort()
	return result


static func is_valid_file_name(file_name: String) -> bool:
	return file_name != "" and file_name == file_name.get_file() and not file_name.contains("..") \
			and not file_name.contains("/") and not file_name.contains("\\") \
			and ALLOWED_EXTENSIONS.has(file_name.get_extension().to_lower())


## 這個檔名是不是音效庫裡真的存在的檔案(選單/播放前都先檢查,不合法或被刪掉的檔名不會讓程式壞掉)。
static func exists(file_name: String) -> bool:
	return is_valid_file_name(file_name) and FileAccess.file_exists(ALARM_DIR + file_name)


## 讀取並解碼;檔名不合法、檔案不存在或壞掉一律回傳 null(呼叫端退回內建鈴聲)。
static func load_stream(file_name: String) -> AudioStream:
	if not exists(file_name):
		return null
	var bytes := FileAccess.get_file_as_bytes(ALARM_DIR + file_name)
	if bytes.size() > MAX_BYTES:
		return null
	return PetVoice.decode(bytes, file_name.get_extension().to_lower())


## 從音效庫移除一個檔案。回傳有沒有真的刪到。
static func delete(file_name: String) -> bool:
	if not exists(file_name):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(ALARM_DIR + file_name)) == OK


## 給選單/清單顯示用的白話標籤:去掉匯入時間戳記與副檔名,底線換空格。
static func display_name(file_name: String) -> String:
	var base := file_name.get_basename()
	var underscore := base.rfind("_")
	if underscore > 0 and base.substr(underscore + 1).is_valid_int():
		base = base.substr(0, underscore)
	return base.replace("_", " ")
