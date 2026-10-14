class_name VoiceLibrary
extends RefCounted
## 說話聲音庫:使用者匯入過的說話聲音檔(PetVoice)留一份在這裡,不綁定特定桌寵——之後想給別隻桌寵用同一個聲音,
## 直接從清單選就好,不用再去硬碟找原本的檔案(2026-10-13 使用者要求:跟「提醒音效庫」AlarmSounds 同樣的概念)。
## 桌寵實際使用的聲音仍然是 PetVoice 那一套(user://voices/<辨識代號>_<時間戳>,設定檔只記檔名、存檔後清掉沒在用的舊檔):
## 從這裡「套用」= 把庫裡的檔案當成來源再走一次 PetVoice.import_file(),所以刪掉庫裡的檔案不會影響正在使用它的桌寵。
## 檔案限制(格式、大小、長度)沿用 PetVoice,進得來的都是 PetVoice 驗證過能解碼的檔案;內容相同的檔案只留一份。

const LIBRARY_DIR := "user://voice_library/"


## 把一個聲音檔加進庫裡(呼叫前應該已經通過 PetVoice 的驗證)。label 是清單上要顯示的名字(空的就用來源檔名)。
## 回傳庫裡的檔名(已經有內容相同的檔案就回那一個,不重複存);失敗回空字串。
static func add_file(source_path: String, label := "") -> String:
	var extension := source_path.get_extension().to_lower()
	if not PetVoice.ALLOWED_EXTENSIONS.has(extension):
		return ""
	var bytes := FileAccess.get_file_as_bytes(source_path)
	if bytes.is_empty() or bytes.size() > PetVoice.MAX_BYTES:
		return ""
	var existing := _find_same(bytes)
	if existing != "":
		return existing
	if PetVoice.decode(bytes, extension) == null:
		return ""
	DirAccess.make_dir_recursive_absolute(LIBRARY_DIR)
	var stem := (label if label != "" else source_path.get_file().get_basename()).validate_filename().replace(" ", "_")
	var file_name := "%s_%d.%s" % [stem if stem != "" else "聲音", Time.get_unix_time_from_system(), extension]
	var counter := 1
	while FileAccess.file_exists(LIBRARY_DIR + file_name):
		counter += 1
		file_name = "%s%d_%d.%s" % [stem if stem != "" else "聲音", counter, Time.get_unix_time_from_system(), extension]
	var target := FileAccess.open(LIBRARY_DIR + file_name, FileAccess.WRITE)
	if target == null:
		return ""
	target.store_buffer(bytes)
	target.close()
	return file_name


## 把桌寵們目前在用的說話聲音(user://voices/,包含這個功能出現以前就導入的)補進庫裡;已經有的不會重複。回傳補了幾個。
static func sync_from_voices() -> int:
	var directory := DirAccess.open(PetVoice.VOICE_DIR)
	if directory == null:
		return 0
	var before := list().size()
	for file_name in directory.get_files():
		if PetVoice.is_valid_file_name(file_name):
			add_file(PetVoice.VOICE_DIR + file_name, display_name(file_name))
	return list().size() - before


## 庫裡目前的檔名清單(排序過)。
static func list() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(LIBRARY_DIR)
	if directory == null:
		return result
	for file_name in directory.get_files():
		if PetVoice.is_valid_file_name(file_name):
			result.append(file_name)
	result.sort()
	return result


static func exists(file_name: String) -> bool:
	return PetVoice.is_valid_file_name(file_name) and FileAccess.file_exists(LIBRARY_DIR + file_name)


## 庫裡這個檔案的路徑(給 PetVoice.import_file 當來源);不存在回空字串。
static func path_of(file_name: String) -> String:
	return LIBRARY_DIR + file_name if exists(file_name) else ""


static func load_stream(file_name: String) -> AudioStream:
	if not exists(file_name):
		return null
	return PetVoice.decode(FileAccess.get_file_as_bytes(LIBRARY_DIR + file_name), file_name.get_extension().to_lower())


## 從庫裡移除一個檔案(正在用這個聲音的桌寵不受影響,它們用的是自己那一份)。回傳有沒有真的刪到。
static func delete(file_name: String) -> bool:
	if not exists(file_name):
		return false
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(LIBRARY_DIR + file_name)) == OK


## 清單顯示用的名字:去掉時間戳記與副檔名,底線換空格(同 AlarmSounds.display_name)。
static func display_name(file_name: String) -> String:
	return AlarmSounds.display_name(file_name)


static func _find_same(bytes: PackedByteArray) -> String:
	var wanted := _digest(bytes)
	for file_name in list():
		var other := FileAccess.get_file_as_bytes(LIBRARY_DIR + file_name)
		if other.size() == bytes.size() and _digest(other) == wanted:
			return file_name
	return ""


static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_MD5)
	context.update(bytes)
	return context.finish().hex_encode()
