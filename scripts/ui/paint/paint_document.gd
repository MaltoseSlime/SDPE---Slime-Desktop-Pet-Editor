class_name PaintDocument
extends RefCounted
## 精靈圖編輯器的繪圖功能(2026-10-22 起,見 SpritePaintWindow)的資料層,沒有介面、方便無頭測試。
## 一份文件是幾張要畫的圖(頁):動作的每一幀、或一個圖層的每一張圖。畫筆、橡皮擦、油漆桶、吸色、形狀、漸層、
## 範圍選取(矩形 / 魔術棒 / 套索,可以加選減選)、剪貼、翻轉旋轉、撤回/重做都在這裡;
## 改了哪幾頁用 changed_pages() 看(跟開啟時或上次套用時比),套用回素材包由呼叫端負責。
##
## 繪圖圖層(第二期):全部頁共用一份圖層清單(名字、顯示、不透明度),每一頁每一層各有一張圖(cels[頁][層]),
## 清單第 0 個在最下面。畫的永遠是「目前的圖層」;看到的、吸色、套用出去的是全部顯示中的圖層合併起來的樣子(composite)。
## 套用時合併成一張幀 PNG(遊戲照舊只讀合併的圖),各層另外存成側檔,下次開繪圖視窗再拆回來(見 PackEditorModel.save_paint_layers)。
##
## 筆畫(begin_stroke → stroke_to → end_stroke):每一筆從「下筆前的圖」重算,同一筆裡重疊的地方取覆蓋率的最大值,
## 所以半透明或平滑邊緣的筆刷來回塗同一筆不會越疊越深。像素筆刷沿著 Bresenham 直線一格一格點,線條不會忽粗忽細。
## 形狀與漸層也走同一套:begin_preview() 之後每次 preview_*() 都從下筆前的圖重畫,end_stroke() 定案成一步撤回。
## 「覆蓋」模式(預設)把顏色連 alpha 直接寫進去(副色調成 alpha 0 就能當橡皮擦用);「疊色」模式照一般繪圖軟體的 alpha 疊上去。
## 選取範圍:selection 是外框,selection_mask 是外框裡的形狀(空的 = 整個矩形)。有選取時畫筆、形狀、漸層、油漆桶、刪除只作用在範圍裡。
## 移動選取的內容會先「拿起來」變成浮動的一塊(原處留透明),放下(commit_floating)時疊回去;貼上也是浮動的一塊。
## 剪貼簿是全部文件共用的(static),所以能複製到別的幀再貼上。
## 筆畫的 params 有 curve = true 時,經過的點之間用 Catmull-Rom 曲線補(滑鼠 / 繪圖筆回報的點是一段一段的直線,
## 畫快時會變成折線,2026-10-23 使用者回報「線條僵硬」),代價是最後一段要等下一個點(或收筆)才畫。
## 畫布尺寸(resize_canvas):四邊各加減幾格,內容跟著移動;page_shifts 記每一頁的內容從開啟(或上次套用)後往右下移了多少,
## 套用時交給呼叫端調整軸心,讓角色在畫面上的位置不變。
## 新增頁(add_page,2026-10-24):在目前這一頁後面插一頁(複製這一頁或空白),可以撤回;每一頁有固定的編號 page_ids
## (開啟時的頁是 0, 1, 2…,新增的往後編、不重複用),呼叫端靠它對回原本的幀。新增的頁在套用之前一律算有變更,
## 套用時呼叫端真的插入新幀(page_source 是它複製自哪一頁的編號,空白 = -1)。

signal changed

const HISTORY_LIMIT := 60
const MAX_LAYERS := 8
## 最多幾頁(新增頁的上限)。
const MAX_PAGES := 999
## 畫布尺寸的上限(每一邊的像素)。
const MAX_CANVAS := 4096
const TRANSPARENT := Color(0, 0, 0, 0)
## 4×4 Bayer 矩陣:漸層的「點陣混色」用。
const BAYER4: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

## 全部繪圖視窗、全部頁共用的剪貼簿(複製到別的幀、別的動作、別的圖層再貼上)。clipboard_origin 是複製時在原圖上的位置,貼上時預設放回同一個位置。
static var clipboard: Image = null
static var clipboard_origin := Vector2i.ZERO

## 繪圖圖層清單:{name, visible, opacity}。
var layers: Array[Dictionary] = []
## cels[頁][層] = Image(RGBA8)。
var cels: Array = []
var index := 0
## 目前在畫的圖層。
var layer := 0
## 選取範圍的外框(空的 = 沒有選取)。
var selection := Rect2i()
## 外框裡的形狀(selection.size 大小,1 = 選到);空的 = 整個外框都選到。
var selection_mask := PackedByteArray()
## 選取範圍每變一次就加一(畫布用來重算虛線框)。
var selection_version := 0
## 浮動的一塊(移動中的選取內容、或剛貼上還沒放下的圖);null = 沒有。位置就是 selection.position。
var floating: Image = null
## 每一頁的內容從開啟(或上次套用)之後,因為改畫布尺寸往右下移了多少(Vector2i;左邊、上面加寬是正的)。
var page_shifts: Array[Vector2i] = []
## 每一頁開啟(或上次套用)時的大小,給呼叫端算圖層對齊點用。
var base_sizes: Array[Vector2i] = []
## 每一頁固定的編號(見檔頭「新增頁」)。
var page_ids: Array[int] = []

## 頁的編號 → 開啟(或上次套用)時的樣子;沒有 = 新增、還沒套用的頁。
var _original_hashes := {}
## 新增的頁的編號 → 它複製自哪一頁(原本就有的頁的編號;空白 = -1)。
var _page_from := {}
var _next_page_id := 0
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []
var _dirty := {}
var _structure_dirty := false
var _float_before: Image = null
var _float_page := -1
var _float_layer := -1
## 拿起來(或貼上)那一刻的選取範圍:取消浮動時退回這個範圍。
var _float_from := Rect2i()
var _float_mask_from := PackedByteArray()
var _stroke_base: Image = null
var _stroke_mask := PackedFloat32Array()
var _stroke_params := {}
var _stroke_last := Vector2.ZERO
var _stroke_touched := Rect2i()
## 下筆前的圖的位元組(開頭存一次,不用每次移動都整張複製)。
var _stroke_base_data := PackedByteArray()
## 上次 _flush_stroke 之後覆蓋率有變的範圍:每次移動只重算這一塊(2026-10-23 使用者回報作畫卡頓;
## 原本每次都重算整筆的外框、整張圖 get_data / set_data,筆畫越長越慢)。
var _flush_rect := Rect2i()
## curve 筆畫還沒畫出去的點:[[位置, 筆壓]…](最多留最後 3 個)。
var _curve_points: Array = []


## 開始一份新文件。images:每一頁(合併後)的圖;page_layers:每一頁的繪圖圖層(上次存的側檔,
## [{name, visible, opacity, image}…],沒有就給空陣列,那一頁就只有一層 = 那張圖)。圖都會複製一份並轉成 RGBA8。
func setup(images: Array, start_index := 0, page_layers: Array = []) -> void:
	cels.clear()
	layers.clear()
	_original_hashes.clear()
	var count := 1
	for entry: Variant in page_layers:
		if entry is Array:
			count = maxi(count, (entry as Array).size())
	count = mini(count, MAX_LAYERS)
	for l in count:
		layers.append(new_layer_meta(_default_layer_name(l)))
	for l in count:
		for entry: Variant in page_layers:
			if entry is Array and l < (entry as Array).size():
				var meta: Dictionary = entry[l]
				layers[l] = {"name": str(meta.get("name", layers[l]["name"])), "visible": bool(meta.get("visible", true)), "opacity": clampf(float(meta.get("opacity", 1.0)), 0.0, 1.0),
						"alpha_lock": bool(meta.get("alpha_lock", false)), "clip": bool(meta.get("clip", false))}
				break
	for p in images.size():
		var flat := _rgba_copy(images[p])
		var stack: Array = []
		var saved: Array = page_layers[p] if p < page_layers.size() and page_layers[p] is Array else []
		for l in count:
			if not saved.is_empty() and l < saved.size() and (saved[l] as Dictionary).get("image") is Image and (saved[l]["image"] as Image).get_size() == flat.get_size():
				stack.append(_rgba_copy(saved[l]["image"]))
			elif saved.is_empty() and l == 0:
				stack.append(flat)
			else:
				stack.append(Image.create(flat.get_width(), flat.get_height(), false, Image.FORMAT_RGBA8))
		cels.append(stack)
	page_shifts.clear()
	base_sizes.clear()
	page_ids.clear()
	_page_from.clear()
	for p in cels.size():
		page_ids.append(p)
		_original_hashes[p] = _page_hash(p)
		page_shifts.append(Vector2i.ZERO)
		base_sizes.append((cels[p][0] as Image).get_size())
	index = clampi(start_index, 0, maxi(cels.size() - 1, 0))
	layer = 0
	_undo.clear()
	_redo.clear()
	selection = Rect2i()
	selection_mask = PackedByteArray()
	floating = null
	_float_before = null
	_float_page = -1
	_stroke_base = null
	_next_page_id = cels.size()
	_structure_dirty = true


## 繪圖圖層的設定:alpha_lock = 鎖定透明度(畫的時候每一格的透明度不變,只改顏色);
## clip = 向下剪裁(只顯示在下面那一層有內容的地方,見 clip_base)。2026-10-24 使用者要求。
static func new_layer_meta(layer_name: String) -> Dictionary:
	return {"name": layer_name, "visible": true, "opacity": 1.0, "alpha_lock": false, "clip": false}


## 向下剪裁的層是剪在哪一層上:往下找第一個不是剪裁的層;不是剪裁層(或下面沒有可以剪的)回 -1。
func clip_base(layer_index: int) -> int:
	if layer_index <= 0 or layer_index >= layers.size() or not bool(layers[layer_index].get("clip", false)):
		return -1
	var at := layer_index - 1
	while at > 0 and bool(layers[at].get("clip", false)):
		at -= 1
	return at


func _default_layer_name(at: int) -> String:
	return TranslationServer.translate("圖層 %d") % (at + 1)


static func _rgba_copy(source: Image) -> Image:
	var copy := source.duplicate() as Image
	if copy.is_compressed():
		copy.decompress()
	copy.convert(Image.FORMAT_RGBA8)
	return copy


func page_count() -> int:
	return cels.size()


## 目前這一頁、目前這個圖層的圖(畫的對象)。
func page() -> Image:
	return cel(index, layer)


func cel(page_index: int, layer_index: int) -> Image:
	if page_index < 0 or page_index >= cels.size() or layer_index < 0 or layer_index >= (cels[page_index] as Array).size():
		return null
	return cels[page_index][layer_index]


func page_size() -> Vector2i:
	var image := page()
	return image.get_size() if image != null else Vector2i.ZERO


## 這一頁全部顯示中的圖層合併起來(照各層的不透明度)。給套用、吸色、洋蔥皮用。
func composite(page_index: int, include_hidden := false) -> Image:
	var stack: Array = cels[page_index]
	var size := (stack[0] as Image).get_size()
	var result := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for l in stack.size():
		if not include_hidden and not layer_shown(l):
			continue
		var opacity := float(layers[l]["opacity"])
		if opacity <= 0.0:
			continue
		var source := _cel_with_floating(page_index, l)
		var base := clip_base(l)
		if base >= 0:
			source = clipped(source, _cel_with_floating(page_index, base))
		if opacity < 1.0:
			source = _with_opacity(source, opacity)
		result.blend_rect(source, Rect2i(Vector2i.ZERO, size), Vector2i.ZERO)
	return result


## 畫布上顯示用的圖:向下剪裁的層是剪好的樣子(不含浮動的一塊),其他就是那張圖本身。
func display_cel(page_index: int, layer_index: int) -> Image:
	var image := cel(page_index, layer_index)
	var base := clip_base(layer_index)
	if image == null or base < 0:
		return image
	return clipped(image, cels[page_index][base])


## 剪裁在 layer_index 上的層(它們的樣子跟著 layer_index 變)。
func clipped_onto(layer_index: int) -> Array[int]:
	var result: Array[int] = []
	for l in range(layer_index + 1, layers.size()):
		if clip_base(l) == layer_index:
			result.append(l)
		elif not bool(layers[l].get("clip", false)):
			break
	return result


## 這一層要不要畫出來:自己藏起來、或剪裁在一個藏起來的層上,都不畫。
func layer_shown(layer_index: int) -> bool:
	if not bool(layers[layer_index]["visible"]):
		return false
	var base := clip_base(layer_index)
	return base < 0 or bool(layers[base]["visible"])


## 一層的圖(浮動的一塊還沒放下時也算進去;沒有浮動就是那張圖本身)。
func _cel_with_floating(page_index: int, layer_index: int) -> Image:
	var source: Image = cels[page_index][layer_index]
	if page_index == _float_page and layer_index == _float_layer and floating != null:
		source = source.duplicate()
		source.blend_rect(floating, Rect2i(Vector2i.ZERO, floating.get_size()), selection.position)
	return source


## 向下剪裁:source 每一格的透明度乘上 base 那一格的透明度(base 沒內容的地方就看不到)。
static func clipped(source: Image, base: Image) -> Image:
	var copy := source.duplicate() as Image
	var data := copy.get_data()
	var mask := base.get_data()
	for at in range(3, mini(data.size(), mask.size()), 4):
		data[at] = roundi(data[at] * mask[at] / 255.0)
	copy.set_data(copy.get_width(), copy.get_height(), false, Image.FORMAT_RGBA8, data)
	return copy


static func _with_opacity(source: Image, opacity: float) -> Image:
	var copy := source.duplicate() as Image
	var data := copy.get_data()
	for at in range(3, data.size(), 4):
		data[at] = roundi(data[at] * opacity)
	copy.set_data(copy.get_width(), copy.get_height(), false, Image.FORMAT_RGBA8, data)
	return copy


## 換頁:浮動的一塊先放下;選取範圍保留(同一個位置換一幀繼續選;大小不同的頁就清掉)。
func set_page(new_index: int) -> void:
	if new_index == index or new_index < 0 or new_index >= cels.size():
		return
	commit_floating()
	cancel_stroke()
	var old_size := page_size()
	index = new_index
	if page_size() != old_size:
		_set_selection(Rect2i(), PackedByteArray())
	changed.emit()


## 換目前在畫的圖層:浮動的一塊先放下。
func set_layer(new_layer: int) -> void:
	if new_layer < 0 or new_layer >= layers.size() or new_layer == layer:
		return
	commit_floating()
	cancel_stroke()
	layer = new_layer
	changed.emit()


## 跟開啟時(或上次 mark_applied 時)不一樣的頁(合併後的樣子或各層的內容不一樣,見 _page_hash)。
func changed_pages() -> Array[int]:
	var result: Array[int] = []
	for p in cels.size():
		if not _original_hashes.has(page_ids[p]) or _page_hash(p) != int(_original_hashes[page_ids[p]]):
			result.append(p)
	return result


## 這一頁是新增的、還沒套用(呼叫端要插入新幀)。
func is_new_page(page_index: int) -> bool:
	return page_index >= 0 and page_index < page_ids.size() and not _original_hashes.has(page_ids[page_index])


## 新增的頁複製自哪一頁(原本就有的頁的編號);空白頁、或原本就有的頁回 -1。
func page_source(page_index: int) -> int:
	return int(_page_from.get(page_ids[page_index], -1)) if page_index >= 0 and page_index < page_ids.size() else -1


## 在目前這一頁後面新增一頁並切過去:copy = 複製目前這一頁(每個繪圖圖層都複製),否則是同樣大小的空白頁。
## 浮動的一塊先放下;算一步撤回。超過 MAX_PAGES 回 false。
func add_page(copy: bool) -> bool:
	if cels.is_empty() or cels.size() >= MAX_PAGES:
		return false
	commit_floating()
	cancel_stroke()
	var before := _snapshot()
	var stack: Array = []
	for image: Image in cels[index]:
		stack.append(image.duplicate() if copy else Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8))
	var id := _next_page_id
	_next_page_id += 1
	# 複製新增的頁 = 跟它一樣複製自同一頁;複製空白頁還是空白
	_page_from[id] = (page_source(index) if is_new_page(index) else page_ids[index]) if copy else -1
	var at := index + 1
	cels.insert(at, stack)
	page_ids.insert(at, id)
	page_shifts.insert(at, page_shifts[index] if copy else Vector2i.ZERO)
	base_sizes.insert(at, base_sizes[index] if copy else (stack[0] as Image).get_size())
	index = at
	_structure_step(before)
	return true


## 套用回素材包之後:現在的樣子就是新的基準,不再算有變更(畫布尺寸的位移也歸零,呼叫端已經照它調好軸心)。
func mark_applied() -> void:
	for p in cels.size():
		_original_hashes[page_ids[p]] = _page_hash(p)
		_page_from.erase(page_ids[p])
		page_shifts[p] = Vector2i.ZERO
		base_sizes[p] = (cels[p][0] as Image).get_size()


## 一頁的「樣子」:合併後的圖 + 各層有內容的圖(全透明的層不算,所以新增空白圖層、改圖層名字不會讓每一幀都變成有變更、
## 套用時全部另存新檔;藏起有內容的層、改它的不透明度會改到合併圖,照樣算)。
func _page_hash(page_index: int) -> int:
	var parts: Array = [hash(composite(page_index).get_data())]
	for l in layers.size():
		var image: Image = cels[page_index][l]
		if not image.is_invisible():
			parts.append([l, hash(image.get_data())])
	return hash(parts)


## 套用時要存的圖層資料(只有一層時是空陣列,不用存側檔)。
func layer_entries(page_index: int) -> Array:
	if layers.size() <= 1:
		return []
	var result: Array = []
	for l in layers.size():
		result.append({"name": layers[l]["name"], "visible": layers[l]["visible"], "opacity": layers[l]["opacity"],
				"alpha_lock": layers[l]["alpha_lock"], "clip": layers[l]["clip"], "image": (cels[page_index][l] as Image).duplicate()})
	return result


## 畫面要重畫的圖(畫布用來更新貼圖),拿了就清掉:[Vector2i(頁, 層)…]。
func take_dirty() -> Array:
	var keys := _dirty.keys()
	_dirty.clear()
	return keys


## 圖層的數量或順序變了(畫布要全部重做貼圖),拿了就清掉。
func take_structure_dirty() -> bool:
	var was := _structure_dirty
	_structure_dirty = false
	return was


func _touch(page_index: int, layer_index := -1) -> void:
	_dirty[Vector2i(page_index, layer if layer_index < 0 else layer_index)] = true


# --- 畫布尺寸 ---

## 改畫布尺寸:pages 的每一頁(每個繪圖圖層)四邊各加 margins = [左, 上, 右, 下] 格(負的 = 裁掉),內容跟著移。
## 每一頁照自己原本的大小加減,所以大小不同的幀也能一起改。結果任何一邊小於 1 或大於 MAX_CANVAS 的頁不動。
## 整份記成一步撤回;回傳實際改了幾頁。
func resize_canvas(pages: Array, margins: Array) -> int:
	var left := int(margins[0])
	var top := int(margins[1])
	var right := int(margins[2])
	var bottom := int(margins[3])
	if left == 0 and top == 0 and right == 0 and bottom == 0:
		return 0
	commit_floating()
	cancel_stroke()
	var before := _snapshot()
	var count := 0
	for p: int in pages:
		if p < 0 or p >= cels.size():
			continue
		var old_size := (cels[p][0] as Image).get_size()
		var new_size := old_size + Vector2i(left + right, top + bottom)
		if new_size.x < 1 or new_size.y < 1 or new_size.x > MAX_CANVAS or new_size.y > MAX_CANVAS:
			continue
		for l in (cels[p] as Array).size():
			var old: Image = cels[p][l]
			var resized := Image.create(new_size.x, new_size.y, false, Image.FORMAT_RGBA8)
			resized.blit_rect(old, Rect2i(Vector2i.ZERO, old_size), Vector2i(left, top))
			cels[p][l] = resized
		page_shifts[p] += Vector2i(left, top)
		count += 1
	if count == 0:
		return 0
	_set_selection(Rect2i(), PackedByteArray())
	_structure_step(before)
	return count


# --- 撤回 / 重做 ---

func can_undo() -> bool:
	return floating != null or not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## 把一張圖「改之前」的樣子記成一步。after 在這時候拍。
func _push_history(page_index: int, layer_index: int, before: Image) -> void:
	_push_step({"kind": "cel", "page": page_index, "layer": layer_index, "before": before, "after": (cels[page_index][layer_index] as Image).duplicate()})


func _push_step(step: Dictionary) -> void:
	_undo.append(step)
	if _undo.size() > HISTORY_LIMIT:
		_undo.pop_front()
	_redo.clear()


## 整份文件的樣子(圖層清單 + 全部的圖):改圖層結構(新增、刪除、順序、合併)前後各拍一份。
func _snapshot() -> Dictionary:
	var copy: Array = []
	for stack: Array in cels:
		var images: Array = []
		for image: Image in stack:
			images.append(image.duplicate())
		copy.append(images)
	return {"layers": layers.duplicate(true), "cels": copy, "layer": layer, "shifts": page_shifts.duplicate(),
			"ids": page_ids.duplicate(), "bases": base_sizes.duplicate(), "index": index}


func _apply_snapshot(snapshot: Dictionary) -> void:
	layers.clear()
	for meta: Dictionary in snapshot["layers"]:
		layers.append(meta.duplicate())
	cels.clear()
	for stack: Array in snapshot["cels"]:
		var images: Array = []
		for image: Image in stack:
			images.append(image.duplicate())
		cels.append(images)
	layer = clampi(int(snapshot["layer"]), 0, layers.size() - 1)
	if snapshot.has("shifts"):
		page_shifts.assign(snapshot["shifts"])
	if snapshot.has("ids"):
		# 開啟(或上次套用)時的大小只在套用時變:還在的頁沿用現在的值,不退回快照當時的
		var base_of := {}
		for p in page_ids.size():
			base_of[page_ids[p]] = base_sizes[p]
		page_ids.assign(snapshot["ids"])
		base_sizes.clear()
		for k in page_ids.size():
			base_sizes.append(base_of.get(page_ids[k], snapshot["bases"][k]))
		index = clampi(int(snapshot["index"]), 0, cels.size() - 1)
	if selection.has_area() and not Rect2i(Vector2i.ZERO, page_size()).encloses(selection):
		_set_selection(Rect2i(), PackedByteArray())
	_structure_dirty = true


## 撤回一步:浮動的一塊還沒放下時先把它取消(回到拿起來之前)。撤回別頁的步驟會切到那一頁。
func undo() -> bool:
	if floating != null:
		cancel_floating()
		return true
	cancel_stroke()
	if _undo.is_empty():
		return false
	var step: Dictionary = _undo.pop_back()
	_redo.append(step)
	_restore_step(step, "before")
	return true


func redo() -> bool:
	commit_floating()
	cancel_stroke()
	if _redo.is_empty():
		return false
	var step: Dictionary = _redo.pop_back()
	_undo.append(step)
	_restore_step(step, "after")
	return true


func _restore_step(step: Dictionary, side: String) -> void:
	if str(step["kind"]) == "all":
		_apply_snapshot(step[side])
		changed.emit()
		return
	var page_index := int(step["page"])
	var layer_index := int(step["layer"])
	(cels[page_index][layer_index] as Image).copy_from(step[side])
	if page_index != index:
		index = page_index
		_set_selection(Rect2i(), PackedByteArray())
	layer = layer_index
	_touch(page_index, layer_index)
	changed.emit()


# --- 繪圖圖層 ---

func _structure_step(before: Dictionary) -> void:
	_push_step({"kind": "all", "before": before, "after": _snapshot()})
	_structure_dirty = true
	changed.emit()


func _unique_layer_name(base: String) -> String:
	var taken := layers.map(func(meta: Dictionary) -> String: return str(meta["name"]))
	if not taken.has(base):
		return base
	var counter := 2
	while taken.has("%s %d" % [base, counter]):
		counter += 1
	return "%s %d" % [base, counter]


## 在目前圖層上面加一個空白圖層(全部頁都加),選中它。到上限回 false。
func add_layer() -> bool:
	if layers.size() >= MAX_LAYERS:
		return false
	commit_floating()
	var before := _snapshot()
	var at := layer + 1
	var number := layers.size() + 1
	var name := _default_layer_name(number - 1)
	while layers.any(func(meta: Dictionary) -> bool: return meta["name"] == name):
		number += 1
		name = _default_layer_name(number - 1)
	layers.insert(at, new_layer_meta(name))
	for stack: Array in cels:
		var size := (stack[0] as Image).get_size()
		stack.insert(at, Image.create(size.x, size.y, false, Image.FORMAT_RGBA8))
	layer = at
	_structure_step(before)
	return true


func duplicate_layer() -> bool:
	if layers.size() >= MAX_LAYERS:
		return false
	commit_floating()
	var before := _snapshot()
	var meta: Dictionary = layers[layer].duplicate()
	meta["name"] = _unique_layer_name(str(meta["name"]))
	layers.insert(layer + 1, meta)
	for stack: Array in cels:
		stack.insert(layer + 1, (stack[layer] as Image).duplicate())
	layer += 1
	_structure_step(before)
	return true


## 刪掉目前的圖層(至少留一層)。
func delete_layer() -> bool:
	if layers.size() <= 1:
		return false
	commit_floating()
	var before := _snapshot()
	layers.remove_at(layer)
	for stack: Array in cels:
		stack.remove_at(layer)
	layer = mini(layer, layers.size() - 1)
	_structure_step(before)
	return true


## 目前的圖層往上(delta = 1,蓋在更上面)或往下移一格。
func move_layer(delta: int) -> bool:
	var target := layer + delta
	if delta == 0 or target < 0 or target >= layers.size():
		return false
	commit_floating()
	var before := _snapshot()
	var meta: Dictionary = layers[layer]
	layers[layer] = layers[target]
	layers[target] = meta
	for stack: Array in cels:
		var image: Variant = stack[layer]
		stack[layer] = stack[target]
		stack[target] = image
	layer = target
	_structure_step(before)
	return true


## 目前的圖層合併到下面那一層(照它的不透明度;全部頁都合併)。這一層是向下剪裁的話,照剪裁後看起來的樣子合併。
func merge_down() -> bool:
	if layer <= 0:
		return false
	commit_floating()
	var before := _snapshot()
	var opacity := float(layers[layer]["opacity"])
	var base := clip_base(layer)
	for stack: Array in cels:
		var upper: Image = stack[layer]
		var lower: Image = stack[layer - 1]
		if base >= 0:
			upper = clipped(upper, stack[base])
		lower.blend_rect(_with_opacity(upper, opacity) if opacity < 1.0 else upper, Rect2i(Vector2i.ZERO, upper.get_size()), Vector2i.ZERO)
		stack.remove_at(layer)
	layers.remove_at(layer)
	layer -= 1
	_structure_step(before)
	return true


## 圖層的顯示 / 不透明度 / 名字(不算撤回步驟,跟一般繪圖軟體一樣)。
func set_layer_visible(layer_index: int, on: bool) -> void:
	if layer_index < 0 or layer_index >= layers.size():
		return
	layers[layer_index]["visible"] = on
	_structure_dirty = true
	changed.emit()


func set_layer_opacity(layer_index: int, opacity: float) -> void:
	if layer_index < 0 or layer_index >= layers.size():
		return
	layers[layer_index]["opacity"] = clampf(opacity, 0.0, 1.0)
	_structure_dirty = true
	changed.emit()


## 鎖定透明度 / 向下剪裁的開關(跟顯示、不透明度一樣不算撤回步驟)。
func set_layer_alpha_lock(layer_index: int, on: bool) -> void:
	if layer_index < 0 or layer_index >= layers.size():
		return
	layers[layer_index]["alpha_lock"] = on
	changed.emit()


func set_layer_clip(layer_index: int, on: bool) -> void:
	if layer_index < 0 or layer_index >= layers.size():
		return
	layers[layer_index]["clip"] = on
	_structure_dirty = true
	changed.emit()


func rename_layer(layer_index: int, new_name: String) -> void:
	var clean := new_name.strip_edges()
	if layer_index < 0 or layer_index >= layers.size() or clean == "":
		return
	layers[layer_index]["name"] = clean
	changed.emit()


# --- 筆畫(畫筆 / 橡皮擦) ---

## params:tool("brush" / "eraser")、color、size(像素,直徑)、smooth(平滑邊緣)、blend(疊色;false = 覆蓋)、
## size_pressure / opacity_pressure(筆壓影響尺寸 / 不透明度)。pos 是圖上的座標(像素,可以有小數)。
func begin_stroke(params: Dictionary, pos: Vector2, pressure := 1.0) -> void:
	if not begin_preview(params):
		return
	_stroke_last = pos
	_curve_points = [[pos, pressure]]
	_curve_dir = Vector2.ZERO
	_dab(pos, pressure)
	_flush_stroke()


## 形狀 / 漸層 / 筆畫共用的開頭:浮動的一塊先放下,記下「下筆前的圖」。
func begin_preview(params: Dictionary = {}) -> bool:
	commit_floating()
	var image := page()
	if image == null:
		return false
	_stroke_base = image.duplicate()
	_stroke_base_data = _stroke_base.get_data()
	_stroke_mask = PackedFloat32Array()
	_stroke_mask.resize(image.get_width() * image.get_height())
	_stroke_params = params.duplicate()
	_stroke_touched = Rect2i()
	_flush_rect = Rect2i()
	return true


func is_stroking() -> bool:
	return _stroke_base != null


## 從上一點畫到這一點(中間補點,不會斷)。
func stroke_to(pos: Vector2, pressure := 1.0) -> void:
	if _stroke_base == null:
		return
	if bool(_stroke_params.get("curve", false)):
		_curve_to(pos, pressure)
	else:
		_line_dabs(_stroke_last, pos, pressure)
	_stroke_last = pos
	_flush_stroke()


## curve 筆畫:收到新的點就馬上畫「上一點 → 這一點」那一段,畫了就不再改。
## 2026-10-24 使用者要求:不要等下一個點才畫(筆尖會拖一段空白)、不要先畫暫時的直線再修正(會打斷作畫的思考),
## 快速畫線(點很稀)也要圓滑。所以每一段都從上一段結束時的方向出發(接點永遠沒有轉角),
## 新的點的方向用「最近三個點連成的圓」在那一點的切線估(圓弧完全準;只用已經收到的點,不用等、不用回頭改),
## 點再稀也是圓的;只有轉得比 CORNER_COS 還急的地方保留成尖角(來回排線不會被畫成圈)。
## 太近的點先不收(抖動)。
const CORNER_COS := 0.26   # 約 75 度

var _curve_dir := Vector2.ZERO


func _curve_to(pos: Vector2, pressure: float) -> void:
	var last: Array = _curve_points[_curve_points.size() - 1]
	if pos.distance_to(last[0]) < 0.5:
		last[1] = pressure
		return
	var from: Vector2 = last[0]
	var chord := pos - from
	var length := chord.length()
	var along := chord / length
	var start_dir := _curve_dir
	var end_dir := along
	var sharp := false
	if _curve_points.size() >= 2:
		var incoming := (from - Vector2(_curve_points[_curve_points.size() - 2][0])).normalized()
		sharp = incoming.dot(along) < CORNER_COS
		if not sharp:
			# 三點連成的圓:上一點的切線 ≈ 進來與出去兩個方向的平分線,新點的切線 = 它對這段弦的鏡射
			var middle := (incoming + along).normalized()
			end_dir = along * (2.0 * middle.dot(along)) - middle
	if start_dir == Vector2.ZERO or sharp or start_dir.dot(along) < CORNER_COS:
		start_dir = along   # 第一段、或急轉彎:直的出去,這裡是尖角
		end_dir = along
	_hermite_segment(from, start_dir * length, pos, end_dir * length, float(last[1]), pressure)
	_curve_dir = end_dir.normalized()
	_curve_points.append([pos, pressure])
	if _curve_points.size() > 2:
		_curve_points.pop_front()


## 收筆:每一段收到點時就畫好了,這裡只清掉記錄。
func _finish_curve() -> void:
	_curve_points = []
	_curve_dir = Vector2.ZERO


## 三次 Hermite 曲線:從 p1(切線 m1)到 p2(切線 m2),切成約 1 像素一段再點筆刷,筆壓線性內插。
func _hermite_segment(p1: Vector2, m1: Vector2, p2: Vector2, m2: Vector2, pressure_from: float, pressure_to: float) -> void:
	var steps := maxi(int(ceil(p1.distance_to(p2) * 1.2)), 1)
	var previous := p1
	for k in range(1, steps + 1):
		var t := float(k) / steps
		var t2 := t * t
		var t3 := t2 * t
		var point := (2.0 * t3 - 3.0 * t2 + 1.0) * p1 + (t3 - 2.0 * t2 + t) * m1 + (-2.0 * t3 + 3.0 * t2) * p2 + (t3 - t2) * m2
		if k == steps:
			point = p2
		_line_dabs(previous, point, lerpf(pressure_from, pressure_to, t))
		previous = point


## 從 from 到 to 沿線點筆刷。像素筆刷走 Bresenham(每一格的中心點一次),平滑筆刷依半徑等距補點。
func _line_dabs(from: Vector2, to: Vector2, pressure: float) -> void:
	if not bool(_stroke_params.get("smooth", false)):
		var a := Vector2i(floori(from.x), floori(from.y))
		var b := Vector2i(floori(to.x), floori(to.y))
		var offset := Vector2(from.x - a.x, from.y - a.y)
		for cell in bresenham(a, b):
			_dab(Vector2(cell) + offset, pressure)
		return
	var step := maxf(0.35, _dab_radius(pressure) * 0.25)
	var steps := maxi(int(ceil(from.distance_to(to) / step)), 1)
	for k in range(1, steps + 1):
		_dab(from.lerp(to, float(k) / steps), pressure)


## 兩格之間的直線格子(含兩端)。
static func bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := -absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var error := dx + dy
	var at := a
	while true:
		cells.append(at)
		if at == b:
			break
		var doubled := error * 2
		if doubled >= dy:
			error += dy
			at.x += sx
		if doubled <= dx:
			error += dx
			at.y += sy
	return cells


## 結束這一筆(或形狀、漸層),記成一步撤回。沒有真的改到任何像素就不記。
func end_stroke() -> void:
	if _stroke_base == null:
		return
	if bool(_stroke_params.get("curve", false)):
		_finish_curve()
	if page().get_data() != _stroke_base.get_data():
		_push_history(index, layer, _stroke_base)
	_stroke_base = null
	_stroke_base_data = PackedByteArray()
	_stroke_mask = PackedFloat32Array()
	changed.emit()


## 放棄畫到一半的這一筆(換頁、撤回時)。
func cancel_stroke() -> void:
	if _stroke_base == null:
		return
	page().copy_from(_stroke_base)
	_stroke_base = null
	_touch(index)


## 最後一筆結束的位置(Shift + 點 = 從這裡拉直線)。
func last_point() -> Vector2:
	return _stroke_last


func _dab_radius(pressure: float) -> float:
	var radius := maxf(float(_stroke_params.get("size", 1)), 1.0) * 0.5
	if bool(_stroke_params.get("size_pressure", false)):
		radius = maxf(radius * clampf(pressure, 0.0, 1.0), 0.5)
	return radius


## 在 pos 點一下筆刷:把覆蓋率記進這一筆的遮罩(取最大值)。
func _dab(pos: Vector2, pressure: float) -> void:
	var image := page()
	var w := image.get_width()
	var h := image.get_height()
	var radius := _dab_radius(pressure)
	var smooth := bool(_stroke_params.get("smooth", false))
	var strength := clampf(pressure, 0.0, 1.0) if bool(_stroke_params.get("opacity_pressure", false)) else 1.0
	var center := pos
	if not smooth:
		# 像素筆刷對齊格子:奇數尺寸以像素中心為圓心,偶數尺寸以格線交點為圓心,畫出來是對稱的硬邊圓
		var diameter := int(round(radius * 2.0))
		center = (pos.floor() + Vector2(0.5, 0.5)) if diameter % 2 == 1 else pos.round()
	var limit := selection if selection.has_area() else Rect2i(0, 0, w, h)
	var x0 := maxi(int(floor(center.x - radius - 1.0)), limit.position.x)
	var y0 := maxi(int(floor(center.y - radius - 1.0)), limit.position.y)
	var x1 := mini(int(ceil(center.x + radius + 1.0)), limit.end.x - 1)
	var y1 := mini(int(ceil(center.y + radius + 1.0)), limit.end.y - 1)
	if x1 < x0 or y1 < y0:
		return
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var distance := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var coverage := 0.0
			if smooth:
				coverage = clampf(radius + 0.5 - distance, 0.0, 1.0)
			elif distance <= radius + 0.001:
				coverage = 1.0
			coverage *= strength
			if coverage > 0.0:
				_cover(x, y, w, coverage)


## 遮罩記一格的覆蓋率(取最大值;選取範圍外的不算)。
func _cover(x: int, y: int, w: int, coverage: float) -> void:
	if not selection_mask.is_empty() and not is_selected(x, y):
		return
	var at := y * w + x
	if coverage > _stroke_mask[at]:
		_stroke_mask[at] = coverage
		var cell := Rect2i(x, y, 1, 1)
		_stroke_touched = _stroke_touched.merge(cell) if _stroke_touched.has_area() else cell
		_flush_rect = _flush_rect.merge(cell) if _flush_rect.has_area() else cell


## 依遮罩把這一筆碰到的範圍從下筆前的圖重算一次。直接寫位元組並四捨五入:Image.set_pixel 轉 8 位元是無條件捨去,
## 吸到的顏色畫回去會每次少 1(0x66 變 0x65),吸色再畫幾次顏色就慢慢跑掉。
func _flush_stroke() -> void:
	if not _flush_rect.has_area():
		return
	var image := page()
	var w := image.get_width()
	var eraser := str(_stroke_params.get("tool", "brush")) == "eraser"
	var blend := bool(_stroke_params.get("blend", false))
	var color: Color = _stroke_params.get("color", Color.BLACK)
	var locked := bool(layers[layer].get("alpha_lock", false))
	var rect := _flush_rect
	_flush_rect = Rect2i()
	# 只把變了的那一塊算好寫回(blit_rect 是直接覆蓋,不疊色)
	var region := image.get_region(rect)
	var data := region.get_data()
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var coverage := _stroke_mask[y * w + x]
			if coverage <= 0.0:
				continue
			var at := (y * w + x) * 4
			var base := Color.from_rgba8(_stroke_base_data[at], _stroke_base_data[at + 1], _stroke_base_data[at + 2], _stroke_base_data[at + 3])
			var result: Color
			if eraser:
				result = Color(base.r, base.g, base.b, base.a * (1.0 - coverage))
			elif blend:
				result = blend_over(base, Color(color.r, color.g, color.b, color.a * coverage))
			else:
				result = base.lerp(color, coverage)
			if locked:
				# 鎖定透明度:沒內容的格子不畫,有內容的只換顏色(橡皮擦就沒有作用)
				if base.a <= 0.0 or eraser:
					continue
				result = Color(base.r, base.g, base.b, base.a).lerp(Color(color.r, color.g, color.b, base.a), coverage * (color.a if blend else 1.0))
			data.encode_u32(((y - rect.position.y) * rect.size.x + (x - rect.position.x)) * 4, result.to_abgr32())
	region.set_data(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8, data)
	image.blit_rect(region, Rect2i(Vector2i.ZERO, rect.size), rect.position)
	_touch(index)


## 一般的 alpha 疊色(src over dst,非預乘)。
static func blend_over(dst: Color, src: Color) -> Color:
	var out_a := src.a + dst.a * (1.0 - src.a)
	if out_a <= 0.0:
		return TRANSPARENT
	var r := (src.r * src.a + dst.r * dst.a * (1.0 - src.a)) / out_a
	var g := (src.g * src.a + dst.g * dst.a * (1.0 - src.a)) / out_a
	var b := (src.b * src.a + dst.b * dst.a * (1.0 - src.a)) / out_a
	return Color(r, g, b, out_a)


# --- 形狀(直線 / 矩形 / 橢圓)與漸層:begin_preview() 之後拖曳中一直呼叫,end_stroke() 定案 ---

## kind:"line" / "rect" / "ellipse";a、b 是拖曳的起點與目前的點(圖上座標);filled = 填滿(直線不管)。
## 外框用筆刷的尺寸與類型畫(params 同 begin_stroke)。
func preview_shape(kind: String, a: Vector2, b: Vector2, params: Dictionary, filled: bool) -> void:
	if _stroke_base == null:
		return
	_stroke_params = params.duplicate()
	_reset_preview()
	var image := page()
	var w := image.get_width()
	var pa := a.floor() + Vector2(0.5, 0.5)
	var pb := b.floor() + Vector2(0.5, 0.5)
	match kind:
		"line":
			_dab(pa, 1.0)
			_line_dabs(pa, pb, 1.0)
		"rect":
			var top_left := Vector2(minf(pa.x, pb.x), minf(pa.y, pb.y))
			var bottom_right := Vector2(maxf(pa.x, pb.x), maxf(pa.y, pb.y))
			if filled:
				for y in range(floori(top_left.y), floori(bottom_right.y) + 1):
					for x in range(floori(top_left.x), floori(bottom_right.x) + 1):
						if _in_limit(x, y):
							_cover(x, y, w, 1.0)
			else:
				var corners: Array[Vector2] = [top_left, Vector2(bottom_right.x, top_left.y), bottom_right, Vector2(top_left.x, bottom_right.y)]
				_dab(corners[0], 1.0)
				for k in 4:
					_line_dabs(corners[k], corners[(k + 1) % 4], 1.0)
		"ellipse":
			var center := (pa + pb) * 0.5
			var radii := ((pb - pa) * 0.5).abs()
			if filled:
				var rx := radii.x + 0.5
				var ry := radii.y + 0.5
				for y in range(floori(center.y - ry), ceili(center.y + ry) + 1):
					for x in range(floori(center.x - rx), ceili(center.x + rx) + 1):
						var d := Vector2((x + 0.5 - center.x) / rx, (y + 0.5 - center.y) / ry)
						if d.length_squared() <= 1.0 and _in_limit(x, y):
							_cover(x, y, w, 1.0)
			else:
				var samples := maxi(16, int(ceil((radii.x + radii.y) * PI * 2.0)))
				var previous := center + Vector2(radii.x, 0.0)
				_dab(previous, 1.0)
				for k in range(1, samples + 1):
					var angle := TAU * k / samples
					var point := center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y)
					_line_dabs(previous, point, 1.0)
					previous = point
	_flush_stroke()
	_touch(index)


func _in_limit(x: int, y: int) -> bool:
	var size := page_size()
	if x < 0 or y < 0 or x >= size.x or y >= size.y:
		return false
	return not selection.has_area() or is_selected(x, y)


## 每次重畫預覽前:圖回到下筆前、遮罩清空。
func _reset_preview() -> void:
	page().copy_from(_stroke_base)
	_stroke_mask.fill(0.0)
	_stroke_touched = Rect2i()
	_flush_rect = Rect2i()


## 拖曳漸層:從 a 拖到 b,from_color 漸變到 to_color(含 alpha)。options:kind("linear" / "radial")、
## steps(0 = 平滑,2 以上 = 分成幾階,像素風用)、dither(分階時用 Bayer 點陣混色)、blend(疊色;false = 覆蓋)。
## 有選取時只填選取範圍裡,沒有就填整個圖層。
func preview_gradient(a: Vector2, b: Vector2, from_color: Color, to_color: Color, options: Dictionary) -> void:
	if _stroke_base == null:
		return
	_reset_preview()
	var image := page()
	var w := image.get_width()
	var h := image.get_height()
	var radial := str(options.get("kind", "linear")) == "radial"
	var steps := int(options.get("steps", 0))
	var dither := bool(options.get("dither", false))
	var blend := bool(options.get("blend", false))
	var span := b - a
	var length_squared := span.length_squared()
	var limit := selection if selection.has_area() else Rect2i(0, 0, w, h)
	var base_data := _stroke_base_data
	var data := image.get_data()
	var locked := bool(layers[layer].get("alpha_lock", false))
	for y in range(limit.position.y, limit.end.y):
		for x in range(limit.position.x, limit.end.x):
			if not selection_mask.is_empty() and not is_selected(x, y):
				continue
			var point := Vector2(x + 0.5, y + 0.5)
			var t := 0.0
			if length_squared > 0.0:
				t = clampf((point - a).length() / sqrt(length_squared), 0.0, 1.0) if radial else clampf((point - a).dot(span) / length_squared, 0.0, 1.0)
			if steps >= 2:
				var scaled := t * (steps - 1)
				var level := floorf(scaled)
				if dither:
					var threshold := (BAYER4[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0
					if scaled - level > threshold:
						level += 1.0
				else:
					level = roundf(scaled)
				t = clampf(level / (steps - 1), 0.0, 1.0)
			var color := from_color.lerp(to_color, t)
			var at := (y * w + x) * 4
			if blend or locked:
				var base := Color.from_rgba8(base_data[at], base_data[at + 1], base_data[at + 2], base_data[at + 3])
				if locked:
					if base.a <= 0.0:
						continue
					color = base.lerp(Color(color.r, color.g, color.b, base.a), color.a if blend else 1.0)
				else:
					color = blend_over(base, color)
			data.encode_u32(at, color.to_abgr32())
	image.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	_stroke_touched = limit
	_touch(index)


# --- 油漆桶 / 吸色 ---

## 從 pixel 開始把相連、顏色(含 alpha)完全一樣的範圍填上 color。有選取時只填選取範圍裡。回傳填了幾個像素。
func fill(pixel: Vector2i, color: Color, blend := false) -> int:
	commit_floating()
	var image := page()
	if image == null:
		return 0
	var w := image.get_width()
	var h := image.get_height()
	if not _in_limit(pixel.x, pixel.y):
		return 0
	var region := _flood(image, pixel, 0)
	var data := image.get_data()
	var before := image.duplicate() as Image
	var fixed := color.to_abgr32()   # RGBA8 在記憶體裡是 R,G,B,A,讀成小端 u32 剛好是 ABGR
	var locked := bool(layers[layer].get("alpha_lock", false))
	var count := 0
	for at in w * h:
		if region[at] == 0 or not _in_limit(at % w, at / w):
			continue
		if locked:
			# 鎖定透明度:只換有內容的格子的顏色
			var base := Color.from_rgba8(data[at * 4], data[at * 4 + 1], data[at * 4 + 2], data[at * 4 + 3])
			if base.a <= 0.0:
				continue
			data.encode_u32(at * 4, base.lerp(Color(color.r, color.g, color.b, base.a), color.a if blend else 1.0).to_abgr32())
		elif blend:
			var base := Color.from_rgba8(data[at * 4], data[at * 4 + 1], data[at * 4 + 2], data[at * 4 + 3])
			data.encode_u32(at * 4, blend_over(base, color).to_abgr32())
		else:
			data.encode_u32(at * 4, fixed)
		count += 1
	if count == 0:
		return 0
	image.set_data(w, h, false, Image.FORMAT_RGBA8, data)
	if image.get_data() != before.get_data():
		_push_history(index, layer, before)
	_touch(index)
	changed.emit()
	return count


## 從 pixel 開始、跟它顏色相近(RGBA 每個通道差都在 tolerance 以內)的範圍:回傳整張圖大小的遮罩(1 = 在範圍裡)。
## contiguous = false 時不管相不相連,整張圖顏色相近的都算。
static func _flood(image: Image, pixel: Vector2i, tolerance: int, contiguous := true) -> PackedByteArray:
	var w := image.get_width()
	var h := image.get_height()
	var data := image.get_data()
	var region := PackedByteArray()
	region.resize(w * h)
	var start := (pixel.y * w + pixel.x) * 4
	var target := [data[start], data[start + 1], data[start + 2], data[start + 3]]
	var similar := func(at: int) -> bool:
		var o := at * 4
		if tolerance <= 0:
			return data[o] == target[0] and data[o + 1] == target[1] and data[o + 2] == target[2] and data[o + 3] == target[3]
		return absi(data[o] - target[0]) <= tolerance and absi(data[o + 1] - target[1]) <= tolerance and absi(data[o + 2] - target[2]) <= tolerance and absi(data[o + 3] - target[3]) <= tolerance
	if not contiguous:
		for at in w * h:
			if similar.call(at):
				region[at] = 1
		return region
	var visited := PackedByteArray()
	visited.resize(w * h)
	var stack: Array[int] = [pixel.y * w + pixel.x]
	while not stack.is_empty():
		var at: int = stack.pop_back()
		if visited[at] != 0:
			continue
		visited[at] = 1
		if not similar.call(at):
			continue
		region[at] = 1
		var x := at % w
		var y := at / w
		if x > 0:
			stack.append(at - 1)
		if x < w - 1:
			stack.append(at + 1)
		if y > 0:
			stack.append(at - w)
		if y < h - 1:
			stack.append(at + w)
	return region


## 這一點現在看起來的顏色(全部顯示中的圖層合併後,含 alpha;浮動的一塊也算)。超出圖的範圍回 null。
func pick(pixel: Vector2i) -> Variant:
	var image := page()
	if image == null or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
		return null
	var result := TRANSPARENT
	for l in layers.size():
		if not layer_shown(l):
			continue
		var color := _pixel_with_floating(l, pixel)
		var base := clip_base(l)
		if base >= 0:
			color.a *= _pixel_with_floating(base, pixel).a
		color.a *= float(layers[l]["opacity"])
		result = blend_over(result, color) if l > 0 or result.a > 0.0 else color
	return result


func _pixel_with_floating(layer_index: int, pixel: Vector2i) -> Color:
	var color := (cels[index][layer_index] as Image).get_pixel(pixel.x, pixel.y)
	if layer_index == _float_layer and index == _float_page and floating != null and selection.has_point(pixel):
		var inside := pixel - selection.position
		color = blend_over(color, floating.get_pixel(inside.x, inside.y))
	return color


# --- 選取範圍 ---

## 這一格在不在選取範圍裡(沒有選取時一律 false)。
func is_selected(x: int, y: int) -> bool:
	if not selection.has_point(Vector2i(x, y)):
		return false
	if selection_mask.is_empty():
		return true
	return selection_mask[(y - selection.position.y) * selection.size.x + (x - selection.position.x)] != 0


func has_selection() -> bool:
	return selection.has_area()


func _set_selection(rect: Rect2i, mask: PackedByteArray) -> void:
	selection = rect
	selection_mask = mask
	selection_version += 1


## 目前的選取範圍攤成整張圖大小的遮罩。
func _full_mask() -> PackedByteArray:
	var size := page_size()
	var full := PackedByteArray()
	full.resize(size.x * size.y)
	var area := selection.intersection(Rect2i(Vector2i.ZERO, size))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if is_selected(x, y):
				full[y * size.x + x] = 1
	return full


## 用整張圖大小的遮罩設定選取範圍(算出外框、裁成外框大小;整個外框都選到就不留遮罩)。
func _select_full_mask(full: PackedByteArray) -> void:
	var size := page_size()
	var min_x := size.x
	var min_y := size.y
	var max_x := -1
	var max_y := -1
	for y in size.y:
		for x in size.x:
			if full[y * size.x + x] != 0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < 0:
		_set_selection(Rect2i(), PackedByteArray())
		return
	var rect := Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)
	var mask := PackedByteArray()
	mask.resize(rect.size.x * rect.size.y)
	var full_rect := true
	for y in rect.size.y:
		for x in rect.size.x:
			var on := full[(rect.position.y + y) * size.x + rect.position.x + x]
			mask[y * rect.size.x + x] = on
			if on == 0:
				full_rect = false
	_set_selection(rect, PackedByteArray() if full_rect else mask)


## 把一塊範圍(整張圖大小的遮罩)跟目前的選取合起來:mode = "replace" 換掉、"add" 加選、"subtract" 減選。
func select_mask(full: PackedByteArray, mode := "replace") -> void:
	commit_floating()
	var size := page_size()
	if full.size() != size.x * size.y:
		return
	var result := full
	if mode != "replace" and selection.has_area():
		result = _full_mask()
		for at in result.size():
			if mode == "add":
				result[at] = 1 if (result[at] != 0 or full[at] != 0) else 0
			else:
				result[at] = 1 if (result[at] != 0 and full[at] == 0) else 0
	elif mode == "subtract":
		return
	_select_full_mask(result)
	changed.emit()


func select_rect(rect: Rect2i, mode := "replace") -> void:
	var clipped := rect.abs().intersection(Rect2i(Vector2i.ZERO, page_size()))
	if mode == "replace":
		commit_floating()
		_set_selection(clipped, PackedByteArray())
		changed.emit()
		return
	var size := page_size()
	var full := PackedByteArray()
	full.resize(size.x * size.y)
	for y in range(clipped.position.y, clipped.end.y):
		for x in range(clipped.position.x, clipped.end.x):
			full[y * size.x + x] = 1
	select_mask(full, mode)


## 魔術棒:點到的那一格開始,顏色相近的範圍(看目前的圖層)。
func select_wand(pixel: Vector2i, tolerance := 0, contiguous := true, mode := "replace") -> void:
	var image := page()
	if image == null or not Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
		return
	commit_floating()
	select_mask(_flood(image, pixel, tolerance, contiguous), mode)


## 套索:自由畫的多邊形圍起來的範圍(圖上座標;像素中心在多邊形裡面的算選到)。
func select_lasso(points: PackedVector2Array, mode := "replace") -> void:
	if points.size() < 3:
		return
	var size := page_size()
	var full := PackedByteArray()
	full.resize(size.x * size.y)
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	var area := Rect2i(Vector2i(floori(bounds.position.x), floori(bounds.position.y)), Vector2i(ceili(bounds.size.x) + 2, ceili(bounds.size.y) + 2)).intersection(Rect2i(Vector2i.ZERO, size))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), points):
				full[y * size.x + x] = 1
	select_mask(full, mode)


func select_all() -> void:
	select_rect(Rect2i(Vector2i.ZERO, page_size()))


func clear_selection() -> void:
	commit_floating()
	_set_selection(Rect2i(), PackedByteArray())
	changed.emit()


func invert_selection() -> void:
	commit_floating()
	var full := _full_mask()
	if not selection.has_area():
		full.fill(1)
	else:
		for at in full.size():
			full[at] = 0 if full[at] != 0 else 1
	_select_full_mask(full)
	changed.emit()


## 選取範圍的內容(外框大小,範圍外的地方透明)。
func _selected_region(image: Image) -> Image:
	var region := image.get_region(selection)
	if selection_mask.is_empty():
		return region
	var data := region.get_data()
	for at in selection_mask.size():
		if selection_mask[at] == 0:
			data[at * 4 + 3] = 0
	region.set_data(region.get_width(), region.get_height(), false, Image.FORMAT_RGBA8, data)
	return region


## 把選到的格子變透明。
func _clear_selected(image: Image) -> void:
	if selection_mask.is_empty():
		image.fill_rect(selection, TRANSPARENT)
		return
	var w := image.get_width()
	var data := image.get_data()
	var area := selection.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if is_selected(x, y):
				data.encode_u32((y * w + x) * 4, 0)
	image.set_data(w, image.get_height(), false, Image.FORMAT_RGBA8, data)


# --- 浮動的一塊 / 剪貼簿 / 翻轉旋轉 ---

## 把選取範圍的內容拿起來變成浮動的一塊(原處留透明),之後可以拖曳移動。已經是浮動的就不動。
func lift_selection() -> bool:
	if floating != null:
		return true
	if not selection.has_area():
		return false
	var image := page()
	selection = selection.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	_float_before = image.duplicate()
	_float_page = index
	_float_layer = layer
	_float_from = selection
	_float_mask_from = selection_mask.duplicate()
	floating = _selected_region(image)
	_clear_selected(image)
	_touch(index)
	changed.emit()
	return true


func move_floating(delta: Vector2i) -> void:
	if floating == null or delta == Vector2i.ZERO:
		return
	selection.position += delta
	selection_version += 1
	_touch(index)
	changed.emit()


## 把浮動的一塊疊回圖上(透明的地方不蓋掉底下),記成一步撤回。選取範圍留在放下的位置(超出圖的部分裁掉)。
func commit_floating() -> void:
	if floating == null:
		return
	var image := cel(_float_page, _float_layer)
	image.blend_rect(floating, Rect2i(Vector2i.ZERO, floating.get_size()), selection.position)
	floating = null
	_clip_selection_to(image.get_size())
	if image.get_data() != _float_before.get_data():
		_push_history(_float_page, _float_layer, _float_before)
	_float_before = null
	_touch(_float_page, _float_layer)
	changed.emit()


## 選取範圍有一部分在圖外面(浮動的一塊拖出去了):裁掉外面的部分,遮罩跟著裁。
func _clip_selection_to(size: Vector2i) -> void:
	var clipped := selection.intersection(Rect2i(Vector2i.ZERO, size))
	if clipped == selection:
		return
	if not clipped.has_area():
		_set_selection(Rect2i(), PackedByteArray())
		return
	var mask := PackedByteArray()
	if not selection_mask.is_empty():
		mask.resize(clipped.size.x * clipped.size.y)
		for y in clipped.size.y:
			for x in clipped.size.x:
				var source := Vector2i(clipped.position.x + x - selection.position.x, clipped.position.y + y - selection.position.y)
				mask[y * clipped.size.x + x] = selection_mask[source.y * selection.size.x + source.x]
	_set_selection(clipped, mask)


## 不要這塊浮動的了:回到拿起來(或貼上)之前的樣子。
func cancel_floating() -> void:
	if floating == null:
		return
	cel(_float_page, _float_layer).copy_from(_float_before)
	floating = null
	_float_before = null
	_set_selection(_float_from, _float_mask_from)
	_touch(_float_page, _float_layer)
	changed.emit()


## 複製選取範圍(沒選取 = 整張)到共用剪貼簿。回傳有沒有複製到東西。
func copy_selection() -> bool:
	var image := page()
	if image == null:
		return false
	if floating != null:
		clipboard = floating.duplicate()
		clipboard_origin = selection.position
	elif selection.has_area():
		clipboard = _selected_region(image)
		clipboard_origin = selection.position
	else:
		clipboard = image.duplicate()
		clipboard_origin = Vector2i.ZERO
	return true


func cut_selection() -> bool:
	if not copy_selection():
		return false
	delete_selection()
	return true


## 清掉選取範圍的內容(變透明;沒選取 = 整張)。浮動的一塊直接丟掉(拿起來時原處已經是透明的)。
func delete_selection() -> void:
	var image := page()
	if image == null:
		return
	if floating != null:
		floating = null
		var before := _float_before
		_float_before = null
		var target := cel(_float_page, _float_layer)
		if target.get_data() != before.get_data():
			_push_history(_float_page, _float_layer, before)
		_touch(_float_page, _float_layer)
		changed.emit()
		return
	var before_delete := image.duplicate() as Image
	if selection.has_area():
		_clear_selected(image)
	else:
		image.fill(TRANSPARENT)
	if image.get_data() != before_delete.get_data():
		_push_history(index, layer, before_delete)
	_touch(index)
	changed.emit()


## 貼上一張圖變成浮動的一塊(可以拖曳移動,放下前還能撤回)。at 省略 = 左上角(超出圖也放左上角)。
func paste_image(source: Image, at: Variant = null) -> void:
	if source == null or source.is_empty():
		return
	commit_floating()
	cancel_stroke()
	var image := page()
	if image == null:
		return
	var piece := _rgba_copy(source)
	var position: Vector2i = at if at is Vector2i else Vector2i.ZERO
	if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(position):
		position = Vector2i.ZERO
	_float_before = image.duplicate()
	_float_page = index
	_float_layer = layer
	_float_from = selection
	_float_mask_from = selection_mask.duplicate()
	floating = piece
	_set_selection(Rect2i(position, piece.get_size()), PackedByteArray())
	_touch(index)
	changed.emit()


func paste_clipboard() -> bool:
	if clipboard == null:
		return false
	paste_image(clipboard, clipboard_origin)
	return true


## 翻轉 / 旋轉選取的內容(沒有選取 = 整個圖層):kind = "flip_h" / "flip_v" / "rotate_cw" / "rotate_ccw" / "rotate_180"。
## 先拿起來變成浮動的一塊再轉(繞著原本的中心),之後可以拖曳調位置、按 Enter 放下;撤回一步就回到轉之前。
func transform_selection(kind: String) -> bool:
	if page() == null:
		return false
	cancel_stroke()
	if not selection.has_area() and floating == null:
		_set_selection(Rect2i(Vector2i.ZERO, page_size()), PackedByteArray())
	if not lift_selection():
		return false
	var mask_image: Image = null
	if not selection_mask.is_empty():
		mask_image = Image.create_from_data(selection.size.x, selection.size.y, false, Image.FORMAT_L8, selection_mask)
	var center := Vector2(selection.position) + Vector2(selection.size) * 0.5
	for target: Image in ([floating, mask_image] if mask_image != null else [floating]):
		match kind:
			"flip_h":
				target.flip_x()
			"flip_v":
				target.flip_y()
			"rotate_cw":
				target.rotate_90(CLOCKWISE)
			"rotate_ccw":
				target.rotate_90(COUNTERCLOCKWISE)
			"rotate_180":
				target.rotate_180()
	var new_size := floating.get_size()
	var new_position := Vector2i((center - Vector2(new_size) * 0.5).round())
	selection = Rect2i(new_position, new_size)
	selection_mask = mask_image.get_data() if mask_image != null else PackedByteArray()
	selection_version += 1
	_touch(index)
	changed.emit()
	return true


## 外部剪貼簿的圖(從別的繪圖軟體複製來的)整理成可以貼的樣子:Windows 的點陣圖常常 alpha 全是 0(其實是不透明的圖),
## 這種就當成不透明;key_color 不是 null 就把那個顏色(只比 RGB)變透明——給沒有透明度的來源用的保底做法。
static func prepare_external(source: Image, key_color: Variant = null) -> Image:
	var image := _rgba_copy(source)
	var data := image.get_data()
	var all_clear := true
	for at in range(3, data.size(), 4):
		if data[at] != 0:
			all_clear = false
			break
	if all_clear:
		for at in range(3, data.size(), 4):
			data[at] = 255
	if key_color is Color:
		var key := key_color as Color
		var kr := key.r8
		var kg := key.g8
		var kb := key.b8
		for at in range(0, data.size(), 4):
			if data[at] == kr and data[at + 1] == kg and data[at + 2] == kb:
				data[at + 3] = 0
	image.set_data(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8, data)
	return image
