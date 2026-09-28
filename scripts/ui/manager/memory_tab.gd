class_name MemoryTab
extends VBoxContainer
## 記憶分頁:重置指定桌寵的記憶(Flag、局部數值、使用者輸入的文字),見 MemoryReset。
## 防呆:範圍勾選(預設同角色所有複製品 + 清除已存本體狀態檔;全域數值與狀態鏡預設不動)、確認視窗列出將被清除的內容、
## 必須逐字輸入通關密碼、執行前自動備份、並可「復原上一次重置」。

signal changed
signal message(text: String)

var _pet: Node
var _summary: Label
var _clones_check: CheckBox
var _saved_check: CheckBox
var _globals_check: CheckBox
var _lenses_check: CheckBox
var _undo_button: Button
var _last_record: Dictionary = {}
## 上一次「讀取記憶存檔」讀之前的記憶:{pet, backup}。
var _last_load: Dictionary = {}
var _slot_rows: Array[Dictionary] = []


func _ready() -> void:
	name = "記憶"
	add_child(ManagerUi.heading("重置記憶"))
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_summary)
	add_child(ManagerUi.hint_row("洗掉 Flag、局部數值與輸入的文字", "洗掉這隻桌寵所有事件 Flag、局部數值(回到宣告的預設值)與使用者輸入的文字(稱呼等)。動作、對話氣泡、事件積木、狀態鏡定義與介面設定完全不受影響。"))
	add_child(HSeparator.new())
	_clones_check = _check("同角色的所有複製品一起重置", true)
	_saved_check = _check("一併清除已存的本體狀態檔(否則下次啟動會讀回舊記憶)", true)
	_globals_check = _check("同時重置「全域數值」(所有桌寵共用,通常不要勾)", false)
	_lenses_check = _check("同時解除目前啟用中的狀態鏡", false)
	var reset := ManagerUi.button("重置記憶…")
	reset.pressed.connect(_open_confirm)
	add_child(reset)
	_undo_button = ManagerUi.button("復原上一次重置 / 讀取")
	_undo_button.disabled = true
	_undo_button.pressed.connect(_undo)
	add_child(_undo_button)
	_build_slots()


## 記憶存檔:5 格,把目前的記憶存起來、之後再讀回來(見 MemorySlots)。
func _build_slots() -> void:
	add_child(HSeparator.new())
	add_child(ManagerUi.heading("記憶存檔(5 格)"))
	add_child(ManagerUi.hint_row("把目前的記憶存起來,之後讀回來", "把這隻桌寵目前的記憶(局部數值、事件 Flag、使用者輸入的文字)存進一格,之後隨時讀回來,也可以在重置前先存一份。同角色的複製品共用這 5 格;狀態鏡與全域數值不在裡面。存檔立刻寫進檔案,不需要再按「儲存」。"))
	for i in MemorySlots.SLOT_COUNT:
		var row := HBoxContainer.new()
		var index_label := Label.new()
		index_label.text = tr("第 %d 格") % (i + 1)
		index_label.custom_minimum_size.x = 56.0
		var name_edit := ManagerUi.line_edit("名稱(選填)")
		name_edit.custom_minimum_size.x = 130.0
		name_edit.max_length = MemorySlots.MAX_NAME
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.clip_text = true
		info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var save_button := ManagerUi.button("存入")
		save_button.pressed.connect(_save_slot.bind(i))
		var load_button := ManagerUi.button("讀取")
		load_button.pressed.connect(_load_slot.bind(i))
		var clear_button := ManagerUi.button("清空")
		clear_button.pressed.connect(_clear_slot.bind(i))
		for control in [index_label, name_edit, info, save_button, load_button, clear_button]:
			row.add_child(control)
		add_child(row)
		_slot_rows.append({"name": name_edit, "info": info, "load": load_button, "clear": clear_button})


func set_pet(pet: Node) -> void:
	_pet = pet
	_refresh_summary()
	_refresh_slots()


func _refresh_slots() -> void:
	if _pet == null:
		return
	var slots := MemorySlots.read_all(_pet)
	for i in MemorySlots.SLOT_COUNT:
		var row: Dictionary = _slot_rows[i]
		(row["info"] as Label).text = MemorySlots.summary(slots[i])
		(row["name"] as LineEdit).text = str((slots[i] as Dictionary).get("name", ""))
		(row["load"] as Button).disabled = (slots[i] as Dictionary).is_empty()
		(row["clear"] as Button).disabled = (slots[i] as Dictionary).is_empty()


## 存入一格:格子已經有內容時先問要不要覆蓋。
func _save_slot(index: int) -> void:
	if _pet == null:
		return
	var existing: Dictionary = MemorySlots.read_all(_pet)[index]
	if existing.is_empty():
		save_slot_now(index)
		return
	_ask(tr("覆蓋第 %d 格?") % (index + 1), tr("第 %d 格已經存了:\n%s\n\n要用目前的記憶覆蓋它嗎?(舊的內容會消失)") % [index + 1, MemorySlots.summary(existing)], "覆蓋", save_slot_now.bind(index))


func save_slot_now(index: int) -> bool:
	var name_text := (_slot_rows[index]["name"] as LineEdit).text
	var ok := MemorySlots.write_slot(_pet, index, MemorySlots.snapshot(_pet, name_text))
	_refresh_slots()
	message.emit(tr("已把目前的記憶存進第 %d 格。") % (index + 1) if ok else "存檔失敗(無法寫入 user://memory_slots/)。")
	return ok


## 讀取一格:會取代目前的記憶,所以先問;讀之前的記憶記下來,可以按「復原」。
func _load_slot(index: int) -> void:
	if _pet == null:
		return
	var data: Dictionary = MemorySlots.read_all(_pet)[index]
	if data.is_empty():
		return
	_ask(tr("讀取第 %d 格?") % (index + 1), tr("要把第 %d 格的記憶讀回 %s 嗎?\n%s\n\n這會取代它目前所有的局部數值、Flag 與使用者輸入的文字(讀取前的記憶會記下來,可以按「復原上一次重置 / 讀取」)。") % [index + 1, _pet.get_label(), MemorySlots.summary(data)], "讀取", load_slot_now.bind(index))


func load_slot_now(index: int) -> bool:
	var data: Dictionary = MemorySlots.read_all(_pet)[index]
	if data.is_empty():
		return false
	_last_load = {"pet": _pet, "backup": MemorySlots.apply(_pet, data)}
	_last_record = {}
	_undo_button.disabled = false
	_refresh_summary()
	changed.emit()
	message.emit(tr("已讀取第 %d 格的記憶。") % (index + 1))
	return true


func _clear_slot(index: int) -> void:
	if _pet == null:
		return
	var existing: Dictionary = MemorySlots.read_all(_pet)[index]
	if existing.is_empty():
		return
	_ask(tr("清空第 %d 格?") % (index + 1), tr("要清空第 %d 格嗎?\n%s\n\n清空後無法復原。") % [index + 1, MemorySlots.summary(existing)], "清空", clear_slot_now.bind(index))


func clear_slot_now(index: int) -> void:
	MemorySlots.clear_slot(_pet, index)
	_refresh_slots()
	message.emit(tr("已清空第 %d 格。") % (index + 1))


## 小確認視窗(標題、內文、確定鈕文字、確定後做什麼)。
func _ask(title_text: String, body: String, ok_text: String, on_ok: Callable) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = title_text
	dialog.dialog_text = body
	dialog.ok_button_text = ok_text
	dialog.cancel_button_text = "取消"
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.confirmed.connect(on_ok)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.min_size = Vector2i(460, 200)
	dialog.popup_centered_clamped(Vector2i(480, 220), 0.9)


func _check(text: String, on: bool) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = on
	add_child(box)
	return box


func _options() -> Dictionary:
	return {"clones": _clones_check.button_pressed, "saved_state": _saved_check.button_pressed,
			"globals": _globals_check.button_pressed, "lenses": _lenses_check.button_pressed}


func _refresh_summary() -> void:
	if _pet == null:
		return
	_summary.text = tr("%s 目前的記憶:局部數值 %d 個、事件 Flag %d 個、使用者輸入的文字 %d 個。") % [_pet.get_label(), _pet.local_values.size(), _pet.flags.size(), _pet.text_values.size()]


func _open_confirm() -> void:
	if _pet == null:
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "重置記憶 — 最後確認"
	dialog.always_on_top = true
	dialog.theme = ManagerUi.make_theme()
	dialog.ok_button_text = "永久清除這些記憶"
	dialog.cancel_button_text = "取消"
	dialog.get_ok_button().disabled = true
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(540, 0)
	var list := TextEdit.new()
	list.editable = false
	list.custom_minimum_size = Vector2(520, 150)
	list.text = MemoryReset.preview(_pet, _options())
	box.add_child(list)
	var instruction := Label.new()
	instruction.text = "這無法用一般方式挽回(只能用「復原上一次重置」)。要繼續,請逐字輸入下面這句通關密碼:"
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instruction.custom_minimum_size.x = 520.0
	box.add_child(instruction)
	var passphrase := Label.new()
	passphrase.text = MemoryReset.PASSPHRASE
	passphrase.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passphrase.theme_type_variation = AppSettings.WARN_LABEL
	box.add_child(passphrase)
	var input := LineEdit.new()
	input.placeholder_text = tr("在這裡輸入通關密碼")
	input.text_changed.connect(func(text: String) -> void: dialog.get_ok_button().disabled = not MemoryReset.matches_passphrase(text))
	box.add_child(input)
	# 內容放進捲動區、視窗給明確的大小並限制在螢幕範圍內:自動換行的文字量不出高度,視窗會太矮而蓋住確認鈕。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(560, 300)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	dialog.add_child(scroll)
	dialog.min_size = Vector2i(600, 440)
	dialog.confirmed.connect(func() -> void:
		if MemoryReset.matches_passphrase(input.text):
			_execute()
		dialog.queue_free())
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	if DisplayServer.get_name() != "headless":
		dialog.popup_centered_clamped(Vector2i(620, 520), 0.9)


func _execute() -> void:
	_last_record = MemoryReset.execute(_pet, _options())
	_last_load = {}
	_undo_button.disabled = false
	_refresh_summary()
	changed.emit()
	message.emit(tr("記憶已重置。備份:%s(可按「復原上一次重置」)") % str(_last_record.get("file", "")))


func _undo() -> void:
	if not _last_load.is_empty():
		var loaded_pet: Node = _last_load["pet"]
		if is_instance_valid(loaded_pet):
			loaded_pet.restore_memory(_last_load["backup"])
		_last_load = {}
		_undo_button.disabled = true
		_refresh_summary()
		message.emit("已復原上一次讀取(記憶回到讀取之前)。")
		return
	if _last_record.is_empty():
		return
	MemoryReset.undo(_last_record)
	_last_record = {}
	_undo_button.disabled = true
	_refresh_summary()
	message.emit("已復原上一次重置。")
