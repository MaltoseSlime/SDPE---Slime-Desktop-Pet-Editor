class_name PetFavor
extends RefCounted
## 桌寵對桌寵的「好感度」自動增減。好感度是 self 對 other 的單向數值(見 Pet.favor_of)。
## 2026-10-07(0.1.9):增減量同時看「好惡等級」與「自己的性格」——
##   · 好惡等級:喜歡的對象加得多、扣得少;討厭的對象反之;普通(0)的對象也有增加事件(小幅)。
##   · 性格(反應區段選的性格,見 PetFavor.personality_of):衝動的減少比較痛、黏人的加得多;平靜會比較不在意輸贏。
## 所有觸發點都走這裡,數值與特效規模的規則只定義在這一個檔案。
##
## 增加(self 對 other):跟隨、1v1 對戰(任何結果,普通與喜歡的對手)、共用家具、跟隨中一起休息。
## 減少(self 對 other):
##   · 輸給討厭的對象(1v1)、跟隨討厭的對象、被討厭的對象跟隨時、與討厭的對象共用家具、碰撞箱接觸超過 3 分鐘。
##   · 連輸(1v1,任何對象,不分好惡):同一對象的連續 5 場 1v1 為一輪,輪末結尾連輸次數 ≥ 門檻才扣。
##     門檻依性格:衝動 2、內向/黏人 4、其餘 3;平靜/友善/活潑「輸了也不氣餒」,不因連輸扣好感。
##     連輸只看同一對象的 1v1(途中改去跟別人打不會中斷);全體遊戲不計入。冷卻 20 分鐘。
## 特效規模:密度(intensity)依增減量縮在 0.25~0.6、持續時間 2 秒,都比桌寵平時的特效小,不會蓋過日常動畫。

## 好惡等級 -3~3 → 增加量(普通 0 也會增加,小幅;討厭的對象只剩一點點)。
const GAIN_BY_LEVEL := {-3: 0.5, -2: 0.5, -1: 1.0, 0: 1.0, 1: 2.0, 2: 4.0, 3: 7.0}
## 好惡等級 -3~3 → 減少量(正數;喜歡的對象扣得少,討厭的對象扣得多)。
const LOSS_BY_LEVEL := {-3: 7.0, -2: 4.0, -1: 1.0, 0: 2.0, 1: 1.5, 2: 1.0, 3: 0.5}
const FEEDBACK_SECONDS := 2.0
const CONTACT_SECONDS := 180.0
const CONTACT_COOLDOWN := 3000.0
## 每種觸發(同一對象、同一種原因)的數值冷卻:只限制好感度的增減,特效每次都會播(2026-10-06 使用者要求)。
const EVENT_COOLDOWN := 1800.0
## 連輸事件的冷卻(使用者要求 20 分鐘)。
const STREAK_COOLDOWN := 1200.0
## 連輸判定的一輪場數(同一對象的 1v1)。
const STREAK_WINDOW := 5
## 普通(好惡 0)關係共用家具/一起休息時,增加好感的觸發機率(沒中就什麼都不做;喜歡/討厭的對象不受這個限制)。
const NEUTRAL_SHARE_CHANCE := 0.35
## 一起玩球的桌寵互相增加一點好感(使用者要求:球對桌寵們來說是特別的,不看好惡等級,雙方都加),冷卻 20 分鐘。
const BALL_TOGETHER_GAIN := 1.0
const BALL_TOGETHER_COOLDOWN := 1200.0


## 好惡等級 level 對 self(pet)來說的增加量(已乘上性格參數「好感度追加倍率」,見 PersonalityParams.favor_gain_mult)。
static func gain_amount(pet: Node, level: int) -> float:
	var base := float(GAIN_BY_LEVEL.get(clampi(level, -3, 3), 1.0))
	return base * pet.vitality.favor_gain_mult


## 好惡等級 level 對 self(pet)來說的減少量(正數,已乘上性格參數「好感度減少倍率」,見 PersonalityParams.favor_loss_mult)。
static func loss_amount(pet: Node, level: int) -> float:
	var base := float(LOSS_BY_LEVEL.get(clampi(level, -3, 3), 3.0))
	return base * pet.vitality.favor_loss_mult


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


## 依 self 對 other 的好惡增減(喜歡/普通 → 增加,討厭 → 減少)。用於共用家具、一起休息這類對等的情境。
static func _by_level(me: Node, other: Node, reason: String) -> void:
	var level: int = me.pet_affinity(other)
	if level < 0:
		bond(me, other, -loss_amount(me, level), level, reason)
	else:
		bond(me, other, gain_amount(me, level), level, reason)


## 雙向各自依自己對對方的好惡決定增減。普通關係(好惡 0)觸發率較低(NEUTRAL_SHARE_CHANCE),喜歡/討厭的對象一定觸發。
static func mutual_bond(a: Node, b: Node, reason: String) -> void:
	for pair: Array in [[a, b], [b, a]]:
		var me: Node = pair[0]
		var other: Node = pair[1]
		if not is_instance_valid(me) or not is_instance_valid(other):
			continue
		if me.pet_affinity(other) == 0 and randf() >= NEUTRAL_SHARE_CHANCE:
			continue
		_by_level(me, other, reason)


## 一起玩同一顆球:雙方都加 BALL_TOGETHER_GAIN,不看好惡等級(球是特別的)。
static func ball_together(a: Node, b: Node) -> void:
	if not is_instance_valid(a) or not is_instance_valid(b) or a == b:
		return
	bond(a, b, BALL_TOGETHER_GAIN, 0, "ball", BALL_TOGETHER_COOLDOWN)
	bond(b, a, BALL_TOGETHER_GAIN, 0, "ball", BALL_TOGETHER_COOLDOWN)


## 開始跟隨:跟隨者依好惡增減;領路人被「討厭它的桌寵」跟隨時,討厭它的桌寵降低好感。
static func follow_started(follower: Node, leader: Node) -> void:
	_by_level(follower, leader, "follow")
	for other: Node in follower.get_tree().get_nodes_in_group("pets"):
		if other == follower or not is_instance_valid(other):
			continue
		var dislike: int = other.pet_affinity(follower)
		if dislike < 0:
			bond(other, follower, -loss_amount(other, dislike), dislike, "followed")


## 1v1 對戰結束(result_a:a 的結果 win / lose / tie)。
## 任何結果(普通與喜歡的對手)都會增加;討厭的對手只有輸了才減少;同時記下這一場給連輸判定用。
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
		if level < 0:
			# 討厭的對手:只有輸了才減少,贏/平不加
			if my_result == "lose":
				bond(me, other, -loss_amount(me, level), level, "lost")
		else:
			# 普通與喜歡的對手:無論輸贏都增加(喜歡的加得多)
			bond(me, other, gain_amount(me, level), level, "duel")
		_record_duel(me, other, my_result)


## 連輸判定:記下 me 對 other 的這一場(W/L/T),滿 STREAK_WINDOW 場就結算一輪:
## 輪末結尾連續輸的次數 ≥ 性格門檻(且性格不是輸了也不氣餒的那幾種)就扣好感,然後清空重算下一輪。
static func _record_duel(me: Node, other: Node, my_result: String) -> void:
	var tag := str(other.recognition_tag)
	var history: Array = me.duel_history.get(tag, [])
	history.append("L" if my_result == "lose" else "W")
	if history.size() < STREAK_WINDOW:
		me.duel_history[tag] = history
		return
	me.duel_history[tag] = []
	var threshold := int(roundi(me.vitality.favor_streak_threshold))
	if threshold <= 0:
		return   # 性格參數「連敗 N 次時觸發扣好感事件」= 0:不氣餒,連敗不扣。
	var trailing := 0
	for i in range(history.size() - 1, -1, -1):
		if history[i] != "L":
			break
		trailing += 1
	if trailing >= threshold:
		var level: int = me.pet_affinity(other)
		bond(me, other, -loss_amount(me, level), level, "streak", STREAK_COOLDOWN)


## 內向的桌寵被同一個人連續邀請(10 分鐘內 3 次,見 PetVitality.note_invited)時,心情 -3 之外,也對邀請者的好感降低。
## 減少量照好惡與性格算(討厭的人扣得多、喜歡的人扣得少),冷卻 20 分鐘。
const PESTER_COOLDOWN := 1200.0
static func pestered(invitee: Node, inviter: Node) -> void:
	var level: int = invitee.pet_affinity(inviter)
	bond(invitee, inviter, -loss_amount(invitee, level), level, "pestered", PESTER_COOLDOWN)


## 碰撞箱接觸的累計時間:討厭的對象接觸超過 CONTACT_SECONDS 就降低好感,之後進入 CONTACT_COOLDOWN 冷卻。
static func contact_strain(self_pet: Node, other: Node, level: int) -> void:
	bond(self_pet, other, -loss_amount(self_pet, level), level, "contact", CONTACT_COOLDOWN)


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

