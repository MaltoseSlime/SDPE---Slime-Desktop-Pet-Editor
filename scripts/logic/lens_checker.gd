class_name LensChecker
extends RefCounted
## 狀態鏡「設定檢查工具」(企劃書第四章,非阻斷式):對目前桌寵的狀態鏡與已載入的積木做兩項靜態掃描——
## (1) 互鎖循環:同一段事件積木裡「讀了鏡片 A 的狀態、又啟用鏡片 B」視為 A→B,若圖上有環(A→B→A)就警告;
## (2) 找不到解除路徑:鏡片沒設逾時,積木裡也沒有任何能解除它的積木(解除該鏡片、解除所有負面且它是負面、
## 限時的「暫時進入狀態」),提示可能永久卡住。
## 結果只是警告清單,不阻止儲存或套用。

const OK_MESSAGE := "沒有發現問題。"


static func check(pet: Node) -> Array[String]:
	var warnings: Array[String] = []
	var blocks: Array = pet.logic.top_blocks() if pet.logic != null else []
	# lambda 只能捕捉到值的複本,要在裡面累積結果就得放進字典(引用型別)。
	var found := {"disable_targets": {}, "disable_negative": false, "disable_positive": false}
	var edges := {}
	for hat in blocks:
		var reads := {}
		var enables := {}
		_walk(hat, _collect.bind(found, reads, enables))
		for from_lens: String in reads:
			for to_lens: String in enables:
				if from_lens != to_lens:
					if not edges.has(from_lens):
						edges[from_lens] = {}
					edges[from_lens][to_lens] = true
	for lens: PetStateLens in pet.state_lenses:
		var has_timeout := lens.timeout_min > 0.0 or lens.timeout_max > 0.0
		var can_release: bool = found["disable_targets"].has(lens.lens_name) or (found["disable_negative"] and lens.has_nature("負面")) or (found["disable_positive"] and lens.has_nature("正面"))
		if not has_timeout and not can_release:
			warnings.append(TranslationServer.translate("「%s」沒有設定逾時,積木檔裡也找不到解除它的積木,可能永久卡住。") % lens.lens_name)
	for cycle in _find_cycles(edges):
		warnings.append(TranslationServer.translate("互鎖循環:%s。") % " → ".join(PackedStringArray(cycle)))
	if warnings.is_empty():
		warnings.append(OK_MESSAGE)
	return warnings


## 走訪時對每顆積木做的登記:reads = 這段事件讀了哪些鏡片的狀態,enables = 啟用了哪些鏡片,
## found 累積整份積木檔裡「有哪些鏡片有解除路徑」。字典是引用型別,所以能在走訪中累積。
static func _collect(block: Dictionary, found: Dictionary, reads: Dictionary, enables: Dictionary) -> void:
	var fields: Dictionary = block.get("fields", {})
	var lens_name := str(fields.get("LENS", ""))
	var type := str(block.get("type", ""))
	if type == "cond_lens_active" or type == "cond_lens_active_over":
		reads[lens_name] = true
	elif type == "lens_enable":
		enables[lens_name] = true
	elif type == "lens_disable":
		found["disable_targets"][lens_name] = true
	elif type == "lens_disable_all_negative":
		found["disable_negative"] = true
	elif type == "lens_disable_all_positive":
		found["disable_positive"] = true
	elif type == "phys_temp_state" and str(fields.get("MODE", "")) == "state_lens":
		enables[lens_name] = true
		if str(fields.get("SEC", "")).strip_edges() != "":
			found["disable_targets"][lens_name] = true


## 走訪積木樹(自己、所有輸入裡的積木、下一顆),對每顆積木呼叫 visitor。
static func _walk(block: Variant, visitor: Callable) -> void:
	if not block is Dictionary:
		return
	visitor.call(block)
	var inputs: Dictionary = block.get("inputs", {})
	for input_name in inputs:
		var entry: Variant = inputs[input_name]
		if entry is Dictionary:
			_walk(entry.get("block", entry.get("shadow")), visitor)
	var next: Variant = block.get("next")
	if next is Dictionary:
		_walk(next.get("block"), visitor)


## 在有向圖裡找環(同一個環只回報一次,不論從哪個起點走到)。
static func _find_cycles(edges: Dictionary) -> Array:
	var cycles: Array = []
	var seen := {}
	for start: String in edges:
		_dfs(start, start, [start], edges, cycles, seen)
	return cycles


static func _dfs(start: String, node: String, path: Array, edges: Dictionary, cycles: Array, seen: Dictionary) -> void:
	for next_node: String in edges.get(node, {}):
		if next_node == start:
			var key := ",".join(PackedStringArray(_canonical(path)))
			if not seen.has(key):
				seen[key] = true
				cycles.append(path + [start])
		elif not path.has(next_node) and path.size() < 8:
			_dfs(start, next_node, path + [next_node], edges, cycles, seen)


## 讓同一個環從不同起點走到時得到同樣的 key。
static func _canonical(path: Array) -> Array:
	var smallest := 0
	for i in path.size():
		if str(path[i]) < str(path[smallest]):
			smallest = i
	return path.slice(smallest) + path.slice(0, smallest)
