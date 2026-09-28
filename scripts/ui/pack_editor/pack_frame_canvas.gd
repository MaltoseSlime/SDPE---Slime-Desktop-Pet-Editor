class_name PackFrameCanvas
extends Control
## 素材包編輯器的畫布:顯示一幀圖、軸心線(腳底線 + 中心點)、上一幀殘影,滑鼠/鍵盤編輯。
##
## 座標:世界腳底點 W = 畫布的固定位置(角色真正踩地的那一點);圖片貼的位置 = W − (軸心 − 圖片偏移) × 縮放。
## 兩種編輯模式:
##  - 移動軸心(PIVOT):軸心線黏在圖上。點/拖曳 = 把軸心線移到滑鼠所在的圖片像素(Shift 只改腳底線 y、Ctrl 只改中心點 x);
##    拖曳期間圖片不動,放開後畫面重新對齊。
##  - 移動圖片(IMAGE):軸心線固定在 W(腳底線、坐下判定不動),拖曳圖片 = 改圖片偏移。
##  - 調整判定框(HITBOX):綠色框是互動判定框(縮放前像素,錨點 = 腳底中心 W)。拖曳邊或角 = 改大小(對邊不動),拖曳框裡面 = 移動。
## 方向鍵微調目前模式的值 1 像素(Shift = 10)。滾輪縮放、右鍵/中鍵拖曳平移畫面。
## 預設是「移動視角畫面」(VIEW):左鍵拖曳平移畫面,不會改到任何資料;另有「裁切圖片」(CROP):拖出一個框,由視窗按「套用裁切」。

## 一次編輯手勢「即將」開始(滑鼠按下 / 方向鍵),視窗據此存撤回點。kind = "drag"(每次按下都是新的一步)或 "key"(連續按鍵合併)。
signal edit_started(kind: String)
signal pivot_edited(pivot: Vector2)
signal offset_edited(offset: Vector2)
signal zoom_changed(zoom: float)
## 判定框被拖曳/微調:rect 是相對腳底中心 W 的範圍(縮放前像素,左上角 + 大小)。
signal hitbox_edited(rect: Rect2)

## 裁切框被拖曳:rect 是圖片像素座標(左上角 + 大小,已夾在圖片範圍內)。
signal crop_changed(rect: Rect2i)
## 在裁切模式按 Enter:視窗當成「套用裁切」。
signal crop_confirm_requested

## 光源(發光效果)錨點被拖曳/微調:index 是第幾盞,at 是相對腳底中心 W 的位置(縮放前像素)。
signal light_edited(index: int, at: Vector2)
## 在畫布上按到某盞光的錨點(選取);沒按到任何一盞是 -1。
signal light_selected(index: int)
## 配件模式:拖曳(或方向鍵微調)配件的錨點(相對腳底軸心的像素);按到別的配件就換選。
signal accessory_edited(index: int, at: Vector2)
signal accessory_selected(index: int)

enum Mode { VIEW, PIVOT, IMAGE, HITBOX, CROP, LIGHT, ACCESSORY }

## 縮放範圍:縮小到 1/4(大圖整張看)、放大到 64 倍(逐像素對位);滾輪與 ＋／－ 沿著這些檔位走。
const MIN_ZOOM := 0.25
const MAX_ZOOM := 64.0
const ZOOM_STEPS: Array[float] = [0.25, 0.5, 1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 32.0, 48.0, 64.0]

const COLOR_FOOT_LINE := Color(1.0, 0.36, 0.3)
const COLOR_CENTER_LINE := Color(0.3, 0.85, 1.0)

const COLOR_IMAGE_PIVOT := Color(1.0, 0.85, 0.2)

const COLOR_HITBOX := Color(0.35, 1.0, 0.45)
const GHOST_ALPHA := 0.35
## 畫布底色、地面色與輔助線的「墨色」:跟著編輯器配色(見 PackEditorWindow.refresh_theme),預設是舊的深色。
var bg_color := Color(0.15, 0.16, 0.19)
var ground_color := Color(0.11, 0.12, 0.14)
var ink_color := Color.WHITE
## 判定框的邊/角在畫布上的可抓取距離(螢幕像素)。
const EDGE_GRAB := 8.0

## 目前的編輯模式(預設「移動視角畫面」);游標形狀跟著換。
var mode: Mode = Mode.VIEW:
	set(value):
		mode = value
		mouse_default_cursor_shape = Control.CURSOR_DRAG if mode == Mode.VIEW else (Control.CURSOR_CROSS if mode == Mode.CROP else Control.CURSOR_ARROW)
		queue_redraw()
var zoom := 4.0
var show_ghost := true
## 編輯器「圖層」頁籤的眼睛:本體圖(動作的幀)在預覽裡要不要畫(只影響畫面,不存檔)。
var show_body := true
var show_hitbox := true
var show_lights := true
## 光源清單(PackLights 的格式)與目前選取、正在拖曳的是第幾盞。
var _lights: Array[Dictionary] = []
var _light_selected := -1
var _light_drag := -1
## 配件預覽:每項 {x, y, scale, origin(圖上「放在錨點的那一點」的像素), texture, name};畫在目前這一幀上,配件模式下可以拖曳。
var _accs: Array[Dictionary] = []
var _acc_selected := -1
var _acc_drag := -1
## 沒有圖可顯示時(還沒開啟素材包、動作是空的)畫在畫布中間的提示文字。
var hint_text := ""

## 判定框(相對 W 的範圍,縮放前像素);explicit 為 false = 自動值,畫成半透明。
var _hitbox := Rect2()
var _hitbox_valid := false
var _hitbox_explicit := false
var _hit_drag: Dictionary = {}

## 裁切框(圖片像素座標);size 為 0 = 沒有框。
var _crop := Rect2i()
var _crop_dragging := false
var _crop_anchor := Vector2i.ZERO

var _texture: Texture2D
var _image_size := Vector2i.ZERO
var _pivot := Vector2.ZERO
var _offset := Vector2.ZERO
var _ghost_texture: Texture2D
var _ghost_place := Vector2.ZERO
var _pan := Vector2.ZERO
var _pivot_dragging := false
var _frozen_origin := Vector2.ZERO
var _image_dragging := false
var _drag_start_mouse := Vector2.ZERO
var _drag_start_offset := Vector2.ZERO
var _panning := false


func _init() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(320, 220)
	mouse_default_cursor_shape = Control.CURSOR_DRAG


## 換一幀。pivot 是軸心(圖片像素座標)、offset 是圖片偏移;拖曳中不要呼叫(視窗只在選幀或數值改變時呼叫)。
func set_frame(texture: Texture2D, size: Vector2i, pivot: Vector2, offset: Vector2) -> void:
	_texture = texture
	_image_size = size
	_pivot = pivot
	_offset = offset
	queue_redraw()


## 上一幀的殘影(對齊用):texture 為 null 就不畫;place = 那一幀的 (軸心 − 圖片偏移)。
func set_ghost(texture: Texture2D, place: Vector2) -> void:
	_ghost_texture = texture
	_ghost_place = place
	queue_redraw()


## 設定要顯示/編輯的判定框(相對 W 的範圍)。拖曳中不要呼叫。
func set_hitbox_rect(rect: Rect2, explicit: bool) -> void:
	_hitbox = rect
	_hitbox_valid = true
	_hitbox_explicit = explicit
	queue_redraw()


## 給畫布畫光源:清單(整理過的字典)與選取的索引。
func set_lights(list: Array[Dictionary], selected: int) -> void:
	_lights = list
	_light_selected = selected if selected >= 0 and selected < list.size() else -1
	queue_redraw()


func set_accessories(list: Array[Dictionary], selected: int) -> void:
	_accs = list
	_acc_selected = selected if selected >= 0 and selected < list.size() else -1
	queue_redraw()


func _acc_screen(acc: Dictionary) -> Vector2:
	return _anchor() + Vector2(float(acc["x"]), float(acc["y"])) * float(zoom)


## 配件:圖片依縮放與倍率畫在錨點上(圖上的 origin 那一點對準錨點),錨點畫十字;配件模式下選取的加粗。
## phase 0 = 「本體後面」的配件圖(畫在本體之前)、1 = 本體上面與最上層的配件圖、2 = 錨點十字與名字(所有沒被隱藏的配件)。
## 配件的 "layer"(back / front / top)和 "hidden"(編輯器裡暫時隱藏,只影響預覽)由編輯器的「圖層」頁籤設定。
func _draw_accessories(phase: int = 1) -> void:
	for i in _accs.size():
		var acc := _accs[i]
		if bool(acc.get("hidden", false)):
			continue
		var center := _acc_screen(acc)
		var texture: Texture2D = acc.get("texture")
		var factor := float(acc["scale"]) * float(zoom)
		var behind := str(acc.get("layer", "front")) == "back"
		if texture != null and phase < 2 and (phase == 0) == behind:
			var origin: Vector2 = acc["origin"]
			draw_texture_rect(texture, Rect2(center - origin * factor, texture.get_size() * factor), false, Color(1, 1, 1, 0.95 if str(acc.get("role", "part")) == "part" else 0.6))
		if phase < 2:
			continue
		var selected := i == _acc_selected
		var color := Color(0.5, 1.0, 0.6, 0.95) if selected else Color(ink_color, 0.6 if mode == Mode.ACCESSORY else 0.25)
		if mode == Mode.ACCESSORY or selected:
			_draw_cross(center, color, 8.0 if selected else 6.0)
			draw_string(get_theme_default_font(), center + Vector2(10.0, -10.0), str(acc["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _begin_acc_drag(mouse: Vector2) -> void:
	var best := -1
	var best_distance := 18.0
	for i in _accs.size():
		if bool(_accs[i].get("hidden", false)):
			continue
		var distance := mouse.distance_to(_acc_screen(_accs[i]))
		if distance <= best_distance:
			best_distance = distance
			best = i
	_acc_selected = best
	accessory_selected.emit(best)
	if best >= 0:
		edit_started.emit("drag")
		_acc_drag = best
	queue_redraw()


func _update_acc_drag(mouse: Vector2) -> void:
	if _acc_drag < 0 or _acc_drag >= _accs.size():
		return
	var at := ((mouse - _anchor()) / float(zoom)).round()
	_accs[_acc_drag]["x"] = at.x
	_accs[_acc_drag]["y"] = at.y
	accessory_edited.emit(_acc_drag, at)
	queue_redraw()


## 光源錨點在畫布上的位置(W + 相對位置 × 縮放)。
func _light_screen(light: Dictionary) -> Vector2:
	return _anchor() + Vector2(float(light["x"]), float(light["y"])) * float(zoom)


func clear_hitbox_rect() -> void:
	_hitbox_valid = false
	queue_redraw()


func set_zoom(value: float) -> void:
	zoom = clampf(value, MIN_ZOOM, MAX_ZOOM)
	zoom_changed.emit(zoom)
	queue_redraw()


## 放大 / 縮小一檔(沿著 ZOOM_STEPS 走)。
func zoom_in() -> void:
	for step in ZOOM_STEPS:
		if step > zoom + 0.001:
			set_zoom(step)
			return
	set_zoom(MAX_ZOOM)


func zoom_out() -> void:
	for i in range(ZOOM_STEPS.size() - 1, -1, -1):
		if ZOOM_STEPS[i] < zoom - 0.001:
			set_zoom(ZOOM_STEPS[i])
			return
	set_zoom(MIN_ZOOM)


## 設定(或清掉,傳空的 Rect2i)裁切框。拖曳中不要呼叫。
func set_crop_rect(rect: Rect2i) -> void:
	_crop = rect
	queue_redraw()


func crop_rect() -> Rect2i:
	return _crop


func reset_view() -> void:
	_pan = Vector2.ZERO
	queue_redraw()


## 世界腳底點 W 在畫布上的位置:水平置中、垂直在 70% 的地方(腳底以上要留比較多空間)。
func _anchor() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.7) + _pan


## 圖片左上角在畫布上的位置。軸心拖曳期間凍結,圖片才不會跟著跑。
func _origin() -> Vector2:
	if _pivot_dragging:
		return _frozen_origin
	return _anchor() - (_pivot - _offset) * float(zoom)


## 用編輯器配色設定底色:畫布 = 視窗背景色、地面 = 背景往文字反方向壓一點,輔助線用文字色。
func apply_theme_colors(bg: Color, text: Color) -> void:
	bg_color = bg
	ground_color = bg.darkened(0.18) if bg.get_luminance() > 0.5 else bg.darkened(0.3)
	ink_color = text
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), bg_color)
	if _texture == null and hint_text != "":
		var font := get_theme_default_font()
		draw_multiline_string(font, Vector2(24, size.y * 0.4), hint_text, HORIZONTAL_ALIGNMENT_CENTER, maxf(size.x - 48.0, 100.0), 17, -1, Color(ink_color, 0.7))
	var anchor := _anchor()
	draw_rect(Rect2(0, anchor.y, size.x, maxf(size.y - anchor.y, 0.0)), ground_color)
	if show_ghost and _ghost_texture != null:
		var ghost_size := Vector2(_ghost_texture.get_size()) * float(zoom)
		draw_texture_rect(_ghost_texture, Rect2(anchor - _ghost_place * float(zoom), ghost_size), false, Color(1, 1, 1, GHOST_ALPHA))
	var origin := _origin()
	_draw_accessories(0)
	if _texture != null and show_body:
		draw_texture_rect(_texture, Rect2(origin, Vector2(_image_size) * float(zoom)), false)
		draw_rect(Rect2(origin, Vector2(_image_size) * float(zoom)), Color(ink_color, 0.25), false, 1.0)
	var pivot_screen := origin + _pivot * float(zoom)
	var moved := _offset != Vector2.ZERO
	if mode == Mode.PIVOT:
		_draw_lines(pivot_screen)
		if moved:
			_draw_cross(anchor, Color(ink_color, 0.7), 8.0)
	else:
		_draw_lines(anchor)
		if moved:
			_draw_cross(pivot_screen, COLOR_IMAGE_PIVOT, 6.0)
	if mode == Mode.CROP and _texture != null:
		_draw_crop(origin)
	if show_lights or mode == Mode.LIGHT:
		_draw_lights()
	_draw_accessories(1)
	_draw_accessories(2)
	if show_hitbox and _hitbox_valid:
		var box := _hitbox_screen_rect()
		var color := COLOR_HITBOX if _hitbox_explicit or mode == Mode.HITBOX else Color(COLOR_HITBOX, 0.45)
		draw_rect(box, Color(color, 0.08), true)
		draw_rect(box, color, false, 2.0 if mode == Mode.HITBOX else 1.0)


## 光源:柔和的光暈(用同一張放射漸層)+ 錨點圓點與名稱;光源模式下選取的那盞加粗外圈,可以抓來拖。
func _draw_lights() -> void:
	for i in _lights.size():
		var light := _lights[i]
		var center := _light_screen(light)
		var radius := float(light["radius"]) * float(zoom)
		var color := Color(str(light["color"]))
		var enabled := bool(light["enabled"])
		color.a = clampf(float(light["energy"]) * 0.6, 0.0, 1.0) * (1.0 if enabled else 0.25)
		draw_texture_rect(PetLights.glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)
		var selected := i == _light_selected
		var marker_color := Color(1.0, 0.95, 0.5, 0.95) if selected else Color(ink_color, 0.7 if mode == Mode.LIGHT else 0.35)
		draw_circle(center, 5.0, marker_color)
		draw_arc(center, 9.0 if selected else 7.0, 0.0, TAU, 20, marker_color, 2.0 if selected else 1.0, true)
		if mode == Mode.LIGHT:
			draw_arc(center, radius, 0.0, TAU, 48, Color(marker_color, 0.35), 1.0, true)
			draw_string(get_theme_default_font(), center + Vector2(12.0, -10.0), str(light["name"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, marker_color)


## 裁切框:框外的圖壓暗、框畫黃色外框,旁邊標出大小。沒有框時畫一行提示。
func _draw_crop(origin: Vector2) -> void:
	var image_rect := Rect2(origin, Vector2(_image_size) * float(zoom))
	if _crop.size == Vector2i.ZERO:
		draw_string(get_theme_default_font(), image_rect.position + Vector2(6, 18), "拖曳畫出要保留的範圍", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.5, 0.9))
		return
	var box := Rect2(origin + Vector2(_crop.position) * float(zoom), Vector2(_crop.size) * float(zoom))
	var dim := Color(0, 0, 0, 0.55)
	draw_rect(Rect2(image_rect.position, Vector2(image_rect.size.x, box.position.y - image_rect.position.y)), dim)
	draw_rect(Rect2(image_rect.position.x, box.end.y, image_rect.size.x, image_rect.end.y - box.end.y), dim)
	draw_rect(Rect2(image_rect.position.x, box.position.y, box.position.x - image_rect.position.x, box.size.y), dim)
	draw_rect(Rect2(box.end.x, box.position.y, image_rect.end.x - box.end.x, box.size.y), dim)
	draw_rect(box, Color(1.0, 0.9, 0.2), false, 2.0)
	draw_string(get_theme_default_font(), box.position + Vector2(4, -6 if box.position.y > 18.0 else 16.0), "%d×%d" % [_crop.size.x, _crop.size.y], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.5))


## 判定框在畫布上的位置(W + 相對範圍 × 縮放)。
func _hitbox_screen_rect() -> Rect2:
	return Rect2(_anchor() + _hitbox.position * float(zoom), _hitbox.size * float(zoom))


## 腳底線(橫,橘紅)+ 中心點線(直,青),各畫成貫穿整個畫布的細線。
func _draw_lines(at: Vector2) -> void:
	draw_line(Vector2(0, at.y), Vector2(size.x, at.y), COLOR_FOOT_LINE, 1.0)
	draw_line(Vector2(at.x, 0), Vector2(at.x, size.y), COLOR_CENTER_LINE, 1.0)


func _draw_cross(at: Vector2, color: Color, arm: float) -> void:
	draw_line(at - Vector2(arm, 0), at + Vector2(arm, 0), color, 2.0)
	draw_line(at - Vector2(0, arm), at + Vector2(0, arm), color, 2.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_mouse_button(event)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(event)
	elif event is InputEventKey and event.pressed:
		_on_key(event)


func _on_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				zoom_in()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				zoom_out()
		MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		MOUSE_BUTTON_LEFT:
			grab_focus()
			if mode == Mode.VIEW:
				# 移動視角畫面:左鍵拖曳 = 平移,不會改到任何資料。
				_panning = event.pressed
				return
			if _texture == null:
				return
			if event.pressed:
				_begin_drag(event.position, event.shift_pressed, event.ctrl_pressed)
			else:
				_pivot_dragging = false
				_image_dragging = false
				_crop_dragging = false
				_hit_drag = {}
				_light_drag = -1
				_acc_drag = -1
				queue_redraw()


func _begin_drag(mouse: Vector2, only_y: bool, only_x: bool) -> void:
	if mode == Mode.HITBOX:
		_begin_hitbox_drag(mouse)
		return
	if mode == Mode.LIGHT:
		_begin_light_drag(mouse)
		return
	if mode == Mode.ACCESSORY:
		_begin_acc_drag(mouse)
		return
	if mode == Mode.CROP:
		_crop_dragging = true
		_crop_anchor = _image_point(mouse)
		_update_crop(_crop_anchor)
		return
	edit_started.emit("drag")
	if mode == Mode.PIVOT:
		_pivot_dragging = true
		_frozen_origin = _origin()
		_move_pivot_to(mouse, only_y, only_x)
	else:
		_image_dragging = true
		_drag_start_mouse = mouse
		_drag_start_offset = _offset


## 滑鼠位置 → 圖片像素座標(夾在圖片範圍內)。
func _image_point(mouse: Vector2) -> Vector2i:
	var point := ((mouse - _origin()) / float(zoom)).round()
	return Vector2i(clampi(int(point.x), 0, _image_size.x), clampi(int(point.y), 0, _image_size.y))


## 裁切框拖曳:從按下的點到目前的點(至少 1×1)。
func _update_crop(current: Vector2i) -> void:
	var low := Vector2i(mini(_crop_anchor.x, current.x), mini(_crop_anchor.y, current.y))
	var high := Vector2i(maxi(_crop_anchor.x, current.x), maxi(_crop_anchor.y, current.y))
	_crop = Rect2i(low, Vector2i(maxi(high.x - low.x, 1), maxi(high.y - low.y, 1))).intersection(Rect2i(Vector2i.ZERO, _image_size))
	crop_changed.emit(_crop)
	queue_redraw()


## 光源模式:按到某盞的錨點(離游標最近、螢幕上 16 像素內)就選取並開始拖曳;沒按到任何一盞就取消選取。
func _begin_light_drag(mouse: Vector2) -> void:
	var best := -1
	var best_distance := 16.0
	for i in _lights.size():
		var distance := mouse.distance_to(_light_screen(_lights[i]))
		if distance <= best_distance:
			best_distance = distance
			best = i
	_light_selected = best
	light_selected.emit(best)
	if best >= 0:
		edit_started.emit("drag")
		_light_drag = best
	queue_redraw()


func _update_light_drag(mouse: Vector2) -> void:
	if _light_drag < 0 or _light_drag >= _lights.size():
		return
	var at := ((mouse - _anchor()) / float(zoom)).round()
	_lights[_light_drag]["x"] = at.x
	_lights[_light_drag]["y"] = at.y
	light_edited.emit(_light_drag, at)
	queue_redraw()


## 判定框拖曳:抓到邊/角就縮放(對邊不動),抓到裡面就整個移動;框外不理。
func _begin_hitbox_drag(mouse: Vector2) -> void:
	if not _hitbox_valid:
		return
	var box := _hitbox_screen_rect()
	var near_left := absf(mouse.x - box.position.x) <= EDGE_GRAB
	var near_right := absf(mouse.x - box.end.x) <= EDGE_GRAB
	var near_top := absf(mouse.y - box.position.y) <= EDGE_GRAB
	var near_bottom := absf(mouse.y - box.end.y) <= EDGE_GRAB
	var within_x := mouse.x >= box.position.x - EDGE_GRAB and mouse.x <= box.end.x + EDGE_GRAB
	var within_y := mouse.y >= box.position.y - EDGE_GRAB and mouse.y <= box.end.y + EDGE_GRAB
	var left := near_left and within_y
	var right := near_right and within_y and not left
	var top := near_top and within_x
	var bottom := near_bottom and within_x and not top
	var moving := not (left or right or top or bottom) and box.has_point(mouse)
	if not (left or right or top or bottom or moving):
		return
	edit_started.emit("drag")
	_hit_drag = {"left": left, "right": right, "top": top, "bottom": bottom, "move": moving, "start": _hitbox, "mouse": mouse}


func _update_hitbox_drag(mouse: Vector2) -> void:
	var start: Rect2 = _hit_drag["start"]
	var delta := ((mouse - (_hit_drag["mouse"] as Vector2)) / float(zoom)).round()
	var left := start.position.x
	var right := start.end.x
	var top := start.position.y
	var bottom := start.end.y
	if _hit_drag["move"]:
		left += delta.x
		right += delta.x
		top += delta.y
		bottom += delta.y
	else:
		if _hit_drag["left"]:
			left = minf(left + delta.x, right - 1.0)
		if _hit_drag["right"]:
			right = maxf(right + delta.x, left + 1.0)
		if _hit_drag["top"]:
			top = minf(top + delta.y, bottom - 1.0)
		if _hit_drag["bottom"]:
			bottom = maxf(bottom + delta.y, top + 1.0)
	_hitbox = Rect2(left, top, right - left, bottom - top)
	_hitbox_explicit = true
	hitbox_edited.emit(_hitbox)
	queue_redraw()


func _on_mouse_motion(event: InputEventMouseMotion) -> void:
	if _panning:
		_pan += event.relative
		queue_redraw()
	elif _crop_dragging:
		_update_crop(_image_point(event.position))
	elif _light_drag >= 0:
		_update_light_drag(event.position)
	elif _acc_drag >= 0:
		_update_acc_drag(event.position)
	elif not _hit_drag.is_empty():
		_update_hitbox_drag(event.position)
	elif _pivot_dragging:
		_move_pivot_to(event.position, event.shift_pressed, event.ctrl_pressed)
	elif _image_dragging:
		var delta := ((event.position - _drag_start_mouse) / float(zoom)).round()
		_offset = _drag_start_offset + delta
		offset_edited.emit(_offset)
		queue_redraw()


func _move_pivot_to(mouse: Vector2, only_y: bool, only_x: bool) -> void:
	var image_point := ((mouse - _frozen_origin) / float(zoom)).round()
	var next := _pivot
	if not only_x:
		next.y = clampf(image_point.y, 0.0, float(_image_size.y))
	if not only_y:
		next.x = clampf(image_point.x, 0.0, float(_image_size.x))
	if next != _pivot:
		_pivot = next
		pivot_edited.emit(_pivot)
	queue_redraw()


## 方向鍵微調目前模式的值:軸心模式 = 軸心線往該方向移;圖片模式 = 圖片往該方向移。
func _on_key(event: InputEventKey) -> void:
	var step := 10.0 if event.shift_pressed else 1.0
	var direction := Vector2.ZERO
	match event.keycode:
		KEY_LEFT:
			direction = Vector2.LEFT
		KEY_RIGHT:
			direction = Vector2.RIGHT
		KEY_UP:
			direction = Vector2.UP
		KEY_DOWN:
			direction = Vector2.DOWN
		KEY_ENTER, KEY_KP_ENTER:
			if mode == Mode.CROP:
				accept_event()
				crop_confirm_requested.emit()
			return
		_:
			return
	accept_event()
	if _texture == null or mode == Mode.VIEW or mode == Mode.CROP:
		return
	if mode == Mode.ACCESSORY:
		if _acc_selected >= 0 and _acc_selected < _accs.size():
			edit_started.emit("key")
			var acc_moved := Vector2(float(_accs[_acc_selected]["x"]), float(_accs[_acc_selected]["y"])) + direction * step
			_accs[_acc_selected]["x"] = acc_moved.x
			_accs[_acc_selected]["y"] = acc_moved.y
			accessory_edited.emit(_acc_selected, acc_moved)
			queue_redraw()
		return
	if mode == Mode.LIGHT:
		if _light_selected >= 0 and _light_selected < _lights.size():
			edit_started.emit("key")
			var moved := Vector2(float(_lights[_light_selected]["x"]), float(_lights[_light_selected]["y"])) + direction * step
			_lights[_light_selected]["x"] = moved.x
			_lights[_light_selected]["y"] = moved.y
			light_edited.emit(_light_selected, moved)
			queue_redraw()
		return
	edit_started.emit("key")
	if mode == Mode.HITBOX:
		if _hitbox_valid:
			_hitbox.position += direction * step
			_hitbox_explicit = true
			hitbox_edited.emit(_hitbox)
	elif mode == Mode.PIVOT:
		_pivot = (_pivot + direction * step).clamp(Vector2.ZERO, Vector2(_image_size))
		pivot_edited.emit(_pivot)
	else:
		_offset += direction * step
		offset_edited.emit(_offset)
	queue_redraw()
