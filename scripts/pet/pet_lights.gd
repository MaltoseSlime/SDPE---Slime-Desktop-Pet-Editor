class_name PetLights
extends Node2D
## 桌寵身上的光源(發光效果,沒有陰影):把 pack.json 的 "lights"(見 PackLights)畫成柔和的圓形光暈,錨點跟著角色縮放、鏡像、爬牆旋轉走
## (掛在 Pet 的視覺根節點底下,座標單位就是縮放前的像素、原點是腳底線中心)。有指定動作的光只在那個動作播放時亮。
## 全部程式畫(共用一張程式產生的放射漸層貼圖),不需要任何圖檔;亮度只有極慢的呼吸起伏(約每 5 秒一次、幅度 ±8%),不會閃爍。
## 全局設定有總開關(AppSettings.lights_enabled),關掉就完全不畫、不佔穿透形狀。前層是「Cutout」群組成員:
## 光暈超出角色的部分也要在可見範圍內。
## 每盞光可以個別選「疊在角色前面」(預設,z_index=8,舊資料都是這個)或「疊在角色後面」(見 PackLights.clean 的 "layer" 欄位)——
## 本體與配件的 z_index 見 pet_overlays.gd 的 LAYER_Z(本體=0、配件 back=-1、front/top=0/1);「疊在角色後面」的光另外開一個
## z_as_relative=false、z_index=-2 的子畫布,保證畫在本體與配件 back 層都更後面。
## 2026-09-29 效能優化(只動後層,前層維持不動):後層光暈改畫到 DecorOverlay(見 firefly_layer.gd 同一套
## _using_decor()/_ensure_canvas() 做法),不再佔用主視窗的穿透形狀計算。前層沒有比照辦理——DecorOverlay
## 是一個永遠疊在主視窗「後面」的獨立系統視窗,前層光暈需要疊在角色本體「前面」,搬過去會整個畫反(疊到
## 角色後面),結構上就沒辦法用同一招;維持原本畫在主視窗裡、繼續佔穿透形狀。
## 裝飾層還沒好(穿透樣式要套用、約 1~2 秒)、失敗、沒有畫面(無頭測試)時,後層退回舊做法:畫在
## _back_canvas(主視窗裡的子畫布,z_index=-2),繼續佔穿透形狀,跟修改前完全一樣。
## get_cutout_polygons() 只有後層在用裝飾層畫的時候才會把後層光暈從回傳清單裡拿掉;is_lit()/light_count()
## 不分前後層,兩層的光都算進去(那兩個是給互動判定用的「有沒有光」語意,不是穿透形狀,跟畫在哪個視窗無關)。

const REDRAW_INTERVAL := 1.0 / 20.0
const PULSE_SPEED := 1.25
const PULSE_AMOUNT := 0.08

static var _glow_texture: GradientTexture2D

const BACK_LAYER_Z := -2

var _pet: Node
var _lights: Array[Dictionary] = []
var _enabled := true
var _redraw_left := 0.0
var _time := 0.0
var _back_canvas: Node2D
## 裝飾層(見檔頭)與自己在它上面的畫布節點,只給後層用;無頭/非 Windows/還沒套用穿透樣式時是 null。
var _decor: DecorOverlay
var _decor_canvas: Node2D
var _has_back_light := false


func setup(pet: Node) -> void:
	_pet = pet
	add_to_group("Cutout")
	add_to_group("pet_lights")
	z_index = 8
	_back_canvas = Node2D.new()
	_back_canvas.z_as_relative = false
	_back_canvas.z_index = BACK_LAYER_Z
	_back_canvas.draw.connect(func() -> void:
		if not _using_decor():
			_draw_layer(_back_canvas, true, false))
	add_child(_back_canvas)
	_decor = DecorOverlay.instance(self)
	refresh_setting()


## 裝飾層是不是已經可以用(穿透樣式已套用):可以就把後層畫在裝飾層,否則畫在 _back_canvas 並照舊佔穿透形狀。
func _using_decor() -> bool:
	return _decor != null and _decor.usable and _decor_canvas != null


## 裝飾層建好之後才有畫布可以掛;每影格檢查一次(很便宜),跟 firefly_layer.gd 同一套做法。
func _ensure_canvas() -> void:
	if _decor == null or _decor_canvas != null or _decor.canvas == null:
		return
	_decor_canvas = Node2D.new()
	_decor_canvas.name = "PetLightsBack"
	_decor_canvas.draw.connect(func() -> void:
		if _using_decor():
			_draw_layer(_decor_canvas, true, true))
	_decor.canvas.add_child(_decor_canvas)
	_decor.usable_changed.connect(func(_usable: bool) -> void:
		_request_redraw())


func _request_redraw() -> void:
	queue_redraw()
	_back_canvas.queue_redraw()
	if _decor_canvas != null:
		_decor_canvas.queue_redraw()


func _exit_tree() -> void:
	if _decor != null:
		_decor.set_wanted(self, false)


func set_lights(list: Array) -> void:
	_lights = PackLights.clean(list)
	_has_back_light = _lights.any(func(l: Dictionary) -> bool: return str(l.get("layer", "front")) == "back")
	if _decor != null:
		_decor.set_wanted(self, _enabled and _has_back_light)
	_request_redraw()


func light_count() -> int:
	return _lights.size()


## 全局設定的總開關改了(或剛建立)時重新讀。
func refresh_setting() -> void:
	_enabled = AppSettings.lights_enabled()
	if _decor != null:
		_decor.set_wanted(self, _enabled and _has_back_light)
	_request_redraw()


func is_lit() -> bool:
	return _enabled and not _current_lights().is_empty()


func _current_action() -> String:
	return str(_pet.current_animation_action()) if _pet != null else ""


func _current_frame() -> int:
	return int(_pet.body_frame()) if _pet != null else 0


func _current_lights() -> Array[Dictionary]:
	if _lights.is_empty():
		return []
	var cond_ids: Dictionary = _pet.light_cond_active if _pet != null and "light_cond_active" in _pet else {}
	return PackLights.active(_lights, _current_action(), _current_frame(), cond_ids)


## 這盞光現在的位置:依目前動作與動畫幀(動作專屬發光錨點,見 PackLights)。
func _position_of(light: Dictionary) -> Vector2:
	if not light.has("anchors") and not light.has("frame_anchors"):
		return Vector2(float(light["x"]), float(light["y"]))
	return PackLights.position_of(light, str(_pet.current_animation_action()) if _pet != null else "", int(_pet.body_frame()) if _pet != null else 0)


func _process(delta: float) -> void:
	_ensure_canvas()
	if not _enabled or _lights.is_empty():
		return
	_time += delta
	_redraw_left -= delta
	if _redraw_left <= 0.0:
		_redraw_left = REDRAW_INTERVAL
		_request_redraw()


static func glow_texture() -> GradientTexture2D:
	if _glow_texture == null:
		var gradient := Gradient.new()
		gradient.offsets = PackedFloat32Array([0.0, 0.3, 0.65, 1.0])
		gradient.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.16), Color(1, 1, 1, 0.0)])
		_glow_texture = GradientTexture2D.new()
		_glow_texture.gradient = gradient
		_glow_texture.fill = GradientTexture2D.FILL_RADIAL
		_glow_texture.fill_from = Vector2(0.5, 0.5)
		_glow_texture.fill_to = Vector2(1.0, 0.5)
		_glow_texture.width = 128
		_glow_texture.height = 128
	return _glow_texture


func _draw() -> void:
	_draw_layer(self, false, false)


## canvas 是要畫的目標(self = 前面那層,_back_canvas 或 _decor_canvas = 後面那層);want_back 篩選
## PackLights.clean() 存的 "layer" 欄位。is_decor = true 時 canvas 是裝飾層上的節點(跟這顆 PetLights
## 不同一棵樹、座標系不共通),用 to_global() 把本體座標系裡算出來的位置換成全域座標再畫(跟
## firefly_layer.gd 的 _paint() 同一招:裝飾層視窗跟主視窗位置對齊,全域座標可以直接當裝飾層畫布的
## 本地座標用)。兩層共用同一份 _current_lights() 與座標計算,只是各自只畫自己那層的光、畫到不同的
## CanvasItem 上。
func _draw_layer(canvas: CanvasItem, want_back: bool, is_decor: bool) -> void:
	if not _enabled:
		return
	var pulse := 1.0 + sin(_time * PULSE_SPEED) * PULSE_AMOUNT
	var action := _current_action()
	var frame := _current_frame()
	for light in _current_lights():
		if (str(light.get("layer", "front")) == "back") != want_back:
			continue
		var radius := PackLights.radius_of(light, action, frame)
		var color := Color(PackLights.color_of(light, action, frame))
		color.a = clampf(PackLights.energy_of(light, action, frame) * pulse * 0.6, 0.0, 1.0)
		var center := _position_of(light)
		if is_decor:
			center = to_global(center)
		canvas.draw_texture_rect(glow_texture(), Rect2(center - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, color)


## 亮著的光暈範圍(全域座標的四邊形),給穿透多邊形用;沒亮或總開關關掉就沒有。後層畫在裝飾層時不算
## 進來(那邊不是主視窗,不需要主視窗讓出穿透範圍);前層一律照算,因為前層固定畫在主視窗裡。
func get_cutout_polygons() -> Array:
	var polygons: Array = []
	if not _enabled:
		return polygons
	var action := _current_action()
	var frame := _current_frame()
	var skip_back := _using_decor()
	for light in _current_lights():
		if skip_back and str(light.get("layer", "front")) == "back":
			continue
		var radius := PackLights.radius_of(light, action, frame)
		var center := _position_of(light)
		polygons.append(PackedVector2Array([
			to_global(center + Vector2(-radius, -radius)), to_global(center + Vector2(radius, -radius)),
			to_global(center + Vector2(radius, radius)), to_global(center + Vector2(-radius, radius))]))
	return polygons
