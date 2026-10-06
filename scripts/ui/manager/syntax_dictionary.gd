class_name SyntaxDictionary
extends RefCounted
## 對話文字語法字典:氣泡樣式(BBCode)、數值與名字標記、單字池、遊戲結果等所有能寫在台詞裡的語法,一處列完。
## 給 Godot 的性格編輯器與網頁編輯器的「語法字典」共用(網頁那份寫在 slime-pet-editor.html 的 SYNTAX_DICTIONARY,內容要保持一致)。
## 每筆:{category, syntax(可以直接插入的範例), meaning(意思)}。

const ENTRIES: Array[Dictionary] = [
	{"category": "文字樣式", "syntax": "[b]粗體[/b]", "meaning": "粗體"},
	{"category": "文字樣式", "syntax": "[i]斜體[/i]", "meaning": "斜體"},
	{"category": "文字樣式", "syntax": "[u]底線[/u]", "meaning": "底線"},
	{"category": "文字樣式", "syntax": "[s]刪除線[/s]", "meaning": "刪除線"},
	{"category": "文字樣式", "syntax": "[color=#ff8080]紅字[/color]", "meaning": "文字顏色(#RRGGBB)"},
	{"category": "文字樣式", "syntax": "[font_size=24]大字[/font_size]", "meaning": "文字大小"},
	{"category": "文字樣式", "syntax": "[wave]波浪[/wave]", "meaning": "波浪起伏的文字"},
	{"category": "文字樣式", "syntax": "[shake]抖動[/shake]", "meaning": "抖動的文字"},
	{"category": "文字樣式", "syntax": "[rainbow]彩虹[/rainbow]", "meaning": "彩虹漸層"},
	{"category": "文字樣式", "syntax": "[pulse]脈動[/pulse]", "meaning": "忽明忽暗的脈動"},
	{"category": "文字樣式", "syntax": "[center]置中[/center]", "meaning": "置中對齊"},
	{"category": "文字樣式", "syntax": "[right]靠右[/right]", "meaning": "靠右對齊"},
	{"category": "文字樣式", "syntax": "[lb]", "meaning": "顯示一個字面的 [ (跳脫;[rb] 是 ])"},
	{"category": "文字樣式", "syntax": "\\n", "meaning": "換行(兩個字元:反斜線加 n)"},
	{"category": "數值", "syntax": "{好感度}", "meaning": "數值的小圖示 + 目前的值(名稱要和數值定義一樣)"},
	{"category": "數值", "syntax": "{num:好感度}", "meaning": "只顯示數值"},
	{"category": "關鍵詞", "syntax": "{tag:愛好}", "meaning": "從標籤是「愛好」的關鍵詞裡隨機挑一個(桌寵與使用者兩份都算);沒有這個標籤的詞就是空字串。標籤清單見關鍵詞庫的下拉選單"},
	{"category": "關鍵詞", "syntax": "{pref:3}", "meaning": "好惡等級 -3~3 的對象名字(-3 超級討厭、-2 討厭、-1 有點討厭、0 普通、1 有點喜歡、2 喜歡、3 超級喜歡)。等級清單用逗號分開:{pref:1,2,3}。0 = 在場的普通桌寵;其他等級可以不在場(用好惡設定裡的名字)。跟好感度高低無關"},
	{"category": "關鍵詞", "syntax": "{liked}", "meaning": "好惡等級 1~3(有點喜歡、喜歡、超級喜歡)的對象名字,隨機一個。等級可以指定:{liked:1,2} = 有點喜歡與喜歡;沒有就是空字串(對象不在場也說得出名字)"},
	{"category": "關鍵詞", "syntax": "{tag:user:愛好|pet:食物}", "meaning": "標籤引用可以列多個,用 | 分開;user: 只看使用者的詞、pet: 只看桌寵的詞,不寫就兩份都算"},
	{"category": "關鍵詞", "syntax": "{neutral}", "meaning": "好惡等級 0(普通)的在場桌寵名字,隨機一個;跟好感度高低無關。沒有就是空字串"},
	{"category": "關鍵詞", "syntax": "{you}", "meaning": "好感度 <100 時是「你」,≥100 時換成使用者的稱呼(話題句沒有寫 {user} 時用它)"},
	{"category": "關鍵詞", "syntax": "{disliked}", "meaning": "好惡等級 -1~-3(有點討厭、討厭、超級討厭)的對象名字,隨機一個。等級可以指定:{disliked:-2,-3} = 討厭與超級討厭;沒有就是空字串"},
	{"category": "數值", "syntax": "{pet_favor:辨識代號}", "meaning": "這隻桌寵對指定桌寵的好感度(-500~1000,取整數;沒記錄 = 0)。積木「改變對桌寵的好感度」/「對桌寵的好感度比較」增減與判斷同一個數值"},
	{"category": "數值", "syntax": "{icon:好感度}", "meaning": "只顯示小圖示"},
	{"category": "名字與稱呼", "syntax": "{self}", "meaning": "自己的名字"},
	{"category": "名字與稱呼", "syntax": "{other}", "meaning": "對象的名字(最近互動的那一位;沒有就是「對方」)"},
	{"category": "名字與稱呼", "syntax": "{opponent}", "meaning": "對手的名字(猜拳/拚骰/邀請對戰時)"},
	{"category": "名字與稱呼", "syntax": "{winner}", "meaning": "贏家的名字"},
	{"category": "名字與稱呼", "syntax": "{loser}", "meaning": "輸家的名字"},
	{"category": "名字與稱呼", "syntax": "{inviter}", "meaning": "發起挑戰的人(自己被邀請時)"},
	{"category": "名字與稱呼", "syntax": "{invitee}", "meaning": "被自己邀請的人"},
	{"category": "名字與稱呼", "syntax": "{user}", "meaning": "使用者的稱呼(交互行為分頁設定,可以填好幾個逗號分隔、每次隨機挑一個;預設是「使用者」)"},
	{"category": "名字與稱呼", "syntax": "{user|朋友}", "meaning": "使用者的稱呼,還沒自訂過(還是預設「使用者」)時顯示「朋友」"},
	{"category": "隨機", "syntax": "{pick:甲|乙|丙}", "meaning": "單字池:夾在句子裡,每次隨機挑一個字(不能再放 { })"},
	{"category": "隨機", "syntax": "第一句|第二句|第三句", "meaning": "用在「隨機說一句」積木:用 | 隔開的整句備選(性格檔的 say 是陣列)"},
	{"category": "關鍵詞庫", "syntax": "{keyword}", "meaning": "這隻角色的關鍵詞庫(桌寵管理 → 性格)裡隨機挑一個;每次出現各自隨機"},
	{"category": "關鍵詞庫", "syntax": "{keyword|某件事}", "meaning": "同上;關鍵詞庫是空的時顯示「某件事」(預設是「某個東西」)"},
	{"category": "關鍵詞庫", "syntax": "{keyword:user}", "meaning": "「使用者有興趣的」關鍵詞庫裡隨機挑一個(桌寵想更了解你時學到的);{keyword:pet} = 桌寵有興趣的(等於 {keyword}),{kw:user:1} 是使用者那份洗牌後的第 1 個"},
	{"category": "關鍵詞庫", "syntax": "{kw:1}", "meaning": "這個事件洗牌後的第 1 個關鍵詞;{kw:1}~{kw:9} 在同一個事件(含對話與選項)裡各不相同,適合做四個選項都是答案的題目"},
	{"category": "關鍵詞庫", "syntax": "{kw:2|某件事}", "meaning": "第 2 個關鍵詞,庫是空的時顯示「某件事」"},
	{"category": "特效", "syntax": "{fx:hearts}", "meaning": "[幸福] 這句話出現時,讓角色身邊噴出一團小愛心(標記本身不顯示;{fx:名稱|秒數} 可以指定持續幾秒)"},
	{"category": "特效", "syntax": "{fx:heart_big}", "meaning": "[愛意] 頭上冒出一個大愛心"},
	{"category": "特效", "syntax": "{fx:vein}", "meaning": "[青筋] 頭上冒出紅色的 # 形青筋"},
	{"category": "特效", "syntax": "{fx:flame}", "meaning": "[惱怒] 頭上冒出一小團火"},
	{"category": "特效", "syntax": "{fx:confused}", "meaning": "[心煩意亂] 頭部右上方三條抖動的鋸齒線"},
	{"category": "特效", "syntax": "{fx:sweat}", "meaning": "[冒汗] 額頭兩側甩出幾滴汗"},
	{"category": "特效", "syntax": "{fx:sparkle}", "meaning": "[閃閃發光] 角色四周閃出黃色小星芒"},
	{"category": "特效", "syntax": "{fx:flowers}", "meaning": "[心花怒放] 冒出一朵朵小花"},
	{"category": "特效", "syntax": "{fx:glow}", "meaning": "[全身發光] 沿著角色的形狀往四周泛出柔和的光"},
	{"category": "特效", "syntax": "{fx:afterimage}", "meaning": "[移動殘影] 移動時留下殘影(要角色在動才看得到)"},
	{"category": "特效", "syntax": "{fx:foam}", "meaning": "[肥皂泡] 角色身上與四周冒出較大的泡沫"},
	{"category": "特效", "syntax": "{fx:sleepy}", "meaning": "[睏倦] 頭旁邊慢慢飄一兩顆小氣泡"},
	{"category": "特效", "syntax": "{fx:gloom}", "meaning": "[憂愁] 角色背後一圈淡淡的藍色圓暈"},
	{"category": "特效", "syntax": "{fx:cry}", "meaning": "[哭泣] 從眼睛附近零零散散撒出小水滴"},
	{"category": "特效", "syntax": "{fx:sweat|4}", "meaning": "冒汗特效持續 4 秒(1~60 秒)"},
	{"category": "文字變數", "syntax": "{text:nickname}", "meaning": "使用者輸入或抽籤存下的文字變數"},
	{"category": "文字變數", "syntax": "{text:nickname|你}", "meaning": "文字變數,還沒有值時顯示「你」"},
	{"category": "遊戲結果", "syntax": "{roll:roll}", "meaning": "擲骰的點數({roll:名稱})"},
	{"category": "遊戲結果", "syntax": "{contest:mine}", "meaning": "拚骰:我的點數"},
	{"category": "遊戲結果", "syntax": "{contest:best}", "meaning": "拚骰:最高點數"},
	{"category": "遊戲結果", "syntax": "{contest:winner}", "meaning": "拚骰:贏家名字"},
	{"category": "遊戲結果", "syntax": "{contest:score}", "meaning": "拚骰:這一場比數(我:最高的對手)"},
	{"category": "遊戲結果", "syntax": "{contest:rounds}", "meaning": "拚骰:打了幾局"},
	{"category": "遊戲結果", "syntax": "{rps:mine}", "meaning": "猜拳:我出的"},
	{"category": "遊戲結果", "syntax": "{rps:theirs}", "meaning": "猜拳:對方出的"},
	{"category": "遊戲結果", "syntax": "{rps:opponent}", "meaning": "猜拳:對手名字"},
	{"category": "遊戲結果", "syntax": "{rps:score}", "meaning": "猜拳:這一場比數(我:對方)"},
	{"category": "遊戲結果", "syntax": "{rps:rounds}", "meaning": "猜拳:打了幾局"},
	{"category": "戰績", "syntax": "{stats:rps:rate}", "meaning": "猜拳勝率(帶 % 號)"},
	{"category": "戰績", "syntax": "{stats:rps:win}", "meaning": "猜拳勝場數(win / lose / tie / total / rate)"},
	{"category": "戰績", "syntax": "{stats:dice:rate}", "meaning": "拚骰勝率"},
	{"category": "戰績", "syntax": "{stats:all:total}", "meaning": "所有小遊戲的總場數(種類 rps / dice / all)"},
]


static func categories() -> Array[String]:
	var result: Array[String] = []
	for entry in ENTRIES:
		if not result.has(str(entry["category"])):
			result.append(str(entry["category"]))
	return result


## 依搜尋字(語法或意思含有,大小寫不分)與類別過濾;類別空字串 = 全部。
static func find(query: String, category := "") -> Array[Dictionary]:
	var wanted := query.strip_edges().to_lower()
	var result: Array[Dictionary] = []
	for entry in ENTRIES:
		if category != "" and str(entry["category"]) != category:
			continue
		if wanted == "" or str(entry["syntax"]).to_lower().contains(wanted) or str(entry["meaning"]).to_lower().contains(wanted) or str(entry["category"]).to_lower().contains(wanted):
			result.append(entry)
	return result
