class_name TextPromptWindow
extends FloatingWindow
## 「桌寵想問你一句話」的輸入視窗(問稱呼、輸入抽籤選項…)。桌面覆蓋層是不可取得焦點的透明視窗,收不到鍵盤輸入,
## 所以文字輸入用獨立的原生視窗。長度上限由 LineEdit 強制,結果一律經過 PetText.sanitize 才交出去。
## 確定 = 接受輸入;略過/關閉/被打斷 = 不接受(呼叫端保留原本的值)。

var _ticket: InputTicket
var _edit: LineEdit
var _max_length := PetText.DEFAULT_MAX_LENGTH


func setup(pet_label: String, prompt: String, default_text: String, max_length: int, ticket: InputTicket) -> void:
	_ticket = ticket
	_max_length = clampi(max_length, 1, PetText.HARD_MAX_LENGTH)
	setup_floating(tr("%s 想問你") % pet_label, Vector2i(460, 190), Vector2i(360, 170))
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
	_ticket.finish(PetText.sanitize(_edit.text, _max_length), true)
	queue_free()


## 叉叉/略過/被打斷:視為沒有輸入。
func _request_close() -> void:
	_ticket.finish("", false)
	queue_free()


func cancel() -> void:
	_request_close()
