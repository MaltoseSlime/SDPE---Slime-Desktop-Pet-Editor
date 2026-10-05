class_name ReservedPetValues
extends RefCounted
## 系統內建、名稱固定被讀取的數值集中列表(見各自模組的 AFFINITY_KEY 等常數):管理視窗「保留數值一覽」
## 小彈窗跟數值改名提醒(ValueEditorTab._commit_key)共用同一份,之後再增加新的保留名稱只要加在這裡,
## 兩邊會自動跟著更新,不用兩處都改。
## 這份清單只是「文件/查詢用」,不是真正的讀取來源——實際讀取的常數還是各自模組自己的
## PetVitality.AFFINITY_KEY / PetBallPlay.AFFINITY_KEY,這裡的 "key" 要跟它們保持一致。

## 2026-10-05 使用者要求補齊:不是只有「真的會被 ValueGateway 字串鍵讀到」才算保留名稱,只要是桌寵身上
## 已經有固定意義、使用者可能誤以為同名的自訂數值會代表同一件事的,都要列出來提醒(即使技術上兩邊資料
## 完全獨立、不會真的互相覆蓋)。精力/心情是狀態面板(StatusPanel)直接顯示給使用者看的內建量表
## (PetVitality.energy/mood),不是透過 ValueGateway 存取,但名稱太直覺,使用者很容易以為自訂一個同名
## 數值就能拿到/影響這個量表,其實兩者完全無關。性格分頁其餘的身體調校參數(疲勞速率、各種門檻、原地小跳
## 機率…)都是用英文代號的滑桿欄位,沒有單一個簡短中文詞彙會被拿來當自訂數值名稱,暫時不列;之後如果有
## 哪個欄位也被使用者誤會,比照這裡的做法加進來就好。
const ENTRIES: Array[Dictionary] = [
	{"key": "好感度", "en": "Affinity", "effect": "使用者對這隻桌寵的好感度:決定心情基準與心情升降速度(PetVitality),也是玩球時使用者參與回饋會加的那個數值(PetBallPlay)。"},
	{"key": "精力", "en": "Energy", "effect": "桌寵目前的精力(PetVitality.energy),狀態面板的精力條直接顯示這個值,決定會不會喊累、要不要休息。不是透過自訂數值系統存取,自訂一個同名數值不會影響它,也不會被它影響,純粹是名稱容易搞混。"},
	{"key": "心情", "en": "Mood", "effect": "桌寵目前的心情(PetVitality.mood,0~100),狀態面板的心情條直接顯示這個值,決定偏開心還是偏生氣。不是透過自訂數值系統存取,自訂一個同名數值不會影響它,也不會被它影響,純粹是名稱容易搞混。"},
]


static func keys() -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in ENTRIES:
		result.append(str(entry.get("key", "")))
	return result


static func is_reserved(key: String) -> bool:
	return keys().has(key)


static func entry_of(key: String) -> Dictionary:
	for entry: Dictionary in ENTRIES:
		if str(entry.get("key", "")) == key:
			return entry
	return {}
