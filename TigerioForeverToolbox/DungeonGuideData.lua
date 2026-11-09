local _, toolbox = ...

-- Area identifiers are lookup keys; task data is queried from the locally
-- loaded QuestieDB, never bundled. Curated notes below are partial summaries.
local general = "https://www.wowhead.com/forever/cn/guide/dungeons/every-dungeon-quest-location"
local official = "https://wow.blizzard.cn/news/24301455/"
toolbox.dungeonGuideData = {
    {name="怒焰裂谷", zoneID=2437, url=general},
    {name="领主大厅", zoneID=16919, level="13–18", location="丹莫罗，铁炉堡地下",
        note="仅列出已核对的部分任务；阵营条件请以游戏内为准。", url="https://www.icy-veins.com/wow-forever/hall-of-thanes-quests/",
        quests={{title="旧铁炉堡入侵", questID=96393, faction="阵营条件待核实", details="先完成地下地图（Underground Map）；再到丹莫罗戈尔戈拉尔采石场附近找大地先知法尔森接取。进领主大厅击败目标后向铁炉堡国王交付。"}}},
    {name="哀嚎洞穴", zoneID=718, url="https://www.icy-veins.com/wow-forever/wailing-caverns-quests/",
        quests={{title="智慧饮料", questID=1491, faction="双方", details="到贫瘠之地棘齿城找麦伯克·米希瑞克斯，先完成“迅猛龙角”，再接“智慧饮料”；哀嚎香精由洞穴内外的软浆怪掉落。"}}},
    {name="死亡矿井", zoneID=1581, url="https://www.wowhead.com/forever/cn/guide/the-deadmines-dungeon-overview-location-rewards",
        quests={{title="红色丝质面罩", questID=214, faction="联盟", details="先推进西部荒野的“迪菲亚兄弟会”系列，再到哨兵岭找哨兵瑞尔接取。面罩可从副本入口附近及副本内敌人取得。"}}},
    {name="洛丹伦废墟", zoneID=16611, level="15–20", location="提瑞斯法林地，幽暗城上方",
        note="以下部落任务前置据正式服上线后攻略整理，任务链可能随版本变化。", url="https://www.wowhead.com/cn/news/new-prerequisites-required-for-ruins-of-lordaeron-dungeon-quests-in-wow-forever-383769",
        quests={
            {title="拉斯玛尔之怒", questID=92422, faction="部落", details="先在提瑞斯法林地找亡灵卫兵林奈完成“巡查后方”系列，再向亡灵卫兵克里斯托弗接取；进本击败拉斯玛尔后交付。"},
            {title="新的瘟疫", questID=95216, faction="部落", details="先在银松森林瑟伯切尔找药剂师伦弗利尔完成“致命的配方”系列，再到幽暗城炼金房找萨多雷·格雷夫；进本取得枯牙的毒株。"},
        }},
    {name="影牙城堡", zoneID=209, url=general},
    {name="黑暗深渊", zoneID=719, url=general},
    {name="暴风城监狱", zoneID=717, url=general},
    {name="挖掘场", zoneID=16732, level="24–29", location="湿地，维尔加挖掘场上方", url=official},
    {name="诺莫瑞根", zoneID=721, url=general},
    {name="剃刀沼泽", zoneID=491, url=general},
    {name="血色修道院", zoneID=796, url=general},
    {name="达拉然城", zoneID=16544, level="28–33", location="奥特兰克山脉", url=official},
    {name="剃刀高地", zoneID=722, url=general},
    {name="奥达曼", zoneID=1337, url=general},
    {name="沉没之城", level="35–40", location="荆棘谷近海", url=official},
    {name="祖尔法拉克", zoneID=1176, url=general},
    {name="克罗多克要塞", level="40–45", location="河林", url=official},
    {name="玛拉顿", zoneID=2100, url=general},
    {name="阿塔哈卡神庙（沉没的神庙）", zoneID=1477, url=general},
    {name="奥卡兹监狱", level="48–53", location="尘泥沼泽，奥卡兹岛", url=official},
    {name="黑石深渊", zoneID=1584, url=general},
    {name="黑石塔", zoneID=1583, note="候选结果可能混有不同区域的任务，请核对所在楼层及队伍规模。", url=general},
    {name="厄运之槌", zoneID=2557, url=general},
    {name="通灵学院", zoneID=2057, url=general},
    {name="斯坦索姆", zoneID=2017, url=general},
    {name="黑喉要塞", level="55–60", location="艾萨拉", url=official},
    {name="塑造者之台", level="58–60", location="安戈洛环形山", url=official},
}
