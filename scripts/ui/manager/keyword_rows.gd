class_name KeywordRows
extends VBoxContainer
## 2026-10-06 關鍵詞列表(取代原本的多行文字框):每個詞一列,可以改文字、用下拉選單改標籤、刪除;最下面一列用來新增。
## 標籤清單見 PetText.KEYWORD_TAGS,沒改過的詞視為「話題」(不寫進標籤字典)。資料由呼叫端讀寫(set_data / get_data)。

signal changed

var _list: VBoxContainer
var _add_word: LineEdit
var _add_tag: OptionButton
var _rows: Array[Dictionary] = []   # 每列:{"row": HBoxContainer, "word": LineEdit, "tag": OptionButton}
var _loading := false


func _init() -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	add_child(_list)
	var add_row := HBoxContainer.new()
	add_child(add_row)
	_add_word = LineEdit.new()
	_add_word.placeholder_text = tr("新增一個詞…")
	_add_word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_word.text_submitted.connect(func(_text: String) -> void: _on_add_pressed())
	add_row.add_child(_add_word)
	_add_tag = _make_tag_option(PetText.DEFAULT_TAG)
	add_row.add_child(_add_tag)
	var add_button := ManagerUi.button(tr("加入"))
	add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(add_button)


## 用桌寵的詞清單與標籤字典重建所有列(不發 changed)。
func set_data(words: PackedStringArray, tags: Dictionary) -> void:
	_loading = true
	for entry in _rows:
		_list.remove_child(entry["row"])
		(entry["row"] as Node).queue_free()
	_rows.clear()
	for word in words:
		_append_row(str(word), PetText.clean_tag(tags.get(str(word), PetText.DEFAULT_TAG)))
	_loading = false


## 目前的內容:words 是整理過的詞清單(去重、去空白、去超長),tags 只含非「話題」的詞。
func get_data() -> Dictionary:
	var raw := PackedStringArray()
	var raw_tags := {}
	for entry in _rows:
		var word := (entry["word"] as LineEdit).text
		raw.append(word)
		raw_tags[word] = PetText.KEYWORD_TAGS[(entry["tag"] as OptionButton).selected]
	var words := PetText.sanitize_keywords(raw)
	var tags := {}
	for word in words:
		var tag := PetText.clean_tag(raw_tags.get(word, PetText.DEFAULT_TAG))
		if tag != PetText.DEFAULT_TAG:
			tags[word] = tag
	return {"words": words, "tags": tags}


func row_count() -> int:
	return _rows.size()


func _append_row(word: String, tag: String) -> void:
	var row := HBoxContainer.new()
	_list.add_child(row)
	var word_edit := LineEdit.new()
	word_edit.text = word
	word_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 只有文字真的改了才發 changed(點進去又離開不算改動,見 TopicRows 同樣的處理)。
	var last := [word]
	var word_changed := func() -> void:
		if word_edit.text != last[0]:
			last[0] = word_edit.text
			_emit_changed()
	word_edit.text_submitted.connect(func(_text: String) -> void: word_changed.call())
	word_edit.focus_exited.connect(func() -> void: word_changed.call())
	row.add_child(word_edit)
	var tag_option := _make_tag_option(tag)
	row.add_child(tag_option)
	var remove_button := ManagerUi.button(tr("刪除"))
	remove_button.pressed.connect(func() -> void:
		_rows.erase(_find_entry(row))
		_list.remove_child(row)
		row.queue_free()
		_emit_changed())
	row.add_child(remove_button)
	_rows.append({"row": row, "word": word_edit, "tag": tag_option})


func _find_entry(row: Node) -> Dictionary:
	for entry in _rows:
		if entry["row"] == row:
			return entry
	return {}


func _make_tag_option(selected_tag: String) -> OptionButton:
	var option := OptionButton.new()
	option.tooltip_text = tr("標籤:閒聊文本用 {tag:標籤名} 引用同一類的詞。不選就是「話題」。")
	for tag in PetText.KEYWORD_TAGS:
		option.add_item(tr(tag))
	option.select(maxi(PetText.KEYWORD_TAGS.find(PetText.clean_tag(selected_tag)), 0))
	option.item_selected.connect(func(_index: int) -> void: _emit_changed())
	return option


func _on_add_pressed() -> void:
	var word := PetText.sanitize(_add_word.text.replace("{", "").replace("}", ""), PetText.MAX_KEYWORD_LENGTH)
	if word == "":
		return
	if row_count() >= PetText.MAX_KEYWORDS:
		return
	_append_row(word, PetText.KEYWORD_TAGS[_add_tag.selected])
	_add_word.text = ""
	_emit_changed()


func _emit_changed() -> void:
	if not _loading:
		changed.emit()
