local _, toolbox = ...

-- Hand-written travel references. Training availability must be confirmed in game.
toolbox.weaponMastersData = {
    weapons = {"单手斧", "双手斧", "单手锤", "双手锤", "单手剑", "双手剑", "匕首", "拳套", "法杖", "长柄武器", "弓", "弩", "枪械", "投掷武器", "魔杖"},
    weaponNotes = {
        ["魔杖"] = "资料称法师、牧师和术士通常自带魔杖技能；武器大师不教授魔杖。请以角色技能面板为准。",
        ["长柄武器"] = "常见攻略称长柄武器有等级和费用要求；请以当前角色的训练界面为准。",
    },
    notes = {
        "地点和教学清单为攻略参考，未在本客户端实测；坐标为旧资料约数，可能随无限服版本变化。",
        "能否学习取决于职业、等级、已学技能等；不自动判断角色是否能学。迷路时可询问主城卫兵。",
    },
    masters = {
        {name="吴平（Woo Ping）", city="暴风城", location="贸易区，维勒的武器店", faction="Alliance", weapons={"单手剑", "双手剑", "匕首", "法杖", "长柄武器", "弩"}},
        {name="布里维夫·石拳（Buliwyf Stonehand）", city="铁炉堡", location="军事区武器店，约 61.2, 89.5", faction="Alliance", weapons={"单手斧", "双手斧", "单手锤", "双手锤", "拳套", "枪械"}},
        {name="比克斯（Bixi Wobblebonk）", city="铁炉堡", location="军事区武器店，约 62.2, 89.6", faction="Alliance", weapons={"匕首", "弩", "投掷武器"}},
        {name="伊琳尼雅·月火（Ilyenia Moonfire）", city="达纳苏斯", location="战士区，约 57.6, 46.7", faction="Alliance", weapons={"弓", "匕首", "拳套", "法杖", "投掷武器"}, uncertainWeapons={"单手剑", "双手剑"}, note="资料对其是否教授单手剑、双手剑有冲突，请到训练界面核实。"},
        {name="塞尤克（Sayoc）", city="奥格瑞玛", location="荣誉谷武器店，约 81.7, 19.5", faction="Horde", weapons={"弓", "匕首", "拳套", "单手斧", "双手斧", "投掷武器"}, uncertainWeapons={"法杖"}, note="资料对其是否教授法杖有冲突；旁边的哈纳什也提供法杖训练参考。"},
        {name="哈纳什（Hanashi）", city="奥格瑞玛", location="荣誉谷武器店，约 81.5, 19.6", faction="Horde", weapons={"弓", "单手斧", "双手斧", "法杖", "投掷武器"}},
        {name="安塞瓦（Ansekhwa）", city="雷霆崖", location="下层高地武器店，约 40.9, 62.7", faction="Horde", weapons={"单手锤", "双手锤", "法杖", "枪械"}},
        {name="阿基巴德（Archibald）", city="幽暗城", location="军事区内环，约 57.3, 32.8", faction="Horde", weapons={"单手剑", "双手剑", "匕首", "长柄武器", "弩"}},
    },
}
