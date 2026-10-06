class_name LensEditorTab
extends HSplitContainer
## 狀態鏡管理分頁(企劃書第四章「數值狀態鏡」):左邊是這隻桌寵的鏡片清單(由上到下 = 優先度由高到低,可上下移),
## 右邊編輯名稱、差分前綴、性質標籤(正面/負面/持續,可複選)、自動逾時區間、以及要覆蓋哪些行動物理數值。
## 另附「設定檢查」(互鎖循環、找不到解除路徑,只是警告)與「測試啟用/解除」按鈕方便當場看效果。

signal changed
signal message(text: String)

const PARAM_LABELS := {
	&"move_speed": "移動速度",
	&"run_speed_multiplier": "奔跑速度倍率",
	&"gravity_scale": "重力縮放",
	&"jump_variance": "平時跳躍浮動(比例)",
	&"max_jump_velocity": "最大跳躍力道",
	&"terminal_fall_velocity": "最大下落速度",
	&"idle_duration_min": "待機時間(最短秒)",
	&"idle_duration_max": "待機時間(最長秒)",
	&"walk_duration_min": "行走時間(最短秒)",
	&"walk_duration_max": "行走時間(最長秒)",
	&"jump_velocity": "跳躍初速度",
	&"jump_air_speed_multiplier": "空中水平速度倍率",
	&"hop_chance_per_second": "順手跳躍機率(每秒)",
	&"edge_drop_chance": "走下邊緣機率",
	&"restitution": "彈跳度(漂浮)",
	&"float_min_speed": "漂浮最低速度",
}

var _pet: Node
var _list: ItemList
var _form: VBoxContainer
var _loading := false

var _name_edit: LineEdit
var _prefix_edit: LineEdit
var _nature_checks: Dictionary = {}
var _timeout_min_spin: SpinBox
var _timeout_max_spin: SpinBox
var _continue_spin: SpinBox
var _decay_spin: SpinBox
var _rounds_spin: SpinBox
var _force_run_check: CheckBox
var _mood_callable_check: CheckBox
var _override_checks: Dictionary = {}
var _override_spins: Dictionary = {}
var _behavior_checks: Dictionary = {}
var _behavior_spins: Dictionary = {}
var _behavior_baseline_labels: Dictionary = {}
var _active_label: Label
var _toggle_button: Button
var _report: TextEdit


func _ready() -> void:
	name = "狀態鏡"
	_build_list_side()
	_build_form_side()


func set_pet(pet: Node) -> void:
	if _pet != null and _pet.active_state_lens_changed.is_connected(_on_active_changed):
		_pet.active_state_lens_changed.disconnect(_on_active_changed)
	_pet = pet
	if _pet != null:
		_pet.active_state_lens_changed.connect(_on_active_changed)
	_rebuild_list()


func _build_list_side() -> void:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 230.0
	add_child(side)
	side.add_child(ManagerUi.heading("狀態鏡(上 = 優先度高)"))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_item_selected)
	side.add_child(_list)
	var row1 := HBoxContainer.new()
	var add := ManagerUi.button("新增")
	add.pressed.connect(_add_lens)
	var delete := ManagerUi.button("刪除")
	delete.pressed.connect(_delete_selected)
	row1.add_child(add)
	row1.add_child(delete)
	side.add_child(row1)
	var row2 := HBoxContainer.new()
	var up := ManagerUi.button("提高優先度 ↑")
	up.pressed.connect(_move_selected.bind(-1))
	var down := ManagerUi.button("降低 ↓")
	down.pressed.connect(_move_selected.bind(1))
	row2.add_child(up)
	row2.add_child(down)
	side.add_child(row2)
	var check := ManagerUi.button("執行設定檢查")
	check.pressed.connect(_run_check)
	side.add_child(check)
	_report = TextEdit.new()
	_report.editable = false
	_report.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_report.custom_minimum_size.y = 110.0
	_report.placeholder_text = tr("設定檢查結果會顯示在這裡(只是警告,不會阻止儲存)。")
	side.add_child(_report)


func _build_form_side() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_form = VBoxContainer.new()
	_form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_form)

	_form.add_child(ManagerUi.heading("基本設定"))
	_name_edit = ManagerUi.line_edit("鏡片名稱(積木下拉選單與 Status 面板顯示)")
	_name_edit.text_submitted.connect(func(_t: String) -> void: _commit_name())
	_name_edit.focus_exited.connect(_commit_name)
	_form.add_child(ManagerUi.labeled("名稱", _name_edit))
	_prefix_edit = ManagerUi.line_edit("例如 tired_ → 優先找 tired_idle_0、tired_walk_0")
	_prefix_edit.text_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("差分前綴", _prefix_edit))
	var nature_row := HBoxContainer.new()
	for tag in PetStateLens.NATURES:
		var box := CheckBox.new()
		box.text = tag
		box.toggled.connect(_on_field_changed)
		_nature_checks[tag] = box
		nature_row.add_child(box)
	_form.add_child(ManagerUi.labeled("性質標籤", nature_row))
	_timeout_min_spin = ManagerUi.spin(0.5, 0.0, 86400.0)
	_timeout_min_spin.value_changed.connect(_on_field_changed)
	_timeout_max_spin = ManagerUi.spin(0.5, 0.0, 86400.0)
	_timeout_max_spin.value_changed.connect(_on_field_changed)
	var timeout_row := HBoxContainer.new()
	_timeout_min_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_timeout_max_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeout_row.add_child(_timeout_min_spin)
	timeout_row.add_child(Label.new())
	(timeout_row.get_child(1) as Label).text = " ~ "
	timeout_row.add_child(_timeout_max_spin)
	_form.add_child(ManagerUi.labeled("自動逾時解除(秒)", timeout_row))
	_form.add_child(ManagerUi.hint_row("說明", "兩格都是 0 = 不逾時;最小≠最大時每次啟用在區間內隨機取值。"))
	_continue_spin = ManagerUi.spin(0.05, 0.0, 1.0)
	_continue_spin.value_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("延續機率", _continue_spin))
	_decay_spin = ManagerUi.spin(0.05, 0.0, 1.0)
	_decay_spin.value_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("每輪衰減", _decay_spin))
	_rounds_spin = ManagerUi.spin(1.0, 1.0, 50.0)
	_rounds_spin.value_changed.connect(_on_field_changed)
	_form.add_child(ManagerUi.labeled("最多幾輪", _rounds_spin))
	_form.add_child(ManagerUi.hint_row("延續執行判定", "逾時到期時擲骰決定要不要再延續一輪(時間重新在上面的區間內抽):機率 = 延續機率 × 每輪衰減^(已完成輪數 − 1),一輪比一輪低,滿「最多幾輪」一定結束(和睡覺的「再睡一輪」同一種做法)。延續機率 0 = 不延續。要先設自動逾時才有作用。"))
	_force_run_check = CheckBox.new()
	_force_run_check.text = tr("啟用期間奔跑(走路變成 run 動作與奔跑速度,疲勞消耗也比較多)")
	_force_run_check.toggled.connect(_on_field_changed)
	_form.add_child(_force_run_check)
	_mood_callable_check = CheckBox.new()
	_mood_callable_check.text = tr("可以被心情門檻叫出來(心情偏高 / 偏低時,依「正面 / 負面」性質挑選)")
	_mood_callable_check.toggled.connect(_on_field_changed)
	_form.add_child(_mood_callable_check)
	_form.add_child(ManagerUi.hint_row("「奔跑」狀態鏡", "名字叫「奔跑」的狀態鏡是桌寵「自己決定跑一下」時啟用的那一個:跑多久、要不要延續、跑多快都在這裡調;什麼時候會自己起跑由性格參數決定(活潑的不管心情、其他的開心或贏了遊戲時才判定,有的性格完全不跑)。"))

	_form.add_child(HSeparator.new())
	_form.add_child(ManagerUi.heading("覆蓋行動物理數值(勾選的才覆蓋)"))
	for prop: StringName in PetStateLens.OVERRIDABLE:
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		check.text = str(PARAM_LABELS.get(prop, prop))
		check.custom_minimum_size.x = ManagerUi.LABEL_WIDTH + 60.0
		check.toggled.connect(_on_field_changed)
		var spin := ManagerUi.spin(0.01, -100000.0, 100000.0)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_on_field_changed)
		row.add_child(check)
		row.add_child(spin)
		_override_checks[prop] = check
		_override_spins[prop] = spin
		_form.add_child(row)

	_form.add_child(HSeparator.new())
	_form.add_child(ManagerUi.heading_with_info("這個狀態下容易呼叫的行為(勾選的才覆蓋倍率)", "跟上面的行動物理數值不一樣,這裡調的是「桌寵自己決定要不要做某件事」的機率倍率(1 = 不變,跟性格在一般狀態下的值相乘;例如設 2 表示這個狀態鏡生效時機率變兩倍)。灰色小字是這隻桌寵在一般狀態下(沒有這個狀態鏡時)的參考數值,方便抓倍率該設多少。「開心」「悠哉」「緊張」「生氣」「悲傷」「疲憊」這六個內建名稱本來就有一套固定效果(見主企劃書),這裡設的倍率是疊加上去,不是取代。"))
	for key: String in PetStateLens.BEHAVIOR_KEYS:
		var row := HBoxContainer.new()
		var check := CheckBox.new()
		check.text = str(PetStateLens.BEHAVIOR_LABELS.get(key, key))
		check.custom_minimum_size.x = ManagerUi.LABEL_WIDTH + 60.0
		check.toggled.connect(_on_field_changed)
		var spin := ManagerUi.spin(0.05, 0.0, 20.0)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(_on_field_changed)
		row.add_child(check)
		row.add_child(spin)
		_behavior_checks[key] = check
		_behavior_spins[key] = spin
		_form.add_child(row)
		var baseline := Label.new()
		baseline.theme_type_variation = AppSettings.MUTED_LABEL
		baseline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_behavior_baseline_labels[key] = baseline
		_form.add_child(baseline)

	_form.add_child(HSeparator.new())
	_form.add_child(ManagerUi.heading("測試"))
	_active_label = Label.new()
	_form.add_child(_active_label)
	_toggle_button = ManagerUi.button("啟用這個狀態鏡")
	_toggle_button.pressed.connect(_toggle_active)
	_form.add_child(_toggle_button)
	_form.visible = false


# --- 列表 ---

func _rebuild_list(select: PetStateLens = null) -> void:
	_list.clear()
	if _pet == null:
		_form.visible = false
		return
	for lens: PetStateLens in _pet.state_lenses:
		_list.add_item(lens.lens_name)
	var index: int = _pet.state_lenses.find(select) if select != null else -1
	if index < 0 and not _pet.state_lenses.is_empty():
		index = 0
	if index >= 0:
		_list.select(index)
		_load_form(_pet.state_lenses[index])
	else:
		_form.visible = false


func _selected() -> PetStateLens:
	var picked := _list.get_selected_items()
	if _pet == null or picked.is_empty() or picked[0] >= _pet.state_lenses.size():
		return null
	return _pet.state_lenses[picked[0]]


func _on_item_selected(index: int) -> void:
	_load_form(_pet.state_lenses[index])


func _load_form(lens: PetStateLens) -> void:
	_loading = true
	_form.visible = true
	_name_edit.text = lens.lens_name
	_prefix_edit.text = lens.prefix
	for tag: String in _nature_checks:
		_nature_checks[tag].button_pressed = lens.has_nature(tag)
	_timeout_min_spin.value = lens.timeout_min
	_timeout_max_spin.value = lens.timeout_max
	_continue_spin.value = lens.continue_chance
	_decay_spin.value = lens.continue_decay
	_rounds_spin.value = lens.max_rounds
	_force_run_check.button_pressed = lens.force_run
	_mood_callable_check.button_pressed = lens.is_mood_callable()
	for prop: StringName in PetStateLens.OVERRIDABLE:
		var enabled := lens.movement_overrides.has(String(prop))
		_override_checks[prop].button_pressed = enabled
		_override_spins[prop].value = float(lens.movement_overrides.get(String(prop), _pet.base_param(prop)))
		_override_spins[prop].editable = enabled
	for key: String in PetStateLens.BEHAVIOR_KEYS:
		var behavior_enabled: bool = lens.behavior_overrides.has(key)
		_behavior_checks[key].button_pressed = behavior_enabled
		_behavior_spins[key].value = float(lens.behavior_overrides.get(key, 1.0))
		_behavior_spins[key].editable = behavior_enabled
		(_behavior_baseline_labels[key] as Label).text = tr("一般狀態下的參考值:%s") % _behavior_baseline_text(key)
	_update_active_ui()
	_loading = false


## 「一般狀態下」(沒有任何狀態鏡影響)的參考數值,給使用者抓倍率用;不是精確的機率,只是同一個量級的參考數字。
func _behavior_baseline_text(key: String) -> String:
	if _pet == null:
		return "?"
	match key:
		"dance":
			return tr("自主跳舞判定機率 %s") % _pet.auto_dance_chance
		"run":
			var chance: float = _pet.vitality.run_chance if _pet.vitality != null else 0.0
			return tr("自主奔跑判定機率 %s(0 = 沒有固定機率,只有特定心情才有一點機會)") % chance if chance <= 0.0 else tr("自主奔跑判定機率 %s") % chance
		"rest":
			return tr("睡醒/被打斷後 %s 秒內不會又自己去休息") % PetVitality.REST_COOLDOWN
		"game_invite":
			return tr("主動邀請對戰的基準機率 %s") % _pet.game_ask_chance
	return "?"


# --- 編輯 ---

func _on_field_changed(_value: Variant = null) -> void:
	var lens := _selected()
	if _loading or lens == null:
		return
	lens.prefix = _prefix_edit.text
	var nature := PackedStringArray()
	for tag: String in PetStateLens.NATURES:
		if _nature_checks[tag].button_pressed:
			nature.append(tag)
	lens.nature = nature
	lens.timeout_min = _timeout_min_spin.value
	lens.timeout_max = _timeout_max_spin.value
	lens.continue_chance = _continue_spin.value
	lens.continue_decay = _decay_spin.value
	lens.max_rounds = int(_rounds_spin.value)
	lens.force_run = _force_run_check.button_pressed
	lens.mood_callable = 1 if _mood_callable_check.button_pressed else 0
	var overrides := {}
	for prop: StringName in PetStateLens.OVERRIDABLE:
		var enabled: bool = _override_checks[prop].button_pressed
		_override_spins[prop].editable = enabled
		if enabled:
			overrides[String(prop)] = snappedf(_override_spins[prop].value, 0.0001)
	lens.movement_overrides = overrides
	var behavior_overrides := {}
	for key: String in PetStateLens.BEHAVIOR_KEYS:
		var behavior_enabled: bool = _behavior_checks[key].button_pressed
		_behavior_spins[key].editable = behavior_enabled
		if behavior_enabled:
			behavior_overrides[key] = snappedf(_behavior_spins[key].value, 0.01)
	lens.behavior_overrides = behavior_overrides
	_pet.reapply_lenses()
	changed.emit()


## 鏡片名稱要唯一;改名時如果它正啟用中先解除(啟用狀態是用名稱記的)。
func _commit_name() -> void:
	var lens := _selected()
	if _loading or lens == null:
		return
	var new_name := _name_edit.text.strip_edges()
	if new_name == lens.lens_name:
		return
	if new_name == "":
		message.emit("狀態鏡名稱不能是空的,已還原。")
		_name_edit.text = lens.lens_name
		return
	for other: PetStateLens in _pet.state_lenses:
		if other != lens and other.lens_name == new_name:
			message.emit(tr("已經有叫「%s」的狀態鏡,請換一個名稱,已還原。") % new_name)
			_name_edit.text = lens.lens_name
			return
	_pet.disable_lens(lens.lens_name)
	lens.lens_name = new_name
	_list.set_item_text(_pet.state_lenses.find(lens), new_name)
	_pet.reapply_lenses()
	changed.emit()


func _add_lens() -> void:
	if _pet == null:
		return
	var lens := PetStateLens.new()
	var index := 1
	while _pet._find_lens(tr("新狀態鏡%d") % index) != null:
		index += 1
	lens.lens_name = tr("新狀態鏡%d") % index
	_pet.state_lenses.append(lens)
	_rebuild_list(lens)
	changed.emit()


func _delete_selected() -> void:
	var lens := _selected()
	if lens == null:
		return
	_pet.state_lenses.erase(lens)
	_pet.reapply_lenses()
	_rebuild_list()
	changed.emit()


## 調整優先度:陣列順序就是優先度,往上 = 提高。
func _move_selected(direction: int) -> void:
	var lens := _selected()
	if lens == null:
		return
	var index: int = _pet.state_lenses.find(lens)
	var target := index + direction
	if target < 0 or target >= _pet.state_lenses.size():
		return
	_pet.state_lenses.remove_at(index)
	_pet.state_lenses.insert(target, lens)
	_pet.reapply_lenses()
	_rebuild_list(lens)
	changed.emit()


func _run_check() -> void:
	if _pet == null:
		return
	_report.text = "\n".join(PackedStringArray(LensChecker.check(_pet)))


# --- 測試啟用 ---

func _toggle_active() -> void:
	var lens := _selected()
	if lens == null:
		return
	if _pet.is_lens_active(lens.lens_name):
		_pet.disable_lens(lens.lens_name)
	else:
		_pet.enable_lens(lens.lens_name)
	_update_active_ui()


func _on_active_changed(_lens_name: String) -> void:
	_update_active_ui()


func _update_active_ui() -> void:
	var lens := _selected()
	if lens == null or _pet == null:
		return
	var active: bool = _pet.is_lens_active(lens.lens_name)
	var top: String = _pet.current_lens_name()
	_active_label.text = tr("這個狀態鏡:%s;目前實際生效的鏡片:%s") % [tr("啟用中") if active else tr("未啟用"), top if top != "" else tr("無")]
	_toggle_button.text = tr("解除這個狀態鏡") if active else tr("啟用這個狀態鏡")
