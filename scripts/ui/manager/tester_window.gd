class_name TesterWindow
extends FloatingWindow
## 測試者面板(浮動小視窗):強制觸發指定桌寵的指定對話、動作、事件、狀態鏡與使用者互動,方便測試積木與美術。
## 所有動作都是「強制」的:觸發前會先中止該桌寵目前的積木鏈與動作佔用,無視自主觸發規則與同一事件已在執行的保護。
## 不會存檔、不會改動設定(數值與狀態鏡的設定請用管理視窗);這裡做的事只影響目前這次執行。

const CHAT_CONTEXTS: Array[String] = ["", "chat", "rest", "sleep"]
const CHAT_CONTEXT_LABELS: Array[String] = ["依目前情境", "閒聊 chat", "休息中 rest", "睡眠中 sleep"]
const MAX_LOG_LINES := 80
const STATUS_INTERVAL := 0.25
## 每張卡片的最小寬度(視窗寬就一排放好幾張)。
const CARD_WIDTH := 236.0

var _pets: Array[Node] = []
var _pet: Node
var _pet_option: OptionButton
var _status_label: Label
var _dialogue_option: OptionButton
var _dialogues: Array[Dictionary] = []
var _event_option: OptionButton
var _events: Array[Dictionary] = []
var _context_option: OptionButton
var _action_option: OptionButton
var _variant_spin: SpinBox
var _effect_option: OptionButton
var _follow_seconds_spin: SpinBox
var _lens_list: ItemList
var _run_check: CheckBox
var _mode_option: OptionButton
var _log: TextEdit
var _status_timer := 0.0
var _loading := false
var _flow: HFlowContainer


func setup() -> void:
	setup_floating("測試者面板", Vector2i(560, 760), Vector2i(280, 460))
	# 靠螢幕右側,不要蓋在管理視窗(置中)上面。
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(0))
	place_on_screen.call_deferred(Vector2i((usable.size.x - size.x) / 2 - 20, 0))
	_build()
	_populate_pets()


func _build() -> void:
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	background.add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)

	var pet_row := HBoxContainer.new()
	_pet_option = OptionButton.new()
	_pet_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pet_option.item_selected.connect(_on_pet_selected)
	pet_row.add_child(_pet_option)
	var refresh := ManagerUi.button("重新整理")
	refresh.tooltip_text = "桌寵增減、匯入積木檔後重新讀取清單"
	refresh.pressed.connect(_populate_pets)
	pet_row.add_child(refresh)
	root.add_child(pet_row)
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.theme_type_variation = AppSettings.MUTED_LABEL
	root.add_child(_status_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	# 每個功能一張窄卡片,依視窗寬度自動排成幾欄。
	_flow = HFlowContainer.new()
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", 8)
	_flow.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_flow)

	# 對話
	var card := _new_card("對話")
	_dialogue_option = OptionButton.new()
	_dialogue_option.fit_to_longest_item = false
	_dialogue_option.clip_text = true
	_dialogue_option.clip_text = true
	card.add_child(_dialogue_option)
	card.add_child(_action_button("強制說這句(含選項與其分支)", _force_dialogue))

	# 事件
	card = _new_card("事件")
	_event_option = OptionButton.new()
	_event_option.fit_to_longest_item = false
	_event_option.clip_text = true
	_event_option.clip_text = true
	card.add_child(_event_option)
	card.add_child(_action_button("強制觸發這個事件", _force_event))
	card.add_child(_action_button("事件管理(查看/停用/移除)", func() -> void: ManagerUi.open_event_manager_window(self, _pet)))

	# 說點什麼
	card = _new_card("說點什麼(隨機閒聊)")
	_context_option = OptionButton.new()
	_context_option.fit_to_longest_item = false
	_context_option.clip_text = true
	for label in CHAT_CONTEXT_LABELS:
		_context_option.add_item(label)
	card.add_child(_context_option)
	card.add_child(_action_button("說點什麼", _force_chat))

	# 動作
	card = _new_card("動作")
	_action_option = OptionButton.new()
	_action_option.fit_to_longest_item = false
	_action_option.clip_text = true
	card.add_child(_action_option)
	_variant_spin = ManagerUi.spin(1.0, -1.0, 99.0)
	_variant_spin.value = -1.0
	card.add_child(ManagerUi.labeled("差分(-1=隨機)", _variant_spin))
	var action_row := _button_row()
	action_row.add_child(_action_button("強制播放", _force_action))
	action_row.add_child(_action_button("釋放佔用", func() -> void:
		_pet.release_hold()
		_note("釋放動作佔用")))
	card.add_child(action_row)

	# 特效(程式繪製的角色特效,見 PetEffects;顏色、大小、密度在桌寵管理 → 介面與自動行為 →「特效外觀」)
	card = _new_card("特效")
	_effect_option = OptionButton.new()
	_effect_option.fit_to_longest_item = false
	_effect_option.clip_text = true
	for effect_label in PetEffects.CATALOG:
		_effect_option.add_item(effect_label)
	card.add_child(_effect_option)
	var effect_row := _button_row()
	effect_row.add_child(_action_button("播放", func() -> void:
		var effect_name := _effect_option.text
		var known: bool = _pet.effects.play(effect_name)
		_note(tr("播放特效「%s」%s") % [effect_name, "" if known else "(不認得)"] + ("" if _pet.effects.enabled else "(這隻的角色特效總開關是關的,故不會繪製)"))))
	effect_row.add_child(_action_button("睡覺 Zzz", func() -> void:
		_pet.play_action(&"sleep", -1, true)
		_pet.extend_hold(6.0)
		_note("強制睡覺 6 秒")))
	effect_row.add_child(_action_button("全部停止", func() -> void:
		_pet.effects.stop_all()
		_note("停止所有特效")))
	card.add_child(effect_row)

	# 狀態鏡
	card = _new_card("狀態鏡")
	# 可複選的清單(前面的 ● = 目前生效中);按「啟用所選」或「清除所選狀態鏡」對勾選的全部一起動作。
	_lens_list = ItemList.new()
	_lens_list.select_mode = ItemList.SELECT_MULTI
	_lens_list.custom_minimum_size.y = 120.0
	_lens_list.auto_height = false
	card.add_child(_lens_list)
	var lens_row := _button_row()
	lens_row.add_child(_action_button("啟用所選", func() -> void:
		var names := _selected_lens_names()
		if names.is_empty():
			_note("沒有選任何狀態鏡")
			return
		for lens_name in names:
			_pet.enable_lens(lens_name)
		_note(tr("啟用狀態鏡:%s") % "、".join(names))
		_refresh_lens_list()))
	lens_row.add_child(_action_button("清除所選狀態鏡", func() -> void:
		var names := _selected_lens_names()
		if names.is_empty():
			_note("沒有選任何狀態鏡")
			return
		for lens_name in names:
			_pet.disable_lens(lens_name)
		_note(tr("清除狀態鏡:%s") % "、".join(names))
		_refresh_lens_list()))
	card.add_child(lens_row)

	# 使用者互動
	card = _new_card("模擬使用者互動")
	var user_row := _button_row()
	user_row.add_child(_action_button("點擊", func() -> void:
		_pet.interaction.clicked.emit()
		_note("模擬:點擊")))
	user_row.add_child(_action_button("摸摸", func() -> void:
		_pet.interaction.petted.emit()
		_note("模擬:摸摸")))
	user_row.add_child(_action_button("interact", func() -> void:
		_pet.begin_interact(1.5)
		_pet.interaction.interact_triggered.emit()
		_note("模擬:interact(高頻互動)")))
	user_row.add_child(_action_button("Status", func() -> void:
		_pet.status_requested.emit()
		_note("開關 Status 面板")))
	card.add_child(user_row)

	# 跟著滑鼠(固定與靜止模式的桌寵不會動,不受影響)
	card = _new_card("跟著滑鼠")
	_follow_seconds_spin = ManagerUi.spin(1.0, 3.0, 3600.0)
	_follow_seconds_spin.value = 60.0
	_follow_seconds_spin.suffix = " 秒"
	card.add_child(_follow_seconds_spin)
	var follow_row := _button_row()
	follow_row.add_child(_action_button("這隻", func() -> void:
		_note(tr("這隻跟著滑鼠 %d 秒 → %s") % [int(_follow_seconds_spin.value), _pet.follow_mouse(_follow_seconds_spin.value)])))
	follow_row.add_child(_action_button("全部", func() -> void:
		_note(tr("%d 隻桌寵開始跟著滑鼠(固定與靜止模式的不算)") % follow_all_mouse(_follow_seconds_spin.value))))
	follow_row.add_child(_action_button("停止全部", func() -> void:
		stop_all_mouse_follow()
		_note("全部停止跟著滑鼠")))
	card.add_child(follow_row)

	# 小道具
	card = _new_card("桌面小道具")
	var prop_row := _button_row()
	prop_row.add_child(_action_button("清空桌面道具", func() -> void:
		_note(tr("清掉 %d 個桌面上的道具") % clear_props())))
	card.add_child(prop_row)

	# 靜音
	card = _new_card("這隻的靜音")
	var mute_row := _button_row()
	mute_row.add_child(_action_button("靜音", func() -> void:
		_pet.set_muted(true)
		_note("靜音")))
	mute_row.add_child(_action_button("解除靜音", func() -> void:
		_pet.set_muted(false)
		_note("解除靜音")))
	card.add_child(mute_row)

	# 開關與移動模式
	card = _new_card("開關與移動模式")
	_run_check = CheckBox.new()
	_run_check.text = "run 奔跑開關"
	_run_check.toggled.connect(func(on: bool) -> void:
		if not _loading:
			_pet.run_enabled = on
			_note(tr("run 開關 → %s") % on))
	card.add_child(_run_check)
	_mode_option = OptionButton.new()
	_mode_option.fit_to_longest_item = false
	_mode_option.clip_text = true
	for mode_name in Pet.MODE_LABELS:
		_mode_option.add_item(mode_name)
	_mode_option.item_selected.connect(func(index: int) -> void:
		if not _loading:
			_pet.set_move_mode(index)
			_note(tr("移動模式 → %s") % Pet.MODE_LABELS[index]))
	card.add_child(_mode_option)

	# 紀錄:固定在視窗底部,不放進卡片流(要一直看得到)。
	root.add_child(ManagerUi.heading("紀錄"))
	_log = TextEdit.new()
	_log.editable = false
	_log.custom_minimum_size.y = 110.0
	_log.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(_log)
	root.add_child(_action_button("清除紀錄", func() -> void: _log.text = ""))


## 場上所有桌寵跟著滑鼠 seconds 秒(固定與靜止模式的略過),回傳幾隻開始跟。
func follow_all_mouse(seconds: float) -> int:
	var count := 0
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		if pet.follow_mouse(seconds):
			count += 1
	return count


func stop_all_mouse_follow() -> void:
	for pet: Node in get_tree().get_nodes_in_group("pets"):
		pet.stop_follow_mouse()


## 清空桌面上丟出來的道具,回傳清掉幾個。
func clear_props() -> int:
	var removed := 0
	for manager: Node in get_tree().get_nodes_in_group("prop_manager"):
		removed += (manager as PropManager).clear_all()
	return removed


## 一張窄卡片(有底色的小面板 + 標題),加進 _flow;回傳放內容用的 VBoxContainer。
func _new_card(title_text: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = CARD_WIDTH
	var style := StyleBoxFlat.new()
	style.bg_color = AppSettings.ink(0.05)
	style.border_color = AppSettings.ink(0.14)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8.0)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.add_child(ManagerUi.heading(title_text))
	panel.add_child(box)
	_flow.add_child(panel)
	return box


## 卡片裡的一排按鈕:放不下會自己換行。
func _button_row() -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	return row

func _action_button(text: String, callback: Callable) -> Button:
	var button := ManagerUi.button(text)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func() -> void:
		if _pet != null and is_instance_valid(_pet):
			callback.call())
	return button


func _process(delta: float) -> void:
	_status_timer -= delta
	if _status_timer > 0.0:
		return
	_status_timer = STATUS_INTERVAL
	_refresh_status()


# --- 桌寵與清單 ---

func _populate_pets() -> void:
	var previous := _pet
	_pets.clear()
	_pet_option.clear()
	for pet in get_tree().get_nodes_in_group("pets"):
		_pets.append(pet)
		_pet_option.add_item(pet.get_label())
	if _pets.is_empty():
		_pet = null
		_status_label.text = "場上目前沒有桌寵。"
		return
	var index := maxi(_pets.find(previous), 0)
	_pet_option.select(index)
	_on_pet_selected(index)


func _on_pet_selected(index: int) -> void:
	if _pet != null and is_instance_valid(_pet) and _pet.action_started.is_connected(_on_action_started):
		_pet.action_started.disconnect(_on_action_started)
	_pet = _pets[index]
	_pet.action_started.connect(_on_action_started)
	_reload_lists()
	_refresh_status()


## 重新讀取這隻桌寵的對話、事件、動作、狀態鏡清單(匯入新積木檔或編輯設定後要按「重新整理」)。
func _reload_lists() -> void:
	_loading = true
	_dialogue_option.clear()
	_dialogues = _pet.logic.list_dialogues()
	for entry in _dialogues:
		_dialogue_option.add_item(entry["label"])
	_event_option.clear()
	_events = _pet.logic.list_events()
	for entry in _events:
		_event_option.add_item(entry["label"])
	_action_option.clear()
	for action in SchemaExporter.collect_actions(_pet):
		_action_option.add_item(str(action))
	_lens_list.clear()
	for lens: PetStateLens in _pet.state_lenses:
		_lens_list.add_item(lens.lens_name)
		_lens_list.set_item_metadata(_lens_list.item_count - 1, lens.lens_name)
	_refresh_lens_list()
	_run_check.button_pressed = _pet.run_enabled
	_mode_option.select(int(_pet.move_mode))
	_loading = false


## 清單勾選的狀態鏡名稱。
func _selected_lens_names() -> Array[String]:
	var names: Array[String] = []
	for index in _lens_list.get_selected_items():
		names.append(str(_lens_list.get_item_metadata(index)))
	return names


## 依目前生效的狀態鏡更新清單文字(生效中的前面加 ●),不動勾選。
func _refresh_lens_list() -> void:
	if _pet == null or _lens_list == null:
		return
	for index in _lens_list.item_count:
		var lens_name := str(_lens_list.get_item_metadata(index))
		_lens_list.set_item_text(index, ("● " if _pet.is_lens_active(lens_name) else "") + lens_name)


func _refresh_status() -> void:
	if _pet == null or not is_instance_valid(_pet):
		return
	_refresh_lens_list()
	var lens: String = _pet.current_lens_name()
	_status_label.text = tr("動作:%s | 情境:%s | 狀態鏡:%s | 模式:%s%s") % [
		_pet._current_action if _pet._current_action != &"" else "-",
		_pet.chat_context(),
		lens if lens != "" else "無",
		Pet.MODE_LABELS[int(_pet.move_mode)],
		(" | 佔用中" if _pet._hold_left > 0.0 else "") + (" | 已靜音" if _pet.muted else ""),
	]


# --- 強制觸發 ---

func _force_dialogue() -> void:
	var index := _dialogue_option.selected
	if index < 0 or index >= _dialogues.size():
		_note("沒有可用的對話(這隻桌寵沒有載入積木檔,或積木檔裡沒有對話積木)")
		return
	_pet.logic.force_dialogue(_dialogues[index]["block"])
	_note(tr("強制說:%s") % _dialogues[index]["label"])


func _force_event() -> void:
	var index := _event_option.selected
	if index < 0 or index >= _events.size():
		_note("沒有可用的事件")
		return
	_pet.logic.force_run_hat(_events[index]["hat"])
	_note(tr("強制觸發事件:%s") % _events[index]["label"])


func _force_chat() -> void:
	var context := CHAT_CONTEXTS[_context_option.selected]
	var said: bool = _pet.logic.say_something(context)
	_note(tr("說點什麼(%s)→ %s") % [CHAT_CONTEXT_LABELS[_context_option.selected], "有話可說" if said else "這個情境沒有可說的內容"])


func _force_action() -> void:
	if _action_option.selected < 0:
		return
	_pet.interrupt_scripts()
	_pet.play_action(StringName(_action_option.text), int(_variant_spin.value), true)
	_note(tr("強制播放動作:%s(差分 %d)") % [_action_option.text, int(_variant_spin.value)])


# --- 紀錄 ---

func _on_action_started(action: StringName) -> void:
	_note(tr("動作開始:%s") % action)


func _note(text: String) -> void:
	var stamp := Time.get_time_string_from_system()
	_log.text += "[%s] %s\n" % [stamp, text]
	var lines := _log.text.split("\n")
	if lines.size() > MAX_LOG_LINES:
		_log.text = "\n".join(lines.slice(lines.size() - MAX_LOG_LINES))
	_log.scroll_vertical = _log.get_line_count()
