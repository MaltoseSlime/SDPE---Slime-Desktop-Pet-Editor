class_name GameInvite
extends RefCounted
## 桌寵閒置時自己發起的小遊戲邀請(猜拳/拚骰):邀請者先在氣泡裡發出邀請,被邀請的桌寵依當下狀況決定要不要接受。
## 拒絕機率見 Pet.game_refusal():睡覺必定拒絕,忙(跳舞、被互動、對話中、爬牆…)或負面狀態(生氣、疲勞、悲傷…)機率更高。
## 只有「自己發起」的邀請會被拒絕;使用者從右鍵選單叫的遊戲、積木寫的遊戲都不受影響。全程只用對話氣泡,不開視窗。

## 邀請的話一律是「先叫對方的名字、再問他要不要」(名字由 invite 加在前面)。
const INVITE_LINES := {
	"rps": ["要不要來玩剪刀石頭布?", "要不要跟我猜個拳?", "無聊耶……來猜拳好不好?"],
	"dice": ["要不要來拚骰子,比誰的點數大?", "要不要擲骰子比一場?", "要不要跟我賭一把運氣?"],
}
const GAME_NAMES := {"rps": "猜拳", "dice": "拚骰"}
const GROUP_LINES: Array[String] = ["要不要一起拚骰子,比誰的點數大?", "要不要一起擲骰子比一場?"]
const ACCEPT_LINES: Array[String] = ["好啊,來吧!", "嘿嘿,奉陪!", "來就來,誰怕誰!"]
const REFUSE_LINES := {
	"sleep": ["(zzZ……)", "……呼……(睡得很沉)"],
	"busy": ["現在沒空啦!", "等一下再說~", "我正忙著呢!"],
	"mood": ["沒心情……", "現在不想玩。", "……別來煩我。"],
	"plain": ["這次就算了吧~", "不要,我不想玩。", "下次吧!"],
	"declined": ["不玩。", "別找我對戰啦。", "我不跟人比這個。"],
}
const DECLINED_LINES: Array[String] = ["(被拒絕了……)", "嘖,好吧。", "那下次再約囉。"]


## 隨機挑場上一隻別的桌寵和一種遊戲,發起邀請(不等它結束)。沒有合適的對象回 false。
## 賽制由邀請者自己決定(Pet.pick_invite_best_of,不看右鍵選單的「賽制」);設了「一律拒絕對戰邀請」的桌寵不會被自動挑來邀請(反正必被拒)。
static func start_random(inviter: Node) -> bool:
	var candidates: Array = inviter.get_tree().get_nodes_in_group("pets").filter(
		func(p: Node) -> bool: return p != inviter and not p.is_queued_for_deletion() and not p.entering and not p.game_always_refuse)
	if candidates.is_empty():
		return false
	invite(inviter, candidates.pick_random(), "rps" if randf() < 0.5 else "dice", inviter.pick_invite_best_of())
	return true


static func _wait(pet: Node, seconds: float) -> void:
	await pet.get_tree().create_timer(seconds).timeout


static func _cancelled(inviter: Node, invitee: Node, generations: Dictionary) -> bool:
	return not is_instance_valid(inviter) or not is_instance_valid(invitee) \
			or inviter.action_generation != generations[inviter] or invitee.action_generation != generations[invitee]


## 被邀請者有符合的「被邀請對戰」積木事件(event_when_game_invited)就跑它、回傳 true(內建那句台詞就不說);沒有回 false。
static func _invitee_event(invitee: Node, inviter: Node, kind: String, answer: String) -> bool:
	if invitee.logic == null:
		return false
	return await invitee.logic.run_invite_hats(kind, answer, str(inviter.recognition_tag))


## 內建台詞有一半的機率帶上對方的名字(「小綠,來玩剪刀石頭布吧!」),不然每次都叫名字太吵。
static func _maybe_named(line: String, person_name: String) -> String:
	return "%s,%s" % [person_name, line] if person_name != "" and randf() < 0.5 else line


## 邀請 → 對方決定 → 接受就開始遊戲、拒絕就各說一句。kind = rps / dice。
## best_of:賽制 1 / 3 / 5(邀請時會說出來),其他值(0)= 用邀請者右鍵選單的「賽制」。wait_game:接受後等整場打完才回來(給積木語句用;自動邀請不等)。
## custom_line 非空 = 用它當邀請的話(已經展開過 {self}、{other} 之類的標記),不用內建台詞。
## 開始前先替雙方記下對象(邀請者、被邀請者、對手),被邀請者的事件與台詞可以用「當對象是 XX」條件與 {other} 叫出邀請者的名字。
## 回傳 {accepted, reason};中途被打斷回空字典。
static func invite(inviter: Node, invitee: Node, kind: String, best_of := 0, wait_game := false, custom_line := "") -> Dictionary:
	if not is_instance_valid(inviter) or not is_instance_valid(invitee) or inviter == invitee:
		return {}
	# 對戰進行到一半時別的邀請進不來:自己還在打就直接作廢;對方在打,邀請者被擋下並在心裡想一句。
	if inviter.is_in_game():
		return {}
	if invitee.is_in_game():
		GameChat.think_blocked(inviter, invitee, TranslationServer.translate(str(GAME_NAMES.get(kind, "遊戲"))))
		return {"accepted": false, "reason": "in_game"}
	var generations := {inviter: inviter.action_generation, invitee: invitee.action_generation}
	if not inviter.BEST_OF_CHOICES.has(best_of):
		best_of = inviter.game_best_of
	inviter.turn_toward(invitee.global_position.x)
	inviter.set_counterpart("invitee", invitee)
	inviter.set_counterpart("opponent", invitee)
	invitee.set_counterpart("inviter", inviter)
	invitee.set_counterpart("opponent", inviter)
	var invite_line := custom_line if custom_line != "" else "%s,%s" % [invitee.get_label(), inviter.speak_tr(str((INVITE_LINES[kind] as Array).pick_random()))]
	if best_of > 1:
		invite_line += "(%s)" % inviter.BEST_OF_NAMES[best_of]
	GameChat.say(inviter, invite_line, 2.4)
	await _wait(inviter, 1.8)
	if _cancelled(inviter, invitee, generations):
		return {}
	if invitee.vitality != null:
		invitee.vitality.note_invited()
	var refusal: Dictionary = invitee.game_refusal()
	if randf() < float(refusal["chance"]):
		var reason := str(refusal["reason"])
		if await _invitee_event(invitee, inviter, kind, "refuse"):
			await _wait(inviter, 0.5)
		else:
			GameChat.say(invitee, invitee.speak_tr(str((REFUSE_LINES[reason] as Array).pick_random())), 2.4)
			await _wait(inviter, 1.6)
		if _cancelled(inviter, invitee, generations):
			return {}
		if reason != "sleep":
			GameChat.say(inviter, inviter.speak_tr(str(DECLINED_LINES.pick_random())), 2.2)
		return {"accepted": false, "reason": reason}
	invitee.turn_toward(inviter.global_position.x)
	if await _invitee_event(invitee, inviter, kind, "accept"):
		await _wait(inviter, 0.5)
	else:
		GameChat.say(invitee, _maybe_named(invitee.speak_tr(str(ACCEPT_LINES.pick_random())), str(inviter.display_name)), 1.6)
		await _wait(inviter, 1.3)
	if _cancelled(inviter, invitee, generations):
		return {}
	if wait_game:
		if kind == "rps":
			await inviter.start_rps_with(invitee, best_of)
		else:
			await inviter.start_dice_contest([invitee], best_of)
	elif kind == "rps":
		inviter.start_rps_with(invitee, best_of)
	else:
		inviter.start_dice_contest([invitee], best_of)
	return {"accepted": true, "reason": ""}

## 一次邀請場上所有別的桌寵拚骰(右鍵選單「跟場上所有桌寵」):先叫出每個人的名字問要不要;任何一隻正在對戰中就被擋下;
## 各自決定接不接受(見 Pet.game_refusal),接受的人才一起比,全都拒絕就作罷。不等整場打完。回傳 {accepted, joined: [桌寵], reason}。
static func invite_all_dice(inviter: Node, best_of := 0) -> Dictionary:
	if not is_instance_valid(inviter) or inviter.is_in_game():
		return {}
	var others: Array = inviter.get_tree().get_nodes_in_group("pets").filter(
		func(p: Node) -> bool: return p != inviter and not p.is_queued_for_deletion() and not p.entering)
	if others.is_empty():
		GameChat.say(inviter, inviter.speak_tr("場上沒有別的桌寵可以一起玩……"), 2.5)
		return {}
	for other: Node in others:
		if other.is_in_game():
			GameChat.think_blocked(inviter, other, TranslationServer.translate("拚骰"))
			return {"accepted": false, "reason": "in_game", "joined": []}
	var generation: int = inviter.action_generation
	var names: Array[String] = []
	for other: Node in others:
		names.append(str(other.get_label()))
	var address: String = "、".join(names) if names.size() <= 3 else TranslationServer.translate("大家")
	GameChat.say(inviter, "%s,%s" % [address, inviter.speak_tr(str(GROUP_LINES.pick_random()))], 2.6)
	await _wait(inviter, 1.9)
	if not is_instance_valid(inviter) or inviter.action_generation != generation:
		return {}
	var joined: Array = []
	for other: Node in others:
		if not is_instance_valid(other):
			continue
		if other.vitality != null:
			other.vitality.note_invited()
		var refusal: Dictionary = other.game_refusal()
		if randf() < float(refusal["chance"]):
			GameChat.say(other, other.speak_tr(str((REFUSE_LINES[str(refusal["reason"])] as Array).pick_random())), 2.2)
		else:
			joined.append(other)
			GameChat.say(other, other.speak_tr(str(ACCEPT_LINES.pick_random())), 1.6)
	await _wait(inviter, 1.5)
	if not is_instance_valid(inviter) or inviter.action_generation != generation:
		return {}
	if joined.is_empty():
		GameChat.say(inviter, inviter.speak_tr(str(DECLINED_LINES.pick_random())), 2.2)
		return {"accepted": false, "reason": "declined", "joined": []}
	inviter.start_dice_contest(joined, best_of)
	return {"accepted": true, "reason": "", "joined": joined}
