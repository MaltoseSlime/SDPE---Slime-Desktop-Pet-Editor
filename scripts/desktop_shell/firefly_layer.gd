class_name FireflyLayer
extends Node2D
## 夜間螢火蟲(企劃書第八章):行動區裡飄動的背景裝飾,不和桌寵、道具產生任何互動。
## 出現時段(AppSettings.firefly_active):預設「自動」= 本機時間 18:00 之後(到隔天 06:00),也可以自己指定幾點到幾點、總是啟用、總是關閉;出現與消失都有 FADE_SECONDS 的淡入淡出。
## 假光 / 真光混合(效能):多數是「假光」——只有一個白色小點忽隱忽現;少數(設定的「真光數量」)是「真光」,再加一圈柔和的暖色光暈。
## 光暈用程式畫的放射漸層貼圖(和桌寵身上的光源同一套,沒有陰影);設定裡「啟用光源」沒勾、或全局設定關掉光源時,真光也只畫粒子。
## 畫在「裝飾層」(DecorOverlay:全螢幕透明、滑鼠完全穿透的另一個視窗)上:螢火蟲不會擋住使用者的點擊,也不受桌寵視窗的穿透形狀裁切(以前光暈飄動、出現與消失時形狀一變就破圖)。
## 裝飾層還沒好(穿透樣式要開一個 PowerShell 行程去套,約 1~2 秒)、失敗、沒有畫面(無頭測試)時,退回舊做法:畫在主視窗裡、用 Cutout 穿透形狀(每隻只佔一個小方塊,是「接下來 CUTOUT_INTERVAL 秒內可能飄到的範圍」,每隔這麼久才更新一次;方塊裡滑鼠點不到桌面)。
## 掛在 DesktopShell 底下,圖層在 DrawLayers 的環境區。

const FADE_SECONDS := 3.0
const CHECK_INTERVAL := 5.0
const CUTOUT_INTERVAL := 0.5
const REAL_RADIUS := 34.0
const DOT_RADIUS := 1.7
const MIN_SPEED := 10.0
const MAX_SPEED := 26.0

var _area: Node2D
var _config: Dictionary = AppSettings.FIREFLY_DEFAULTS.duplicate()
var _flies: Array[Dictionary] = []
var _fade := 0.0
var _target := 0.0
var _check_left := 0.0
var _cutout: Array = []
var _cutout_left := 0.0
var _time := 0.0
var _real_lights := true
## 裝飾層(見檔頭)與自己在它上面的畫布節點;無頭時 _decor 是 null。
var _decor: DecorOverlay
var _canvas: Node2D
## 測試用:>= 0 時用這個當「現在是一天的第幾分鐘」。
var override_minute := -1


func setup(area: Node2D) -> void:
	_area = area
	z_index = DrawLayers.AMBIENT_MIN + 10
	add_to_group("fireflies")
	add_to_group("Cutout")
	_decor = DecorOverlay.instance(self)
	visible = false
	refresh_setting()


## 裝飾層是不是已經可以用(穿透樣式已套用):可以就畫在裝飾層,否則畫在自己身上並用 Cutout 形狀。
func _using_decor() -> bool:
	return _decor != null and _decor.usable and _canvas != null


## 裝飾層建好之後才有畫布可以掛;每影格檢查一次(很便宜)。
func _ensure_canvas() -> void:
	if _decor == null or _canvas != null or _decor.canvas == null:
		return
	_canvas = Node2D.new()
	_canvas.name = "Fireflies"
	_canvas.draw.connect(func() -> void:
		if _using_decor():
			_paint(_canvas))
	_decor.canvas.add_child(_canvas)
	_decor.usable_changed.connect(func(_usable: bool) -> void:
		_cutout = []
		_request_redraw())

func _request_redraw() -> void:
	queue_redraw()
	if _canvas != null:
		_canvas.queue_redraw()


## 全局設定改了(或剛建立)時重新讀,立刻重新判斷該不該出現。
func refresh_setting() -> void:
	_config = AppSettings.fireflies()
	_real_lights = bool(_config["lights"]) and AppSettings.lights_enabled()
	_resize(int(_config["count"]))
	_evaluate()
	_request_redraw()


func minute_now() -> int:
	return override_minute if override_minute >= 0 else AppSettings.minute_of_day_now()


func _evaluate() -> void:
	_target = 1.0 if AppSettings.firefly_active(_config, minute_now()) else 0.0
	_check_left = CHECK_INTERVAL


## 目前顯示到多亮(0 = 完全沒出現)。
func fade() -> float:
	return _fade


func firefly_count() -> int:
	return _flies.size()


## 現在有幾隻是真光(有光暈)。
func real_count() -> int:
	if not _real_lights:
		return 0
	return mini(int(_config["real"]), _flies.size())


func _bounds() -> Rect2:
	return _area.boundary_rect if _area != null else Rect2(0.0, 0.0, 600.0, 600.0)


## 螢火蟲集中出現的範圍:行動區由上到下三等分(上 / 中 / 下),「全域」= 整個行動區。
func zone_rect() -> Rect2:
	var rect := _bounds()
	var index := AppSettings.FIREFLY_ZONES.find(str(_config["zone"])) - 1
	if index < 0:
		return rect
	var third := rect.size.y / 3.0
	return Rect2(rect.position.x, rect.position.y + third * float(index), rect.size.x, third)


func _resize(count: int) -> void:
	while _flies.size() > count:
		_flies.pop_back()
	var rect := zone_rect()
	while _flies.size() < count:
		_flies.append({
			"pos": rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y),
			"angle": randf() * TAU, "turn": 0.0, "turn_left": 0.0,
			"speed": randf_range(MIN_SPEED, MAX_SPEED),
			"phase": randf() * TAU, "rate": randf_range(0.8, 2.2), "size": randf_range(0.8, 1.3),
		})


func _process(delta: float) -> void:
	_ensure_canvas()
	_check_left -= delta
	if _check_left <= 0.0:
		_evaluate()
	_fade = move_toward(_fade, _target, delta / FADE_SECONDS)
	if _fade <= 0.0:
		if visible:
			visible = false
			_cutout = []
			if _decor != null:
				_decor.set_wanted(self, false)
			_request_redraw()
		return
	if not visible:
		visible = true
		if _decor != null:
			_decor.set_wanted(self, true)
	_time += delta
	var rect := _bounds()
	var zone := zone_rect()
	var stay := zone.grow(24.0).intersection(rect) if zone != rect else rect
	var speed_scale := float(_config["speed"])
	for fly in _flies:
		fly["turn_left"] = float(fly["turn_left"]) - delta
		if float(fly["turn_left"]) <= 0.0:
			fly["turn_left"] = randf_range(0.8, 2.4)
			fly["turn"] = randf_range(-1.6, 1.6)
		var angle := float(fly["angle"]) + float(fly["turn"]) * delta
		var position: Vector2 = fly["pos"]
		# 快飄出集中範圍(預設是整個行動區)時慢慢轉向範圍中心;換了位置設定時,原本在範圍外的也這樣慢慢游過去
		if not zone.grow(-8.0).has_point(position):
			var to_center := (zone.get_center() - position).angle()
			angle = lerp_angle(angle, to_center, minf(delta * 2.5, 1.0))
		fly["angle"] = angle
		position += Vector2.from_angle(angle) * float(fly["speed"]) * speed_scale * delta
		var limit := stay if stay.has_point(fly["pos"]) else rect
		fly["pos"] = Vector2(clampf(position.x, limit.position.x, limit.end.x), clampf(position.y, limit.position.y, limit.end.y))
	_cutout_left -= delta
	if not _using_decor() and (_cutout_left <= 0.0 or _cutout.is_empty()):
		_cutout_left = CUTOUT_INTERVAL
		_cutout = _build_cutout()
	_request_redraw()


## 這隻現在的亮度 0~1(忽隱忽現:每隻各有自己的節奏與相位;約一半時間是暗的)。
func _glow_of(fly: Dictionary) -> float:
	var wave := sin(_time * float(fly["rate"]) + float(fly["phase"]))
	return pow(maxf(wave, 0.0), 2.0)


## 裝飾層可以用時畫在它的畫布上(見 _ensure_canvas),否則畫在自己身上。
func _draw() -> void:
	if not _using_decor():
		_paint(self)


func _paint(target: CanvasItem) -> void:
	if _fade <= 0.0:
		return
	var brightness := float(_config["brightness"])
	var glow_size := float(_config["glow_size"])
	var glow_strength := float(_config["glow_strength"])
	var real_left := real_count()
	for i in _flies.size():
		var fly := _flies[i]
		var glow := _glow_of(fly) * _fade
		if glow < 0.02:
			continue
		var position: Vector2 = to_global(fly["pos"]) if target != self else fly["pos"]
		var fly_size := float(fly["size"])
		if i < real_left:
			var radius := REAL_RADIUS * fly_size * glow_size
			target.draw_texture_rect(PetLights.glow_texture(), Rect2(position - Vector2(radius, radius), Vector2(radius, radius) * 2.0), false, Color(0.86, 1.0, 0.5, clampf(0.5 * glow * brightness * glow_strength, 0.0, 1.0)))
			target.draw_circle(position, DOT_RADIUS * 1.3 * fly_size, Color(1.0, 1.0, 0.85, clampf(glow * brightness, 0.0, 1.0)))
		else:
			target.draw_circle(position, DOT_RADIUS * fly_size, Color(1.0, 1.0, 0.92, clampf(0.9 * glow * brightness, 0.0, 1.0)))


## 每隻螢火蟲在下一個更新週期內可能到達的範圍(方形),給穿透形狀用。
func _build_cutout() -> Array:
	var polygons: Array = []
	var reach := MAX_SPEED * float(_config["speed"]) * CUTOUT_INTERVAL + 4.0
	var real_left := real_count()
	var glow_size := float(_config["glow_size"])
	for i in _flies.size():
		var fly := _flies[i]
		var base := (REAL_RADIUS * float(fly["size"]) * glow_size * 0.9) if i < real_left else (DOT_RADIUS * float(fly["size"]) + 1.0)
		var half := base + reach
		var position: Vector2 = fly["pos"]
		polygons.append(PackedVector2Array([
			to_global(position + Vector2(-half, -half)), to_global(position + Vector2(half, -half)),
			to_global(position + Vector2(half, half)), to_global(position + Vector2(-half, half))]))
	return polygons


func get_cutout_polygons() -> Array:
	return _cutout if _fade > 0.0 and not _using_decor() else []
