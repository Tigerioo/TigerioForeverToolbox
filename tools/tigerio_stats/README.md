# Tigerio 本地统计

在项目根目录的 PowerShell 中运行：

```powershell
.\tools\tigerio_stats\tigerio.cmd status --json
.\tools\tigerio_stats\tigerio.cmd characters --json
.\tools\tigerio_stats\tigerio.cmd stats levels --week current --json
.\tools\tigerio_stats\tigerio.cmd stats levels --class HUNTER --week current --json
.\tools\tigerio_stats\tigerio.cmd stats gear --character "角色名" --week current --json
.\tools\tigerio_stats\tigerio.cmd stats item-level --character "角色名" --week current --json
.\tools\tigerio_stats\tigerio.cmd events --type gear_equipped --format jsonl
```

默认自动发现 `E:\World of Warcraft\_forever_\WTF\Account\*\SavedVariables\TigerioForeverToolbox.lua` 并只读导入；来源路径和落盘时间包含在 JSON 中。游戏保存变量通常在 `/reload`、正常登出或退出时写盘，数据不是实时的。默认数据库是 `%LOCALAPPDATA%\TigerioForeverToolbox\statistics.sqlite3`，不会写入游戏目录。此启动器优先使用本机 Codex 自带 Python，其他电脑可通过 `py -3` 运行。

运行 `.\tools\tigerio_stats\tigerio.cmd --input <存档路径> --db <数据库路径> status` 可指定来源和数据库；全局选项放在子命令之前。`--no-sync` 只查询已有数据库。导入失败保留上一次成功数据并在 `sources` 标出错误。

时间区间使用本地时区，`--from YYYY-MM-DD` 包含当天，`--to YYYY-MM-DD` 不包含当天；`--week current` 使用本周一至下周一。没有可靠覆盖的数据输出 `null` 或标记 `partial`，已观测数量不等于完整总量。`item-level` 需要区间开始之前的可靠快照作为基线。当前装备获得只包含采集器可确认的来源。

升级统计的 `observed_level_events` 是事件数；`minimum_levels_gained` 是有证据的升级级数下限。只有前等级观测时间也在查询区间内时，跨等级跳升才按完整跨度计算；否则只计算已到达的等级，并在 `events_without_in_range_start` 标记。`complete_levels_gained` 在覆盖不完整时为 `null`。

CLI 解析受限的 Lua 数据语法，不执行存档代码，不会修改 SavedVariables。历史日历记录和新增采集的相同角色、同等级、5 秒内升级去重。相同名字的多账号角色使用 `--account` 或 GUID 精确区分。
