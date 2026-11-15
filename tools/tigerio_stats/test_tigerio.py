"""Focused tests using synthetic data only; never access actual game data."""
import contextlib
import datetime as dt
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import time
import unittest

import lua_data
import tigerio


class StatisticsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.db = self.root / 'data.sqlite3'
        self.source = self.root / 'Account' / 'A' / 'SavedVariables' / 'TigerioForeverToolbox.lua'
        self.source.parent.mkdir(parents=True)
        today = dt.date.today()
        monday = today - dt.timedelta(days=today.weekday())
        self.start = int(time.mktime(monday.timetuple()))
        self.source.write_text('''TigerioForeverToolboxDB = {
          ["characters"] = {["Player-1"] = {name="测试", realm="测试服", days={
              ["2026-01-01"]={seconds=60,levels={{level=11,when=%d}}}}}},
          telemetry={version=1,characters={["Player-1"]={name="测试",class="HUNTER",started_at=%d,
            events={
             {id="level-1",type="level_up",ts=%d,level=11,source="player_level_up"},
             {id="loot-1",type="equipment_acquired",ts=%d,item_id=12,quantity=2,source="loot_chat_self"},
             {id="equip-1",type="gear_equipped",ts=%d,slot=3,item_id=12},
             {id="snap-old",type="gear_snapshot",ts=%d,average_item_level=10,
               average_item_level_kind="equipped_raw",snapshot_complete=false},
             {id="snap-new",type="gear_snapshot",ts=%d,average_item_level=12.5,
               average_item_level_kind="equipped_raw",snapshot_complete=false}
            }}}}
        }''' % (self.start + 101, self.start - 1000, self.start + 100,
                self.start + 200, self.start + 201, self.start - 10, self.start + 300), encoding='utf-8')

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args):
        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = tigerio.main(['--db', str(self.db), '--input', str(self.source), *args])
        return code, json.loads(stdout.getvalue()) if stdout.getvalue() else None, stderr.getvalue()

    def test_level_dedup_idempotence_and_gear_baseline(self):
        code, levels, _ = self.run_cli('stats', 'levels', '--class', 'HUNTER', '--week', 'current')
        self.assertEqual(code, 0)
        self.assertEqual(levels['result']['observed_levels_gained'], 1)
        self.assertIsNone(levels['result']['complete_levels_gained'])
        code, levels, _ = self.run_cli('stats', 'levels', '--week', 'current')
        self.assertEqual(levels['result']['observed_levels_gained'], 1)
        _, gear, _ = self.run_cli('stats', 'gear', '--week', 'current')
        self.assertEqual(gear['result']['observed_equipment_acquired'], 2)
        self.assertEqual(gear['result']['observed_equipment_changes'], 1)
        self.assertIsNone(gear['result']['complete_equipment_acquired'])
        _, itemlevel, _ = self.run_cli('stats', 'item-level', '--week', 'current')
        self.assertEqual(itemlevel['results'][0]['increase'], 2.5)
        self.assertEqual(itemlevel['results'][0]['item_level_kind'], 'equipped_raw')

    def test_level_jump_and_prior_observation_time(self):
        jump = {'source_id': 'account-a', 'guid': 'Player-1', 'timestamp': 100,
                'data': {'from_level': 1, 'level': 3, 'from_level_observed_at': 95}}
        inside = tigerio.level_summary([jump], 90)
        self.assertEqual(inside['observed_level_events'], 1)
        self.assertEqual(inside['minimum_levels_gained'], 2)
        cross_boundary = tigerio.level_summary([jump], 99)
        self.assertEqual(cross_boundary['minimum_levels_gained'], 1)
        self.assertEqual(cross_boundary['events_without_in_range_start'], 1)
        prior_unknown = {'source_id': 'account-a', 'guid': 'Player-1', 'timestamp': 98,
                         'data': {'level': 2}}
        overlapping = tigerio.level_summary([prior_unknown, jump], 90)
        self.assertEqual(overlapping['minimum_levels_gained'], 2)
        self.assertEqual(overlapping['observed_level_events'], 2)
        self.assertIsNone(overlapping['complete_levels_gained'])

    def test_invalid_source_preserves_last_good_data(self):
        self.run_cli('status')
        self.source.write_text('TigerioForeverToolboxDB = os.execute("bad")', encoding='utf-8')
        code, data, _ = self.run_cli('stats', 'levels', '--week', 'current')
        self.assertEqual(code, 0)
        self.assertEqual(data['result']['observed_levels_gained'], 1)
        self.assertIsNotNone(data['sources'][0]['last_error'])

    def test_identical_guid_in_two_accounts_remains_distinct(self):
        second = self.root / 'Account' / 'B' / 'SavedVariables' / 'TigerioForeverToolbox.lua'
        second.parent.mkdir(parents=True)
        second.write_bytes(self.source.read_bytes())
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = tigerio.main(['--db', str(self.db), '--input', str(self.source), '--input', str(second),
                                 'stats', 'levels', '--week', 'current'])
        self.assertEqual(code, 0)
        result = json.loads(stdout.getvalue())
        self.assertEqual(result['result']['observed_levels_gained'], 2)
        self.assertEqual({event['account'] for event in result['events']}, {'A', 'B'})

    def test_no_current_snapshot_does_not_invent_zero_increase(self):
        self.run_cli('status')
        db = sqlite3.connect(str(self.db))
        db.execute("DELETE FROM events WHERE event_id='snap-new'")
        db.commit(); db.close()
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = tigerio.main(['--db', str(self.db), '--no-sync', 'stats', 'item-level', '--week', 'current'])
        self.assertEqual(code, 0)
        result = json.loads(stdout.getvalue())['results'][0]
        self.assertIsNone(result['end'])
        self.assertIsNone(result['increase'])

    def test_foreign_existing_database_is_not_modified(self):
        other = self.root / 'other.sqlite3'
        db = sqlite3.connect(str(other))
        db.execute('CREATE TABLE unrelated (v TEXT)')
        db.execute("INSERT INTO unrelated VALUES ('keep')")
        db.commit(); db.close()
        with self.assertRaises(ValueError):
            tigerio.connect(other)
        db = sqlite3.connect(str(other))
        self.assertEqual(db.execute('SELECT v FROM unrelated').fetchone()[0], 'keep')
        self.assertEqual(db.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='events'").fetchone()[0], 0)
        db.close()

    def test_unknown_database_version_is_not_modified(self):
        other = self.root / 'future.sqlite3'
        db = sqlite3.connect(str(other))
        db.execute('CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)')
        db.executemany('INSERT INTO metadata VALUES (?,?)', [('application', 'tigerio_stats'), ('schema_version', '999')])
        db.commit(); db.close()
        with self.assertRaises(ValueError):
            tigerio.connect(other)
        db = sqlite3.connect(str(other))
        self.assertEqual(db.execute("SELECT COUNT(*) FROM sqlite_master WHERE name='events'").fetchone()[0], 0)
        self.assertEqual(db.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()[0], '999')
        db.close()

    def test_only_failed_import_is_unavailable(self):
        self.source.write_text('TigerioForeverToolboxDB = os.execute("bad")', encoding='utf-8')
        code, data, _ = self.run_cli('status')
        self.assertEqual(code, 0)
        self.assertEqual(data['coverage']['status'], 'unavailable')
        self.assertIsNotNone(data['sources'][0]['last_error'])

    def test_lua_data_never_executes_code(self):
        with self.assertRaises(lua_data.ParseError):
            lua_data.parse('TigerioForeverToolboxDB = { value = os.execute("cmd") }')
        data = lua_data.parse(r'TigerioForeverToolboxDB = { ["name"]="\228\189\160", ok=true, list={1,2}, }')
        self.assertEqual(data['name'], '你')
        self.assertEqual(lua_data.sequence(data['list']), [1, 2])


if __name__ == '__main__':
    unittest.main()
