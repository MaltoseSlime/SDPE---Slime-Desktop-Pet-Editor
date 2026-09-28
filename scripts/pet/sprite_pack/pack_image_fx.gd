class_name PackImageFx
extends RefCounted
## 精靈圖編輯器的「圖片處理」:裁切、水平/垂直翻轉、以角度旋轉。不改動原圖檔——處理步驟寫在 pack.json 的 frames 項目裡
## (欄位 "fx",一串用「;」隔開、依序執行的步驟),載入時才即時算出處理後的圖(結果只算一次、之後重用)。
##
## 步驟寫法(依序執行,每一步作用在前一步的結果上):
##   c<x>,<y>,<寬>,<高>   裁切(座標是當時那張圖的像素;超出範圍的部分會被截掉)
##   h                     水平翻轉(左右對調)
##   v                     垂直翻轉(上下對調)
##   r<角度>               順時針旋轉的角度(可以是負的、可以有小數,畫布會放大到裝得下整張旋轉後的圖,空白處透明)
## 例:"c4,0,32,48;h;r15"。90 的倍數的旋轉是無損的;其他角度用最近點取樣(像素風不會被糊掉)。
## 軸心(pivot)是相對「處理後的圖」的像素座標,所以每加一步,編輯器會把已經設定過的軸心跟著換算(map_point)。

const MAX_OPS := 12
const MAX_SIDE := 4096


## 文字 → 步驟清單 [{op: "c"/"h"/"v"/"r", rect?: Rect2i, degrees?: float}];格式不對回 null(空字串 = 沒有步驟,回空陣列)。
static func parse(text: String) -> Variant:
	var ops: Array = []
	var clean := text.strip_edges()
	if clean == "":
		return ops
	var parts := clean.split(";", false)
	if parts.size() > MAX_OPS:
		return null
	for part: String in parts:
		var step := part.strip_edges()
		if step == "":
			continue
		match step.substr(0, 1):
			"h", "v":
				if step.length() != 1:
					return null
				ops.append({"op": step})
			"r":
				var degrees_text := step.substr(1)
				if not degrees_text.is_valid_float():
					return null
				var degrees := float(degrees_text)
				if absf(degrees) > 3600.0:
					return null
				ops.append({"op": "r", "degrees": degrees})
			"c":
				var numbers := step.substr(1).split(",")
				if numbers.size() != 4:
					return null
				for number: String in numbers:
					if not number.is_valid_int():
						return null
				var rect := Rect2i(int(numbers[0]), int(numbers[1]), int(numbers[2]), int(numbers[3]))
				if rect.size.x < 1 or rect.size.y < 1 or rect.size.x > MAX_SIDE or rect.size.y > MAX_SIDE:
					return null
				ops.append({"op": "c", "rect": rect})
			_:
				return null
	return ops


## 步驟清單 → 文字(parse 的反向)。
static func serialize(ops: Array) -> String:
	var parts: PackedStringArray = []
	for step: Dictionary in ops:
		match str(step["op"]):
			"h", "v":
				parts.append(str(step["op"]))
			"r":
				parts.append("r%s" % _degrees_text(float(step["degrees"])))
			"c":
				var rect: Rect2i = step["rect"]
				parts.append("c%d,%d,%d,%d" % [rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	return ";".join(parts)


static func _degrees_text(degrees: float) -> String:
	var rounded_degrees := snappedf(degrees, 0.1)
	return str(int(rounded_degrees)) if is_equal_approx(rounded_degrees, roundf(rounded_degrees)) else str(rounded_degrees)


## 加一步(回傳新的清單,不改原本的)。連續兩次一樣的翻轉互相抵消;連續的旋轉合併成一步(轉到 0 度就拿掉)。超過步驟上限回 null。
static func with_op(ops: Array, op: Dictionary) -> Variant:
	var result := ops.duplicate(true)
	if not result.is_empty():
		var last: Dictionary = result[result.size() - 1]
		if str(last["op"]) == str(op["op"]) and (str(op["op"]) == "h" or str(op["op"]) == "v"):
			result.pop_back()
			return result
		if str(last["op"]) == "r" and str(op["op"]) == "r":
			var merged := fposmod(float(last["degrees"]) + float(op["degrees"]), 360.0)
			result.pop_back()
			if not is_zero_approx(snappedf(merged, 0.1)) and not is_equal_approx(snappedf(merged, 0.1), 360.0):
				result.append({"op": "r", "degrees": merged})
			return result
	if result.size() >= MAX_OPS:
		return null
	result.append(op)
	return result


## 套用所有步驟。回傳新圖(RGBA8);任何一步讓圖變成空的或超過邊長上限就回 null。原圖不會被改。
static func apply(source: Image, ops: Array) -> Image:
	var image := source.duplicate() as Image
	image.convert(Image.FORMAT_RGBA8)
	for step: Dictionary in ops:
		match str(step["op"]):
			"h":
				image.flip_x()
			"v":
				image.flip_y()
			"c":
				var rect: Rect2i = (step["rect"] as Rect2i).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
				if rect.size.x < 1 or rect.size.y < 1:
					return null
				image = image.get_region(rect)
			"r":
				image = _rotate(image, float(step["degrees"]))
				if image == null:
					return null
	return image


## 順時針轉 degrees 度。90 的倍數用內建的無損旋轉,其他角度逐像素反向取樣(最近點)。
static func _rotate(image: Image, degrees: float) -> Image:
	var normalized := fposmod(degrees, 360.0)
	if is_zero_approx(normalized) or is_equal_approx(normalized, 360.0):
		return image
	if is_equal_approx(normalized, 90.0):
		image.rotate_90(CLOCKWISE)
		return image
	if is_equal_approx(normalized, 180.0):
		image.rotate_180()
		return image
	if is_equal_approx(normalized, 270.0):
		image.rotate_90(COUNTERCLOCKWISE)
		return image
	var size := rotated_size(image.get_size(), normalized)
	if size.x > MAX_SIDE or size.y > MAX_SIDE:
		return null
	var result := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	var source_data := image.get_data()
	var target_data := result.get_data()
	var radians := deg_to_rad(normalized)
	var cos_a := cos(radians)
	var sin_a := sin(radians)
	var source_size := image.get_size()
	var source_center := Vector2(source_size) * 0.5
	var target_center := Vector2(size) * 0.5
	for y in size.y:
		var dy := float(y) + 0.5 - target_center.y
		for x in size.x:
			var dx := float(x) + 0.5 - target_center.x
			# 反向旋轉:目標像素對應到原圖的哪一點。
			var sx := int(floorf(dx * cos_a + dy * sin_a + source_center.x))
			var sy := int(floorf(-dx * sin_a + dy * cos_a + source_center.y))
			if sx < 0 or sy < 0 or sx >= source_size.x or sy >= source_size.y:
				continue
			var from := (sy * source_size.x + sx) * 4
			var to := (y * size.x + x) * 4
			target_data[to] = source_data[from]
			target_data[to + 1] = source_data[from + 1]
			target_data[to + 2] = source_data[from + 2]
			target_data[to + 3] = source_data[from + 3]
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, target_data)


## 順時針轉 degrees 度之後,裝得下整張圖的畫布大小。
static func rotated_size(size: Vector2i, degrees: float) -> Vector2i:
	var normalized := fposmod(degrees, 360.0)
	if is_equal_approx(normalized, 90.0) or is_equal_approx(normalized, 270.0):
		return Vector2i(size.y, size.x)
	if is_zero_approx(normalized) or is_equal_approx(normalized, 180.0) or is_equal_approx(normalized, 360.0):
		return size
	var radians := deg_to_rad(normalized)
	var abs_cos := absf(cos(radians))
	var abs_sin := absf(sin(radians))
	return Vector2i(maxi(1, int(ceilf(size.x * abs_cos + size.y * abs_sin - 0.001))), maxi(1, int(ceilf(size.x * abs_sin + size.y * abs_cos - 0.001))))


## 圖經過「一步」處理之後的大小。
static func size_after(size: Vector2i, step: Dictionary) -> Vector2i:
	match str(step["op"]):
		"c":
			return ((step["rect"] as Rect2i).intersection(Rect2i(Vector2i.ZERO, size))).size
		"r":
			return rotated_size(size, float(step["degrees"]))
	return size


## 一個點(圖片像素座標,從左上角算)經過「一步」處理之後的位置(軸心跟著換算用)。size 是處理之前的圖大小。
static func map_point(point: Vector2, size: Vector2i, step: Dictionary) -> Vector2:
	match str(step["op"]):
		"h":
			return Vector2(float(size.x) - point.x, point.y)
		"v":
			return Vector2(point.x, float(size.y) - point.y)
		"c":
			var rect: Rect2i = (step["rect"] as Rect2i).intersection(Rect2i(Vector2i.ZERO, size))
			var moved := point - Vector2(rect.position)
			return Vector2(clampf(moved.x, 0.0, float(rect.size.x)), clampf(moved.y, 0.0, float(rect.size.y)))
		"r":
			var new_size := rotated_size(size, float(step["degrees"]))
			var radians := deg_to_rad(fposmod(float(step["degrees"]), 360.0))
			var relative := point - Vector2(size) * 0.5
			var rotated := Vector2(relative.x * cos(radians) - relative.y * sin(radians), relative.x * sin(radians) + relative.y * cos(radians))
			return (rotated + Vector2(new_size) * 0.5).round()
	return point


## 一個點經過整串步驟之後的位置。
static func map_point_through(point: Vector2, size: Vector2i, ops: Array) -> Vector2:
	var current := point
	var current_size := size
	for step: Dictionary in ops:
		current = map_point(current, current_size, step)
		current_size = size_after(current_size, step)
	return current


## 圖經過整串步驟之後的大小。
static func size_through(size: Vector2i, ops: Array) -> Vector2i:
	var current := size
	for step: Dictionary in ops:
		current = size_after(current, step)
	return current
