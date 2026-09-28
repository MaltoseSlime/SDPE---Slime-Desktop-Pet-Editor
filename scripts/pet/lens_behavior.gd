class_name LensBehavior
extends RefCounted
## 內建狀態鏡的效果表:依狀態鏡的「名稱」決定生效期間桌寵的表現(名稱固定:開心、悠哉、緊張、生氣、悲傷、疲憊;性格會附上這些狀態鏡)。
## 多個狀態鏡同時生效時,倍率相乘、加成相加、阻擋任一個有就阻擋(見 Pet.lens_mod / lens_add / lens_blocks)。使用者自己另外建的狀態鏡不受這張表影響(照舊靠「覆蓋行動物理數值」)。
##
## 倍率鍵(1 = 不變):
##   speed 移動速度、jump 平時跳躍力道、gravity 重力(越大越沉重)、mood_gain / mood_loss 心情上升 / 下降幅度、fatigue 疲勞累積速度、
##   run 自己決定起跑的機率、run_duration 奔跑持續時間、dance 自己跳舞的機率、chat 自動閒聊的頻率、pause_time 停下來的時間、rest 休息的頻率、game_invite 自己邀請對戰的頻率。
## 加成鍵(0 = 沒有):game_accept 同意遊戲/對戰邀請的機率加成(降低拒絕率)、game_refuse 拒絕率加成、pause_chance 走一段後改成停一下的機率、mood_drift 每分鐘持續增減的心情點數。
## block:生效期間不做的事(climb 爬牆與天花板、dance 跳舞、run 奔跑、ball 玩球、game 遊戲與對戰);正在爬牆會回到地面。
## hasten:互動讓這個狀態更快結束——事件 → 縮短的秒數(有逾時的狀態鏡);疲憊沒有逾時,改成事件 → 恢復的精力點數。事件:touch 被摸、liked_prop 與喜歡的道具互動、prop 與任何道具互動。
## end_mood:心情走回這個範圍就解除(只有由心情門檻叫出來的狀態鏡):below_happy 心情低於「開心門檻 − 5」、above_angry 高於「生氣門檻 + 5」、above_sad 高於「悲傷門檻 + 5」、below:<數字> 低於該數字。

const TABLE := {
	"開心": {"speed": 1.08, "jump": 1.15, "gravity": 0.92, "mood_loss": 0.6, "run": 1.6, "dance": 2.0, "game_accept": 0.25, "game_invite": 1.5, "end_mood": "below_happy"},
	"悠哉": {"speed": 0.88, "mood_loss": 0.6, "run": 0.4, "dance": 2.0, "game_accept": 0.3, "chat": 1.4, "end_mood": "below_happy"},
	"緊張": {"fatigue": 1.5, "mood_gain": 0.6, "run": 1.6, "run_duration": 0.55, "game_refuse": 0.3, "hasten": {"prop": 20.0}, "end_mood": "above_angry"},
	"生氣": {"speed": 1.2, "gravity": 1.15, "run": 1.5, "mood_gain": 1.6, "mood_loss": 1.6, "game_refuse": 0.15, "hasten": {"touch": 20.0, "liked_prop": 20.0}, "end_mood": "above_angry"},
	"悲傷": {"speed": 0.9, "gravity": 1.08, "pause_time": 1.5, "pause_chance": 0.25, "mood_gain": 0.6, "game_refuse": 0.15, "hasten": {"touch": 20.0, "liked_prop": 20.0}, "end_mood": "above_sad"},
	"疲憊": {"gravity": 1.2, "pause_time": 1.8, "pause_chance": 0.4, "rest": 1.5, "chat": 0.5, "mood_loss": 1.5, "mood_drift": -5.0,
			"block": ["climb", "dance", "run", "ball", "game"], "hasten": {"liked_prop": 6.0}},
}
## 疲憊的速度倍率由精力機制的 tired_move_factor 管(見 PetVitality.speed_factor),這裡不重複乘。


## 沒有另外勾選時預設會被心情門檻叫出來的狀態鏡名稱。
const MOOD_DEFAULT_CALLABLE: Array[String] = ["開心", "悠哉", "緊張", "生氣", "悲傷"]

## 這六個內建名稱是唯一識別碼、使用者不能改(性格帶進來的),但介面語系切成英文後桌寵的對話會說英文,
## 如果手動輸入狀態鏡名稱的地方(道具/家具的「觸發時切換狀態鏡」等)也只認得到中文「疲憊」,對英文使用者
## 不友善。2026-09-28 使用者要求:只做這六個內建名稱的中英文讀取相容,不做完整的多語系別名系統
## (使用者自己建的狀態鏡沒有別名,必須用建立當下打的原文,通常是中文——這是使用者自己的決定,見管理視窗
## 「觸發時切換狀態鏡」旁的 ⓘ 說明)。Pet.enable_lens/disable_lens/is_lens_active/lens_active_seconds/
## lens_stamp/find_lens/has_lens 都在最前面呼叫 canonical_name() 正規化,之後全部照中文原名比對與儲存。
const ALIASES := {
	"happy": "開心", "relaxed": "悠哉", "nervous": "緊張", "angry": "生氣", "sad": "悲傷", "tired": "疲憊",
}


## 把英文別名換成中文原名;不認得的別名(包含使用者自己建的狀態鏡名稱)原樣傳回,不強制轉換。
static func canonical_name(name: String) -> String:
	return str(ALIASES.get(name.strip_edges().to_lower(), name))


static func of(lens_name: String) -> Dictionary:
	return TABLE.get(lens_name, {})


static func value(lens_name: String, key: String, fallback: float) -> float:
	return float((TABLE.get(lens_name, {}) as Dictionary).get(key, fallback))


static func blocks(lens_name: String, what: String) -> bool:
	return ((TABLE.get(lens_name, {}) as Dictionary).get("block", []) as Array).has(what)


static func hasten_amount(lens_name: String, event: String) -> float:
	return float(((TABLE.get(lens_name, {}) as Dictionary).get("hasten", {}) as Dictionary).get(event, 0.0))


## 心情走到這個範圍就該解除嗎(只有「被心情門檻叫出來」的狀態鏡用)。thresholds = {happy, angry, sad}。
static func mood_ended(lens_name: String, mood: float, thresholds: Dictionary, hysteresis: float, positive: bool) -> bool:
	var rule := str((TABLE.get(lens_name, {}) as Dictionary).get("end_mood", ""))
	match rule:
		"below_happy":
			return mood < float(thresholds["happy"]) - hysteresis
		"above_angry":
			return mood > float(thresholds["angry"]) + hysteresis
		"above_sad":
			return mood > float(thresholds["sad"]) + hysteresis
	if rule.begins_with("below:"):
		return mood < float(rule.trim_prefix("below:"))
	# 使用者自己建的狀態鏡:正面的比照開心、負面的比照生氣。
	return mood < float(thresholds["happy"]) - hysteresis if positive else mood > float(thresholds["angry"]) + hysteresis
