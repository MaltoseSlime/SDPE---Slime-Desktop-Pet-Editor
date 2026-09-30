class_name FurnitureManager
extends Node2D
## 桌面上已經放置的家具:管理清單、存讀(user://furniture/_placed.json:每筆 {defId, x, y}),渲染交給 DecorOverlay(見 furniture_item.gd 檔頭)。
## 新放的家具先掛在主視窗裡(裝飾層還沒準備好時的退路),每影格檢查一次,裝飾層可以用了就搬過去(見 _process);
## 這樣不管裝飾層要花多久套用「滑鼠完全穿透」的系統設定,家具一開始就看得見,只是短暫還會擋一下點擊。
## 第一批(純裝飾)只有「放置」與「移除」,坐下/躺下/交互是下一批。
##
## 家具編輯模式(edit_mode,見 set_edit_mode):平時家具都在裝飾層裡完全穿透,滑鼠點不到、拖不動。
## 開啟編輯模式時家具暫時搬回主視窗、加入「Cutout」群組(比照 HoverBall/PropManager,見 desktop_shell.gd
## 的 _collect_cutout_polygon),變成滑鼠點得到、能拖曳移動、右鍵能收回桌面(不會刪掉家具本身,家具庫裡還在);
## 關掉編輯模式後 _process 會自動把家具搬回裝飾層,恢復純裝飾。編輯模式中桌面會多一塊「家具欄」(見 FurnitureBar),
## 從裡面把家具拖出來就是「放置」。

signal placed_changed
## 使用者雙擊一件容器家具(平時純裝飾滑鼠穿透,只有容器類的家具會例外被算進 Cutout 判定範圍,不用開編輯模式):
## 想打開「查看內容物」的視窗,見 desktop_shell.gd 接線。
signal container_open_requested(item: FurnitureItem)

const PLACED_PATH := "user://furniture/_placed.json"
## 測試用:非空就覆蓋存檔路徑,不動使用者真正的資料。
static var path_override := ""
## 雙擊容器判定的間隔上限(跟 PetInteraction.DOUBLE_CLICK_TIME 同一個數字)。
const DOUBLE_CLICK_TIME := 0.45

var items: Array[FurnitureItem] = []
var _action_area: Node
var _decor: DecorOverlay
## 「顯示在桌寵與對話氣泡之上」(FurnitureDef.render_above_ui)的家具畫在這裡,見 _home_parent_for()。
var _top_layer: Node
var edit_mode := false
## 正被拖著的家具(一次只有一個);_mouse 是最近一次滑鼠的畫布座標。
var dragged: FurnitureItem
var _mouse := Vector2.ZERO
var _last_container_click_item: FurnitureItem
var _last_container_click_time := -100.0


func setup(action_area: Node, top_layer: Node = null) -> void:
	_action_area = action_area
	_top_layer = top_layer
	add_to_group("furniture_manager")
	# 永遠留在 Cutout 群組(不像編輯模式那樣開關):平常只有容器類家具會被算進穿透判定範圍(見 get_cutout_polygons),
	# 讓使用者不用開家具編輯模式也能雙擊容器打開查看內容物;純裝飾的家具維持滑鼠完全穿透,不受影響。
	add_to_group("Cutout")
	_decor = DecorOverlay.instance(self)
	_restore()


## 裝飾層(平時家具真正畫的地方,見 DecorOverlay)的畫布節點,給 DesktopShell 右鍵暫時穿透時一起淡化用;
## 還沒有裝飾層(無頭、非 Windows、還沒套用成功)回 null。
func decor_canvas() -> Node2D:
	return _decor.canvas if _decor != null else null


static func _path() -> String:
	return path_override if path_override != "" else PLACED_PATH


## 放一件家具在 at(主場景樹的全域座標);沒給位置就放在行動區正中央。讀不到這個家具的素材(sprite/ 沒有 normal 狀態的圖)回 null。
## persist = false 給 _restore() 用(讀存檔時不要每放一件就整份重寫一次)。
func spawn(def: FurnitureDef, at := Vector2.INF, persist := true) -> FurnitureItem:
	var frames := FurnitureLibrary.load_sprite(def)
	if frames == null:
		return null
	var item := FurnitureItem.new()
	add_child(item)
	item.global_position = at if at != Vector2.INF else _bounds().get_center()
	item.setup(def, frames)
	items.append(item)
	if _decor != null:
		_decor.set_wanted(self, true)
	if persist:
		_save()
	placed_changed.emit()
	return item


## 家具欄拖出來時用:在滑鼠位置生一件、立刻抓在手上(編輯模式才會被呼叫,見 FurnitureBar)。
func spawn_dragged(def: FurnitureDef, at_mouse: Vector2) -> FurnitureItem:
	var item := spawn(def, at_mouse, false)
	if item != null:
		begin_drag(item, at_mouse)
	return item


func begin_drag(item: FurnitureItem, at_mouse := Vector2.INF) -> void:
	if dragged != null and dragged != item:
		end_drag()
	dragged = item
	if at_mouse != Vector2.INF:
		_mouse = at_mouse
		item.global_position = at_mouse


## 放開:存檔目前位置。
func end_drag() -> void:
	if dragged == null:
		return
	dragged = null
	_save()


## 從桌面收回(家具庫裡的定義不會被刪掉,之後還能再放一次)。
func remove(item: FurnitureItem) -> void:
	if not items.has(item):
		return
	if item == dragged:
		dragged = null
	items.erase(item)
	if is_instance_valid(item):
		item.queue_free()
	if _decor != null:
		_decor.set_wanted(self, not items.is_empty())
	_save()
	placed_changed.emit()


## 清空全部(測試/管理用)。
func clear() -> void:
	for item in items.duplicate():
		remove(item)


func count() -> int:
	return items.size()


## 精靈圖編輯器改了某件家具的定義並存檔後呼叫(見 PackEditorWindow._save_furniture):場上同一件家具的每個實例都換上
## 剛存的新定義,不然光源座標/大小/顏色、above_light 疊層順序、坐躺錨點都會停在放上桌面那一刻讀到的舊版本。
func refresh_def(furniture_id: String) -> void:
	var fresh := FurnitureLibrary.load_def(furniture_id)
	if fresh == null:
		return
	for item in items:
		if is_instance_valid(item) and item.def != null and item.def.id == furniture_id:
			item.apply_def(fresh)


## 調整一件家具在其他家具之間的圖層順序(只影響場上家具彼此蓋住的先後,不影響桌寵、介面或其他物件)。
## up = true 往後移一位(晚畫,蓋住原本在它前面的那件);到頂/到底了什麼都不做。
func move_layer(item: FurnitureItem, up: bool) -> void:
	var index := items.find(item)
	if index < 0:
		return
	var target := index + 1 if up else index - 1
	if target < 0 or target >= items.size():
		return
	items.remove_at(index)
	items.insert(target, item)
	var container := item.get_parent()
	if container != null:
		container.move_child(item, target)
	_save()
	placed_changed.emit()


## 開/關家具編輯模式,見檔頭。
func set_edit_mode(on: bool) -> void:
	if edit_mode == on:
		return
	edit_mode = on
	if on:
		for item in items:
			if is_instance_valid(item) and item.get_parent() != self:
				item.reparent(self, true)
	else:
		end_drag()
		# 搬回各自該去的地方(裝飾層,或「顯示在桌寵與對話氣泡之上」的那件搬回頂層)交給 _process 自然處理
		# (見 _home_parent_for()),不用在這裡立刻做。


## 「Cutout」群組成員介面:編輯模式時每件家具各自的可點擊範圍;平時(純裝飾滑鼠穿透)只有容器類的家具例外算進來,
## 讓使用者不用開編輯模式就能雙擊容器(見 _handle_container_click)。正被拖著的那件放大比較多(見 PropItem
## .get_cutout_polygons 同樣的理由):視窗形狀的更新比滑鼠晚一影格,拖得快的話滑鼠會跑到還沒更新的形狀外面,
## 窗口那一刻收不到事件,拖曳就會斷斷續續甚至完全動不了。
func get_cutout_polygons() -> Array:
	var polygons: Array = []
	if edit_mode:
		for item in items:
			if is_instance_valid(item):
				var grow := 120.0 if item == dragged else 4.0
				polygons.append(_rect_polygon(item.touch_rect().grow(grow)))
		return polygons
	for item in items:
		if is_instance_valid(item) and item.is_container():
			polygons.append(_rect_polygon(item.touch_rect().grow(4.0)))
	return polygons


static func _rect_polygon(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])


## 平時(非編輯模式)雙擊一件容器家具:發出 container_open_requested,不影響拖曳/右鍵移除(那些只在編輯模式生效)。
func _handle_container_click(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed):
		return
	var item := item_at(_mouse)
	if item == null or not item.is_container():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if item == _last_container_click_item and now - _last_container_click_time <= DOUBLE_CLICK_TIME:
		_last_container_click_item = null
		_last_container_click_time = -100.0
		container_open_requested.emit(item)
		get_viewport().set_input_as_handled()
	else:
		_last_container_click_item = item
		_last_container_click_time = now


## 畫布座標 point 下最上面(清單裡最後面)的家具,沒有回 null。
func item_at(point: Vector2) -> FurnitureItem:
	for i in range(items.size() - 1, -1, -1):
		var item := items[i]
		if is_instance_valid(item) and item.touch_rect().grow(6.0).has_point(point):
			return item
	return null


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse = get_viewport().get_canvas_transform().affine_inverse() * event.position
	if get_node("/root/DesktopShellState").is_passthrough_frozen:
		return
	if not edit_mode:
		_handle_container_click(event)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var picked := item_at(_mouse)
		if picked != null and dragged == null:
			remove(picked)   # 右鍵 = 從桌面收回(定義還在家具庫)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var item := item_at(_mouse)
			if item != null:
				begin_drag(item)
				get_viewport().set_input_as_handled()
		elif dragged != null:
			end_drag()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and dragged != null:
		dragged.global_position = _mouse
		get_viewport().set_input_as_handled()


## 裝飾層可以用了(穿透樣式套用成功)就把一般家具搬過去,讓它們真的滑鼠穿透;搬過去之前畫在主視窗裡,
## 看得見但會擋點擊。「顯示在桌寵與對話氣泡之上」的家具(見 _home_parent_for())不等裝飾層,直接搬去
## 頂層 CanvasLayer,那一層本來就存在、不用等穿透樣式套用。編輯模式中都不搬(家具留在主視窗才點得到、
## 拖得動),關掉編輯模式後下一影格自然各自搬回去。
func _process(_delta: float) -> void:
	if edit_mode:
		return
	for item in items:
		if not is_instance_valid(item):
			continue
		var target := _home_parent_for(item)
		if target != null and item.get_parent() != target:
			item.reparent(target, true)


## 這件家具平時(非編輯模式)該掛在哪個節點底下:「顯示在桌寵與對話氣泡之上」的去頂層 CanvasLayer;
## 其餘照舊——裝飾層可以用就去裝飾層,裝飾層還沒準備好(或這台系統沒有,見 DecorOverlay.instance())
## 就先留在主視窗(item.get_parent() 已經是 self 或還沒設過都算,回傳 null 表示「不用動」)。
func _home_parent_for(item: FurnitureItem) -> Node:
	if item.def != null and item.def.render_above_ui and _top_layer != null:
		return _top_layer
	if _decor != null and _decor.canvas != null and _decor.usable:
		return _decor.canvas
	return null


func _bounds() -> Rect2:
	if _action_area != null and "boundary_rect" in _action_area:
		var rect: Rect2 = _action_area.boundary_rect
		return Rect2(_action_area.to_global(rect.position), rect.size)
	return Rect2(0.0, 0.0, 1920.0, 1080.0)


## 換螢幕、或同一台螢幕解析度/縮放比例變了(見 DesktopShell.apply_monitor_setting()):每件家具的位置照
## 新舊視窗尺寸的比例挪過去,盡量維持在螢幕上的相對位置;挪完再夾回目前行動區範圍內(比例算出來的位置理論上
## 都在合理範圍,這裡是防呆——螢幕長寬比差很多、或行動區本身還沒跟著長大時,位置還是不會被推到框外去)。
func rescale_positions(old_size: Vector2, new_size: Vector2) -> void:
	if old_size.x <= 0.0 or old_size.y <= 0.0 or old_size.is_equal_approx(new_size):
		return
	var scale := new_size / old_size
	var bounds := _bounds()
	for item in items:
		if not is_instance_valid(item):
			continue
		var scaled := item.global_position * scale
		item.global_position = Vector2(clampf(scaled.x, bounds.position.x, bounds.end.x), clampf(scaled.y, bounds.position.y, bounds.end.y))
	_save()


func _save() -> void:
	var list: Array = []
	for item in items:
		if is_instance_valid(item) and item.def != null:
			var entry := {"defId": item.def.id, "x": item.global_position.x, "y": item.global_position.y}
			if item.is_container():
				entry["containerRemaining"] = item.container_remaining.duplicate()
			list.append(entry)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path()).get_base_dir())
	var file := FileAccess.open(_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(list))
	file.close()


func _restore() -> void:
	if not FileAccess.file_exists(_path()):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(_path())) != OK or not json.data is Array:
		return
	for entry: Variant in (json.data as Array):
		if not entry is Dictionary:
			continue
		var def := FurnitureLibrary.load_def(str((entry as Dictionary).get("defId", "")))
		if def == null:
			continue
		var x: Variant = (entry as Dictionary).get("x", 0.0)
		var y: Variant = (entry as Dictionary).get("y", 0.0)
		if (x is float or x is int) and (y is float or y is int):
			var item := spawn(def, Vector2(float(x), float(y)), false)
			var remaining: Variant = (entry as Dictionary).get("containerRemaining")
			if item != null and remaining is Dictionary:
				for id: String in item.container_remaining.keys():
					var saved: Variant = (remaining as Dictionary).get(id)
					if saved is int or saved is float:
						item.container_remaining[id] = clampi(int(saved), 0, item.container_capacity(id))
