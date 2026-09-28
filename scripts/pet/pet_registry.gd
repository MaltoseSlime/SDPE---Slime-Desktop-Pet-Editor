class_name PetRegistry
extends RefCounted
## 場上桌寵的編號(Pet.instance_index):同一個角色(辨識代號相同;沒有代號就用顯示名稱)在場有好幾隻時,
## 依出現先後編成 (1)(2)…,方便在系統匣選單、管理視窗、測試者視窗分辨、管理各自的狀態鏡。
## 只有一隻時不編號。已經有的編號盡量保持不變(第 1 隻離開後,第 2 隻不會突然變成 1),缺的補最小的空號。


## 同角色(辨識代號相同,沒有代號就用顯示名稱)的分組,每組依生成先後(spawn_serial)排序,最早的在最前面。
static func groups(tree: SceneTree) -> Dictionary:
	var result := {}
	for pet: Node in tree.get_nodes_in_group("pets"):
		if pet.is_queued_for_deletion():
			continue
		var key: String = pet.recognition_tag if pet.recognition_tag != "" else pet.display_name
		if not result.has(key):
			result[key] = []
		result[key].append(pet)
	for key in result:
		result[key].sort_custom(func(a: Node, b: Node) -> bool: return a.spawn_serial < b.spawn_serial)
	return result


## 各複製品的「可能不同的狀態」指紋:局部數值、Flag、啟用中的狀態鏡。指紋不同代表這組複製品各自走出了不同的設定。
static func state_signature(pet: Node) -> String:
	return JSON.stringify([pet.local_values, pet.flags, pet.text_values, pet.active_lens_names()], "", true)


## 有 2 隻以上、而且狀態指紋不完全相同的分組(key → 依生成先後排序的桌寵陣列)。
static func divergent_groups(tree: SceneTree) -> Dictionary:
	var result := {}
	var all := groups(tree)
	for key in all:
		var pets: Array = all[key]
		if pets.size() < 2:
			continue
		var first := state_signature(pets[0])
		if pets.any(func(p: Node) -> bool: return state_signature(p) != first):
			result[key] = pets
	return result


## 依政策選出預設的本體:earliest = 最早生成的,latest = 最晚生成的。
static func pick_default(pets: Array, policy: String) -> Node:
	return pets[pets.size() - 1] if policy == "latest" else pets[0]


static func refresh_labels(tree: SceneTree) -> void:
	if tree == null:
		return
	var groups: Dictionary = {}
	for pet: Node in tree.get_nodes_in_group("pets"):
		if not pet.is_inside_tree() or pet.is_queued_for_deletion():
			continue
		var key: String = pet.recognition_tag if pet.recognition_tag != "" else pet.display_name
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pet)
	for key in groups:
		var pets: Array = groups[key]
		if pets.size() == 1:
			pets[0].set_instance_index(0)
			continue
		var used := {}
		var needs_number: Array = []
		for pet: Node in pets:
			if pet.instance_index > 0 and not used.has(pet.instance_index):
				used[pet.instance_index] = true
			else:
				needs_number.append(pet)
		var next := 1
		for pet: Node in needs_number:
			while used.has(next):
				next += 1
			used[next] = true
			pet.set_instance_index(next)
