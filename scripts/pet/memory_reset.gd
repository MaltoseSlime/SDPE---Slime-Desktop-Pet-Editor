class_name MemoryReset
extends RefCounted
## 重置指定桌寵的記憶(所有事件 Flag、局部數值、使用者輸入的文字洗白):**不動**動作積木、對話與氣泡、狀態鏡定義、介面設定。
## 這是破壞性操作,所以有多重防呆:先列出將被清除的內容、必須逐字輸入通關密碼才能執行、執行前自動備份(檔案 + 記憶體)並可復原。

const PASSPHRASE := "Into the fog abandoning my own tracks, I know it will never be the same."
const BACKUP_DIR := "user://backups/"


## 通關密碼要逐字相符(區分大小寫、標點與空白要一樣;只容許頭尾多餘的空白)。
static func matches_passphrase(input: String) -> bool:
	return input.strip_edges() == PASSPHRASE


## 受影響的桌寵:預設只有自己,opts.clones = true 時包含同辨識代號的所有複製品。
static func targets(pet: Node, opts: Dictionary) -> Array[Node]:
	var result: Array[Node] = [pet]
	if bool(opts.get("clones", true)) and pet.recognition_tag != "":
		for other: Node in pet.get_tree().get_nodes_in_group("pets"):
			if other != pet and other.recognition_tag == pet.recognition_tag:
				result.append(other)
	return result


## 將被清除內容的清單(逐行文字),給確認視窗顯示。
static func preview(pet: Node, opts: Dictionary) -> String:
	var lines: PackedStringArray = []
	for target in targets(pet, opts):
		lines.append("■ %s" % target.get_label())
		lines.append(TranslationServer.translate("  局部數值 %d 個:%s") % [target.local_values.size(), _list(target.local_values)])
		lines.append(TranslationServer.translate("  事件 Flag %d 個:%s") % [target.flags.size(), _list(target.flags)])
		lines.append(TranslationServer.translate("  使用者輸入的文字 %d 個:%s") % [target.text_values.size(), _list(target.text_values)])
		if bool(opts.get("lenses", false)):
			lines.append(TranslationServer.translate("  啟用中的狀態鏡:%s(將被解除)") % ", ".join(PackedStringArray(target.active_lens_names())))
	if bool(opts.get("globals", false)):
		var state := pet.get_node("/root/DesktopShellState")
		lines.append(TranslationServer.translate("■ 全域數值(所有桌寵共用)%d 個:%s") % [state.global_values.size(), _list(state.global_values)])
	if bool(opts.get("saved_state", true)):
		lines.append("■ 已存的本體狀態檔也會一併清除(下次啟動不會讀回舊記憶)")
	lines.append("")
	lines.append("不會動到:動作素材與差分、對話與氣泡、事件積木、狀態鏡定義、介面與聲音設定。")
	return "\n".join(lines)


## 執行重置。先備份(檔案 + 回傳的記錄,供復原),再清除。回傳 {pets: {pet: 備份}, globals: 備份或 null, file: 備份檔路徑}。
static func execute(pet: Node, opts: Dictionary) -> Dictionary:
	var state := pet.get_node("/root/DesktopShellState")
	var record := {"pets": {}, "globals": null, "file": ""}
	var file_data := {"time": Time.get_datetime_string_from_system(), "pets": {}}
	for target in targets(pet, opts):
		record["pets"][target] = target.reset_memory(bool(opts.get("lenses", false)))
		file_data["pets"][target.get_label()] = record["pets"][target]
		if bool(opts.get("saved_state", true)):
			PetProfile.delete_state(target)
	if bool(opts.get("globals", false)):
		record["globals"] = state.global_values.duplicate(true)
		file_data["globals"] = record["globals"]
		state.global_values = {}
		ValueGateway.init_defaults(pet)
	record["file"] = _write_backup(pet, file_data)
	return record


## 復原上一次重置(用 execute 回傳的記錄)。
static func undo(record: Dictionary) -> void:
	for target in record.get("pets", {}):
		if is_instance_valid(target):
			target.restore_memory(record["pets"][target])
	if record.get("globals") is Dictionary and not record["pets"].is_empty():
		var first: Node = record["pets"].keys()[0]
		if is_instance_valid(first):
			first.get_node("/root/DesktopShellState").global_values = record["globals"].duplicate(true)


static func _write_backup(pet: Node, data: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
	var tag: String = (pet.recognition_tag if pet.recognition_tag != "" else pet.display_name).validate_filename()
	var path := "%s%s_memory_%d.json" % [BACKUP_DIR, tag, Time.get_unix_time_from_system()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(data, "\t"))
	return path


static func _list(values: Dictionary) -> String:
	if values.is_empty():
		return "(無)"
	var parts: PackedStringArray = []
	for key in values:
		parts.append("%s=%s" % [key, str(values[key])])
		if parts.size() >= 12:
			parts.append("…")
			break
	return ", ".join(parts)
