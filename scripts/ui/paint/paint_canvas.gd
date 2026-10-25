class_name PaintCanvas
extends Control
## 繪圖視窗(SpritePaintWindow)中間的畫布:顯示 PaintDocument 目前這一頁,把滑鼠 / 繪圖筆的操作變成文件的操作。
## 滾輪縮放(以游標為中心)、中鍵或按住空白鍵拖曳平移;放大到一定倍率顯示像素格線;洋蔥皮顯示前後幀;
## 吸色時游標旁有迷你放大鏡(連 alpha 一起顯示色碼)。
## 左鍵用目前的工具;右鍵用綁到右鍵的工具(沒綁 = 畫筆畫副色;綁橡皮擦 = 用畫筆的設定擦(尺寸、筆刷類型、筆壓);綁吸色 = 吸到主色)。
## 繪圖筆的筆尾(橡皮擦端)一律當橡皮擦;Alt + 左鍵臨時吸色;Shift + 點 從上一筆的終點拉直線。
## 選取類工具(矩形 / 魔術棒 / 套索)按著 Shift 加選、按著 Ctrl 減選;形狀按著 Shift 畫正方形 / 正圓 / 45 度直線。
## 繪圖圖層一層一張貼圖(照圖層的顯示與不透明度疊起來);選取範圍不是矩形時沿著邊緣畫黑白相間的虛線。
## 透明棋盤格用底下一個平鋪的 TextureRect 畫(要重複貼圖),其餘都畫在上面那一層(_overlay)。
## 畫筆 / 橡皮擦可以開防手震(stabilizer:畫的位置慢慢追上游標,收筆時補到游標的位置)。
## 「畫布尺寸」工具(canvas):拖曳四邊或四角調整畫布範圍(canvas_margins = 四邊各加減幾格),旁邊即時顯示幾 px,
## 視窗那邊按「套用尺寸」才真的改(見 SpritePaintWindow)。

signal color_picked(color: Color)
signal hover_changed(pixel: Variant)
signal view_changed
## 「畫布尺寸」工具拖曳四邊時,canvas_margins 變了。
signal canvas_margins_changed

const ZOOMS: Array[float] = [0.25, 0.5, 1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0, 64.0]
const GRID_MIN_ZOOM := 6.0
const MAGNIFIER_CELLS := 11
const MAGNIFIER_CELL := 8.0
const CHECKER_CELL := 8
## 拖曳畫布邊緣的感應距離(螢幕像素)。
const EDGE_GRAB := 8.0
## 透明的棋盤格底色:[亮的那格, 暗的那格];亮 / 暗兩套(工具列的日月按鈕切換,2026-10-23 使用者要求)。
const CHECKER_LIGHT: Array[Color] = [Color(0.8, 0.8, 0.82), Color(0.62, 0.62, 0.66)]
const CHECKER_DARK: Array[Color] = [Color(0.3, 0.3, 0.32), Color(0.2, 0.2, 0.22)]

var doc: PaintDocument
var tool := "brush"
var right_tool := ""
var primary := Color(0, 0, 0, 1)
var secondary := Color(1, 1, 1, 0)
## 畫筆 / 橡皮擦各自的設定:size、smooth、size_pressure(筆壓影響粗細)、opacity_pressure(筆壓影響不透明度)。
## 畫筆 / 橡皮擦各自的設定:另有 stabilizer(防手震 0~10,0 = 關)。
var brush := {"size": 1, "smooth": false, "size_pressure": true, "opacity_pressure": false, "stabilizer": 0}
var eraser := {"size": 4, "smooth": false, "size_pressure": true, "opacity_pressure": false, "stabilizer": 0}
var blend := false
var show_onion := true
var show_grid := true
var show_reference := true
## 棋盤格用暗的那一套(改了要呼叫 set_checker_dark 才會重做貼圖)。
var checker_dark := false
## 形狀要不要填滿。
var shape_filled := false
## 漸層:kind("linear" / "radial")、steps(0 = 平滑)、dither。
var gradient := {"kind": "linear", "steps": 0, "dither": false}
## 魔術棒:tolerance(0~255)、contiguous(只選相連的)。
var wand := {"tolerance": 0, "contiguous": true}
## 每一頁的軸心標記(Vector2,圖上的座標;沒有就是 null),畫成淡淡的十字與腳底線。
var markers: Array = []
## 每一頁底下墊的參考圖({texture, offset(圖上的座標), scale(可省略,負的 = 翻過來)} 或 null;畫圖層時墊本體)。
var references: Array = []
## 「畫布尺寸」工具的待套用範圍:[左, 上, 右, 下] 各加幾格(負的 = 裁掉)。
var canvas_margins: Array[int] = [0, 0, 0, 0]
## 視窗按著空白鍵時設成 true:左鍵拖曳變成平移。
var space_held := false
var zoom := 8.0
## 圖的左上角在畫布上的位置。
var pan := Vector2.ZERO

var _checker_rect: TextureRect
var _overlay: Control
var _textures := {}
var _float_texture: ImageTexture = null
var _float_source: Image = null
var _hover: Variant = null
var _hover_screen := Vector2.ZERO
var _drag := ""
var _drag_start := Vector2.ZERO
var _drag_pan := Vector2.ZERO
var _select_anchor := Vector2i.ZERO
var _select_moved := false
var _select_mode := "replace"
var _select_preview := Rect2i()
var _lasso := PackedVector2Array()
var _shape_from := Vector2.ZERO
var _shape_to := Vector2.ZERO
var _shape_params := {}
var _outline_key: Variant = null
var _outline: Array = []
var _move_last := Vector2i.ZERO
var _pressure := 1.0
var _pen_seen := false
var _raw_pressure := 0.0
var _pending_stroke := {}
var _pen_inverted := false
var _has_last := false
var _stabilizer := 0
var _smoothed := Vector2.ZERO
var _raw_at := Vector2.ZERO
## 拖曳中的畫布邊緣:[左, 上, 右, 下] 有沒有抓到;_edge_from 是按下時的 canvas_margins。
var _edges: Array[bool] = [false, false, false, false]
var _edge_from: Array[int] = [0, 0, 0, 0]
var _bg := Color(0.16, 0.16, 0.18)
var _line := Color(1, 1, 1)


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	_checker_rect = TextureRect.new()
	_checker_rect.texture = _make_checker(checker_colors())
	_checker_rect.stretch_mode = TextureRect.STRETCH_TILE
	_checker_rect.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_checker_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_checker_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_checker_rect)
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	resized.connect(_layout_checker)


static func _make_checker(colors: Array[Color]) -> ImageTexture:
	var image := Image.create(CHECKER_CELL * 2, CHECKER_CELL * 2, false, Image.FORMAT_RGBA8)
	image.fill(colors[0])
	image.fill_rect(Rect2i(0, 0, CHECKER_CELL, CHECKER_CELL), colors[1])
	image.fill_rect(Rect2i(CHECKER_CELL, CHECKER_CELL, CHECKER_CELL, CHECKER_CELL), colors[1])
	return ImageTexture.create_from_image(image)


func checker_colors() -> Array[Color]:
	return CHECKER_DARK if checker_dark else CHECKER_LIGHT


func set_checker_dark(dark: bool) -> void:
	checker_dark = dark
	if _checker_rect != null:
		_checker_rect.texture = _make_checker(checker_colors())
	_refresh()


func set_document(new_doc: PaintDocument) -> void:
	doc = new_doc
	_textures.clear()
	_float_texture = null
	_float_source = null
	_has_last = false
	doc.changed.connect(_refresh)
	_refresh()


func apply_theme_colors(background: Color, text: Color) -> void:
	_bg = background
	_line = text
	queue_redraw()


## 下筆期間把影格率拉高(AppSettings.STROKE_FPS),收筆或畫布關掉就放回去。
func _set_stroking(active: bool) -> void:
	if AppSettings.stroking != active:
		AppSettings.stroking = active
		AppSettings.refresh_fps()


func _exit_tree() -> void:
	_set_stroking(false)


func _process(_delta: float) -> void:
	if doc == null:
		return
	_set_stroking(doc.is_stroking() or not _pending_stroke.is_empty())
	var structure := doc.take_structure_dirty()
	if structure:
		_textures.clear()
	var dirty := doc.take_dirty()
	if dirty.is_empty() and not structure and _float_source == doc.floating:
		return
	# 剪裁在改到的層上面的層,樣子也跟著變
	for key: Vector2i in dirty.duplicate():
		for l in doc.clipped_onto(key.y):
			if not dirty.has(Vector2i(key.x, l)):
				dirty.append(Vector2i(key.x, l))
	for key: Vector2i in dirty:
		var image := doc.display_cel(key.x, key.y)
		if image == null:
			continue
		var texture: ImageTexture = _textures.get(key)
		if texture != null and Vector2i(texture.get_size()) == image.get_size():
			texture.update(image)
		else:
			_textures[key] = ImageTexture.create_from_image(image)
	if doc.floating != _float_source or not dirty.is_empty() or structure:
		_float_source = doc.floating
		_float_texture = ImageTexture.create_from_image(doc.floating) if doc.floating != null else null
	_refresh()


func _refresh() -> void:
	_layout_checker()
	queue_redraw()
	if _overlay != null:
		_overlay.queue_redraw()


func _texture_of(page_index: int, layer_index: int) -> ImageTexture:
	var key := Vector2i(page_index, layer_index)
	if not _textures.has(key):
		var image := doc.display_cel(page_index, layer_index)
		if image == null:
			return null
		_textures[key] = ImageTexture.create_from_image(image)
	return _textures.get(key)


# --- 視角 ---

func image_rect() -> Rect2:
	return Rect2(pan, Vector2(doc.page_size()) * zoom) if doc != null else Rect2()


func to_image(screen: Vector2) -> Vector2:
	return (screen - pan) / zoom


func to_pixel(screen: Vector2) -> Vector2i:
	var at := to_image(screen)
	return Vector2i(floori(at.x), floori(at.y))


## 整張圖放進畫布(取放得下的最大倍率),置中。
func fit_view() -> void:
	if doc == null or doc.page_size() == Vector2i.ZERO or size.x <= 0.0:
		return
	var image_size := Vector2(doc.page_size())
	zoom = ZOOMS[0]
	for candidate in ZOOMS:
		if image_size.x * candidate <= size.x * 0.92 and image_size.y * candidate <= size.y * 0.92:
			zoom = candidate
	pan = ((size - image_size * zoom) * 0.5).floor()
	_refresh()
	view_changed.emit()


func set_zoom(value: float, focus := Vector2(-1, -1)) -> void:
	var center := size * 0.5 if focus.x < 0.0 else focus
	var old := zoom
	zoom = clampf(value, ZOOMS[0], ZOOMS[ZOOMS.size() - 1])
	pan = (center - (center - pan) * (zoom / old)).floor()
	_refresh()
	view_changed.emit()


## 放大(steps > 0)/ 縮小一級。
func step_zoom(steps: int, focus := Vector2(-1, -1)) -> void:
	var at := 0
	for i in ZOOMS.size():
		if ZOOMS[i] <= zoom + 0.001:
			at = i
	set_zoom(ZOOMS[clampi(at + steps, 0, ZOOMS.size() - 1)], focus)


func _layout_checker() -> void:
	if _checker_rect == null or doc == null:
		return
	var rect := image_rect()
	_checker_rect.position = rect.position
	_checker_rect.size = rect.size


# --- 輸入 ---

func _gui_input(event: InputEvent) -> void:
	if doc == null or doc.page() == null:
		return
	if event is InputEventMouseMotion:
		_on_motion(event)
	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			step_zoom(1 if button.button_index == MOUSE_BUTTON_WHEEL_UP else -1, button.position)
			accept_event()
			return
		if button.pressed:
			grab_focus()
			_press(button)
		else:
			_release(button)
		accept_event()


func _on_motion(motion: InputEventMouseMotion) -> void:
	# Windows 上滑鼠只有按著左鍵時回報 1.0、其他時候是 0;繪圖筆碰到板子才有 0~1 的筆壓、懸空是 0。
	# 所以 0 一律當成全壓(滑鼠右鍵畫圖也是 0),只有「繪圖筆懸空時按下」要等第一個帶筆壓的移動才下筆(見 _start_stroke)。
	_raw_pressure = motion.pressure
	if (_raw_pressure > 0.0 and _raw_pressure < 1.0) or motion.pen_inverted:
		_pen_seen = true
	_pressure = _raw_pressure if _raw_pressure > 0.0 else 1.0
	_pen_inverted = motion.pen_inverted
	_hover_screen = motion.position
	_update_edge_cursor(motion.position)
	var pixel := to_pixel(motion.position)
	var inside := Rect2i(Vector2i.ZERO, doc.page_size()).has_point(pixel)
	var new_hover: Variant = pixel if inside else null
	if new_hover != _hover:
		_hover = new_hover
		hover_changed.emit(_hover)
	match _drag:
		"stroke":
			if not _pending_stroke.is_empty():
				_begin_pending(_pressure)
			_raw_at = to_image(motion.position)
			if _stabilizer > 0:
				# 防手震:每次只往游標走一部分(數字越大越慢、越穩)
				_smoothed = _smoothed.lerp(_raw_at, 1.0 / (1.0 + _stabilizer * 0.6))
				doc.stroke_to(_smoothed, _pressure)
			else:
				doc.stroke_to(_raw_at, _pressure)
		"edges":
			_drag_edges(motion.position)
		"pan":
			pan = (_drag_pan + motion.position - _drag_start).floor()
			_layout_checker()
			view_changed.emit()
		"select":
			var clamped := pixel.clamp(Vector2i.ZERO, doc.page_size() - Vector2i.ONE)
			if clamped != _select_anchor:
				_select_moved = true
			var top_left := Vector2i(mini(clamped.x, _select_anchor.x), mini(clamped.y, _select_anchor.y))
			var bottom_right := Vector2i(maxi(clamped.x, _select_anchor.x), maxi(clamped.y, _select_anchor.y))
			_select_preview = Rect2i(top_left, bottom_right - top_left + Vector2i.ONE)
		"lasso":
			var point := to_image(motion.position)
			if _lasso.is_empty() or _lasso[_lasso.size() - 1].distance_to(point) >= 0.5:
				_lasso.append(point)
		"shape":
			_shape_to = _constrained(to_image(motion.position), motion.shift_pressed)
			doc.preview_shape(tool, _shape_from, _shape_to, _shape_params, shape_filled)
		"gradient":
			_shape_to = _constrained(to_image(motion.position), motion.shift_pressed)
			doc.preview_gradient(_shape_from, _shape_to, primary, secondary, _gradient_options())
		"move":
			doc.move_floating(pixel - _move_last)
			_move_last = pixel
		"pick":
			_pick(pixel)
	_overlay.queue_redraw()


func _press(button: InputEventMouseButton) -> void:
	var pixel := to_pixel(button.position)
	var at := to_image(button.position)
	if button.button_index == MOUSE_BUTTON_MIDDLE or (button.button_index == MOUSE_BUTTON_LEFT and (tool == "pan" or space_held)):
		_drag = "pan"
		_drag_start = button.position
		_drag_pan = pan
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		if tool == "canvas":
			return   # 調畫布範圍時右鍵不畫圖
		match right_tool:
			"eraser":
				_start_stroke(_params("eraser", primary, brush), at, button.shift_pressed)
			"picker":
				_drag = "pick"
				_pick(pixel)
			_:
				_start_stroke(_params("brush", secondary, brush), at, button.shift_pressed)
		return
	if button.button_index != MOUSE_BUTTON_LEFT:
		return
	if _pen_inverted:
		_start_stroke(_params("eraser", primary, eraser), at, button.shift_pressed)
		return
	if button.alt_pressed:
		_drag = "pick"
		_pick(pixel)
		return
	match tool:
		"brush":
			_start_stroke(_params("brush", primary, brush), at, button.shift_pressed)
		"eraser":
			_start_stroke(_params("eraser", primary, eraser), at, button.shift_pressed)
		"picker":
			_drag = "pick"
			_pick(pixel)
		"fill":
			doc.fill(pixel, primary, blend)
		"select":
			_press_select(pixel, _mode_of(button))
		"wand":
			doc.select_wand(pixel, int(wand.get("tolerance", 0)), bool(wand.get("contiguous", true)), _mode_of(button))
		"lasso":
			doc.commit_floating()
			_drag = "lasso"
			_select_mode = _mode_of(button)
			_lasso = PackedVector2Array([at])
		"line", "rect", "ellipse":
			_drag = "shape"
			_shape_params = _params("brush", primary, brush)
			_shape_from = at
			_shape_to = at
			if doc.begin_preview(_shape_params):
				doc.preview_shape(tool, at, at, _shape_params, shape_filled)
		"gradient":
			_drag = "gradient"
			_shape_from = at
			_shape_to = at
			doc.begin_preview()
		"canvas":
			_edges = edges_at(button.position)
			if _edges.has(true):
				_drag = "edges"
				_drag_start = button.position
				_edge_from = canvas_margins.duplicate()
			else:
				_drag = "pan"
				_drag_start = button.position
				_drag_pan = pan


func _release(button: InputEventMouseButton) -> void:
	match _drag:
		"stroke":
			if not _pending_stroke.is_empty():
				_begin_pending(1.0)
			if _stabilizer > 0 and _smoothed.distance_to(_raw_at) > 0.01:
				doc.stroke_to(_raw_at, _pressure)   # 收筆時補到游標的位置
			doc.end_stroke()
			_has_last = true
		"select":
			if _select_moved or _select_mode != "replace":
				doc.select_rect(_select_preview, _select_mode)
			else:
				doc.clear_selection()
			_select_preview = Rect2i()
		"lasso":
			if _lasso.size() >= 3:
				doc.select_lasso(_lasso, _select_mode)
			elif _select_mode == "replace":
				doc.clear_selection()
			_lasso = PackedVector2Array()
		"shape", "gradient":
			doc.end_stroke()
	if button.button_index != MOUSE_BUTTON_WHEEL_UP and button.button_index != MOUSE_BUTTON_WHEEL_DOWN:
		_drag = ""
	_overlay.queue_redraw()


func _params(kind: String, color: Color, settings: Dictionary) -> Dictionary:
	return {"tool": kind, "color": color, "size": int(settings.get("size", 1)), "smooth": bool(settings.get("smooth", false)),
			"blend": blend, "size_pressure": bool(settings.get("size_pressure", false)), "opacity_pressure": bool(settings.get("opacity_pressure", false)),
			"curve": true, "stabilizer": int(settings.get("stabilizer", 0))}


func _start_stroke(params: Dictionary, at: Vector2, line_from_last: bool) -> void:
	_drag = "stroke"
	_pending_stroke = {}
	_stabilizer = int(params.get("stabilizer", 0))
	_smoothed = at
	_raw_at = at
	if line_from_last and _has_last:
		params = params.duplicate()
		params["curve"] = false   # Shift + 點 = 直線
	if line_from_last and _has_last:
		doc.begin_stroke(params, doc.last_point(), _pressure)
		doc.stroke_to(at, _pressure)
	elif _pen_seen and _raw_pressure <= 0.0:
		# 繪圖筆懸空時的最後一個筆壓是 0,拿它下筆會在起點蓋一個全壓的點:等第一個帶筆壓的移動再下筆
		_pending_stroke = {"params": params, "at": at}
	else:
		doc.begin_stroke(params, at, _pressure)


func _begin_pending(pressure: float) -> void:
	doc.begin_stroke(_pending_stroke["params"], _pending_stroke["at"], pressure)
	_pending_stroke = {}


## 按著 Shift = 加選、Ctrl = 減選,都沒按 = 換掉原本的選取。
static func _mode_of(button: InputEventMouseButton) -> String:
	if button.ctrl_pressed:
		return "subtract"
	if button.shift_pressed:
		return "add"
	return "replace"


func _press_select(pixel: Vector2i, mode: String) -> void:
	var on_floating := doc.floating != null and doc.selection.has_point(pixel)
	if mode == "replace" and (on_floating or doc.is_selected(pixel.x, pixel.y)):
		doc.lift_selection()
		_drag = "move"
		_move_last = pixel
		return
	doc.commit_floating()
	_drag = "select"
	_select_mode = mode
	_select_moved = false
	_select_anchor = pixel.clamp(Vector2i.ZERO, doc.page_size() - Vector2i.ONE)
	_select_preview = Rect2i(_select_anchor, Vector2i.ONE)


## 形狀按著 Shift:直線鎖 45 度的倍數,矩形 / 橢圓變成正方形 / 正圓。
func _constrained(to: Vector2, shift: bool) -> Vector2:
	if not shift:
		return to
	var delta := to - _shape_from
	if tool == "line" or tool == "gradient":
		var angle := snappedf(delta.angle(), PI / 4.0)
		return _shape_from + Vector2.from_angle(angle) * delta.length()
	if tool == "rect" or tool == "ellipse":
		var side := maxf(absf(delta.x), absf(delta.y))
		return _shape_from + Vector2(side * (1.0 if delta.x >= 0.0 else -1.0), side * (1.0 if delta.y >= 0.0 else -1.0))
	return to


func _gradient_options() -> Dictionary:
	var options := gradient.duplicate()
	options["blend"] = blend
	return options


func _pick(pixel: Vector2i) -> void:
	var color: Variant = doc.pick(pixel)
	if color is Color:
		color_picked.emit(color)


## 畫筆與橡皮擦換工具時,浮動的一塊照常放下;換頁、撤回時這一筆作廢(由文件處理)。這裡只重設拖曳狀態。
func cancel_drag() -> void:
	_pending_stroke = {}
	if _drag == "stroke" or _drag == "shape" or _drag == "gradient":
		doc.end_stroke()
	_drag = ""
	_lasso = PackedVector2Array()
	_select_preview = Rect2i()


# --- 畫布尺寸 ---

## 這一頁的內容因為改畫布尺寸往右下移了多少(軸心標記、墊的參考圖跟著移)。
func _shift() -> Vector2i:
	return doc.page_shifts[doc.index] if doc != null and doc.index < doc.page_shifts.size() else Vector2i.ZERO


## 待套用的畫布範圍(圖上的座標;左上可以是負的 = 往外加)。
func pending_canvas_rect() -> Rect2i:
	var page := doc.page_size()
	return Rect2i(-canvas_margins[0], -canvas_margins[1], page.x + canvas_margins[0] + canvas_margins[2], page.y + canvas_margins[1] + canvas_margins[3])


func set_canvas_margins(margins: Array) -> void:
	for k in 4:
		canvas_margins[k] = int(margins[k])
	if _overlay != null:
		_overlay.queue_redraw()


func reset_canvas_margins() -> void:
	set_canvas_margins([0, 0, 0, 0])
	canvas_margins_changed.emit()


## 螢幕上這一點靠近待套用範圍的哪幾邊:[左, 上, 右, 下](角落 = 兩邊都抓)。
func edges_at(screen: Vector2) -> Array[bool]:
	var pending := pending_canvas_rect()
	var rect := Rect2(pan + Vector2(pending.position) * zoom, Vector2(pending.size) * zoom)
	var grab := rect.grow(EDGE_GRAB)
	if not grab.has_point(screen):
		return [false, false, false, false]
	return [absf(screen.x - rect.position.x) <= EDGE_GRAB, absf(screen.y - rect.position.y) <= EDGE_GRAB,
			absf(screen.x - rect.end.x) <= EDGE_GRAB, absf(screen.y - rect.end.y) <= EDGE_GRAB]


func _drag_edges(screen: Vector2) -> void:
	var delta := Vector2i(((screen - _drag_start) / zoom).round())
	var page := doc.page_size()
	var margins := _edge_from.duplicate()
	if _edges[0]:
		margins[0] = _edge_from[0] - delta.x
	if _edges[2]:
		margins[2] = _edge_from[2] + delta.x
	if _edges[1]:
		margins[1] = _edge_from[1] - delta.y
	if _edges[3]:
		margins[3] = _edge_from[3] + delta.y
	# 至少留 1 格、最多 MAX_CANVAS:超過就把拖的那一邊擋住
	var limit := PaintDocument.MAX_CANVAS
	for axis in 2:
		var low := axis
		var high := axis + 2
		var length: int = page[axis] + margins[low] + margins[high]
		if length < 1 or length > limit:
			var target := clampi(length, 1, limit)
			if _edges[high]:
				margins[high] += target - length
			else:
				margins[low] += target - length
	if margins != canvas_margins:
		set_canvas_margins(margins)
		canvas_margins_changed.emit()


func _update_edge_cursor(screen: Vector2) -> void:
	var shape := Control.CURSOR_CROSS
	if tool == "canvas":
		var near := edges_at(screen) if _drag != "edges" else _edges
		var horizontal := near[0] or near[2]
		var vertical := near[1] or near[3]
		if horizontal and vertical:
			shape = Control.CURSOR_FDIAGSIZE if (near[0] and near[1]) or (near[2] and near[3]) else Control.CURSOR_BDIAGSIZE
		elif horizontal:
			shape = Control.CURSOR_HSIZE
		elif vertical:
			shape = Control.CURSOR_VSIZE
		else:
			shape = Control.CURSOR_MOVE
	if mouse_default_cursor_shape != shape:
		mouse_default_cursor_shape = shape


## 待套用的畫布範圍:虛線框、八個把手、裁掉的地方蓋紅色、旁邊寫尺寸(px)與四邊各加減多少。
func _draw_canvas_frame() -> void:
	var pending := pending_canvas_rect()
	var rect := Rect2(pan + Vector2(pending.position) * zoom, Vector2(pending.size) * zoom)
	var image := image_rect()
	var cut := Color(1.0, 0.25, 0.25, 0.35)
	if canvas_margins[0] < 0:
		_overlay.draw_rect(Rect2(image.position, Vector2(-canvas_margins[0] * zoom, image.size.y)), cut)
	if canvas_margins[2] < 0:
		_overlay.draw_rect(Rect2(Vector2(image.end.x + canvas_margins[2] * zoom, image.position.y), Vector2(-canvas_margins[2] * zoom, image.size.y)), cut)
	if canvas_margins[1] < 0:
		_overlay.draw_rect(Rect2(image.position, Vector2(image.size.x, -canvas_margins[1] * zoom)), cut)
	if canvas_margins[3] < 0:
		_overlay.draw_rect(Rect2(Vector2(image.position.x, image.end.y + canvas_margins[3] * zoom), Vector2(image.size.x, -canvas_margins[3] * zoom)), cut)
	_overlay.draw_rect(rect, Color(0.3, 0.75, 1.0, 0.08))
	_draw_dashed_rect(rect, Color(0.3, 0.8, 1.0, 1.0), Color(0, 0, 0, 0.85))
	for point: Vector2 in [rect.position, Vector2(rect.get_center().x, rect.position.y), Vector2(rect.end.x, rect.position.y),
			Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y),
			Vector2(rect.position.x, rect.end.y), Vector2(rect.get_center().x, rect.end.y), rect.end]:
		var handle := Rect2(point - Vector2(4, 4), Vector2(8, 8))
		_overlay.draw_rect(handle, Color(1, 1, 1))
		_overlay.draw_rect(handle, Color(0, 0, 0), false, 1.0)
	var font := get_theme_default_font()
	var text := margins_text(pending.size, canvas_margins)
	var at := Vector2(rect.position.x, rect.position.y - 8.0)
	if at.y < 16.0:
		at.y = rect.end.y + 18.0
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	_overlay.draw_rect(Rect2(at + Vector2(-4, -14), Vector2(width + 8, 19)), Color(_bg, 0.9))
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _line)


## 「W × H px(左 +2 上 0 右 -3 下 +1)」:沒有加減就只寫尺寸。
static func margins_text(new_size: Vector2i, margins: Array) -> String:
	var text := "%d × %d px" % [new_size.x, new_size.y]
	if margins.any(func(m: int) -> bool: return m != 0):
		var parts: Array[String] = []
		for k in 4:
			parts.append("%s %s" % [TranslationServer.translate(["左", "上", "右", "下"][k]), ("%+d" % margins[k]) if margins[k] != 0 else "0"])
		text += "(" + " ".join(parts) + ")"
	return text


func is_picking_view() -> bool:
	return tool == "picker" or _drag == "pick" or Input.is_key_pressed(KEY_ALT)


# --- 繪製 ---

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _bg)


func _draw_overlay() -> void:
	if doc == null or doc.page() == null:
		return
	var rect := image_rect()
	var count := doc.page_count()
	if show_reference and doc.index < references.size() and references[doc.index] is Dictionary:
		var reference: Dictionary = references[doc.index]
		var texture: Texture2D = reference["texture"]
		var at := pan + (Vector2(reference["offset"]) + Vector2(_shift())) * zoom
		var factor: Vector2 = reference.get("scale", Vector2.ONE)
		if factor == Vector2.ONE:
			_overlay.draw_texture_rect(texture, Rect2(at, texture.get_size() * zoom), false, Color(1, 1, 1, 0.4))
		else:
			# 圖層有縮放、翻轉或鏡像:本體照比例縮放 / 翻過來墊(見 PackEditorWindow.layer_reference)
			_overlay.draw_set_transform(at, 0.0, factor * zoom)
			_overlay.draw_texture(texture, Vector2.ZERO, Color(1, 1, 1, 0.4))
			_overlay.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if show_onion and count > 1:
		var previous := (doc.index - 1 + count) % count
		_draw_page(previous, rect, Color(1.0, 0.45, 0.45, 0.3), false)
		var next := (doc.index + 1) % count
		if next != previous:
			_draw_page(next, rect, Color(0.45, 0.65, 1.0, 0.22), false)
	_draw_page(doc.index, rect, Color.WHITE, true)
	if show_grid and zoom >= GRID_MIN_ZOOM:
		_draw_grid(rect)
	_overlay.draw_rect(rect, Color(_line, 0.35), false, 1.0)
	if doc.index < markers.size() and markers[doc.index] is Vector2:
		var marker := pan + ((markers[doc.index] as Vector2) + Vector2(_shift())) * zoom
		var faint := Color(0.3, 0.85, 1.0, 0.55)
		_overlay.draw_line(Vector2(rect.position.x, marker.y), Vector2(rect.end.x, marker.y), faint, 1.0)
		_overlay.draw_line(marker + Vector2(0, -8), marker + Vector2(0, 8), faint, 1.0)
	if doc.selection.has_area():
		if doc.selection_mask.is_empty():
			var selected := Rect2(pan + Vector2(doc.selection.position) * zoom, Vector2(doc.selection.size) * zoom)
			_draw_dashed_rect(selected, Color(1, 1, 1, 0.95), Color(0, 0, 0, 0.85))
		else:
			_draw_mask_outline()
	if _drag == "select" and _select_preview.has_area():
		_draw_dashed_rect(Rect2(pan + Vector2(_select_preview.position) * zoom, Vector2(_select_preview.size) * zoom), Color(1, 1, 1, 0.95), Color(0, 0, 0, 0.85))
	if _drag == "lasso" and _lasso.size() >= 2:
		var screen := PackedVector2Array()
		for point in _lasso:
			screen.append(pan + point * zoom)
		screen.append(screen[0])
		_overlay.draw_polyline(screen, Color(0, 0, 0, 0.85), 1.0)
		for k in screen.size() - 1:
			_overlay.draw_dashed_line(screen[k], screen[k + 1], Color(1, 1, 1, 0.95), 1.0, 4.0)
	if _drag == "gradient":
		var a := pan + _shape_from * zoom
		var b := pan + _shape_to * zoom
		_overlay.draw_line(a, b, Color(0, 0, 0, 0.85), 3.0)
		_overlay.draw_line(a, b, Color(1, 1, 1, 0.95), 1.0)
		_overlay.draw_circle(a, 3.0, primary)
		_overlay.draw_circle(b, 3.0, Color(secondary, maxf(secondary.a, 0.5)))
	if tool == "canvas":
		_draw_canvas_frame()
		return
	if _hover is Vector2i:
		if is_picking_view():
			_draw_magnifier(_hover)
		elif tool in ["brush", "eraser", "line"] or ((tool == "rect" or tool == "ellipse") and not shape_filled):
			var settings := eraser if tool == "eraser" else brush
			var diameter := float(int(settings.get("size", 1)))
			var center := _hover_screen if bool(settings.get("smooth", false)) else pan + (Vector2(_hover as Vector2i) + Vector2(0.5, 0.5)) * zoom
			if int(diameter) % 2 == 0 and not bool(settings.get("smooth", false)):
				center = pan + to_image(_hover_screen).round() * zoom
			_overlay.draw_arc(center, maxf(diameter * zoom * 0.5, 2.0), 0.0, TAU, 32, Color(_line, 0.7), 1.0)


## 一頁全部顯示中的繪圖圖層(照不透明度);current = 目前這一頁(浮動的一塊畫在目前的圖層上面)。
func _draw_page(page_index: int, rect: Rect2, tint: Color, current: bool) -> void:
	for l in doc.layers.size():
		var meta: Dictionary = doc.layers[l]
		if not doc.layer_shown(l):
			continue
		var modulate := Color(tint, tint.a * float(meta["opacity"]))
		var texture := _texture_of(page_index, l)
		if texture != null:
			_overlay.draw_texture_rect(texture, rect, false, modulate)
		if current and l == doc.layer and _float_texture != null and doc.floating != null:
			_overlay.draw_texture_rect(_float_texture, Rect2(pan + Vector2(doc.selection.position) * zoom, Vector2(doc.floating.get_size()) * zoom), false, modulate)


## 不是矩形的選取範圍:沿著遮罩的邊緣一格一段,黑白交錯(像虛線)。邊緣只在遮罩變了才重算。
func _draw_mask_outline() -> void:
	var key := [doc.selection.size, hash(doc.selection_mask)]
	if key != _outline_key:
		_outline_key = key
		_outline = _mask_edges(doc.selection_mask, doc.selection.size)
	var origin := pan + Vector2(doc.selection.position) * zoom
	var light := Color(1, 1, 1, 0.95)
	var dark := Color(0, 0, 0, 0.85)
	var lines := PackedVector2Array()
	var colors := PackedColorArray()
	for edge: Array in _outline:
		var a: Vector2 = edge[0]
		var b: Vector2 = edge[1]
		lines.append(origin + a * zoom)
		lines.append(origin + b * zoom)
		colors.append(light if (int(a.x) + int(a.y)) % 2 == 0 else dark)
	if not lines.is_empty():
		_overlay.draw_multiline_colors(lines, colors, 1.0)


## 遮罩每一格選到、旁邊沒選到的那一邊算一段邊緣:[[起點, 終點]…](遮罩裡的座標)。
static func _mask_edges(mask: PackedByteArray, size: Vector2i) -> Array:
	var edges: Array = []
	var on := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < size.x and y < size.y and mask[y * size.x + x] != 0
	for y in size.y:
		for x in size.x:
			if mask[y * size.x + x] == 0:
				continue
			if not on.call(x, y - 1):
				edges.append([Vector2(x, y), Vector2(x + 1, y)])
			if not on.call(x, y + 1):
				edges.append([Vector2(x, y + 1), Vector2(x + 1, y + 1)])
			if not on.call(x - 1, y):
				edges.append([Vector2(x, y), Vector2(x, y + 1)])
			if not on.call(x + 1, y):
				edges.append([Vector2(x + 1, y), Vector2(x + 1, y + 1)])
	return edges


func _draw_grid(rect: Rect2) -> void:
	var color := Color(_line, 0.12)
	var shown := rect.intersection(Rect2(Vector2.ZERO, size))
	if not shown.has_area():
		return
	var first := to_pixel(shown.position)
	var last := to_pixel(shown.end)
	for x in range(maxi(first.x, 0), mini(last.x + 1, doc.page_size().x) + 1):
		var sx := pan.x + x * zoom
		_overlay.draw_line(Vector2(sx, shown.position.y), Vector2(sx, shown.end.y), color, 1.0)
	for y in range(maxi(first.y, 0), mini(last.y + 1, doc.page_size().y) + 1):
		var sy := pan.y + y * zoom
		_overlay.draw_line(Vector2(shown.position.x, sy), Vector2(shown.end.x, sy), color, 1.0)


func _draw_dashed_rect(rect: Rect2, light: Color, dark: Color) -> void:
	var corners: Array[Vector2] = [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		_overlay.draw_line(corners[k], corners[(k + 1) % 4], dark, 1.0)
		_overlay.draw_dashed_line(corners[k], corners[(k + 1) % 4], light, 1.0, 4.0)


## 吸色的迷你放大鏡:游標附近 11×11 個像素放大,中間那格框起來,底下寫色碼(含 alpha)。
func _draw_magnifier(pixel: Vector2i) -> void:
	var box := Vector2.ONE * MAGNIFIER_CELLS * MAGNIFIER_CELL
	var at := _hover_screen + Vector2(22, 22)
	if at.x + box.x + 4.0 > size.x:
		at.x = _hover_screen.x - 22.0 - box.x
	if at.y + box.y + 26.0 > size.y:
		at.y = _hover_screen.y - 22.0 - box.y - 22.0
	var font := get_theme_default_font()
	_overlay.draw_rect(Rect2(at - Vector2(3, 3), box + Vector2(6, 28)), Color(_bg, 0.95))
	var half := MAGNIFIER_CELLS / 2
	var image_rect_i := Rect2i(Vector2i.ZERO, doc.page_size())
	for dy in MAGNIFIER_CELLS:
		for dx in MAGNIFIER_CELLS:
			var cell := Rect2(at + Vector2(dx, dy) * MAGNIFIER_CELL, Vector2.ONE * MAGNIFIER_CELL)
			var checker := checker_colors()[(dx + dy) % 2]
			_overlay.draw_rect(cell, checker)
			var source := pixel + Vector2i(dx - half, dy - half)
			if image_rect_i.has_point(source):
				var color: Variant = doc.pick(source)
				if color is Color:
					_overlay.draw_rect(cell, color)
	var center := Rect2(at + Vector2(half, half) * MAGNIFIER_CELL, Vector2.ONE * MAGNIFIER_CELL)
	_overlay.draw_rect(center.grow(1.0), Color(0, 0, 0), false, 1.0)
	_overlay.draw_rect(center.grow(2.0), Color(1, 1, 1), false, 1.0)
	var picked: Variant = doc.pick(pixel)
	if picked is Color:
		_overlay.draw_string(font, at + Vector2(0, box.y + 18.0), "#" + (picked as Color).to_html(true).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, box.x, 13, _line)
