class_name TarotPanel
extends PanelContainer
## 塔羅牌占卜結果的懸浮面板(右鍵選單「幫我占卜…→塔羅牌」):顯示抽到的牌名與正逆位,不解讀(使用者明確
## 要求)。流程是先在 TarotPickBoard 選牌(牌背,見那邊的說明),選完才翻開到這個面板——這裡只負責顯示。
## 卡牌畫面目前是直長方形的色塊佔位(2026-10-04:使用者會之後提供真正的卡牌素材,先用程式畫的色塊佔位,
## 不自己繪製/生成圖像素材檔,見 feedback-no-generated-art;素材到位後把 _make_card() 的 ColorRect 換成
## 真正的卡牌貼圖即可,其餘排版/收起邏輯不用動)。
## 版面與收起邏輯抄 StatusPanel 的樣子(點擊收起、滑鼠離開一段時間後自動收起),但不需要它的數值即時更新那些。

signal closed

const HOVER_GRACE := 10.0
const CARD_WIDTH := 60.0
const CARD_HEIGHT := 100.0

var pet: Node
## 顯示在桌寵左側嗎(管理器排版用的遲滯旗標,預設右側)。
var flipped := false

var _style: PetUiStyle
var _factor := 1.0
var _font: Font
var _tag: PanelContainer
var _hovered := false
var _idle_left := HOVER_GRACE
var _closed := false


func setup(target_pet: Node, question: String, cards: Array[Dictionary]) -> void:
	pet = target_pet
	_style = pet.ui_style
	_factor = _style.scale_factor()
	_font = UiFonts.get_font(_style.default_font)
	add_to_group("Cutout")
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyleKit.panel_style(_style, _factor))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(6 * _factor))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	if question != "":
		column.add_child(_make_label(tr("占卜:%s") % question, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(8 * _factor))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for card: Dictionary in cards:
		row.add_child(_make_card(card))
	_tag = UiStyleKit.name_tag(pet.get_label(), _font, _style, _factor)
	add_child(_tag)
	_tag.top_level = true
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func _make_card(card: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(2 * _factor))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var placeholder := ColorRect.new()
	placeholder.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT) * _factor
	placeholder.color = _style.option
	box.add_child(placeholder)
	box.add_child(_make_label(str(card.get("name", "")), false))
	box.add_child(_make_label(TarotDeck.orientation_text(bool(card.get("reversed", false))), false))
	return box


func _make_label(text: String, wrap: bool) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", _font)
	label.add_theme_font_size_override("font_size", int(UiStyleKit.BASE_FONT_SIZE * _style.text_scale_factor()))
	label.add_theme_color_override("font_color", _style.text)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = 200.0 * _factor
	return label


func _process(delta: float) -> void:
	if _closed:
		return
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
	closed.emit()


func global_rect() -> Rect2:
	return Rect2(global_position, size)


func get_cutout_polygons() -> Array:
	if not is_visible_in_tree():
		return []
	var rect := Rect2(global_position, size.max(get_combined_minimum_size()))
	return [DialogueBubble._rect_polygon(rect), DialogueBubble._rect_polygon(Rect2(_tag.global_position, _tag.size))]


## 名字標籤跨在面板上緣之外的高度(排版時上緣要多留,見 DialogueBubble.tag_overhang)。
func tag_overhang() -> float:
	return ceilf(_tag.get_combined_minimum_size().y * 0.5)


func place_tag() -> void:
	UiStyleKit.place_tag(_tag, self, _factor)
