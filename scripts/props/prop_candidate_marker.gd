class_name PropCandidateMarker
extends Node2D
## 選中狀態的視覺回饋(企劃書第五章):拖著道具碰到桌寵時,沿著「放開後會被套用的那一隻」的輪廓畫一圈外框(顏色用那隻桌寵對話泡泡的邊框色與粗細),頭頂上方一個小三角形;
## 換到別隻時舊的立刻取消(target 換掉)。輪廓來自目前這一幀不透明像素的外緣(依貼圖快取),讀不到圖就退回互動判定框的矩形。
## 是「Cutout」群組成員,外框與三角形才不會被穿透裁掉。

const COLOR := Color(1.0, 0.85, 0.3, 0.95)
const MAX_CACHE := 96
## 輪廓簡化的容許誤差(像素):越大越省、越不貼。
const OUTLINE_EPSILON := 1.5

static var _outline_cache: Dictionary = {}

var target: Node


func _ready() -> void:
	add_to_group("Cutout")
	z_index = 25


## 換目標(null = 取消)。
func set_target(pet: Node) -> void:
	target = pet
	queue_redraw()


func _process(_delta: float) -> void:
	if target != null:
		if not is_instance_valid(target):
			target = null
		queue_redraw()


func _box() -> Rect2:
	return (target.interaction_rect() as Rect2).grow(6.0) if target != null and is_instance_valid(target) else Rect2()


func _color() -> Color:
	if target != null and is_instance_valid(target) and target.get("ui_style") != null:
		var border: Color = (target.ui_style as PetUiStyle).border
		return Color(border, 0.95)
	return COLOR


func _line_width() -> float:
	if target != null and is_instance_valid(target) and target.get("ui_style") != null:
		return clampf(float((target.ui_style as PetUiStyle).border_width), 1.5, 5.0)
	return 2.0


## 目前這一幀貼圖的輪廓(貼圖虛擬畫布座標,可能有好幾圈);依貼圖快取。空陣列 = 讀不到或整張透明。
static func outline_of(texture: Texture2D) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if texture == null:
		return result
	var key := texture.get_instance_id()
	if _outline_cache.has(key):
		return _outline_cache[key]
	var image := texture.get_image()
	if image != null and not image.is_empty():
		image.convert(Image.FORMAT_RGBA8)
		var bitmap := BitMap.new()
		bitmap.create_from_image_alpha(image, 0.2)
		var shift := Vector2.ZERO
		if texture is AtlasTexture:
			shift = (texture as AtlasTexture).margin.position
		for polygon: PackedVector2Array in bitmap.opaque_to_polygons(Rect2i(Vector2i.ZERO, image.get_size()), OUTLINE_EPSILON):
			if polygon.size() < 3:
				continue
			var moved := PackedVector2Array()
			for point in polygon:
				moved.append(point + shift)
			result.append(moved)
	if _outline_cache.size() >= MAX_CACHE:
		_outline_cache.clear()
	_outline_cache[key] = result
	return result


## 貼圖座標 → 全域座標(和 Pet.pixel_hit 反過來的同一套換算)。
static func to_global_points(outline: PackedVector2Array, snapshot: Dictionary) -> PackedVector2Array:
	var texture: Texture2D = snapshot["texture"]
	var xform: Transform2D = snapshot["xform"]
	var offset: Vector2 = snapshot["offset"]
	var centered: bool = snapshot["centered"]
	var origin := offset - (texture.get_size() * 0.5 if centered else Vector2.ZERO)
	var result := PackedVector2Array()
	for point in outline:
		result.append(xform * (point + origin))
	return result


## 這隻桌寵目前的輪廓(全域座標);沒有回空陣列。
func _global_outlines() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if target == null or not is_instance_valid(target) or not target.has_method("visual_snapshot"):
		return result
	var snapshot: Dictionary = target.visual_snapshot()
	if snapshot.is_empty():
		return result
	for outline in outline_of(snapshot["texture"]):
		result.append(to_global_points(outline, snapshot))
	return result


func get_cutout_polygons() -> Array:
	if target == null or not is_instance_valid(target):
		return []
	var box := _box()
	return [DialogueBubble._rect_polygon(Rect2(box.position - Vector2(4.0, 26.0), box.size + Vector2(8.0, 30.0)))]


func _draw() -> void:
	if target == null or not is_instance_valid(target):
		return
	var color := _color()
	var width := _line_width()
	var box := _box()
	var outlines := _global_outlines()
	var top := box.position.y
	if outlines.is_empty():
		draw_rect(box, Color(color, 0.12))
		draw_rect(box, color, false, width)
	else:
		top = INF
		for polygon in outlines:
			if not Geometry2D.triangulate_polygon(polygon).is_empty():
				draw_colored_polygon(polygon, Color(color, 0.12))
			var closed := polygon.duplicate()
			closed.append(polygon[0])
			draw_polyline(closed, color, width, true)
			for point in polygon:
				top = minf(top, point.y)
	var tip := Vector2(box.get_center().x, top - 4.0)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-9.0, -14.0), tip + Vector2(9.0, -14.0)]), color)
