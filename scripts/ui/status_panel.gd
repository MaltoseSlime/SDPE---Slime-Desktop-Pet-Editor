class_name StatusPanel
extends PanelContainer
## 桌寵的 Status 面板(企劃書第六章「桌面 Status 菜單與白名單顯示機制」):右鍵選單「查看狀態」後,
## 在桌寵身旁彈出的懸浮面板。用該桌寵的專屬配色、半透明背景與名字標籤;只顯示創作者勾選「在 Status 中顯示」
## 的數值(預設全部隱藏,避免洩露中介變數或彩蛋),依排序權重排列,可選純文字或進度條,支援前後綴與小圖示;
## 有狀態鏡的桌寵另外顯示目前生效的狀態鏡。數值或狀態鏡改變時即時更新。
##
## 收起方式:點擊面板,或滑鼠離開面板超過 HOVER_GRACE 秒(滑鼠停在面板上就不會自動收起)。

signal closed

## 精力/心情條每隔這麼多秒重畫一次(它們一直在變,不像數值只在被改時才通知)。
const VITALS_REFRESH := 1.0
const HOVER_GRACE := 8.0
const BASE_WIDTH := 200.0

var pet: Node
## 顯示在桌寵左側嗎(管理器排版用的遲滯旗標,預設右側)。
var flipped := false

var _style: PetUiStyle
var _state: Node
var _font: Font
var _factor := 1.0
var _column: VBoxContainer
var _tag: PanelContainer
var _hovered := false
var _idle_left := HOVER_GRACE
var _closed := false
var _vitals_left := VITALS_REFRESH


func setup(target_pet: Node) -> void:
	pet = target_pet
	_state = get_node("/root/DesktopShellState")
	_style = pet.ui_style
	_factor = _style.scale_factor()
	_font = UiFonts.get_font(_style.default_font)
	add_to_group("Cutout")
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyleKit.panel_style(_style, _factor))
	custom_minimum_size.x = BASE_WIDTH * _factor
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", int(6 * _factor))
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_tag = UiStyleKit.name_tag(pet.get_label(), _font, _style, _factor)
	add_child(_tag)
	_tag.top_level = true
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)
	_state.value_updated.connect(_on_value_updated)
	pet.active_state_lens_changed.connect(_on_lens_changed)
	_rebuild()


func _process(delta: float) -> void:
	if _closed:
		return
	if pet.status_show_energy or pet.status_show_mood:
		_vitals_left -= delta
		if _vitals_left <= 0.0:
			_vitals_left = VITALS_REFRESH
			_rebuild()
	if _hovered:
		_idle_left = HOVER_GRACE
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		close()


func _gui_input(event: InputEvent) -> void:
	if _closed or not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	close()


func close() -> void:
	if _closed:
		return
	_closed = true
	if _state.value_updated.is_connected(_on_value_updated):
		_state.value_updated.disconnect(_on_value_updated)
	if is_instance_valid(pet) and pet.active_state_lens_changed.is_connected(_on_lens_changed):
		pet.active_state_lens_changed.disconnect(_on_lens_changed)
	closed.emit()


func global_rect() -> Rect2:
	return Rect2(global_position, size)


func get_cutout_polygons() -> Array:
	if not is_visible_in_tree():
		return []
	# 標籤突出在面板外的部分也要算進穿透多邊形,否則會被視窗區域裁掉(見 DialogueBubble.get_cutout_polygons)。
	# 尺寸取「目前最小尺寸」與 size 較大者:容器重排是延遲到影格尾端的(理由見 DialogueBubble._cutout_rect)。
	var rect := Rect2(global_position, size.max(get_combined_minimum_size()))
	return [DialogueBubble._rect_polygon(rect), DialogueBubble._rect_polygon(Rect2(_tag.global_position, _tag.size))]


## 名字標籤跨在面板上緣之外的高度(排版時上緣要多留,見 DialogueBubble.tag_overhang)。
func tag_overhang() -> float:
	return ceilf(_tag.get_combined_minimum_size().y * 0.5)


func place_tag() -> void:
	UiStyleKit.place_tag(_tag, self, _factor)


func _on_value_updated(_pet: Node, _scope: String, _key: String, _new_value: float, _old_value: float) -> void:
	_rebuild()


func _on_lens_changed(_lens_name: String) -> void:
	_rebuild()


## 依目前的白名單與數值重建所有列(列數很少,重建比逐列更新簡單也不容易出錯)。
func _rebuild() -> void:
	for child in _column.get_children():
		_column.remove_child(child)
		child.queue_free()
	var defs := ValueGateway.status_defs(pet)
	for def in defs:
		_column.add_child(_make_value_row(def))
	if pet.status_show_energy:
		_column.add_child(_make_energy_row())
	if pet.status_show_mood:
		_column.add_child(_make_mood_row())
	if not pet.state_lenses.is_empty():
		var lens_name: String = pet.current_lens_name()
		_column.add_child(_make_label(tr("目前狀態") + "：" + (lens_name if lens_name != "" else tr("正常"))))
	if _column.get_child_count() == 0:
		_column.add_child(_make_label(tr("沒有可顯示的狀態")))
	reset_size()


func _make_value_row(def: PetValueDef) -> Control:
	var value := ValueGateway.get_value(pet, def.key)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", int(2 * _factor))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(4 * _factor))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
	if def.icon != null:
		var icon := TextureRect.new()
		icon.texture = def.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2.ONE * 16.0 * _factor
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
	line.add_child(_make_label("%s：%s" % [def.label(), def.format_text(value)]))
	if def.display_mode == PetValueDef.DisplayMode.BAR and def.has_max():
		row.add_child(_make_bar(def, value))
	elif def.display_mode == PetValueDef.DisplayMode.GAUGE and def.has_finite_range():
		row.add_child(_make_gauge(def, value))
	return row


## 精力條:填到目前精力,刻度標「累了」(tired_threshold)與「累到睡著」(exhausted_threshold),底下一行是休息階段。疲勞機制關閉時只說明這隻不會累。
func _make_energy_row() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", int(2 * _factor))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vitality: PetVitality = pet.vitality
	if vitality == null or not vitality.fatigue_enabled():
		row.add_child(_make_label(tr("精力") + "：" + tr("不會累")))
		return row
	var stage: String = {PetVitality.Mode.ACTIVE: tr("活動中"), PetVitality.Mode.STANDING: tr("站著休息"), PetVitality.Mode.RESTING: tr("坐著休息"), PetVitality.Mode.SLEEPING: tr("睡覺中")}.get(vitality.mode, "")
	row.add_child(_make_label("%s：%d%%　%s" % [tr("精力"), int(vitality.energy), stage]))
	var bar := ThresholdBar.new()
	bar.setup(0.0, PetVitality.MAX_ENERGY, vitality.energy, [vitality.exhausted_threshold, vitality.tired_threshold], _style.option, _style.text, _factor)
	row.add_child(bar)
	return row


## 心情條:填到目前心情(0~100),刻度標「生氣」門檻與「開心」門檻,文字寫目前偏哪一邊。
func _make_mood_row() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", int(2 * _factor))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vitality: PetVitality = pet.vitality
	if vitality == null:
		return row
	row.add_child(_make_label("%s：%d（%s）" % [tr("心情"), int(vitality.mood), tr(vitality.mood_text())]))
	var bar := ThresholdBar.new()
	bar.setup(0.0, 100.0, vitality.mood, [vitality.mood_angry_threshold, vitality.mood_happy_threshold], _style.option, _style.text, _factor)
	row.add_child(bar)
	return row


## 心情量表:漸層色的槓 + 三角形標記目前數值(需要有限的上下限才畫得出範圍)。
func _make_gauge(def: PetValueDef, value: float) -> GaugeBar:
	var gauge := GaugeBar.new()
	gauge.setup(def.min_value, def.max_value, value, def.gauge_reverse, _factor, _style.text)
	return gauge


func _make_bar(def: PetValueDef, value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0 if def.min_value < -1.0e8 else def.min_value
	bar.max_value = def.max_value
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8.0 * _factor
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.0, 0.0, 0.0, 0.35)
	background.set_corner_radius_all(int(4 * _factor))
	var fill := StyleBoxFlat.new()
	fill.bg_color = _style.option
	fill.set_corner_radius_all(int(4 * _factor))
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", int(UiStyleKit.BASE_FONT_SIZE * _style.text_scale_factor()))
	label.add_theme_color_override("font_color", _style.text)
	return label
