class_name TarotPickBoard
extends Node2D
## 塔羅牌占卜的選牌小視窗(2026-10-04 使用者要求):問完問題之後先開這塊,22 張牌背排成一排讓使用者點選
## 要抽的張數(1/3/5)。選中的牌用外框標示,已選過的牌不能再選;選滿張數或按 ✕ 取消都會發一次 finished
## 訊號(cancelled, indices——indices 是選牌的先後順序,用來對應 TarotDeck.shuffled_deck() 洗好的那副牌)。
## 版面/拖曳/閒置自動收都比照小遊戲棋盤(TttBoard)同一套做法:程式畫的可拖曳面板,不是視窗、不用圖片素材;
## 閒置 IDLE_TIMEOUT(10 分鐘,跟 TttBoard 一致,使用者明確要求「與小遊戲棋盤一致」)沒人互動就視同取消收掉。
## 使用者填過的占卜問題只會用這一次(問完就洗掉,不存檔),所以選牌期間粗體顯示在牌堆上方提醒自己問了什麼。
## 2026-10-04 使用者要求:可以拖出行動區外面,但不能拖出螢幕範圍(見 _screen_rect());意外跑到螢幕外時,
## 右鍵選單「行動區重設」會呼叫 recall() 撈回來(見 DesktopShell._on_tray_recall())。

signal finished(cancelled: bool, indices: Array)

const COLUMNS := 11
const CARD_W := 34.0
const CARD_H := 50.0
const GAP := 6.0
const PAD := 14.0
const HEADER := 30.0
const QUESTION_HEIGHT := 22.0
const IDLE_TIMEOUT := 600.0
const BOLD_EMBOLDEN := 0.7   # 跟 DialogueBubble 的 [b] 粗體同一套 FontVariation 做法

var need := 1
var question := ""
var picked: Array[int] = []

var _area: Node
var _fraction: Variant = null   # 拖過之後記住位置(比例);沒拖過就置中
var _rects: Dictionary = {}
var _dragging_header := false
var _drag_grab := Vector2.ZERO
var _mouse := Vector2.ZERO
var _idle_left := IDLE_TIMEOUT
var _last_area_cache := Rect2()
var _done := false


func setup(area: Node, wanted: int, asked_question := "") -> void:
	_area = area
	need = clampi(wanted, 1, TarotDeck.MAJOR_ARCANA.size())
	question = asked_question.strip_edges()
	add_to_group("Cutout")
	add_to_group("screen_clamped_boards")
	z_index = 40
	_layout()


func _question_height() -> float:
	return QUESTION_HEIGHT if question != "" else 0.0


func _area_rect() -> Rect2:
	if _area != null and "boundary_rect" in _area:
		var rect: Rect2 = _area.boundary_rect
		return Rect2(_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 可以拖到的範圍(整個螢幕,不是行動區):無頭環境讀不到螢幕資訊時退回跟 _area_rect() 一樣的假範圍。
func _screen_rect() -> Rect2:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return _area_rect()
	var origin := Vector2(get_window().position)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Rect2(Vector2(usable.position) - origin, Vector2(usable.size))


## 「行動區重設」用:忘記拖到哪裡了,直接退回預設(貼著行動區置中)的位置。
func recall() -> void:
	_fraction = null
	_layout()


func panel_size() -> Vector2:
	var rows := ceili(float(TarotDeck.MAJOR_ARCANA.size()) / float(COLUMNS))
	return Vector2(PAD * 2.0 + COLUMNS * CARD_W + (COLUMNS - 1) * GAP, HEADER + _question_height() + PAD * 2.0 + rows * CARD_H + (rows - 1) * GAP)


func _layout() -> void:
	var area := _area_rect()
	var screen := _screen_rect()
	var size := panel_size()
	var pos: Vector2
	if _fraction is Vector2:
		var free := (screen.size - size).max(Vector2.ONE)
		pos = screen.position + free * (_fraction as Vector2)
	else:
		pos = area.position + (area.size - size) * 0.5
	pos.x = clampf(pos.x, screen.position.x, maxf(screen.end.x - size.x, screen.position.x))
	pos.y = clampf(pos.y, screen.position.y, maxf(screen.end.y - size.y, screen.position.y))
	var panel := Rect2(pos, size)
	_rects.clear()
	_rects["panel"] = panel
	_rects["header"] = Rect2(panel.position, Vector2(size.x - 28.0, HEADER))
	_rects["close"] = Rect2(panel.end.x - 26.0, panel.position.y + 4.0, 22.0, 22.0)
	if question != "":
		_rects["question"] = Rect2(panel.position + Vector2(PAD, HEADER), Vector2(size.x - PAD * 2.0, QUESTION_HEIGHT))
	var origin := panel.position + Vector2(PAD, HEADER + _question_height() + PAD)
	for i in TarotDeck.MAJOR_ARCANA.size():
		var col := i % COLUMNS
		var row := i / COLUMNS
		_rects["card:%d" % i] = Rect2(origin + Vector2(col * (CARD_W + GAP), row * (CARD_H + GAP)), Vector2(CARD_W, CARD_H))
	_last_area_cache = area
	queue_redraw()


func get_cutout_polygons() -> Array:
	if not _rects.has("panel"):
		return []
	var rect: Rect2 = _rects["panel"]
	return [DialogueBubble._rect_polygon(rect.grow(80.0 if _dragging_header else 4.0))]


func _process(delta: float) -> void:
	if _done or _area == null:
		return
	if _area_rect() != _last_area_cache:
		_layout()
	_idle_left -= delta
	if _idle_left <= 0.0:
		_finish(true)


func note_activity() -> void:
	_idle_left = IDLE_TIMEOUT


func _input(event: InputEvent) -> void:
	if _done:
		return
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if event is InputEventMouseMotion:
		_on_motion()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_on_press()
		else:
			_dragging_header = false


func _id_at(point: Vector2) -> String:
	for id: String in ["close", "header"]:
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	for i in TarotDeck.MAJOR_ARCANA.size():
		var id := "card:%d" % i
		if _rects.has(id) and (_rects[id] as Rect2).has_point(point):
			return id
	return ""


func _on_motion() -> void:
	if _dragging_header:
		var screen := _screen_rect()
		var size := panel_size()
		var free := (screen.size - size).max(Vector2.ONE)
		var top_left := _mouse - _drag_grab
		_fraction = Vector2(clampf((top_left.x - screen.position.x) / free.x, 0.0, 1.0), clampf((top_left.y - screen.position.y) / free.y, 0.0, 1.0))
		_layout()


## 2026-10-04 使用者實機回報(步步為營那邊先發現的同一個坑):點在面板範圍內但沒打到任何按鈕/牌的地方
## 會穿透到後面的對話氣泡選項按鈕,面板既然蓋在對話氣泡之上,只要滑鼠在面板範圍內就該整個吃掉這次點擊。
func _on_press() -> void:
	if not _rects.has("panel") or not (_rects["panel"] as Rect2).has_point(_mouse):
		return
	get_viewport().set_input_as_handled()
	var id := _id_at(_mouse)
	if id == "":
		return
	note_activity()
	match id:
		"header":
			_dragging_header = true
			_drag_grab = _mouse - (_rects["panel"] as Rect2).position
		"close":
			_finish(true)
		_:
			if id.begins_with("card:"):
				var index := int(id.trim_prefix("card:"))
				if not picked.has(index) and picked.size() < need:
					picked.append(index)
					queue_redraw()
					if picked.size() >= need:
						_finish(false)


func _on_release() -> void:
	_dragging_header = false


func _finish(cancelled: bool) -> void:
	if _done:
		return
	_done = true
	finished.emit(cancelled, picked.duplicate())


func _draw() -> void:
	if not _rects.has("panel"):
		return
	var look := AppSettings.appearance()
	var colors: Dictionary = look["colors"]
	var bg: Color = colors["bg"]
	var text_color: Color = colors["text"]
	var accent: Color = colors["accent"]
	var muted: Color = colors["muted"]
	var font := UiFonts.get_font(str(look["font"]))
	var panel: Rect2 = _rects["panel"]
	var local_panel := Rect2(panel.position - global_position, panel.size)
	draw_rect(local_panel, Color(bg, 0.95), true)
	draw_rect(local_panel, Color(accent, 0.7), false, 2.0)
	var header: Rect2 = _rects["header"]
	var status := tr("選 %d 張牌(%d/%d)") % [need, picked.size(), need]
	draw_string(font, Vector2(header.position.x - global_position.x + 6.0, header.position.y - global_position.y + 20.0), status, HORIZONTAL_ALIGNMENT_LEFT, header.size.x, 15, Color(text_color, 0.95))
	var close: Rect2 = _rects["close"]
	draw_string(font, Vector2(close.position.x - global_position.x + 4.0, close.position.y - global_position.y + 16.0), "×", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(muted, 0.9))
	if question != "" and _rects.has("question"):
		var bold_font := FontVariation.new()
		bold_font.base_font = font
		bold_font.variation_embolden = BOLD_EMBOLDEN
		var question_rect: Rect2 = _rects["question"]
		draw_string(bold_font, Vector2(question_rect.position.x - global_position.x, question_rect.position.y - global_position.y + 16.0), question, HORIZONTAL_ALIGNMENT_LEFT, question_rect.size.x, 15, Color(text_color, 0.95))
	for i in TarotDeck.MAJOR_ARCANA.size():
		var cell: Rect2 = _rects["card:%d" % i]
		var local_cell := Rect2(cell.position - global_position, cell.size)
		var is_picked := picked.has(i)
		draw_rect(local_cell, Color(muted, 0.35), true)
		draw_rect(local_cell, Color(accent if is_picked else muted, 0.95 if is_picked else 0.5), false, 3.0 if is_picked else 1.5)
