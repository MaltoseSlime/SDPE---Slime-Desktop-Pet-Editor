class_name PackLayers
extends RefCounted
## 精靈圖編輯器的「圖層」:本體(動作的幀)加上配件(overlays.json 的部件),由下到上的繪製順序是
##   「本體後面」的配件(layer = back)→ 本體 → 「本體上面」的配件(front)→「最上層」的配件(top)→「光源之上」的配件(above_light);
## 同一層裡清單後面的蓋在前面的上面。「光源之上」比「最上層」還要再上面一層,是唯一會蓋過桌寵身上光暈(PetLights)的圖層(見 pet_overlays.gd LAYER_Z)。
## 這裡只放純資料的順序操作(顯示用的堆疊、上移下移),編輯器的清單與按鈕呼叫它。

const LAYERS: Array[String] = ["back", "front", "top", "above_light"]
const BODY := -1


static func layer_of(part: Dictionary) -> String:
	var layer := str(part.get("layer", "front"))
	return layer if LAYERS.has(layer) else "front"


## 由下到上的繪製順序:每一項是配件在清單裡的索引,BODY(-1)是本體。
static func draw_order(parts: Array) -> Array[int]:
	var order: Array[int] = []
	for layer: String in ["back"]:
		for i in parts.size():
			if layer_of(parts[i]) == layer:
				order.append(i)
	order.append(BODY)
	for layer: String in ["front", "top", "above_light"]:
		for i in parts.size():
			if layer_of(parts[i]) == layer:
				order.append(i)
	return order


## 圖層清單顯示用的堆疊:最上面的在前面(和 draw_order 相反)。
static func stack(parts: Array) -> Array[int]:
	var order := draw_order(parts)
	order.reverse()
	return order


## 把第 part_index 個配件往上(direction = 1)或往下(-1)移一格。跨過本體時「本體後面 / 本體上面」互換,
## 移到別的配件的位置就跟那個配件同一層。回傳 {parts(新的清單,按繪製順序排好)、index(這個配件在新清單的位置)、changed}。
static func move(parts: Array, part_index: int, direction: int) -> Dictionary:
	var order := draw_order(parts)
	var position := order.find(part_index)
	var target := position + direction
	if part_index < 0 or part_index >= parts.size() or position < 0 or target < 0 or target >= order.size() or direction == 0:
		return {"parts": parts, "index": part_index, "changed": false}
	var neighbor := order[target]
	var copies: Array[Dictionary] = []
	for part: Dictionary in parts:
		copies.append(part.duplicate(true))
	if neighbor == BODY:
		copies[part_index]["layer"] = "front" if direction > 0 else "back"
	else:
		copies[part_index]["layer"] = layer_of(copies[neighbor])
	order[position] = neighbor
	order[target] = part_index
	var result: Array[Dictionary] = []
	var new_index := 0
	for entry in order:
		if entry == BODY:
			continue
		if entry == part_index:
			new_index = result.size()
		result.append(copies[entry])
	return {"parts": result, "index": new_index, "changed": true}
