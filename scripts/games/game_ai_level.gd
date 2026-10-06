class_name GameAiLevel
extends RefCounted
## 井字棋/步步為營/珠璣妙算三個遊戲共用的「AI 強度」等級換算(使用者要求「同一套分級機制三個遊戲一起套用,
## 不要做三套不同的」)。1~4 級,數字愈小愈容易犯錯/隨便選,愈大愈接近「一定選目前看起來最好的那個」。
## 4 級 = 完全不犯錯(跟三個遊戲原本寫死的行為一致);預設 3 級(步步為營/珠璣妙算原本就有 20% 隨機成分,
## 维持原汁原味,井字棋原本是完全不犯錯,套這個預設後會偶爾犯錯,正好對應「桌寵對戰常常一路平局」的原始抱怨)。
## 三個遊戲各自把這個等級換成「犯錯機率」套進自己的決策邏輯(`_ai_move`/`get_best_action`/`_pet_guess`),
## 不是同一個決策演算法,只共用這一個「等級 → 機率」對照表跟右鍵選單/設定卡片的文字。

const CHOICES: Array[int] = [1, 2, 3, 4]
const NAMES := {1: "隨性", 2: "普通", 3: "用心", 4: "全力"}
const DEFAULT_LEVEL := 3


static func mistake_chance(level: int) -> float:
	match level:
		1:
			return 0.6
		2:
			return 0.35
		3:
			return 0.2
		_:
			return 0.0


## 好惡影響對弈的 AI 等級(2026-10-06 使用者要求)。每場對戰開頭擲一次(不是每一步擲,免得機率疊起來失真):
## 討厭對手的那方(pet_affinity < 0)有低機率臨時把自己的等級調高一級去擊潰對方;超級喜歡對手(= 3)的那方
## 有低機率調低一級放水讓對方贏。等級不會因此超出 CHOICES 的範圍。
const DISLIKE_BUMP_CHANCE_PER_LEVEL := 0.05
const LIKE_THROW_CHANCE := 0.1


static func match_level(pet: Node, opponent: Node, base: int) -> int:
	var level := clamp_level(base)
	if pet == null or opponent == null or not pet.has_method("pet_affinity"):
		return level
	var affinity: int = pet.pet_affinity(opponent)
	if affinity < 0 and randf() < DISLIKE_BUMP_CHANCE_PER_LEVEL * float(-affinity):
		return mini(level + 1, CHOICES.back())
	if affinity >= 3 and randf() < LIKE_THROW_CHANCE:
		return maxi(level - 1, CHOICES.front())
	return level


static func clamp_level(level: int) -> int:
	return level if CHOICES.has(level) else DEFAULT_LEVEL
