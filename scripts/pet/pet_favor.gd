class_name PetFavor
extends RefCounted
## 桌寵對桌寵的「好感度」自動增減(2026-10-06 使用者要求)。好感度是 self 對 other 的單向數值(見 Pet.favor_of),
## 增減量取決於 self 對 other 的好惡等級(好惡 ±1~3 → 增減 2 / 4 / 7),並播對應的特效。
## 所有觸發點都走這裡,數值與特效規模的規則只定義在這一個檔案。
##
## 觸發(好感度增加,喜歡的一方):跟隨喜歡的對象、1v1 對戰(無論輸贏)、一起使用同一件家具、跟隨中一起休息。
## 觸發(好感度減少,討厭的一方):輸給討厭的對象(1v1)、被討厭的對象跟隨時(被跟隨的那隻,討厭它的桌寵降低好感)、
##   與討厭的對象共用家具、與討厭的對象碰撞箱接觸超過 3 分鐘(這個事件冷卻 50 分鐘)。
## 特效規模:密度(intensity)依增減量縮在 0.25~0.6、持續時間 2 秒,都比桌寵平時的特效小,不會蓋過日常動畫。

const AMOUNT_BY_LEVEL := {1: 2.0, 2: 4.0, 3: 7.0}
const FEEDBACK_SECONDS := 2.0
const CONTACT_SECONDS := 180.0
const CONTACT_COOLDOWN := 3000.0
## 每種觸發(同一對象、同一種原因)的數值冷卻:只限制好感度的增減,特效每次都會播(2026-10-06 使用者要求)。
const EVENT_COOLDOWN := 1800.0


## 好惡等級 level(-3~3)對應的好感度增減量(永遠是正數,方向由呼叫端決定)。
static func amount(level: int) -> float:
	return float(AMOUNT_BY_LEVEL.get(clampi(absi(level), 1, 3), 2.0))


## self 對 other 的好感度增減 delta,並播放對應的特效(播在 self 身上)。reason 只用來挑特效:
## "lost" = 輸給討厭的對象(可以出現青筋/惱怒)。同一對象、同一原因在 cooldown 秒內只改數值一次(特效照播)。
static func bond(self_pet: Node, other: Node, delta: float, level: int, reason: String, cooldown := EVENT_COOLDOWN) -> void:
	if not is_instance_valid(self_pet) or not is_instance_valid(other) or self_pet == other or delta == 0.0:
		return
	var tag := str(other.recognition_tag)
	if self_pet.favor_cooldown_ready(tag, reason):
		self_pet.change_favor(tag, delta)
		self_pet.start_favor_cooldown(tag, reason, cooldown)
	_play_feedback(self_pet, delta, level, reason)


## 雙向各自依自己對對方的好惡決定增減(喜歡 → 增加、討厭 → 減少),用於共用家具、一起休息這類對等的情境。
static func mutual_bond(a: Node, b: Node, reason: String) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var me: Node = pair[0]
		var other: Node = pair[1]
		if not is_instance_valid(me) or not is_instance_valid(other):
			continue
		var level: int = me.pet_affinity(other)
		if level > 0:
			bond(me, other, amount(level), level, reason)
		elif level < 0:
			bond(me, other, -amount(level), level, reason)


## 開始跟隨:跟隨者若喜歡領路人 → 增加;領路人被「討厭它的桌寵」跟隨(被跟隨的是被討厭的那隻)→ 討厭它的桌寵降低好感。
static func follow_started(follower: Node, leader: Node) -> void:
	var level: int = follower.pet_affinity(leader)
	if level > 0:
		bond(follower, leader, amount(level), level, "follow")
	elif level < 0:
		bond(follower, leader, -amount(level), level, "follow")
	for other: Node in follower.get_tree().get_nodes_in_group("pets"):
		if other == follower or not is_instance_valid(other):
			continue
		var dislike: int = other.pet_affinity(follower)
		if dislike < 0:
			bond(other, follower, -amount(dislike), dislike, "followed")


## 1v1 對戰結束(result_a:a 的結果 win / lose / tie / draw)。喜歡的對手無論輸贏都增加;討厭的對手只有輸了才減少。
static func duel(a: Node, b: Node, result_a: String) -> void:
	var result_b := "tie"
	if result_a == "win":
		result_b = "lose"
	elif result_a == "lose":
		result_b = "win"
	for triple: Array in [[a, b, result_a], [b, a, result_b]]:
		var me: Node = triple[0]
		var other: Node = triple[1]
		var my_result: String = triple[2]
		if not is_instance_valid(me) or not is_instance_valid(other):
			continue
		var level: int = me.pet_affinity(other)
		if level > 0:
			bond(me, other, amount(level), level, "duel")
		elif level < 0 and my_result == "lose":
			bond(me, other, -amount(level), level, "lost")


## 碰撞箱接觸的累計時間:討厭的對象接觸超過 CONTACT_SECONDS 就降低好感,之後進入 CONTACT_COOLDOWN 冷卻。
## 回傳這次是否真的觸發了(呼叫端負責累計時間與冷卻,見 Pet._tick_pet_affinity_contact)。
static func contact_strain(self_pet: Node, other: Node, level: int) -> void:
	bond(self_pet, other, -amount(level), level, "contact", CONTACT_COOLDOWN)


## ── 桌寵對使用者的好感度(保留數值「好感度」,ValueGateway 的 local 範圍)──────────────────
## 摸摸(極少~最少)、一起玩球、教新詞、跟使用者 1v1、參與全體遊戲。每種各自冷卻,冷卻只限制數值,特效照播。
const USER_TINY := 0.5      # 極少量:參與全體遊戲
const USER_MINIMAL := 1.0   # 最少量:摸摸、一起玩球
const USER_SMALL := 2.0     # 少量:教新詞、1v1
const USER_PET_COOLDOWN := 1200.0    # 摸摸 20 分鐘
const USER_BALL_COOLDOWN := 3600.0   # 一起玩球 1 小時
const USER_TEACH_COOLDOWN := 1800.0  # 教新詞 30 分鐘
const USER_DUEL_COOLDOWN := 3600.0   # 1v1 1 小時
const USER_GROUP_COOLDOWN := 3600.0  # 全體遊戲 1 小時


## 桌寵對使用者的好感度增加 amount,但同一種原因在 cooldown 秒內只算一次。回傳這次有沒有真的加到。
static func user_bond(pet: Node, reason: String, amount_value: float, cooldown: float) -> bool:
	if not is_instance_valid(pet) or not pet.favor_cooldown_ready("user", reason):
		return false
	ValueGateway.modify_value(pet, "好感度", amount_value, "local")
	pet.start_favor_cooldown("user", reason, cooldown)
	return true


## 全體遊戲(猜拳/珠璣妙算)中使用者參與:每隻參與的桌寵各自對使用者加一點點。
static func user_group(pets: Array) -> void:
	for pet: Node in pets:
		user_bond(pet, "group", USER_TINY, USER_GROUP_COOLDOWN)


static func _play_feedback(pet: Node, delta: float, level: int, reason: String) -> void:
	if pet.effects == null:
		return
	var pool: Array[String] = []
	if delta > 0.0:
		pool = ["sparkle", "hearts", "flowers"]
		if level >= 3:
			pool.append("heart_big")   # 愛意:限超級喜歡
	else:
		pool = ["gloom", "confused"]
		# 青筋/惱怒:限超級討厭,或討厭/超級討厭時輸給對手
		if level <= -3 or (reason == "lost" and level <= -2):
			pool.append_array(["vein", "flame"])
	var effect_name: String = pool.pick_random()
	var intensity := clampf(absf(delta) / 7.0, 0.25, 0.6)
	pet.effects.play(effect_name, FEEDBACK_SECONDS, intensity)


## ── 對象關係的清除(2026-10-06):記憶重置的勾選項與測試者面板共用 ──────────────────────
## 清空對使用者的好感度(歸零)。
static func clear_user_favor(pet: Node) -> void:
	ValueGateway.set_value(pet, "好感度", 0.0, "local")


## 清空對其他桌寵的好惡與好感度(「全部角色」的預設好惡保留)。
static func clear_pet_relations(pet: Node) -> void:
	var rules: Dictionary = pet.interaction_rules.duplicate(true)
	var kept: Array = []
	for entry: Variant in rules.get("pet_prefs", []):
		if entry is Dictionary and str((entry as Dictionary).get("target", "")) == InteractionRules.ALL_PETS_TARGET:
			kept.append(entry)
	rules["pet_prefs"] = kept
	pet.set_interaction_rules(rules)
	pet.pet_favors = {}


## 讓場上其他桌寵對這隻桌寵的好感度歸零。
static func forget_me(pet: Node) -> void:
	for other: Node in pet.get_tree().get_nodes_in_group("pets"):
		if other != pet and is_instance_valid(other):
			other.pet_favors.erase(str(pet.recognition_tag))

