class_name TarotDeck
extends RefCounted
## 塔羅牌占卜用的大阿爾克那牌組(22 張)。只負責抽牌跟正逆位,刻意不解讀(使用者明確要求)。
## 2026-10-04 改版:抽牌流程多了「選牌」步驟(見 TarotPickBoard)——先洗好整副牌(含正逆位),使用者在
## 選牌視窗點選牌背,選到哪個位置就翻開這個陣列裡對應位置的那張,不是另外再抽一次。

const MAJOR_ARCANA: Array[String] = [
	"愚者", "魔術師", "女祭司", "皇后", "皇帝", "教皇", "戀人", "戰車", "力量", "隱者",
	"命運之輪", "正義", "吊人", "死神", "節制", "惡魔", "高塔", "星星", "月亮", "太陽", "審判", "世界",
]


## 洗好的整副牌(22 張不重複,各自隨機正逆位),依洗好的順序排列,給選牌視窗當底牌用。
static func shuffled_deck() -> Array[Dictionary]:
	var pool := MAJOR_ARCANA.duplicate()
	pool.shuffle()
	var result: Array[Dictionary] = []
	for card_name: String in pool:
		result.append({"name": card_name, "reversed": randf() < 0.5})
	return result


## 正逆位的括號說明文字,例如「(正位)」「(逆位)」;不用 tr() 包,跟卡牌名稱一樣交給 Control 的自動翻譯
## (翻譯表裡登記這兩個字面字串即可)。
static func orientation_text(reversed: bool) -> String:
	return "(逆位)" if reversed else "(正位)"
