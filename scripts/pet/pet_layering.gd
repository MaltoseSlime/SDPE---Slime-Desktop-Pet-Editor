class_name PetLayering
extends RefCounted
## 一般桌寵之間的前後順序(2026-10-11 使用者要求)。半身立繪(貼底的固定模式)不歸這裡管,它們有自己的立繪帶
## (見 DrawLayers.still_z、DesktopShell._layout_bottom_pets),永遠在一般桌寵後面。
##
## 兩層規則:
##  1. 手動層級(Pet.layer_tier,右鍵選單「圖層」,存在角色設定檔):後面 / 中間(預設)/ 前面。層級不同就一定照層級排。
##  2. 同一個層級裡自動判定:腳底(position.y)比較高(畫面上比較上面)的排後面,比較低的排前面——站在高處平臺上的
##     會被站在地上的擋住,看起來才有前後距離。腳底差不多高(相差 Y_STEP 以內,例如都站在地上)就算同一排,
##     照原本的規則:點過的那隻浮到最上面(節點順序,見 PetInteraction._on_press)。
## 拖曳中的那隻一律拉到最前面。
##
## 做法:只改 z_index,落在 DrawLayers 的 PET 區段(-30 ~ 0;道具 z = 5、特效 +100 起都還在桌寵前面,跟原本一樣)。
## 每個層級 ROWS_PER_TIER 個編號,同層級裡不同高度的「排」超過這個數量時,最前面的幾排併在一起(不會跑到別的層級)。

enum Tier { BACK = -1, MIDDLE = 0, FRONT = 1 }

const TIER_LABELS := {Tier.BACK: "後面", Tier.MIDDLE: "中間", Tier.FRONT: "前面"}
const ROWS_PER_TIER := 10
## 腳底高度差在這個像素數以內算同一排(站在同一個地面上的桌寵座標會有零點幾像素的誤差,不能讓它決定前後)。
const Y_STEP := 8.0


static func manages(pet: Node) -> bool:
	return not (pet.bottom_anchored and pet.move_mode == Pet.MoveMode.FIXED)


## 層級 tier 的第 row 排(0 = 最後面)的 z_index。
static func z_for(tier: int, row: int) -> int:
	return DrawLayers.PET + (clampi(tier, Tier.BACK, Tier.FRONT) - Tier.FRONT) * ROWS_PER_TIER - (ROWS_PER_TIER - 1) + clampi(row, 0, ROWS_PER_TIER - 1)


## 重新排一次場上所有一般桌寵的 z_index。桌寵數量不多,整批重算即可(DesktopShell 定時呼叫)。
static func apply(tree: SceneTree) -> void:
	var by_tier := {}
	for pet: Node in tree.get_nodes_in_group("pets"):
		if not is_instance_valid(pet) or pet.is_queued_for_deletion() or not manages(pet):
			continue
		if pet.dragging:
			pet.z_index = DrawLayers.PET   # 抓在手上的:最前面
			continue
		var tier := clampi(int(pet.layer_tier), Tier.BACK, Tier.FRONT)
		if not by_tier.has(tier):
			by_tier[tier] = []
		(by_tier[tier] as Array).append(pet)
	for tier: int in by_tier:
		var pets: Array = by_tier[tier]
		# 由高到低(y 小到大)掃一遍:跟上一隻的腳底差超過 Y_STEP 才算新的一排(用相鄰差距分排,不用固定格線,
		# 免得剛好站在格線上的兩隻因為零點幾像素的誤差一直互換前後)。排數太多時最前面的幾排併成一排(z_for 會夾住)。
		pets.sort_custom(func(a: Node, b: Node) -> bool: return a.global_position.y < b.global_position.y)
		var row := 0
		var last_y: float = pets[0].global_position.y
		for pet: Node in pets:
			if pet.global_position.y - last_y > Y_STEP:
				row += 1
			last_y = pet.global_position.y
			var z := z_for(tier, row)
			if pet.z_index != z:
				pet.z_index = z
