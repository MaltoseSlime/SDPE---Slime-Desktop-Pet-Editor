class_name PersonalityEditorWindow
extends FloatingWindow
## 性格編輯器:改一個性格檔的內容並存成自訂性格(user://personalities/)。基本資料、所有參數(可填式方塊)、閒聊台詞與反應台詞(每種情境可以寫好幾項)。
## 編輯內建的預設性格時不會改到原檔,而是存成新的自訂性格(預設 id 加 _mine)。數值定義、狀態鏡、進階事件積木(blocks)原樣保留,不在這裡編輯。
## 想要更多語法或細節設定:到網頁編輯器用「匯入性格檔」做進階編輯(積木),或直接在台詞裡手打語法(見各分頁提示)。
## 儲存/關閉按鈕是釘在視窗底部的浮動列;有沒存的變更就按叉叉或「不儲存並關閉」時會先問。

signal saved(id: String)
## 改動存到「這隻角色自己的版本」(不是共用的性格檔)。
signal saved_to_pet(id: String)

const BAR_HEIGHT := 46
const SYNTAX_HINT := "想要更多語法或細節設定?到網頁編輯器用「匯入性格檔」做進階編輯(積木),或在台詞裡直接手打語法:[b]粗體[/b]、[i]斜體[/i]、[wave]…[/wave]、[shake]…[/shake]、[color=#ff8080]…[/color]、{數值名稱}(插入目前數值)。"

var _base: Dictionary = {}
var _params: Dictionary = {}
var _original_id := ""
var _was_builtin := false
var _dirty := false
var _updating := false
var _name_edit: LineEdit
var _id_edit: LineEdit
var _author_edit: LineEdit
var _description_edit: TextEdit
var _extra_label: Label
var _params_panel: PersonalityParamsPanel
var _chat_editor: PersonalityEntriesEditor
var _reaction_editor: PersonalityEntriesEditor
var _status: Label
var _bar_style: StyleBoxFlat
var _confirm: ConfirmationDialog
## 非空 = 這個編輯器改的是這隻角色帶著的性格副本(_original_id 那一份):「儲存到這隻角色」只寫進角色,「另存為共用性格」才寫成共用的性格檔。
var _pet: Node


## personality:PersonalityFile.validate 整理過的性格(也可以是從桌寵目前設定匯出後驗證過的)。builtin = 來源是內建性格(存檔時不能用同一個 id)。
func setup(personality: Dictionary, builtin: bool, pet: Node = null) -> void:
	setup_floating(tr("性格編輯器 — %s") % str(personality.get("name", "")), Vector2i(900, 700), Vector2i(720, 480))
	_pet = pet
	_base = personality.duplicate(true)
	_params = (personality.get("params", {}) as Dictionary).duplicate(true)
	_original_id = str(personality.get("id", ""))
	_was_builtin = builtin
	_build()
	_load_into_widgets()
	_dirty = false


func _build() -> void:
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_theme_constant_override("margin_bottom", BAR_HEIGHT + 6)
	background.add_child(margin)
	var tabs := TabContainer.new()
	margin.add_child(tabs)
	tabs.add_child(_build_basic_tab())
	tabs.add_child(_scrolled("參數", _build_params_tab()))
	tabs.add_child(_scrolled("閒聊台詞", _build_lines_tab("chat", "閒聊台詞:桌寵按「說點什麼」或自動閒聊時,會從符合情境的所有項目裡隨機抽一項來說(一項 = 一張籤,想讓某句更常出現就多寫幾項)。")))
	tabs.add_child(_scrolled("反應台詞", _build_lines_tab("reactions", "反應台詞:遇到某件事(被摸、被拖曳、輸贏…)時說的話與做的動作;同一件事有好幾項就隨機挑一項。沒有寫的事件會用內建反應。")))
	_build_floating_bar()
	_confirm = ConfirmationDialog.new()
	# 不設 always_on_top,見 manager_ui.gd 的 ask_name() 說明(跟置頂衝突,會把視窗卡死)。
	_confirm.title = tr("尚未儲存的變更")
	_confirm.dialog_text = "這個性格有還沒儲存的變更,要儲存後關閉嗎?"
	_confirm.ok_button_text = "儲存後關閉"
	_confirm.cancel_button_text = "取消"
	_confirm.add_button("不儲存關閉", true, "discard")
	_confirm.confirmed.connect(func() -> void:
		if (save_to_pet() if _pet != null else save_now()) == "":
			queue_free())
	_confirm.custom_action.connect(func(action: StringName) -> void:
		if action == &"discard":
			queue_free())
	add_child(_confirm)


func _scrolled(tab_name: String, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	return scroll


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.theme_type_variation = AppSettings.MUTED_LABEL
	return label


func _build_basic_tab() -> Control:
	var page := VBoxContainer.new()
	page.name = "基本資料"
	page.add_theme_constant_override("separation", 6)
	_name_edit = ManagerUi.line_edit("下拉選單裡顯示的名字")
	_name_edit.max_length = 40
	_name_edit.text_changed.connect(func(_t: String) -> void: _mark_dirty())
	page.add_child(ManagerUi.labeled("名稱", _name_edit))
	_id_edit = ManagerUi.line_edit("英數、底線、連字號、中文;這個性格的唯一代號(也是檔名)")
	_id_edit.max_length = 40
	_id_edit.text_changed.connect(func(_t: String) -> void: _mark_dirty())
	page.add_child(ManagerUi.labeled("代號 id", _id_edit))
	_author_edit = ManagerUi.line_edit("作者(選填)")
	_author_edit.max_length = 60
	_author_edit.text_changed.connect(func(_t: String) -> void: _mark_dirty())
	page.add_child(ManagerUi.labeled("作者", _author_edit))
	_description_edit = TextEdit.new()
	_description_edit.custom_minimum_size.y = 90.0
	_description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description_edit.placeholder_text = tr("這個性格的說明(滑過選單時顯示)")
	_description_edit.text_changed.connect(_mark_dirty)
	page.add_child(ManagerUi.labeled("說明", _description_edit))
	_extra_label = _hint("")
	page.add_child(_extra_label)
	page.add_child(ManagerUi.syntax_row(self, "台詞語法與進階編輯", SYNTAX_HINT))
	return page


func _build_params_tab() -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(ManagerUi.hint_row("只有動過的參數會寫進性格檔", "只有你動過(或原本就有)的參數會寫進性格檔,沒動的維持「不調整」,套用這個性格時不會去改它。每列右邊的 ↺ 回到預設值(回到預設值也算調整過,套用時會把桌寵設回預設值)。滑過參數名稱看完整說明。"))
	_params_panel = PersonalityParamsPanel.new()
	_params_panel.value_changed.connect(func(key: String, value: Variant) -> void:
		if _updating:
			return
		_params[key] = value
		_mark_dirty())
	page.add_child(_params_panel)
	return page


func _build_lines_tab(kind: String, hint_text: String) -> Control:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	page.add_child(ManagerUi.hint_row("這裡的台詞怎麼被抽到", hint_text))
	page.add_child(ManagerUi.syntax_row(self, "台詞語法與進階編輯", SYNTAX_HINT))
	var editor := PersonalityEntriesEditor.new()
	editor.setup(kind)
	editor.changed.connect(_mark_dirty)
	page.add_child(editor)
	if kind == "chat":
		_chat_editor = editor
	else:
		_reaction_editor = editor
	return page


## 底部按鈕列的底色與邊線跟著編輯器配色(不再是固定深色)。
func _restyle_bar() -> void:
	var colors: Dictionary = AppSettings.appearance()["colors"]
	_bar_style.bg_color = (colors["bg"] as Color).lerp(colors["text"], 0.06)
	_bar_style.border_color = AppSettings.ink(0.18)


func refresh_theme() -> void:
	super.refresh_theme()
	_restyle_bar()


func _build_floating_bar() -> void:
	var bar := PanelContainer.new()
	bar.name = "FloatingButtons"
	bar.custom_minimum_size.y = BAR_HEIGHT
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -BAR_HEIGHT
	var style := StyleBoxFlat.new()
	_bar_style = style
	_restyle_bar()
	style.border_width_top = 1
	style.set_content_margin_all(6.0)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	bar.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_status = Label.new()
	_status.theme_type_variation = AppSettings.MUTED_LABEL
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status.clip_text = true
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_status)
	var save := ManagerUi.button("另存為共用性格檔" if _pet != null else "儲存")
	save.tooltip_text = tr("存成共用的自訂性格(user://personalities/,所有角色的下拉選單都選得到),不影響已經套用了這個性格的角色自己的副本。") if _pet != null else ""
	save.pressed.connect(func() -> void: _save_with_prompt(false))
	var save_close := ManagerUi.button("儲存並關閉")
	save_close.pressed.connect(func() -> void: _save_with_prompt(true) if _pet == null else _save_to_pet_and_close())
	var discard := ManagerUi.button("不儲存並關閉")
	discard.pressed.connect(_request_close)
	if _pet != null:
		var save_pet := ManagerUi.button("儲存到這隻角色")
		save_pet.tooltip_text = tr("只改這隻角色帶著的這份性格,別隻角色與共用的性格檔都不受影響(打包角色時這份會跟著走)。")
		save_pet.pressed.connect(func() -> void: save_to_pet())
		row.add_child(save_pet)
	for button in [save, save_close, discard]:
		row.add_child(button)
	add_child(bar)


func _load_into_widgets() -> void:
	_updating = true
	# 改角色自己的副本時名稱與代號保持原樣(要另存成共用性格時,撞到內建的代號會自動加 _mine);從共用性格開的才預設加「(我的)」與 _mine。
	var default_id := _original_id + "_mine" if _was_builtin and _pet == null else _original_id
	_name_edit.text = str(_base.get("name", "")) + (tr("(我的)") if _was_builtin and _pet == null else "")
	_id_edit.text = default_id
	_author_edit.text = str(_base.get("author", ""))
	_description_edit.text = str(_base.get("description", ""))
	var values := {}
	for key: String in _params:
		values[key] = _params[key]
	_params_panel.set_values(values)
	_chat_editor.load_entries(_base.get("chat", []))
	_reaction_editor.load_entries(_base.get("reactions", []))
	var extras: Array[String] = []
	if not (_base.get("valueDefs", []) as Array).is_empty():
		extras.append(tr("數值定義 %d 個") % (_base["valueDefs"] as Array).size())
	if not (_base.get("lenses", []) as Array).is_empty():
		extras.append(tr("狀態鏡 %d 個") % (_base["lenses"] as Array).size())
	if not (_base.get("blocks", []) as Array).is_empty():
		extras.append(tr("進階事件積木 %d 個") % (_base["blocks"] as Array).size())
	_extra_label.text = tr("還帶有:%s(存檔時原樣保留)") % "、".join(PackedStringArray(extras)) if not extras.is_empty() else tr("沒有數值定義、狀態鏡與進階事件積木")
	if _was_builtin:
		_status.text = tr("這是內建的預設性格,改完會存成新的自訂性格(原檔不會被改)。")
	_updating = false


func _mark_dirty(_arg: Variant = null) -> void:
	if _updating:
		return
	_dirty = true
	title = tr("性格編輯器 — %s *") % _name_edit.text
	_status.text = tr("有尚未儲存的變更。")


## 目前編輯內容整理成性格(內部格式,還沒驗證)。
func collect() -> Dictionary:
	var personality := _base.duplicate(true)
	personality["id"] = PersonalityFile.clean_id(_id_edit.text)
	personality["name"] = _name_edit.text.strip_edges()
	personality["description"] = _description_edit.text.strip_edges()
	personality["author"] = _author_edit.text.strip_edges()
	personality["params"] = _params.duplicate(true)
	personality["chat"] = _chat_editor.entries()
	personality["reactions"] = _reaction_editor.entries()
	return personality


## 存檔的所有檢查;回傳錯誤文字(空字串 = 沒問題)。
func check_before_save(personality: Dictionary) -> String:
	if str(personality["name"]) == "":
		return "名稱不能是空的"
	if str(personality["id"]) == "":
		return "代號 id 不能是空的(只能用英數、底線、連字號、中文)"
	for item in PersonalityFile.list_all():
		if bool(item["builtin"]) and str(item["id"]) == str(personality["id"]):
			return tr("代號「%s」是內建性格在用的,請換一個(內建的預設性格不能被覆蓋)") % personality["id"]
	return ""


## 存成自訂性格檔。回傳錯誤文字(空字串 = 成功)。overwrite_ok = false 時,代號和「另一個」已存在的自訂性格撞名會拒絕(由呼叫端先問使用者)。
func save_now(overwrite_ok := true) -> String:
	# 從角色開的編輯器另存成共用性格時,代號撞到內建的就自動換一個(加 _mine 與「(我的)」),不用使用者自己想。
	if _pet != null:
		for item in PersonalityFile.list_all():
			if bool(item["builtin"]) and str(item["id"]) == PersonalityFile.clean_id(_id_edit.text):
				_id_edit.text = PersonalityFile.clean_id(_id_edit.text) + "_mine"
				if not _name_edit.text.ends_with("(我的)"):
					_name_edit.text += "(我的)"
				break
	var personality := collect()
	var problem := check_before_save(personality)
	if problem != "":
		_status.text = problem
		return problem
	var path := PersonalityFile.CUSTOM_DIR + str(personality["id"]) + PersonalityFile.EXTENSION
	if str(personality["id"]) != _original_id and FileAccess.file_exists(path) and not overwrite_ok:
		return "exists"
	if str(personality["id"]) == _original_id and not _was_builtin:
		personality["revision"] = int(personality.get("revision", 1)) + 1
	else:
		personality["revision"] = 1
	var data := PersonalityFile.to_file_data(personality)
	var checked := PersonalityFile.validate(data)
	if not bool(checked["ok"]):
		var reason := "; ".join(PackedStringArray(checked["report"]))
		_status.text = tr("存不了:%s") % reason
		return reason
	DirAccess.make_dir_recursive_absolute(PersonalityFile.CUSTOM_DIR)
	var error := PersonalityFile.write_file(path, data)
	if error != OK:
		_status.text = tr("存檔失敗(無法寫入 %s)") % PersonalityFile.CUSTOM_DIR
		return "write"
	PersonalityFile.clear_cache()
	_original_id = str(personality["id"])
	_was_builtin = false
	_base["revision"] = personality["revision"]
	_dirty = false
	title = tr("性格編輯器 — %s") % _name_edit.text
	_status.text = tr("已存成自訂性格「%s」。回到「性格」分頁的下拉選單就能選它。") % personality["name"]
	saved.emit(_original_id)
	return ""


## 存到「這隻角色的版本」:只換角色身上帶著的那份(代號不變),不寫共用的性格檔。回傳錯誤文字(空字串 = 成功)。
func save_to_pet() -> String:
	if _pet == null:
		return "這個編輯器不是從角色開啟的"
	var personality := collect()
	personality["id"] = _original_id
	if str(personality["name"]) == "":
		_status.text = tr("名稱不能是空的")
		return "名稱不能是空的"
	var data := PersonalityFile.to_file_data(personality)
	var checked := PersonalityFile.validate(data)
	if not bool(checked["ok"]):
		var reason := "; ".join(PackedStringArray(checked["report"]))
		_status.text = tr("存不了:%s") % reason
		return reason
	PersonalityApplier.set_own(_pet, _original_id, PersonalityFile.to_file_data(checked["personality"]))
	_dirty = false
	title = tr("性格編輯器 — %s") % _name_edit.text
	_status.text = tr("已存到這隻角色自己的版本。要讓新的參數生效,回到「性格」分頁按「套用」。")
	saved_to_pet.emit(_original_id)
	return ""


func _save_to_pet_and_close() -> void:
	if save_to_pet() == "":
		queue_free()


## 按鈕用:代號撞到別的自訂性格時先問要不要覆蓋。
func _save_with_prompt(close_after: bool) -> void:
	var result := save_now(false)
	if result == "exists":
		var dialog := ConfirmationDialog.new()
		dialog.title = tr("覆蓋既有的自訂性格?")
		dialog.dialog_text = tr("已經有一個代號叫「%s」的自訂性格了,要用目前的內容覆蓋它嗎?") % PersonalityFile.clean_id(_id_edit.text)
		dialog.ok_button_text = "覆蓋"
		dialog.cancel_button_text = "取消"
		# 不設 always_on_top,見 _ready() 裡 _confirm 的說明(跟置頂衝突,會把視窗卡死)。
		dialog.theme = ManagerUi.make_theme()
		dialog.confirmed.connect(func() -> void:
			if save_now(true) == "" and close_after:
				queue_free())
		dialog.confirmed.connect(dialog.queue_free)
		dialog.canceled.connect(dialog.queue_free)
		add_child(dialog)
		FloatingWindow.popup_child_dialog(self, get_window(), dialog, Vector2i(440, 160))
		return
	if result == "" and close_after:
		queue_free()


## 叉叉或「不儲存並關閉」:有沒存的變更就先問(儲存後關閉 / 不儲存關閉 / 取消)。
func _request_close() -> void:
	if not _dirty:
		queue_free()
		return
	FloatingWindow.popup_child_dialog(self, get_window(), _confirm, Vector2i(460, 160))


func is_dirty() -> bool:
	return _dirty
