class_name TopicRows
extends VBoxContainer
## 2026-10-06 話題文本:每句一列(條件 + 文字),最下面一列用來新增;刪除在事件管理做。結構跟「基本反應對話」一樣是可改寫的文字清單。
## 條件用📝按鈕開 TopicConditionDialog 勾選產生(不再自由輸入),hover 顯示目前條件,格式見 LogicInterpreter._special_atom()。
## 句中引用:{tag:愛好}、{tag:user:愛好}、{liked}、{disliked}、{neutral}、{you}(見 LogicInterpreter)。資料格式 {condition, text}(見 Pet.topic_custom)。

signal changed

var _list: VBoxContainer
var _add_text: TextEdit
var _add_condition_button: Button
var _add_condition := ""
var _rows: Array[Dictionary] = []   # 每列:{"row": HBoxContainer, "condition": String, "cond_button": Button, "text": TextEdit}
var _loading := false
var _dialog: TopicConditionDialog
var _editing: Dictionary = {}       # 目前正在設定條件的那一列(空 = 新增列)


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	_add_condition_button = _condition_button()
	_add_condition_button.text = "📝"
	_add_condition_button.pressed.connect(func() -> void: _open_dialog({}, _add_condition))
	add_row.add_child(_add_condition_button)
	_add_text = TextEdit.new()
	_add_text.custom_minimum_size.y = 40.0
	_add_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_add_text.placeholder_text = tr("新增一句話題…(可以用 {tag:愛好}、{liked}、{disliked}、{neutral})")
	_add_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_add_text)
	var add_button := ManagerUi.button(tr("加入"))
	add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(add_button)
	_dialog = TopicConditionDialog.new()
	_dialog.condition_chosen.connect(_on_condition_chosen)
	add_child(_dialog)


## 用桌寵的話題清單重建所有列(不發 changed)。
func set_data(lines: Array) -> void:
	_loading = true
	for entry in _rows:
		_list.remove_child(entry["row"])
		(entry["row"] as Node).queue_free()
	_rows.clear()
	for line: Variant in lines:
		if line is Dictionary:
			_append_row(str((line as Dictionary).get("condition", "")), str((line as Dictionary).get("text", "")), str((line as Dictionary).get("en", "")))
	_loading = false


## 目前的內容:只保留文字不空的句子。
func get_data() -> Array:
	var result: Array = []
	for entry in _rows:
		var text := PetText.sanitize((entry["text"] as TextEdit).text.replace("\n", " "), PetText.HARD_MAX_LENGTH)
		if text != "":
			var line := {"condition": str(entry["condition"]), "text": text}
			# 英文版只在中文原文沒被改過時保留(改了的話譯文已經對不上,捨棄)。
			if str(entry["en"]) != "" and text == str(entry["orig"]):
				line["en"] = str(entry["en"])
			result.append(line)
	return result


func _append_row(condition: String, text: String, en := "") -> void:
	var row := HBoxContainer.new()
	_list.add_child(row)
	var entry := {"row": row, "condition": condition, "cond_button": _condition_button(), "text": null, "en": en, "orig": text}
	_refresh_button(entry)
	(entry["cond_button"] as Button).pressed.connect(func() -> void: _open_dialog(entry, str(entry["condition"])))
	row.add_child(entry["cond_button"])
	var text_edit := TextEdit.new()
	text_edit.text = text
	text_edit.custom_minimum_size.y = 40.0
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 只有文字真的改了才發 changed:單純點進去又離開(或視窗關閉造成失焦)不算改動,否則會被當成「有未儲存的變更」。
	var last := [text]
	text_edit.focus_exited.connect(func() -> void:
		if text_edit.text != last[0]:
			last[0] = text_edit.text
			_emit_changed())
	row.add_child(text_edit)
	entry["text"] = text_edit
	# 話題句的刪除在事件管理裡做(見 EventManagerWindow 的話題列),這裡不再提供刪除鍵。
	_rows.append(entry)


func _condition_button() -> Button:
	var button := ManagerUi.button("")
	# 只是 📝 圖示,寬度跟圖示一樣;真正要寫的是右邊的文字框,不佔寬度。
	return button


func _refresh_button(entry: Dictionary) -> void:
	var condition := str(entry["condition"])
	# 按鈕只顯示 📝,hover 才看到目前套用中的條件內容。
	(entry["cond_button"] as Button).text = "📝"
	(entry["cond_button"] as Button).tooltip_text = (tr("目前條件:%s") % condition) if condition != "" else tr("目前條件:無(任何時候都可以被選到)。點一下設定條件。")


## 開啟條件設定。entry 為空 = 新增列的條件。
func _open_dialog(entry: Dictionary, condition: String) -> void:
	_editing = entry
	_dialog.set_condition(condition)
	FloatingWindow.popup_child_dialog_clamped(self, get_window(), _dialog, Vector2i(460, 520), 0.9)


func _on_condition_chosen(condition: String) -> void:
	if _editing.is_empty():
		_add_condition = condition
		_add_condition_button.tooltip_text = (tr("目前條件:%s") % condition) if condition != "" else tr("目前條件:無")
	else:
		_editing["condition"] = condition
		_refresh_button(_editing)
		_emit_changed()
	_editing = {}


func _on_add_pressed() -> void:
	var text := PetText.sanitize(_add_text.text.replace("\n", " "), PetText.HARD_MAX_LENGTH)
	if text == "":
		return
	_append_row(_add_condition, text)
	_add_text.text = ""
	_add_condition = ""
	_add_condition_button.tooltip_text = tr("目前條件:無")
	_emit_changed()


func _emit_changed() -> void:
	if not _loading:
		changed.emit()
