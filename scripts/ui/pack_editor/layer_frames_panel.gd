class_name LayerFramesPanel
extends VBoxContainer
## 精靈圖編輯器「圖層」頁的小窗(2026-10-15 使用者要求):管理選取的圖層的每一張圖(動畫幀)——
## 縮圖清單(可複選)、前後移動、複製一份、刪除、加入圖片;下面的預覽可以拖曳畫出裁切範圍,或點選「圖上放在錨點的那一點」(對齊點)。
## 裁切只是「只顯示圖上的這一塊」,位置不變(對齊點仍然照原圖算,見 PetOverlays.crop_rect),所以整張大畫布的圖(例如 512×512 只畫了眼睛)
## 可以放心裁掉空白。資料:部件的 images(檔名)與 crops(一一對應的 [x, y, 寬, 高] 或 null)、origin(預設點名稱或 [x, y])。
## 這個面板不直接動素材包:每次修改發出 part_changed(改好的部件複本),由編輯器存撤回點、寫回模型。
## 版面分兩塊(2026-10-15 圖層頁整理):面板本身是縮圖清單與按鈕;預覽、裁切、對齊點放在 crop_box,由編輯器擺到頁面底下可收合的區段。

signal part_changed(part: Dictionary, message: String, checkpoint_key: String)
signal add_images_requested
signal replace_images_requested(indices: Array)
## 圖層鎖住了還想改(編輯器在狀態列提示先解除鎖定)。
signal locked_touched

const THUMB := Vector2i(48, 48)
const ORIGIN_PRESETS: Array[String] = ["center", "top_left", "bottom_center", "top_center"]

var _part: Dictionary = {}
var _texture_of: Callable   # (相對路徑) -> Texture2D(原圖,沒裁切)
var _image_of: Callable     # (相對路徑) -> Image(原圖,自動裁透明邊用)
var _list: ItemList
var _buttons: Array[Button] = []
var _add_button: Button
var _preview: LayerImagePreview
var _mode: OptionButton
var _crop_spins: Array[SpinBox] = []
var _origin_x: SpinBox
var _origin_y: SpinBox
var _crop_label: Label
var _selected: Array = []
var _focus := 0
var _updating := false
## 預覽、裁切、對齊點(編輯器自己擺位置;面板 _ready 時把內容建進去)。
var crop_box := VBoxContainer.new()


func setup(texture_of: Callable, image_of: Callable) -> void:
	_texture_of = texture_of
	_image_of = image_of


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	crop_box.add_theme_constant_override("separation", 4)
	_list = ItemList.new()
	_list.icon_mode = ItemList.ICON_MODE_TOP
	_list.max_columns = 0
	_list.fixed_icon_size = THUMB
	_list.select_mode = ItemList.SELECT_MULTI
	_list.custom_minimum_size.y = 76.0
	_list.multi_selected.connect(_on_multi_selected)
	add_child(_list)
	# 2026-10-16 改成一排圖示按鈕(名稱在滑鼠停留提示)
	var grid := HFlowContainer.new()
	for spec: Array in [["◀", "前移:選取的圖往前移一格", _move.bind(-1)], ["▶", "後移:選取的圖往後移一格", _move.bind(1)], ["📑", "複製一份:把選取的圖複製一份,接在後面", _duplicate], ["🗑", "刪除選取的圖(至少要留一張)", _delete]]:
		var button := ManagerUi.button(spec[0])
		button.tooltip_text = tr(spec[1])
		button.pressed.connect(spec[2])
		grid.add_child(button)
		_buttons.append(button)
	_add_button = ManagerUi.button("➕")
	_add_button.tooltip_text = tr("加入圖片:選一張或多張圖片加在這個圖層的最後面(多張會循環播放)。")
	_add_button.pressed.connect(func() -> void: add_images_requested.emit())
	grid.add_child(_add_button)
	var replace := ManagerUi.button("🔄")
	replace.tooltip_text = tr("更換圖片:把選取的圖換成別的圖檔(選幾張就依序換幾張),裁切範圍、對齊點、錨點等設定都保留——用同一套模板做不同角色、或重畫某幾張時,不用重新裁切對位。")
	replace.pressed.connect(func() -> void: replace_images_requested.emit(_selected.duplicate()))
	grid.add_child(replace)
	_buttons.append(replace)
	add_child(grid)
	_mode = OptionButton.new()
	_mode.add_item(tr("移動視角畫面"))
	_mode.add_item(tr("拖曳畫裁切範圍"))
	_mode.add_item(tr("點選對齊點"))
	_mode.tooltip_text = tr("移動視角畫面:左鍵拖曳平移預覽(預設)。滾輪放大縮小;任何模式下中鍵、右鍵拖曳也能平移,雙擊中鍵回到整張圖。")
	_mode.item_selected.connect(func(i: int) -> void: _preview.mode = i)
	crop_box.add_child(ManagerUi.labeled("預覽操作", _mode))
	_preview = LayerImagePreview.new()
	_preview.custom_minimum_size = Vector2(0.0, 190.0)
	_preview.crop_drawn.connect(_on_crop_drawn)
	_preview.origin_picked.connect(_on_origin_picked)
	crop_box.add_child(_preview)
	_crop_label = Label.new()
	_crop_label.theme_type_variation = AppSettings.MUTED_LABEL
	_crop_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	crop_box.add_child(_crop_label)
	var crop_grid := GridContainer.new()
	crop_grid.columns = 4
	for caption in ["左", "上", "寬", "高"]:
		var spin := ManagerUi.spin(1.0, 0.0, float(PetOverlays.MAX_SIDE))
		spin.custom_minimum_size.x = 60.0
		spin.tooltip_text = tr("裁切範圍的%s(原圖像素)") % tr(caption)
		spin.value_changed.connect(func(_v: float) -> void: _on_crop_spin_changed())
		_crop_spins.append(spin)
		crop_grid.add_child(spin)
	crop_box.add_child(crop_grid)
	var crop_row := HFlowContainer.new()
	var apply_selected := ManagerUi.button("套用到選取的圖")
	apply_selected.pressed.connect(func() -> void: _apply_crop(_selected))
	var apply_all := ManagerUi.button("套用到全部")
	apply_all.pressed.connect(func() -> void: _apply_crop(range(_images().size())))
	var auto := ManagerUi.button("自動裁掉透明邊")
	auto.tooltip_text = tr("選取的每張圖各自裁到有畫東西(不透明)的範圍。位置不會變。")
	auto.pressed.connect(_auto_trim)
	var clear := ManagerUi.button("清除裁切")
	clear.tooltip_text = tr("選取的圖回到整張原圖。")
	clear.pressed.connect(_clear_crop)
	for button: Button in [apply_selected, apply_all, auto, clear]:
		crop_row.add_child(button)
		_buttons.append(button)
	crop_box.add_child(crop_row)
	var origin_row := HBoxContainer.new()
	_origin_x = ManagerUi.spin(1.0, -float(PetOverlays.MAX_SIDE), float(PetOverlays.MAX_SIDE) * 2.0)
	_origin_y = ManagerUi.spin(1.0, -float(PetOverlays.MAX_SIDE), float(PetOverlays.MAX_SIDE) * 2.0)
	for spin: SpinBox in [_origin_x, _origin_y]:
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spin.value_changed.connect(func(_v: float) -> void: _on_origin_spin_changed())
		origin_row.add_child(spin)
	var origin_reset := ManagerUi.button("回到中心")
	origin_reset.tooltip_text = tr("對齊點回到圖片中心(預設)。")
	origin_reset.pressed.connect(func() -> void: _set_origin("center", tr("對齊點回到圖片中心")))
	origin_row.add_child(origin_reset)
	_buttons.append(origin_reset)
	crop_box.add_child(ManagerUi.labeled("對齊點 X / Y", origin_row))
	_refresh()


## 換成另一個圖層(或同一個圖層改過之後重新整理)。part 空的 = 沒選圖層。
func set_part(part: Dictionary) -> void:
	var same := not _part.is_empty() and not part.is_empty() and str(_part.get("name", "")) == str(part.get("name", ""))
	_part = part.duplicate(true)
	if not same:
		_selected = [0] if not _images().is_empty() else []
		_focus = 0
		if _preview != null:
			_preview.reset_view()
	_selected = _selected.filter(func(i: int) -> bool: return i < _images().size())
	if _selected.is_empty() and not _images().is_empty():
		_selected = [mini(_focus, _images().size() - 1)]
	_focus = clampi(_focus, 0, maxi(_images().size() - 1, 0))
	if is_node_ready():
		_refresh()


## 切換預覽操作(0 = 移動視角畫面、1 = 拖曳畫裁切範圍、2 = 點選對齊點)。
func use_mode(index: int) -> void:
	_mode.select(index)
	_preview.mode = index


func selected_indices() -> Array:
	return _selected.duplicate()


func _images() -> Array:
	return _part.get("images", []) if _part.get("images") is Array else []


func _crops() -> Array:
	var crops: Array = (_part.get("crops", []) as Array).duplicate(true) if _part.get("crops") is Array else []
	while crops.size() < _images().size():
		crops.append(null)
	return crops.slice(0, _images().size())


func _crop_of(index: int) -> Variant:
	var crops := _crops()
	return PetOverlays.crop_rect(crops[index]) if index >= 0 and index < crops.size() else null


func _full_texture(index: int) -> Texture2D:
	var images := _images()
	if index < 0 or index >= images.size() or not _texture_of.is_valid():
		return null
	return _texture_of.call(str(images[index]))


func _refresh() -> void:
	_updating = true
	_list.clear()
	var images := _images()
	for i in images.size():
		var texture := _full_texture(i)
		_list.add_item(str(i), _thumb(i, texture))
		var crop: Variant = _crop_of(i)
		_list.set_item_tooltip(i, "%s%s" % [str(images[i]).get_file(), (tr("\n裁切:%d, %d, %d×%d") % [crop.position.x, crop.position.y, crop.size.x, crop.size.y]) if crop is Rect2i else ""])
	for i in _selected:
		_list.select(i, false)
	var has_part := not _part.is_empty()
	for button: Button in _buttons:
		button.disabled = not has_part or images.is_empty()
	_buttons[0].disabled = not has_part or _selected.is_empty() or _selected.min() == 0
	_buttons[1].disabled = not has_part or _selected.is_empty() or _selected.max() >= images.size() - 1
	_buttons[3].disabled = not has_part or _selected.is_empty() or _selected.size() >= images.size()
	_add_button.disabled = not has_part or images.size() >= PetOverlays.MAX_FRAMES
	var texture := _full_texture(_focus)
	var size := Vector2(texture.get_size()) if texture != null else Vector2.ZERO
	var crop: Variant = _crop_of(_focus)
	var crop_rect: Rect2i = crop if crop is Rect2i else Rect2i(Vector2i.ZERO, Vector2i(size))
	for i in 4:
		_crop_spins[i].editable = texture != null
	_crop_spins[0].value = crop_rect.position.x
	_crop_spins[1].value = crop_rect.position.y
	_crop_spins[2].value = crop_rect.size.x
	_crop_spins[3].value = crop_rect.size.y
	var origin := PetOverlays._origin_pixels(_part.get("origin", "center"), size)
	_origin_x.value = origin.x
	_origin_y.value = origin.y
	_origin_x.editable = texture != null
	_origin_y.editable = texture != null
	_crop_label.text = "" if texture == null else (tr("第 %d 張:原圖 %d×%d,裁切成 %d×%d") % [_focus, int(size.x), int(size.y), crop_rect.size.x, crop_rect.size.y] if crop is Rect2i else tr("第 %d 張:原圖 %d×%d,沒有裁切") % [_focus, int(size.x), int(size.y)])
	_preview.show_image(texture, crop_rect if crop is Rect2i else Rect2i(), origin)
	# 圖層鎖住:按鈕與數字框都停用,滑鼠停留提示先解除鎖定(縮圖還是能選、預覽還是能看)
	var locked := PackLayers.is_locked(_part)
	var controls: Array[Control] = []
	controls.append_array(_buttons)
	controls.append_array(_crop_spins)
	controls.append_array([_add_button, _origin_x, _origin_y])
	for control in controls:
		LayerListView.mark_locked(control, locked)
	_preview.tooltip_text = PackLayers.lock_hint() if locked else ""
	_updating = false


## 縮圖:有裁切就只顯示裁切後的那一塊,一眼看得出裁了什麼。
func _thumb(index: int, texture: Texture2D) -> Texture2D:
	var crop: Variant = _crop_of(index)
	if texture == null or not crop is Rect2i:
		return texture
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2((crop as Rect2i).intersection(Rect2i(Vector2i.ZERO, texture.get_size())))
	return atlas


func _on_multi_selected(index: int, selected: bool) -> void:
	_selected = []
	for i in _list.get_selected_items():
		_selected.append(i)
	_selected.sort()
	if selected:
		_focus = index
	elif not _selected.is_empty():
		_focus = _selected[_selected.size() - 1]
	_refresh()


func _emit(images: Array, crops: Array, message: String, key := "") -> void:
	if _refuse_locked():
		return
	var part := _part.duplicate(true)
	part["images"] = images
	while not crops.is_empty() and crops[crops.size() - 1] == null:
		crops.pop_back()
	if crops.is_empty():
		part.erase("crops")
	else:
		part["crops"] = crops
	_part = part
	_refresh()
	part_changed.emit(part.duplicate(true), message, key)


func _move(direction: int) -> void:
	var images := _images().duplicate()
	var crops := _crops()
	var order: Array[int] = []
	for i in images.size():
		order.append(i)
	var picked := _selected.duplicate()
	if direction > 0:
		picked.reverse()
	for i: int in picked:
		var target: int = i + direction
		if target < 0 or target >= images.size():
			return
		var swap: int = order[target]
		order[target] = order[i]
		order[i] = swap
	_selected = _selected.map(func(i: int) -> int: return i + direction)
	_focus += direction
	_emit(order.map(func(i: int) -> Variant: return images[i]), order.map(func(i: int) -> Variant: return crops[i]), tr("已調整圖層圖片的順序"))


func _duplicate() -> void:
	if _images().size() + _selected.size() > PetOverlays.MAX_FRAMES:
		return
	var images := _images().duplicate()
	var crops := _crops()
	var at: int = _selected.max() + 1
	var copies: Array = _selected.map(func(i: int) -> Variant: return images[i])
	var copy_crops: Array = _selected.map(func(i: int) -> Variant: return crops[i])
	for k in copies.size():
		images.insert(at + k, copies[k])
		crops.insert(at + k, copy_crops[k])
	var count := copies.size()
	_selected = []
	for k in count:
		_selected.append(at + k)
	_focus = at
	_emit(images, crops, tr("已複製 %d 張圖") % count)


func _delete() -> void:
	if _selected.size() >= _images().size():
		return
	var images: Array = []
	var crops: Array = []
	var old_crops := _crops()
	for i in _images().size():
		if not _selected.has(i):
			images.append(_images()[i])
			crops.append(old_crops[i])
	var removed := _selected.size()
	_focus = mini(_selected.min(), images.size() - 1)
	_selected = [_focus]
	_emit(images, crops, tr("已刪除 %d 張圖") % removed)


## 圖層鎖住了:不改,畫面回到原本的值,通知編輯器提示。
func _refuse_locked() -> bool:
	if not PackLayers.is_locked(_part):
		return false
	_refresh()
	locked_touched.emit()
	return true


func _on_crop_drawn(rect: Rect2i) -> void:
	if _refuse_locked():
		return
	_updating = true
	_crop_spins[0].value = rect.position.x
	_crop_spins[1].value = rect.position.y
	_crop_spins[2].value = rect.size.x
	_crop_spins[3].value = rect.size.y
	_updating = false
	_preview.set_pending_crop(rect)


func _on_crop_spin_changed() -> void:
	if _updating:
		return
	_preview.set_pending_crop(_spin_rect())


func _spin_rect() -> Rect2i:
	return Rect2i(int(_crop_spins[0].value), int(_crop_spins[1].value), maxi(int(_crop_spins[2].value), 1), maxi(int(_crop_spins[3].value), 1))


## 把裁切框套用到這些圖(框比圖大就截到圖的範圍;框跟整張圖一樣大 = 不裁切)。
func _apply_crop(indices: Array) -> void:
	if indices.is_empty():
		return
	var rect := _spin_rect()
	var crops := _crops()
	for i: int in indices:
		var texture := _full_texture(i)
		if texture == null:
			continue
		var clipped := rect.intersection(Rect2i(Vector2i.ZERO, texture.get_size()))
		crops[i] = null if clipped.size.x <= 0 or clipped == Rect2i(Vector2i.ZERO, texture.get_size()) else [clipped.position.x, clipped.position.y, clipped.size.x, clipped.size.y]
	_emit(_images().duplicate(), crops, tr("已套用裁切(%d 張)") % indices.size())


func _auto_trim() -> void:
	if not _image_of.is_valid():
		return
	var crops := _crops()
	var trimmed := 0
	for i in _selected:
		var image: Image = _image_of.call(str(_images()[i]))
		if image == null:
			continue
		var used := image.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0 or used == Rect2i(Vector2i.ZERO, image.get_size()):
			crops[i] = null
			continue
		crops[i] = [used.position.x, used.position.y, used.size.x, used.size.y]
		trimmed += 1
	_emit(_images().duplicate(), crops, tr("已自動裁掉透明邊(%d 張)") % trimmed)


func _clear_crop() -> void:
	var crops := _crops()
	for i in _selected:
		crops[i] = null
	_emit(_images().duplicate(), crops, tr("已清除裁切"))


func _on_origin_picked(point: Vector2) -> void:
	_set_origin([roundf(point.x), roundf(point.y)], tr("已設定對齊點"))


func _on_origin_spin_changed() -> void:
	if _updating:
		return
	_set_origin([_origin_x.value, _origin_y.value], "", "layer_origin")


func _set_origin(origin: Variant, message: String, key := "") -> void:
	if _part.is_empty() or _refuse_locked():
		return
	var part := _part.duplicate(true)
	part["origin"] = origin
	_part = part
	_refresh()
	part_changed.emit(part.duplicate(true), message, key)


## 預覽:整張原圖(棋盤格底),裁切範圍外變暗、框線標出範圍,十字是對齊點。
## mode:0 = 移動視角畫面(左鍵拖曳平移)、1 = 拖曳畫裁切範圍(發 crop_drawn,還沒套用)、2 = 點選對齊點(發 origin_picked,原圖像素座標)。
## 滾輪以滑鼠位置為中心放大縮小;中鍵、右鍵拖曳任何模式都能平移;雙擊中鍵回到整張圖。換圖層時 reset_view。
class LayerImagePreview:
	extends Control
	signal crop_drawn(rect: Rect2i)
	signal origin_picked(point: Vector2)

	const MODE_PAN := 0
	const MODE_CROP := 1
	const MODE_ORIGIN := 2
	const ZOOM_STEP := 1.25
	const ZOOM_MIN := 0.25
	const ZOOM_MAX := 64.0

	var mode := MODE_PAN
	var _zoom := 1.0   # 相對「整張圖剛好放得下」的倍率
	var _pan := Vector2.ZERO
	var _panning := false
	var _texture: Texture2D
	var _crop := Rect2i()
	var _pending := Rect2i()
	var _origin := Vector2.ZERO
	var _drag_from := Vector2(-1, -1)
	## 拖裁切線(2026-10-18):抓到框的邊/角就只移那幾條(往外拉 = 把裁掉的拿回來);空的 = 畫新框。
	var _edge_drag: Dictionary = {}
	const EDGE_GRAB := 7.0

	func _ready() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 放大看像素圖要清楚

	func reset_view() -> void:
		_zoom = 1.0
		_pan = Vector2.ZERO
		queue_redraw()

	func show_image(texture: Texture2D, crop: Rect2i, origin: Vector2) -> void:
		_texture = texture
		_crop = crop
		_pending = Rect2i()
		_origin = origin
		queue_redraw()

	func set_pending_crop(rect: Rect2i) -> void:
		_pending = rect
		queue_redraw()

	func _layout() -> Dictionary:
		if _texture == null:
			return {}
		var image_size := Vector2(_texture.get_size())
		var fit := minf((size.x - 12.0) / maxf(image_size.x, 1.0), (size.y - 12.0) / maxf(image_size.y, 1.0))
		fit = maxf(fit, 0.01)
		if fit >= 1.0:
			fit = floorf(fit)   # 放得下時用整數倍,像素圖看得清楚
		var scale := fit * _zoom
		var drawn := image_size * scale
		return {"scale": scale, "origin": ((size - drawn) * 0.5 + _pan).round(), "size": drawn}

	func _to_image(point: Vector2) -> Vector2:
		var layout := _layout()
		if layout.is_empty():
			return Vector2.ZERO
		return ((point - (layout["origin"] as Vector2)) / float(layout["scale"])).clamp(Vector2.ZERO, Vector2(_texture.get_size()))

	func _draw() -> void:
		var ink := ManagerUi.muted_color(self)
		draw_rect(Rect2(Vector2.ZERO, size), Color(ink, 0.08))
		var layout := _layout()
		if layout.is_empty():
			draw_string(get_theme_default_font(), Vector2(10, size.y * 0.5), tr("(沒有圖片)"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
			return
		var top_left: Vector2 = layout["origin"]
		var scale := float(layout["scale"])
		var area := Rect2(top_left, layout["size"])
		_draw_board(area)
		draw_texture_rect(_texture, area, false)
		var shown := _shown_crop()
		if shown.size.x > 0:
			var rect := Rect2(top_left + Vector2(shown.position) * scale, Vector2(shown.size) * scale)
			var shade := Color(0, 0, 0, 0.45)
			draw_rect(Rect2(area.position, Vector2(area.size.x, rect.position.y - area.position.y)), shade)
			draw_rect(Rect2(Vector2(area.position.x, rect.end.y), Vector2(area.size.x, area.end.y - rect.end.y)), shade)
			draw_rect(Rect2(Vector2(area.position.x, rect.position.y), Vector2(rect.position.x - area.position.x, rect.size.y)), shade)
			draw_rect(Rect2(Vector2(rect.end.x, rect.position.y), Vector2(area.end.x - rect.end.x, rect.size.y)), shade)
			var color := ManagerUi.accent_color(self) if _pending.size.x == 0 else Color(1.0, 0.75, 0.2)
			draw_rect(rect, color, false, 2.0)
			if mode == MODE_CROP:
				for handle: Vector2 in [Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), Vector2(rect.get_center().x, rect.position.y), Vector2(rect.get_center().x, rect.end.y)]:
					draw_rect(Rect2(handle - Vector2(3, 3), Vector2(6, 6)), color)
		draw_rect(area, Color(ink, 0.5), false, 1.0)
		var cross := top_left + _origin * scale
		var red := Color(1.0, 0.3, 0.3)
		draw_line(cross + Vector2(-7, 0), cross + Vector2(7, 0), red, 2.0)
		draw_line(cross + Vector2(0, -7), cross + Vector2(0, 7), red, 2.0)

	func _shown_crop() -> Rect2i:
		return _pending if _pending.size.x > 0 else _crop

	## 滑鼠按在裁切框的哪幾條線上(螢幕上 EDGE_GRAB 以內);沒按到回空字典。
	func _edges_at(mouse: Vector2) -> Dictionary:
		var shown := _shown_crop()
		var layout := _layout()
		if shown.size.x <= 0 or layout.is_empty():
			return {}
		var scale := float(layout["scale"])
		var box := Rect2((layout["origin"] as Vector2) + Vector2(shown.position) * scale, Vector2(shown.size) * scale)
		var within_x := mouse.x >= box.position.x - EDGE_GRAB and mouse.x <= box.end.x + EDGE_GRAB
		var within_y := mouse.y >= box.position.y - EDGE_GRAB and mouse.y <= box.end.y + EDGE_GRAB
		var left := absf(mouse.x - box.position.x) <= EDGE_GRAB and within_y
		var right := absf(mouse.x - box.end.x) <= EDGE_GRAB and within_y and not left
		var top := absf(mouse.y - box.position.y) <= EDGE_GRAB and within_x
		var bottom := absf(mouse.y - box.end.y) <= EDGE_GRAB and within_x and not top
		if not (left or right or top or bottom):
			return {}
		return {"left": left, "right": right, "top": top, "bottom": bottom, "start": shown, "mouse": mouse, "scale": scale}

	func _edge_rect(mouse: Vector2) -> Rect2i:
		var start: Rect2i = _edge_drag["start"]
		var delta := Vector2i(((mouse - (_edge_drag["mouse"] as Vector2)) / float(_edge_drag["scale"])).round())
		var full := _texture.get_size()
		var left := start.position.x
		var right := start.end.x
		var top := start.position.y
		var bottom := start.end.y
		if _edge_drag["left"]:
			left = clampi(left + delta.x, 0, right - 1)
		if _edge_drag["right"]:
			right = clampi(right + delta.x, left + 1, int(full.x))
		if _edge_drag["top"]:
			top = clampi(top + delta.y, 0, bottom - 1)
		if _edge_drag["bottom"]:
			bottom = clampi(bottom + delta.y, top + 1, int(full.y))
		return Rect2i(left, top, right - left, bottom - top)

	func _draw_board(area: Rect2) -> void:
		# 棋盤格只畫看得到的部分(放大後圖可能比預覽大很多)
		var cell := 8.0
		var visible_area := area.intersection(Rect2(Vector2.ZERO, size))
		var y := floorf((visible_area.position.y - area.position.y) / cell) * cell
		while y < visible_area.end.y - area.position.y:
			var x := floorf((visible_area.position.x - area.position.x) / cell) * cell
			while x < visible_area.end.x - area.position.x:
				if int(x / cell + y / cell) % 2 == 0:
					draw_rect(Rect2(area.position + Vector2(x, y), Vector2(minf(cell, area.size.x - x), minf(cell, area.size.y - y))), Color(0.5, 0.5, 0.5, 0.18))
				x += cell
			y += cell

	func _zoom_at(mouse: Vector2, factor: float) -> void:
		var before := _layout()
		var next := clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
		if before.is_empty() or is_equal_approx(next, _zoom):
			return
		var image_point := (mouse - (before["origin"] as Vector2)) / float(before["scale"])
		_zoom = next
		var after := _layout()
		# 滑鼠底下那一點放大後還在滑鼠底下
		_pan += mouse - ((after["origin"] as Vector2) + image_point * float(after["scale"]))
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if _texture == null:
			return
		if event is InputEventMouseButton:
			var button := event as InputEventMouseButton
			if button.pressed and (button.button_index == MOUSE_BUTTON_WHEEL_UP or button.button_index == MOUSE_BUTTON_WHEEL_DOWN):
				_zoom_at(button.position, ZOOM_STEP if button.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP)
				accept_event()
				return
			if button.button_index == MOUSE_BUTTON_MIDDLE and button.double_click:
				reset_view()
				accept_event()
				return
			if button.button_index == MOUSE_BUTTON_MIDDLE or button.button_index == MOUSE_BUTTON_RIGHT or (button.button_index == MOUSE_BUTTON_LEFT and mode == MODE_PAN):
				_panning = button.pressed
				accept_event()
				return
		if event is InputEventMouseMotion and _panning:
			_pan += (event as InputEventMouseMotion).relative
			queue_redraw()
			accept_event()
			return
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var pressed := (event as InputEventMouseButton).pressed
			var point := _to_image((event as InputEventMouseButton).position)
			if mode == MODE_ORIGIN:
				if pressed:
					origin_picked.emit(point)
				accept_event()
				return
			if pressed and mode == MODE_CROP:
				_edge_drag = _edges_at((event as InputEventMouseButton).position)
			if pressed and not _edge_drag.is_empty():
				pass
			elif not pressed and not _edge_drag.is_empty():
				var dragged := _edge_rect((event as InputEventMouseButton).position)
				_edge_drag = {}
				crop_drawn.emit(dragged)
			elif pressed:
				_drag_from = point
			elif _drag_from.x >= 0.0:
				var rect := Rect2(_drag_from, Vector2.ZERO).expand(point)
				_drag_from = Vector2(-1, -1)
				if rect.size.x >= 1.0 and rect.size.y >= 1.0:
					crop_drawn.emit(Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.size.ceil())))
			accept_event()
		elif event is InputEventMouseMotion and not _edge_drag.is_empty():
			_pending = _edge_rect((event as InputEventMouseMotion).position)
			queue_redraw()
			accept_event()
		elif event is InputEventMouseMotion and mode == MODE_CROP and _drag_from.x < 0.0:
			var edges := _edges_at((event as InputEventMouseMotion).position)
			var horizontal: bool = edges.get("left", false) or edges.get("right", false)
			var vertical: bool = edges.get("top", false) or edges.get("bottom", false)
			mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE if horizontal and vertical else (Control.CURSOR_HSIZE if horizontal else (Control.CURSOR_VSIZE if vertical else Control.CURSOR_ARROW))
		elif event is InputEventMouseMotion and _drag_from.x >= 0.0 and mode == MODE_CROP:
			var rect := Rect2(_drag_from, Vector2.ZERO).expand(_to_image((event as InputEventMouseMotion).position))
			_pending = Rect2i(Vector2i(rect.position.floor()), Vector2i(rect.size.ceil()))
			queue_redraw()
			accept_event()
