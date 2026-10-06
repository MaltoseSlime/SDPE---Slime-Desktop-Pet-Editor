class_name PetBallPlay
extends Node
## 桌寵玩球(掛在 Pet 底下):場上有圓球道具(def.shape == "ball")時,有興趣的桌寵會去追球,碰到球就「拋球」(往上往旁邊踢出去)或「頂球」(把球頂在頭頂——判定框頭頂位置——一小段時間再往上拋);
## 玩一陣子(或碰球次數夠了)就沒興趣,休息一段時間才會再玩。
## 加不加入:Pet.ball_play_chance(性格參數「玩球意願」,每秒起玩的機率,0 = 不會)、心情不好(有負面狀態鏡)、睡著、忙著、被拖曳時都不加入;
## 對這顆球的個別設定是「不喜歡」或「不與此道具交互」也不玩。使用者把球丟過來(放開球)時,有興趣的桌寵有 75% 機率立刻跟著玩(不受休息時間限制)。
## 使用者參與(最近 USER_WINDOW_MSEC 內抓過、丟過這顆球)時,桌寵碰球會得到好感度回饋(每 REWARD_INTERVAL 秒一次:好感度 +1、心情變好、冒小愛心)。
## 對話:玩球的各個時刻會發出性格的「反應」事件(Pet.logic.fire_event):ball_found 發現球(自己起玩)、ball_invite 邀請別隻桌寵(桌寵之間才有)、ball_join 答應加入(被邀請或使用者丟球)、
## ball_decline 不參與(被邀請但沒興趣或心情不好)、ball_playing 玩球中、ball_end 結束玩球、ball_watch 看到別隻在玩自己沒加入。所有玩球對話共用一個冷卻(SAY_COOLDOWN),不會連珠炮。
## 場上有很多顆球時,進入玩球狀態的桌寵會一直去頂離自己最近的球(碰到任何一顆都算),不會只顧一顆;
## 但發現球、邀請別隻的對話不會因為球多而重複:發現球的話有 FOUND_COOLDOWN 冷卻、全場的邀請共用 GROUP_INVITE_COOLDOWN 冷卻,而且被邀請時婉拒過的桌寵有 DECLINE_PROTECT 秒不會再被問。
## 玩球期間球不計自動消失(見 PropItem.mark_played);玩的時候桌寵的移動目標就是球(Pet._secondary_goal)。

const SCAN_SECONDS := 0.7
const REACH_X := 34.0
const MAX_PLAY_SECONDS := 40.0
const MAX_TOUCHES := 8
const COOLDOWN := Vector2(25.0, 50.0)
const BALANCE_SECONDS := Vector2(1.6, 3.6)
const USER_WINDOW_MSEC := 10000
const REWARD_INTERVAL := 8.0
const BALANCE_CHANCE := 0.45
const INVITE_CHANCE := 0.75
const AFFINITY_KEY := "好感度"
## 玩球時使用者碰過球的好感度獎勵量(目前固定 +1),跟「滿強度」所需的量,兩者的比值就是愛心特效的強度。
const REWARD_AFFINITY_GAIN := 1.0
const REWARD_AFFINITY_FULL := 2.0
const SAY_COOLDOWN := 7.0
const INVITE_COOLDOWN := 300.0
## 全場任何桌寵發出邀請後,這麼久之內沒有別的桌寵再發邀請(2026-10-06 使用者要求:發出過邀請就給明確的 5 分鐘,
## 不會 A 邀請後馬上換 B 邀請)。
const GROUP_INVITE_COOLDOWN := 300.0
## 婉拒玩球邀請之後,這麼多秒內不會再被邀請(2026-10-06 使用者要求:5 分鐘)。
const DECLINE_PROTECT := 300.0
## 「發現球」的對話最短間隔(不論場上有幾顆球)。
const FOUND_COOLDOWN := 120.0
## 全場最後一次發邀請的時間(msec)。
static var _last_group_invite_msec := -1000000
## 好幾隻桌寵幾乎同時發現同一顆球時(各自的掃描間隔剛好都到),只有最先的那隻說「發現球」,
## 這段時間內其他隻不再重複說(但還是照常開始玩),免得對話框一次跳出一大排洗版畫面。
const FOUND_GROUP_COOLDOWN := 6.0
static var _last_found_group_msec := -1000000
const WATCH_COOLDOWN := 45.0
const PLAYING_SAY_COOLDOWN := 22.0

var ball: PropItem
## 空 = 沒在玩;chase = 追球中;balance = 球頂在頭上。
var state := ""
var _pet: Node
var _timer := 0.0
var _balance_left := 0.0
var _touches := 0
var _cooldown := 0.0
var _scan_left := 0.0
var _contact_cooldown := 0.0
var _reward_left := 0.0
var _wobble := 0.0
var _say_left := 0.0
var _invite_left := 0.0
var _watch_left := 0.0
var _playing_say_left := 0.0
var _retarget_left := 0.0
var _decline_protect_left := 0.0
var _found_left := 0.0


func setup(pet: Node) -> void:
	_pet = pet


## 現在想不想玩:ongoing = 已經在玩了(踢球後動作短暫佔用不算忙)。
func interested(ongoing := false) -> bool:
	return _pet.ball_play_chance > 0.0 and not _pet.lens_blocks("ball") and not _pet.is_sleeping() and not _pet.entering and not _pet.dragging \
			and _pet.is_ground_mode() and (ongoing or not _pet.is_busy_for_game())


func active() -> bool:
	return state != ""


## 現在能不能被邀請玩球(婉拒過的有保護冷卻)。
func invitable() -> bool:
	return state == "" and _decline_protect_left <= 0.0


## 場上所有這隻桌寵願意玩的球。
func _wanted_balls() -> Array[PropItem]:
	var result: Array[PropItem] = []
	for node: Node in get_tree().get_nodes_in_group("props"):
		var item := node as PropItem
		if item != null and _wants(item):
			result.append(item)
	return result


func _nearest_ball(limit := 1200.0) -> PropItem:
	var best := limit
	var chosen: PropItem = null
	for item: PropItem in _wanted_balls():
		var distance: float = _pet.global_position.distance_to(item.global_position)
		if distance < best:
			best = distance
			chosen = item
	return chosen


## 追球時的移動目標(行動區座標);沒有回 null。
## 追球時的目標球即使正被使用者拖著也還算數(桌寵會一路跟到手邊,這是使用者想跟桌寵搶球玩的正常情境,
## 不是「球不見了」);真的不要拖著玩的地方(挑新目標、發起邀請)另外呼叫 _wants() 不給 allow_dragging。
func goal() -> Variant:
	if state != "chase" or not is_instance_valid(ball):
		return null
	return _pet.get_parent().to_local(ball.global_position) if _pet.get_parent() is Node2D else ball.global_position


## allow_dragging = true:正在玩的這顆球被使用者拿起來也還算「想要」(用來判斷「目前已經在追/頂的這顆球還算不算數」);
## 預設 false 給「要不要挑這顆當新目標」用的地方(場上候選清單、邀請),不主動衝去追使用者正拿在手上的球。
func _wants(item: PropItem, allow_dragging := false) -> bool:
	if item == null or item.def == null or item.def.shape != "ball" or item.consuming or item.collected:
		return false
	if item.dragging and not allow_dragging:
		return false
	if item.carried_by != null and item.carried_by != _pet:
		return false
	return not (["ignore", "dislike"] as Array).has(_pet.prop_preference(item.def))


## 發一個玩球的對話事件(共用冷卻);回傳有沒有發。
func _say(event: StringName, force := false) -> bool:
	if _pet.is_sleeping() or _pet.entering or _pet.dragging or (_say_left > 0.0 and not force) or _pet.logic == null:
		return false
	_say_left = SAY_COOLDOWN
	_pet.logic.fire_event(event)
	return true


## 使用者把球丟出來(或放開)時呼叫:有興趣的桌寵有機率立刻加入。回傳有沒有加入。
func invite(item: PropItem) -> bool:
	if state != "" or not _wants(item) or not interested() or randf() >= INVITE_CHANCE:
		return false
	_begin(item)
	_say(&"ball_join", true)
	return true


## 別隻桌寵邀請一起玩(只發生在桌寵與桌寵之間):有興趣就加入(說「加入」),否則婉拒(說「不參與」)。回傳有沒有加入。
## 「遊戲與對戰」設定卡片的「一律接受/一律拒絕」(game_force_accept/game_force_decline,鍵 "ball")優先於
## 下面原本依 ball_play_chance 算的機率,跟 Pet.game_refusal() 的 kind 覆寫同一套道理。
func receive_invite(item: PropItem) -> bool:
	if state != "" or _pet.is_sleeping() or _pet.entering or not _wants(item):
		return false
	if bool(_pet.game_force_decline.get("ball", false)):
		_say(&"ball_decline", true)
		_decline_protect_left = DECLINE_PROTECT
		return false
	if _pet.vitality != null:
		_pet.vitality.note_invited()
	if bool(_pet.game_force_accept.get("ball", false)) or (interested() and randf() < 0.35 + minf(_pet.ball_play_chance * 3.0, 0.6)):
		_begin(item)
		_say(&"ball_join", true)
		return true
	_say(&"ball_decline", true)
	_decline_protect_left = DECLINE_PROTECT
	return false


## 自己發現球起玩之後,邀請場上其他桌寵(隔 1.5 秒讓對方回應,不會兩個氣泡同時冒出來)。
## 「遊戲與對戰」設定卡片的「自動邀請」(game_auto_invite,鍵 "ball")關掉時完全不邀請別人。
func _invite_others(item: PropItem) -> void:
	if not _pet.game_auto_invite_enabled("ball"):
		return
	if _invite_left > 0.0 or Time.get_ticks_msec() - _last_group_invite_msec < int(GROUP_INVITE_COOLDOWN * 1000.0):
		return
	var others: Array = []
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != _pet and not other.is_queued_for_deletion() and other.ball_play != null and other.ball_play.invitable() and not other.is_sleeping():
			others.append(other)
	if others.is_empty():
		return
	_invite_left = INVITE_COOLDOWN
	_last_group_invite_msec = Time.get_ticks_msec()
	# 先讓「發現球」那句說完(2.8 秒),再邀請;對方再隔 1.5 秒回應,三句不會擠在一起被吃掉。
	get_tree().create_timer(2.8).timeout.connect(func() -> void:
		if state == "" or not is_instance_valid(item):
			return
		_say(&"ball_invite", true)
		get_tree().create_timer(1.5).timeout.connect(func() -> void:
			for other: Node in others:
				if is_instance_valid(other) and is_instance_valid(item) and other.ball_play != null and other.ball_play.receive_invite(item):
					break))


func _begin(item: PropItem) -> void:
	if _pet.is_following():   # 想去玩球算「想去做別的事情」,先離開路隊(見 Pet._tick_pet_follow_lifecycle 的說明)。
		_pet.stop_follow()
	ball = item
	state = "chase"
	_timer = MAX_PLAY_SECONDS
	_touches = 0
	_contact_cooldown = 0.4
	item.mark_played()


func stop() -> void:
	if is_instance_valid(ball) and ball.carried_by == _pet:
		ball.carried_by = null
	if state != "" and _touches >= 2:
		_say(&"ball_end", true)
	ball = null
	state = ""
	_cooldown = randf_range(COOLDOWN.x, COOLDOWN.y)


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_contact_cooldown = maxf(_contact_cooldown - delta, 0.0)
	_reward_left = maxf(_reward_left - delta, 0.0)
	_say_left = maxf(_say_left - delta, 0.0)
	_invite_left = maxf(_invite_left - delta, 0.0)
	_watch_left = maxf(_watch_left - delta, 0.0)
	_playing_say_left = maxf(_playing_say_left - delta, 0.0)
	_decline_protect_left = maxf(_decline_protect_left - delta, 0.0)
	_found_left = maxf(_found_left - delta, 0.0)
	if state == "":
		_scan_left -= delta
		if _scan_left <= 0.0:
			_scan_left = SCAN_SECONDS
			_maybe_start()
			_maybe_watch()
		return
	if not interested(true):
		stop()
		return
	if state == "chase":
		# 追球中每隔一下重新挑最近的一顆(球很多就一顆接一顆去頂);目標球被使用者拿起來不算「不見了」
		# (見 _wants 的 allow_dragging),桌寵會繼續跟過去,場上真的一顆能玩的都沒有才結束。
		_retarget_left -= delta
		if not is_instance_valid(ball) or not _wants(ball, true):
			ball = null
		if _retarget_left <= 0.0:
			_retarget_left = SCAN_SECONDS
			var nearest := _nearest_ball()
			if nearest != null:
				ball = nearest
		if ball == null:
			stop()
			return
	elif not is_instance_valid(ball) or not _wants(ball, true):
		stop()
		return
	elif ball.dragging:
		# 球頂在頭上時被使用者拿走:先退回追球狀態(頭上已經沒有球可以頂了),不直接結束整場玩球。
		state = "chase"
		_balance_left = 0.0
	var balls := _wanted_balls()
	for item: PropItem in balls:
		item.mark_played()
	_timer -= delta
	if _timer <= 0.0 or _touches >= MAX_TOUCHES * clampi(balls.size(), 1, 3):
		stop()
		return
	if state == "balance":
		_tick_balance(delta)
	elif _contact_cooldown <= 0.0:
		for item: PropItem in balls:
			if not item.dragging and _in_reach(item):
				ball = item
				_contact()
				break


func _maybe_start() -> void:
	if _cooldown > 0.0 or not interested() or randf() >= _pet.ball_play_chance * SCAN_SECONDS:
		return
	var chosen := _nearest_ball()
	if chosen != null and chosen.carried_by == null:
		_begin(chosen)
		var group_ready := Time.get_ticks_msec() - _last_found_group_msec >= int(FOUND_GROUP_COOLDOWN * 1000.0)
		if _found_left <= 0.0 and group_ready and _say(&"ball_found", true):
			_found_left = FOUND_COOLDOWN
			_last_found_group_msec = Time.get_ticks_msec()
		_invite_others(chosen)


## 積木「去玩球」:不擲機率、不受休息時間限制,直接去找最近的球玩(沒有球、不想玩 / 不能玩就回傳 false)。
func force_start() -> bool:
	if state != "" or not interested():
		return false
	var chosen := _nearest_ball()
	if chosen == null or chosen.carried_by != null:
		return false
	_begin(chosen)
	return true


## 場上有別隻正在玩球、自己沒加入:偶爾說一句「看到別人在玩球」。
func _maybe_watch() -> void:
	if _watch_left > 0.0 or _pet.is_sleeping() or _pet.entering or _pet.dragging or randf() > 0.25:
		return
	for other: Node in get_tree().get_nodes_in_group("pets"):
		if other != _pet and other.ball_play != null and other.ball_play.active() and _say(&"ball_watch"):
			_watch_left = WATCH_COOLDOWN
			return


func _in_reach(item: PropItem) -> bool:
	var rect: Rect2 = _pet.interaction_rect()
	var ball_position := item.global_position
	return absf(ball_position.x - rect.get_center().x) < REACH_X + rect.size.x * 0.5 and ball_position.y > rect.position.y - 36.0 and ball_position.y < rect.end.y + 40.0


func _contact() -> void:
	_touches += 1
	_contact_cooldown = 0.9
	# 使用者在道具編輯器設的「特效」(PropDef.effect):玩球是獨立的一套判定,原本沒接上,不管設什麼永遠只有
	# _reward_if_user_involved() 那個寫死的小愛心(使用者參與獎勵,語意不同,兩個各自獨立、都會播)。
	if ball != null and ball.def != null and ball.def.effect != "" and _pet.effects != null:
		_pet.effects.play(ball.def.effect)
	_reward_if_user_involved()
	_retarget_left = 0.0   # 踢出去之後馬上重新找最近的球
	if _touches >= 3 and _playing_say_left <= 0.0 and _say(&"ball_playing"):
		_playing_say_left = PLAYING_SAY_COOLDOWN
	if randf() < BALANCE_CHANCE and ball.velocity.length() < 260.0:
		state = "balance"
		_balance_left = randf_range(BALANCE_SECONDS.x, BALANCE_SECONDS.y)
		_wobble = 0.0
		ball.carried_by = _pet
		return
	var direction := signf(ball.global_position.x - _pet.global_position.x)
	if direction == 0.0:
		direction = 1.0 if randf() < 0.5 else -1.0
	ball.kick(Vector2(direction * randf_range(180.0, 380.0), -randf_range(360.0, 560.0)))   # 拋球
	_pet.turn_toward(ball.global_position.x)
	_pet.play_action_silently(&"interact", -1, true)   # 只借 interact 的動畫;不然踢球會被當成被摸(觸發被摸台詞與心情)


func _tick_balance(delta: float) -> void:
	_balance_left -= delta
	_wobble += delta
	_pet.hold_still_for(0.3)
	var rect: Rect2 = _pet.interaction_rect()
	var head := Vector2(rect.get_center().x, rect.position.y)   # 判定框頭頂
	ball.global_position = head + Vector2(sin(_wobble * 3.0) * 2.0, -absf(sin(_wobble * 5.0)) * 4.0)
	ball.velocity = Vector2.ZERO
	if _balance_left <= 0.0:
		var direction := 1.0 if randf() < 0.5 else -1.0
		ball.kick(Vector2(direction * randf_range(60.0, 200.0), -randf_range(520.0, 700.0)))   # 頂完往上拋
		state = "chase"
		_touches += 1
		_contact_cooldown = 1.2


## 使用者最近碰過這顆球:好感度 +1、心情變好、冒小愛心(每 REWARD_INTERVAL 秒最多一次)。
func _reward_if_user_involved() -> void:
	if _reward_left > 0.0 or Time.get_ticks_msec() - ball.user_touch_msec > USER_WINDOW_MSEC:
		return
	_reward_left = REWARD_INTERVAL
	# 2026-10-06:一起玩球的好感度最少量,冷卻 1 小時(數值);心情與小愛心特效照常。
	PetFavor.user_bond(_pet, "ball", PetFavor.USER_MINIMAL, PetFavor.USER_BALL_COOLDOWN)
	if _pet.vitality != null:
		_pet.vitality.change_mood(3.0)
	if _pet.effects != null:
		_pet.effects.play("hearts", 1.5, clampf(REWARD_AFFINITY_GAIN / REWARD_AFFINITY_FULL, 0.0, 1.0))

