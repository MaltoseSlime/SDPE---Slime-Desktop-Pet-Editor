class_name DialogueBubble
extends PanelContainer
## 一隻桌寵的對話氣泡(企劃書第六章):StyleBoxFlat 程序化繪製、名字標籤嵌在左上角邊框、打字機效果、
## 點擊推進或靜置秒數自動跳下一句、句尾選項按鈕。位置由 DialogueManager 統一排版,氣泡自己只負責內容與輸入。
##
## 氣泡在 Cutout group 裡提供自己的矩形,才收得到點擊(視窗其餘部分是穿透的)。

signal advanced(choice: int)

const TYPEWRITER_CPS := 30.0
const BASE_FONT_SIZE := UiStyleKit.BASE_FONT_SIZE
const BASE_WIDTH := 260.0
const CUTOUT_MARGIN := 6.0
## 版面剛變動(剛出現、選項顯示、換行重排)後的頭幾次穿透形狀查詢多留這麼大一圈,等版面穩定。
const SETTLE_GROW := 48.0
const SETTLE_QUERIES := 4
static var ICON_REGEX := RegEx.create_from_string("\\[icon=([^\\]]+)\\]")
## 氣泡支援的樣式標籤(HTML 編輯器的 BBCode 工具列與預覽以此為準):粗體/斜體/底線/刪除線、顏色、字級、置中/靠右、
## 文字特效(波浪/抖動/彩虹/脈動)。圖示標記夾在標籤中間時要跨段延續這些標籤(見 _append_segment)。
static var STYLE_TAG_REGEX := RegEx.create_from_string("\\[(/?)(b|i|u|s|color|font_size|center|right|wave|shake|rainbow|pulse)((?:[= ][^\\]]*)?)\\]")
## 斜體用的傾斜變換(RichTextLabel 的 [i] 用 italics_font;系統字型沒有斜體字重,所以用變形模擬)。
const ITALIC_SKEW := 0.2
const BOLD_EMBOLDEN := 0.7
## 「等點擊」的句子(line["wait_click"],例如桌寵主動問使用者稱呼這類重要對話)放著不管這麼久就自動關掉,避免氣泡永遠掛在桌面上。
const IDLE_DISMISS_SECONDS := 30.0
## 沒有選項、也沒設自動秒數、也不是「等點擊」的一般句子:打完字後依字數自動收起(不必等人點;點一下仍可提早跳下一句)。
## 停留秒數 = 基本 + 每個可見字元 × 每字,夾在上下限之間。
const READ_BASE_SECONDS := 1.0
const READ_SECONDS_PER_CHAR := 0.1
const READ_MIN_SECONDS := 1.8
const READ_MAX_SECONDS := 10.0

var pet: Node
## 目前是垂直翻轉(顯示在腳底下方)嗎;排版管理器用來做遲滯,避免兩個選擇之間來回跳動。
var flipped := false
var bind_action: StringName = &""
## 思考泡泡(line["bubble"] = "thought"):配色用 PetUiStyle 的 thought_*,圓角更大,尾巴是往桌寵頭部排的幾顆小圓泡泡(見 ThoughtTail)。
var is_thought := false

var _style: PetUiStyle
var _state: Node
var _label: RichTextLabel
var _tail: ThoughtTail
var _tag: PanelContainer
var _option_box: VBoxContainer
var _typing := false
var _type_progress := 0.0
var _idle_left := 0.0
var _auto_seconds := 0.0
## 有選項時額外要求的最短等待秒數(桌寵發起的提問要停留很久);沒指定就用風格設定的「選項最長等待」。
var _patience := 0.0
var _wait_click := false
var _option_scroll: ScrollContainer
var _has_options := false
var _closed := false
var _peeking := false
var _peek_left := 0.0
var _saved_text := ""
var _raw_text := ""
var _saved_options_visible := false
var _settle_left := SETTLE_QUERIES
var _previous_rect := Rect2()


## 建立氣泡內容。line 格式見 DesktopShellState.dialogue_line_requested。
func setup(target_pet: Node, line: Dictionary) -> void:
	pet = target_pet
	_state = get_node("/root/DesktopShellState")
	_style = pet.ui_style
	bind_action = StringName(str(line.get("bind_action", "")))
	_auto_seconds = float(line.get("auto_seconds", 0.0))
	_patience = float(line.get("patience", 0.0))
	_wait_click = bool(line.get("wait_click", false))
	var factor := _style.scale_factor()
	var font := UiFonts.get_font(str(line.get("font", "")), _style.default_font)
	var options: Array = line.get("options", [])
	_has_options = not options.is_empty()
	is_thought = str(line.get("bubble", "speech")).to_lower() == "thought"
	var colors := _style.palette(is_thought)

	add_to_group("Cutout")
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiStyleKit.panel_style(_style, factor, is_thought))
	if is_thought:
		_tail = ThoughtTail.new()
		add_child(_tail)
		# 尾巴的圓要不透明,不然半透明的泡泡底色會讓圓和框線疊出雜色。
		var tail_fill: Color = colors["background"]
		tail_fill.a = maxf(tail_fill.a, 0.9)
		_tail.setup(tail_fill, colors["border"], float(maxi(_style.border_width, 1)), factor)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(6 * factor))
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_label = RichTextLabel.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # 桌寵說的話是內容,不是介面文字:不要被介面翻譯表(ui_strings.csv)改到
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_label.custom_minimum_size.x = BASE_WIDTH * factor
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 粗體/斜體:系統字型不一定有對應字重,這裡用 FontVariation 加粗與傾斜,[b][i] 才看得出效果。
	var bold_font := FontVariation.new()
	bold_font.base_font = font
	bold_font.variation_embolden = BOLD_EMBOLDEN
	var italic_font := FontVariation.new()
	italic_font.base_font = font
	italic_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(ITALIC_SKEW, 1.0), Vector2.ZERO)
	var bold_italic_font := FontVariation.new()
	bold_italic_font.base_font = font
	bold_italic_font.variation_embolden = BOLD_EMBOLDEN
	bold_italic_font.variation_transform = italic_font.variation_transform
	_label.add_theme_font_override("normal_font", font)
	_label.add_theme_font_override("bold_font", bold_font)
	_label.add_theme_font_override("italics_font", italic_font)
	_label.add_theme_font_override("bold_italics_font", bold_italic_font)
	var text_factor := _style.text_scale_factor()
	_label.add_theme_font_size_override("normal_font_size", int(BASE_FONT_SIZE * text_factor))
	_label.add_theme_font_size_override("bold_font_size", int(BASE_FONT_SIZE * text_factor))
	_label.add_theme_font_size_override("italics_font_size", int(BASE_FONT_SIZE * text_factor))
	_label.add_theme_font_size_override("bold_italics_font_size", int(BASE_FONT_SIZE * text_factor))
	_label.add_theme_color_override("default_color", colors["text"])
	column.add_child(_label)
	_set_content(str(line.get("text", "")))

	# 選項一行一個、文字太長自動換行;選項很多時放進捲動區(高度上限見 _fit_option_scroll),不讓氣泡長到超出螢幕。
	_option_scroll = ScrollContainer.new()
	_option_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_option_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_option_scroll)
	_option_box = VBoxContainer.new()
	_option_box.add_theme_constant_override("separation", int(4 * factor))
	_option_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_option_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_option_box.visible = false
	_option_scroll.add_child(_option_box)
	for i in options.size():
		_option_box.add_child(_make_option_button(str(options[i]), i, font, factor))

	_tag = UiStyleKit.name_tag(pet.get_label(), font, _style, factor, is_thought)
	add_child(_tag)
	_tag.top_level = true

	if bool(line.get("typewriter", true)) and _label.get_total_character_count() > 0:
		_label.visible_characters = 0
		_typing = true
		# 打字機滾動期間讓桌寵切到 _sp 說話差分(沒有差分就維持原樣)。
		pet.set_speaking(true)
	else:
		_on_text_complete()


## 設定氣泡文字。內文可以有 [icon=數值名稱] 標記(對話插值 { 名稱 } 產生的),換成該數值綁定的小圖示,
## 圖示高度與字級一致、寬度依原圖比例;一般的 [b][i][u][s] 樣式照舊。沒有圖示標記就走一般的 BBCode 路徑。
## 圖示夾在樣式標籤中間時(例如 [b]金幣 [icon=金幣] 5[/b]),RichTextLabel 的 append_text 不能跨呼叫延續標籤,
## 所以每一段開頭都補上前面還沒關的樣式標籤。
func _set_content(raw: String) -> void:
	_raw_text = raw
	var matches := ICON_REGEX.search_all(raw)
	if matches.is_empty():
		_label.text = raw
		return
	_label.clear()
	var icon_height := int(UiStyleKit.BASE_FONT_SIZE * _style.text_scale_factor())
	var open_tags: Array[String] = []
	var cursor := 0
	for match_result in matches:
		var segment := raw.substr(cursor, match_result.get_start() - cursor)
		_append_segment(segment, open_tags)
		cursor = match_result.get_end()
		var def := ValueGateway.find_def(pet, match_result.get_string(1).strip_edges())
		if def != null and def.icon != null:
			var texture: Texture2D = def.icon
			var height := icon_height
			var width := int(roundf(float(texture.get_width()) * height / maxf(texture.get_height(), 1.0)))
			_label.add_image(texture, width, height)
	_append_segment(raw.substr(cursor), open_tags)


## 開著的標籤字串(如 "color=#ff0000")的標籤名稱部分。
static func _tag_name(open_tag: String) -> String:
	return open_tag.split(" ")[0].split("=")[0]


func _append_segment(segment: String, open_tags: Array[String]) -> void:
	var prefix := ""
	for open_tag in open_tags:
		prefix += "[%s]" % open_tag
	_label.append_text(prefix + segment)
	for tag_match in STYLE_TAG_REGEX.search_all(segment):
		var tag_name := tag_match.get_string(2)
		if tag_match.get_string(1) == "/":
			for index in range(open_tags.size() - 1, -1, -1):
				if _tag_name(open_tags[index]) == tag_name:
					open_tags.remove_at(index)
					break
		else:
			open_tags.append(tag_name + tag_match.get_string(3))


## 重複前一句(說話中):暫時把文字換成「前一句」,不動目前這句的計時、選項與積木鏈;時間到或點一下就換回來。
func peek_line(line: Dictionary, seconds: float) -> void:
	if _closed:
		return
	if _typing:
		_finish_typing()
	if not _peeking:
		_saved_text = _raw_text
		_saved_options_visible = _option_box.visible
	_peeking = true
	_peek_left = seconds
	_set_content(str(line.get("text", "")))
	_label.visible_characters = -1
	_option_box.visible = false
	_apply_option_height()


func _end_peek() -> void:
	if not _peeking:
		return
	_peeking = false
	_set_content(_saved_text)
	_option_box.visible = _saved_options_visible
	_apply_option_height()


func _process(delta: float) -> void:
	if _closed:
		return
	if _peeking:
		_peek_left -= delta
		if _peek_left <= 0.0:
			_end_peek()
		return
	if _typing:
		_type_progress += delta * TYPEWRITER_CPS
		var total := _label.get_total_character_count()
		var previous := maxi(_label.visible_characters, 0)
		_label.visible_characters = mini(int(_type_progress), total)
		# 只有「輸出字」的時候才發說話音效:這一影格新顯示的字裡有可見字元(不是空白/換行)才發,頻率節流由音效管理器負責。
		if _label.visible_characters > previous and not _label.get_parsed_text().substr(previous, _label.visible_characters - previous).strip_edges().is_empty():
			_state.speech_tick_requested.emit(pet)
		if _label.visible_characters >= total:
			_finish_typing()
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_close(-1)


## 點擊氣泡:打字中先顯示全文,已打完就跳下一句(有選項時只有按選項才會前進)。
func _gui_input(event: InputEvent) -> void:
	if _closed or not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if _peeking:
		_end_peek()
		return
	if _typing:
		_finish_typing()
	elif not _has_options:
		_close(-1)


## 氣泡外框(全域座標),排版與穿透形狀共用。
func global_rect() -> Rect2:
	return Rect2(global_position, size)


## 穿透形狀用的外框。容器的最小尺寸更新是延遲到影格尾端才生效的:選項一出現、文字換行後氣泡會在「同一影格畫出來之前」長大,
## 但這裡讀到的 size 還是舊的,新長出來的那一圈會被視窗區域裁掉(選項剛出現時整個氣泡破圖一兩影格)。
## 所以取 size 與「目前最小尺寸」較大者(get_combined_minimum_size 會即時重算),版面剛變動的幾影格再額外多留一圈。
func _cutout_rect() -> Rect2:
	var rect := Rect2(global_position, size.max(get_combined_minimum_size()))
	if _settle_left > 0:
		_settle_left -= 1
		rect = rect.grow(SETTLE_GROW)
	return rect


func get_cutout_polygons() -> Array:
	if not is_visible_in_tree():
		return []
	var rect := _cutout_rect()
	var tag_rect := Rect2(_tag.global_position, _tag.size)
	# 氣泡跟著桌寵跑(桌寵被甩出去、翻到頭頂/腳底時位置一次跳很遠):往桌寵的移動方向預留一段(與桌寵自己的穿透形狀同一套),
	# 上一影格的位置也保留,視窗形狀慢一步時邊緣才不會被裁出一條。
	var lead := Vector2.ZERO
	if is_instance_valid(pet) and pet.has_method("cutout_lead"):
		lead = pet.cutout_lead()
	var polygons: Array = [
		_rect_polygon(rect.merge(Rect2(rect.position + lead, rect.size))),
		# 名字標籤有一半在氣泡外面:穿透多邊形若只含氣泡本體,標籤突出的部分會被視窗區域裁掉(看起來像標籤被切掉一半),
		# 所以標籤的矩形也要算進去(DesktopShell 會自動扣掉與氣泡重疊的部分)。
		_rect_polygon(tag_rect.merge(Rect2(tag_rect.position + lead, tag_rect.size))),
	]
	if _tail != null and _tail.size != Vector2.ZERO:
		var tail_rect := _tail.global_rect()
		polygons.append(_rect_polygon(tail_rect.merge(Rect2(tail_rect.position + lead, tail_rect.size))))
	if _previous_rect.size != Vector2.ZERO and not _previous_rect.is_equal_approx(rect):
		polygons.append(_rect_polygon(_previous_rect))
	_previous_rect = rect
	return polygons


## 矩形轉穿透多邊形,四周多留 CUTOUT_MARGIN:視窗形狀更新總會慢一影格,介面跟著桌寵移動時邊緣才不會被裁掉一條。
static func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	rect = rect.grow(CUTOUT_MARGIN)
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


## 思考泡泡尾巴佔的高度(排版時桌寵與泡泡之間要多留這麼多);一般對話框沒有尾巴,回 0。
func tail_space() -> float:
	return ThoughtTail.total_height(_style.scale_factor()) if is_thought else 0.0


## 由管理器排版後呼叫(思考泡泡才有動作):把尾巴接在泡泡靠桌寵的那一側,朝桌寵頭部(泡泡在下方時朝腳底)排開。
func place_tail(body: Rect2) -> void:
	if _tail == null:
		return
	var target := Vector2(body.get_center().x, body.end.y if flipped else body.position.y)
	_tail.place(global_rect(), target, flipped)


## 由管理器排版後呼叫:把名字標籤貼在氣泡左上角邊框上(標籤跨在邊框線上)。
func place_tag() -> void:
	UiStyleKit.place_tag(_tag, self, _style.scale_factor())


func is_closed() -> bool:
	return _closed


## 中斷(使用者互動、被新的一句取代):不算選擇,直接關閉。
func close_silently() -> void:
	_close(-1)


func _close(choice: int) -> void:
	if _closed:
		return
	_closed = true
	if is_instance_valid(pet):
		pet.set_speaking(false)
	advanced.emit(choice)


func _finish_typing() -> void:
	_typing = false
	pet.set_speaking(false)
	_label.visible_characters = -1
	_on_text_complete()


func _on_text_complete() -> void:
	if _has_options:
		_option_box.visible = true
		_fit_option_scroll()
	if _has_options:
		# 有選項的句子要給使用者足夠的時間看和選;逾時視為沒有選擇(不套用任何選項)。可在 PetUiStyle 調整。
		_idle_left = maxf(_style.option_wait_seconds, _patience)
	elif _auto_seconds > 0.0:
		_idle_left = _auto_seconds
	elif _wait_click:
		_idle_left = IDLE_DISMISS_SECONDS
	else:
		_idle_left = clampf(READ_BASE_SECONDS + READ_SECONDS_PER_CHAR * _label.get_total_character_count(), READ_MIN_SECONDS, READ_MAX_SECONDS)


## 選項區的高度 = 選項實際需要的高度,但最多佔螢幕高度的 OPTION_MAX_SCREEN_FRACTION(超過就出現捲軸)。
## 自動換行的按鈕要等排版算出寬度才知道高度,所以先設一次、下一影格再修正。
const OPTION_MAX_SCREEN_FRACTION := 0.4


func _fit_option_scroll() -> void:
	_apply_option_height()
	await get_tree().process_frame
	if not _closed and is_inside_tree():
		_apply_option_height()


func _apply_option_height() -> void:
	_settle_left = SETTLE_QUERIES
	var cap := float(get_viewport().get_visible_rect().size.y) * OPTION_MAX_SCREEN_FRACTION
	_option_scroll.custom_minimum_size.y = minf(_option_box.get_combined_minimum_size().y, cap) if _option_box.visible else 0.0


func _make_option_button(label: String, index: int, font: Font, factor: float) -> Button:
	var button := UiStyleKit.option_button(label, font, _style, factor, is_thought)
	button.pressed.connect(_close.bind(index))
	return button


## 名字標籤有一半跨在氣泡上緣之外,排版時上緣要多留這麼多空間,否則貼著螢幕頂端時標籤上半會被裁掉。
func tag_overhang() -> float:
	return ceilf(_tag.get_combined_minimum_size().y * 0.5)
