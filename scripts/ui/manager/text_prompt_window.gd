class_name TextPromptWindow
extends FloatingWindow
## 「桌寵想問你一句話」的輸入視窗(問稱呼、輸入抽籤選項…)。桌面覆蓋層是不可取得焦點的透明視窗,收不到鍵盤輸入,
## 所以文字輸入用獨立的原生視窗。長度上限由 LineEdit 強制,結果一律經過 PetText.sanitize 才交出去。
## 確定 = 接受輸入;略過/關閉/被打斷 = 不接受(呼叫端保留原本的值)。

var _ticket: InputTicket
var _edit: LineEdit
var _max_length := PetText.DEFAULT_MAX_LENGTH
## 關鍵詞詢問才有的標籤下拉選單(見 setup 的 tag_picker);其他詢問是 null。
var _tag_option: OptionButton
## 第二個輸入欄(見 setup 的 second);沒有是 null。
var _second_edit: LineEdit
var _second_max := PetText.DEFAULT_MAX_LENGTH


## tag_picker = true:答案會被記進關鍵詞庫的詢問(2026-10-11 使用者要求),多一行標籤下拉選單,讓使用者當下順手把
## 這個詞的標籤定好,不用事後再去關鍵詞庫補;選的標籤由 ticket.tag 帶回去。
## second 非空 = 同一個視窗裡多問一題({prompt, default, max_length};2026-10-11 使用者要求:計時器的「要計時多久」與「中途提醒」
## 原本是接連兩個視窗,合成一個問完),內容由 ticket.extra 帶回去;這一欄可以留空。
func setup(pet_label: String, prompt: String, default_text: String, max_length: int, ticket: InputTicket, tag_picker := false, second := {}) -> void:
	_ticket = ticket
	_max_length = clampi(max_length, 1, PetText.HARD_MAX_LENGTH)
	var extra := (36 if tag_picker else 0) + (120 if not second.is_empty() else 0)
	setup_floating(tr("%s 想問你") % pet_label, Vector2i(460, 190 + extra), Vector2i(360, 170 + extra))
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	background.add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	column.add_child(build_title_bar(pet_label + " 想問你"))
	var label := Label.new()
	label.text = prompt
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)
	_edit = LineEdit.new()
	_edit.text = PetText.sanitize(default_text, _max_length)
	_edit.max_length = _max_length
	_edit.placeholder_text = tr("最多 %d 個字") % _max_length
	_edit.text_submitted.connect(func(_t: String) -> void: _accept())
	column.add_child(_edit)
	if not second.is_empty():
		var second_label := Label.new()
		second_label.text = str(second.get("prompt", ""))
		second_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(second_label)
		_second_max = clampi(int(second.get("max_length", PetText.DEFAULT_MAX_LENGTH)), 1, PetText.HARD_MAX_LENGTH)
		_second_edit = LineEdit.new()
		_second_edit.text = PetText.sanitize(str(second.get("default", "")), _second_max)
		_second_edit.max_length = _second_max
		_second_edit.placeholder_text = tr("可以留空")
		_second_edit.text_submitted.connect(func(_t: String) -> void: _accept())
		column.add_child(_second_edit)
	if tag_picker:
		var tag_row := HBoxContainer.new()
		var tag_label := Label.new()
		tag_label.text = tr("標籤")
		tag_row.add_child(tag_label)
		_tag_option = KeywordRows.make_tag_option(PetText.DEFAULT_TAG)
		_tag_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tag_row.add_child(_tag_option)
		column.add_child(tag_row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var ok := ManagerUi.button("確定")
	ok.pressed.connect(_accept)
	var skip := ManagerUi.button("略過")
	skip.pressed.connect(_request_close)
	buttons.add_child(ok)
	buttons.add_child(skip)
	column.add_child(buttons)
	_edit.grab_focus.call_deferred()


func _accept() -> void:
	if _tag_option != null:
		_ticket.tag = PetText.KEYWORD_TAGS[_tag_option.selected]
	if _second_edit != null:
		_ticket.extra = PetText.sanitize(_second_edit.text, _second_max)
	_ticket.finish(PetText.sanitize(_edit.text, _max_length), true)
	queue_free()


## 叉叉/略過/被打斷:視為沒有輸入。
func _request_close() -> void:
	_ticket.finish("", false)
	queue_free()


func cancel() -> void:
	_request_close()
