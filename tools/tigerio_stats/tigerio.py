#!/usr/bin/env python3
"""Read-only SavedVariables importer and local, JSON-first statistics CLI."""
import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import sqlite3
import sys
import time

from lua_data import MAX_SIZE, ParseError, parse, sequence

GAME_WTF = Path(r'E:\World of Warcraft\_forever_\WTF')
DEFAULT_DB = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / 'TigerioForeverToolbox' / 'statistics.sqlite3'


def obj(value):
    return value if isinstance(value, dict) else {}


def number(value):
    return isinstance(value, (float, int)) and not isinstance(value, bool) and math.isfinite(value)


def iso(epoch):
    try:
        return dt.datetime.fromtimestamp(epoch).astimezone().isoformat(timespec='seconds')
    except (ValueError, OverflowError, OSError, TypeError):
        return None


def safe_db_path(path, sources):
    absolute = Path(path).expanduser().resolve()
    parts = [part.casefold() for part in absolute.parts]
    if 'wtf' in parts:
        raise ValueError('数据库不能放在游戏 WTF 目录中')
    for source in sources:
        if absolute == Path(source).resolve():
            raise ValueError('数据库路径不能与输入存档相同')
    return absolute


def connect(path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        # A caller-specified existing SQLite file may belong to another app.
        # Inspect it read-only before creating tables or writing any data.
        previous = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True, timeout=10)
        try:
            marker = previous.execute("SELECT value FROM metadata WHERE key='application'").fetchone()
            if not marker or marker[0] != 'tigerio_stats':
                raise ValueError('现有数据库不是 Tigerio 统计数据库；请指定新的文件')
            version = previous.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()
            if not version or version[0] != '1':
                raise ValueError('不支持此数据库版本')
        except sqlite3.Error as exc:
            raise ValueError('现有数据库不是 Tigerio 统计数据库；请指定新的文件') from exc
        finally:
            previous.close()
    db = sqlite3.connect(str(path), timeout=10)
    db.row_factory = sqlite3.Row
    db.executescript('''
    CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    CREATE TABLE IF NOT EXISTS sources (
      source_id TEXT PRIMARY KEY, account TEXT NOT NULL, path TEXT NOT NULL,
      mtime REAL, sha256 TEXT, imported_at REAL, last_error TEXT
    );
    CREATE TABLE IF NOT EXISTS characters (
      source_id TEXT NOT NULL, guid TEXT NOT NULL, name TEXT, realm TEXT,
      class TEXT, level INTEGER, started_at REAL, updated_at REAL,
      PRIMARY KEY (source_id, guid)
    );
    CREATE TABLE IF NOT EXISTS events (
      source_id TEXT NOT NULL, guid TEXT NOT NULL, event_id TEXT NOT NULL,
      type TEXT NOT NULL, ts REAL NOT NULL, level INTEGER, origin TEXT NOT NULL,
      payload TEXT NOT NULL, PRIMARY KEY (source_id, guid, event_id)
    );
    CREATE INDEX IF NOT EXISTS events_by_time ON events(type, ts);
    CREATE TABLE IF NOT EXISTS calendar_days (
      source_id TEXT NOT NULL, guid TEXT NOT NULL, day TEXT NOT NULL, seconds REAL,
      PRIMARY KEY (source_id, guid, day)
    );
    ''')
    version = db.execute("SELECT value FROM metadata WHERE key='schema_version'").fetchone()
    if version and version[0] != '1':
        raise ValueError('不支持此数据库版本')
    db.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('schema_version','1')")
    db.execute("INSERT OR IGNORE INTO metadata(key,value) VALUES('application','tigerio_stats')")
    db.commit()
    return db


def account_for(path):
    p = Path(path)
    return p.parent.parent.name if p.parent.name.casefold() == 'savedvariables' else p.stem


def stable_read(path):
    path = Path(path)
    for _ in range(2):
        before = path.stat()
        if before.st_size > MAX_SIZE:
            raise ValueError('存档超过允许的大小')
        with path.open('rb') as stream:
            data = stream.read(MAX_SIZE + 1)
        after = path.stat()
        if len(data) <= MAX_SIZE and (before.st_size, before.st_mtime_ns) == (after.st_size, after.st_mtime_ns) and len(data) == after.st_size:
            return data, after.st_mtime
    raise ValueError('存档正在变化，稍后重试')


def insert_character(db, source, guid, character):
    if not isinstance(guid, str) or not isinstance(character, dict):
        return
    def s(key):
        value = character.get(key)
        return value if isinstance(value, str) else None
    level = character.get('level')
    started, updated = character.get('started_at'), character.get('updated_at')
    db.execute('''INSERT INTO characters(source_id,guid,name,realm,class,level,started_at,updated_at)
      VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(source_id,guid) DO UPDATE SET
      name=COALESCE(excluded.name,characters.name), realm=COALESCE(excluded.realm,characters.realm),
      class=COALESCE(excluded.class,characters.class), level=COALESCE(excluded.level,characters.level),
      started_at=COALESCE(characters.started_at,excluded.started_at),
      updated_at=COALESCE(excluded.updated_at,characters.updated_at)''',
      (source, guid, s('name'), s('realm'), s('class'), int(level) if number(level) else None,
       started if number(started) else None, updated if number(updated) else None))


def ingest(db, source, root):
    telemetry = obj(root.get('telemetry'))
    if telemetry and telemetry.get('version') != 1:
        raise ValueError('不支持此采集数据版本')
    characters = obj(telemetry.get('characters'))
    for guid, character in characters.items():
        if not isinstance(guid, str) or not isinstance(character, dict):
            continue
        insert_character(db, source, guid, character)
        for event in sequence(character.get('events')):
            event = obj(event)
            eid, kind, when = event.get('id'), event.get('type'), event.get('ts')
            if not isinstance(eid, str) or not eid or not isinstance(kind, str) or not number(when):
                continue
            level = event.get('level')
            level = int(level) if number(level) else None
            if kind == 'level_up' and level is not None:
                db.execute("DELETE FROM events WHERE source_id=? AND guid=? AND origin='calendar' AND type='level_up' AND level=? AND ABS(ts-?)<=5", (source, guid, level, when))
            db.execute('''INSERT INTO events(source_id,guid,event_id,type,ts,level,origin,payload)
              VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(source_id,guid,event_id) DO UPDATE SET
              type=excluded.type,ts=excluded.ts,level=excluded.level,origin=excluded.origin,payload=excluded.payload''',
              (source, guid, eid, kind, when, level, 'telemetry', json.dumps(event, ensure_ascii=False, separators=(',', ':'))))
    for guid, character in obj(root.get('characters')).items():
        if not isinstance(guid, str) or not isinstance(character, dict):
            continue
        insert_character(db, source, guid, character)
        for day, record in obj(character.get('days')).items():
            if not isinstance(day, str) or not isinstance(record, dict):
                continue
            seconds = record.get('seconds')
            db.execute('''INSERT INTO calendar_days(source_id,guid,day,seconds) VALUES(?,?,?,?)
              ON CONFLICT(source_id,guid,day) DO UPDATE SET seconds=excluded.seconds''',
              (source, guid, day, seconds if number(seconds) and seconds >= 0 else None))
            for event in sequence(record.get('levels')):
                event = obj(event)
                level, when = event.get('level'), event.get('when')
                if not number(level) or not number(when):
                    continue
                level = int(level)
                duplicate = db.execute("SELECT 1 FROM events WHERE source_id=? AND guid=? AND type='level_up' AND level=? AND ABS(ts-?)<=5 LIMIT 1", (source, guid, level, when)).fetchone()
                if duplicate:
                    continue
                eid = 'calendar:' + hashlib.sha256(f'{guid}\0{level}\0{when}'.encode()).hexdigest()
                payload = {'level': level, 'ts': when, 'day': day, 'source': event.get('source') or 'calendar'}
                db.execute('INSERT OR IGNORE INTO events VALUES(?,?,?,?,?,?,?,?)',
                           (source, guid, eid, 'level_up', when, level, 'calendar', json.dumps(payload, ensure_ascii=False)))


def sync_one(db, path, account=None):
    absolute = str(Path(path).expanduser().resolve())
    source = hashlib.sha256(os.path.normcase(absolute).encode('utf-8')).hexdigest()[:24]
    account = account or account_for(path)
    try:
        raw, mtime = stable_read(path)
        digest = hashlib.sha256(raw).hexdigest()
        current = db.execute('SELECT sha256 FROM sources WHERE source_id=?', (source,)).fetchone()
        if current and current['sha256'] == digest:
            db.execute('UPDATE sources SET mtime=?,last_error=NULL WHERE source_id=?', (mtime, source))
            db.commit()
            return
        root = parse(raw.decode('utf-8-sig'))
        with db:
            ingest(db, source, root)
            db.execute('''INSERT INTO sources(source_id,account,path,mtime,sha256,imported_at,last_error)
              VALUES(?,?,?,?,?,?,NULL) ON CONFLICT(source_id) DO UPDATE SET account=excluded.account,
              path=excluded.path,mtime=excluded.mtime,sha256=excluded.sha256,imported_at=excluded.imported_at,last_error=NULL''',
              (source, account, absolute, mtime, digest, time.time()))
    except (OSError, UnicodeDecodeError, ParseError, ValueError, sqlite3.Error) as exc:
        with db:
            db.execute('''INSERT INTO sources(source_id,account,path,last_error) VALUES(?,?,?,?)
              ON CONFLICT(source_id) DO UPDATE SET last_error=excluded.last_error''',
              (source, account, absolute, str(exc)))


def sources(db):
    return [dict(row) | {'mtime': iso(row['mtime']), 'imported_at': iso(row['imported_at'])}
            for row in db.execute('SELECT source_id,account,path,mtime,imported_at,last_error FROM sources ORDER BY account,path')]


def bounds(args, default_week=False):
    today = dt.date.today()
    if getattr(args, 'week', None) and (getattr(args, 'start', None) or getattr(args, 'end', None)):
        raise ValueError('--week 不能与 --from 或 --to 同时使用')
    if getattr(args, 'week', None) == 'current' or (default_week and not getattr(args, 'start', None) and not getattr(args, 'end', None)):
        start = today - dt.timedelta(days=today.weekday())
        end = start + dt.timedelta(days=7)
    else:
        start = dt.date.fromisoformat(args.start) if getattr(args, 'start', None) else None
        end = dt.date.fromisoformat(args.end) if getattr(args, 'end', None) else None
    if start and end and start >= end:
        raise ValueError('开始日期必须早于结束日期（结束日期不包含）')
    def midnight(day):
        return time.mktime(day.timetuple()) if day else None
    return midnight(start), midnight(end), str(start) if start else None, str(end) if end else None


def rows(db, args, kind=None, start=None, end=None):
    clauses, params = [], []
    if kind:
        clauses.append('e.type=?'); params.append(kind)
    if start is not None:
        clauses.append('e.ts>=?'); params.append(start)
    if end is not None:
        clauses.append('e.ts<?'); params.append(end)
    if getattr(args, 'character', None):
        clauses.append('(c.name=? OR c.guid=?)'); params.extend([args.character, args.character])
    if getattr(args, 'class_name', None):
        clauses.append('UPPER(c.class)=?'); params.append(args.class_name.upper())
    if getattr(args, 'account', None):
        clauses.append('(s.account=? OR s.source_id=?)'); params.extend([args.account, args.account])
    where = 'WHERE ' + ' AND '.join(clauses) if clauses else ''
    query = f'''SELECT e.*,c.name,c.realm,c.class,s.account FROM events e
       LEFT JOIN characters c ON c.source_id=e.source_id AND c.guid=e.guid
       JOIN sources s ON s.source_id=e.source_id {where} ORDER BY e.ts,e.event_id'''
    result = []
    for row in db.execute(query, params):
        result.append({'account': row['account'], 'source_id': row['source_id'], 'guid': row['guid'],
                       'character': row['name'], 'realm': row['realm'], 'class': row['class'],
                       'id': row['event_id'], 'type': row['type'], 'time': iso(row['ts']),
                       'timestamp': row['ts'], 'origin': row['origin'], 'data': json.loads(row['payload'])})
    return result


def coverage(db, args, kind):
    notes = ['历史采集可能不完整；未记录不等于没有发生', '查询基于最近落盘快照，游戏内新数据可能尚未写盘']
    if kind == 'equipment_acquired':
        notes.append('装备获得仅包含可确认来源，其他来源可能遗漏')
    if getattr(args, 'class_name', None):
        notes.append('未记录职业的角色无法按职业归类；历史事件的职业来自同一角色后续记录')
    source_list = sources(db)
    if any(row['last_error'] for row in source_list):
        notes.append('部分来源导入失败，保留上次成功的数据')
    usable = any(row['mtime'] and row['imported_at'] for row in source_list)
    return {'status': 'partial' if usable else 'unavailable', 'notes': notes}


def level_summary(records, start):
    # The reached level proves at least one level, not that a missing prior
    # observation happened in this period. Expand jumps only when the earlier
    # level was observed within the requested interval.
    per_character, unknown_start = {}, 0
    for record in records:
        payload = record['data']
        level, before, observed_at = payload.get('level'), payload.get('from_level'), payload.get('from_level_observed_at')
        reached_valid = number(level) and 1 <= level <= 1000 and level == int(level)
        if not reached_valid:
            unknown_start += 1
            continue
        level = int(level)
        key = (record['source_id'], record['guid'])
        seen = per_character.setdefault(key, set())
        seen.add(level)
        valid_prior = (number(before) and 1 <= before < level and before == int(before)
                       and number(observed_at) and observed_at <= record['timestamp']
                       and (start is None or observed_at >= start))
        if valid_prior:
            seen.update(range(int(before) + 1, level + 1))
        else:
            unknown_start += 1
    minimum = sum(len(levels) for levels in per_character.values())
    return {'observed_level_events': len(records), 'observed_levels_gained': minimum,
            'confirmed_levels_gained': minimum, 'minimum_levels_gained': minimum,
            'events_without_in_range_start': unknown_start, 'complete_levels_gained': None}


def query(db, args):
    srcs = sources(db)
    base = {'schema_version': 1, 'sources': srcs, 'data_as_of': max((s['mtime'] for s in srcs if s['mtime']), default=None)}
    if args.command in ('sync', 'status'):
        base.update({'command': args.command, 'database': str(args.db), 'coverage': coverage(db, args, None)})
        return base
    if args.command == 'characters':
        base['characters'] = [dict(row) for row in db.execute('''SELECT c.*,s.account FROM characters c
          JOIN sources s ON s.source_id=c.source_id ORDER BY s.account,c.realm,c.name''')]
        base['coverage'] = coverage(db, args, None)
        return base
    is_stats = args.command == 'stats'
    start, end, start_date, end_date = bounds(args, default_week=is_stats)
    base['range'] = {'from': start_date, 'to_exclusive': end_date, 'timezone': time.tzname[time.localtime().tm_isdst > 0]}
    if args.command in ('events', 'export'):
        base['events'] = rows(db, args, args.type, start, end)
        base['coverage'] = coverage(db, args, args.type)
        return base
    if args.metric == 'levels':
        records = rows(db, args, 'level_up', start, end)
        base.update({'metric': 'levels', 'result': level_summary(records, start),
                     'events': records, 'coverage': coverage(db, args, 'level_up')})
    elif args.metric == 'gear':
        gained = rows(db, args, 'equipment_acquired', start, end)
        equipped = rows(db, args, 'gear_equipped', start, end)
        quantities = [r['data'].get('quantity') for r in gained]
        count = sum(x for x in quantities if number(x) and x > 0)
        base.update({'metric': 'gear', 'result': {'observed_equipment_acquired': count,
                     'complete_equipment_acquired': None, 'observed_equipment_changes': len(equipped)},
                     'acquired': gained, 'equipped': equipped, 'coverage': coverage(db, args, 'equipment_acquired')})
    else:
        all_snapshots = rows(db, args, 'gear_snapshot', None, end)
        by_char = {}
        for record in all_snapshots:
            payload = record['data']
            level = payload.get('average_item_level')
            if number(level) and isinstance(payload.get('average_item_level_kind'), str):
                key = (record['source_id'], record['guid'])
                by_char.setdefault(key, []).append(record)
        results = []
        for values in by_char.values():
            prior = [v for v in values if start is not None and v['timestamp'] < start]
            begin = prior[-1] if prior else None
            within = [v for v in values if start is None or v['timestamp'] >= start]
            latest = within[-1] if within else None
            identity = latest or begin
            if not identity:
                continue
            same_kind = begin and (not latest or begin['data']['average_item_level_kind'] == latest['data']['average_item_level_kind'])
            a = begin['data']['average_item_level'] if same_kind else None
            b = latest['data']['average_item_level'] if latest else None
            results.append({'account': identity['account'], 'character': identity['character'], 'guid': identity['guid'],
                            'start': a, 'start_time': begin['time'] if same_kind else None,
                            'end': b, 'end_time': latest['time'] if latest else None,
                            'item_level_kind': latest['data']['average_item_level_kind'] if latest else None,
                            'increase': round(b-a, 3) if a is not None and b is not None else None})
        base.update({'metric': 'item-level', 'results': results, 'coverage': coverage(db, args, 'gear_snapshot')})
    return base


def filters(parser, timed=True):
    parser.add_argument('--character')
    parser.add_argument('--class', dest='class_name')
    parser.add_argument('--account')
    if timed:
        parser.add_argument('--week', choices=['current'])
        parser.add_argument('--from', dest='start', help='开始日期 YYYY-MM-DD（包含）')
        parser.add_argument('--to', dest='end', help='结束日期 YYYY-MM-DD（不包含）')
    parser.add_argument('--json', action='store_true', help='兼容参数；默认输出 JSON')


def main(argv=None):
    parser = argparse.ArgumentParser(description='Tigerio 工具箱本地统计；只读游戏存档')
    parser.add_argument('--db', type=Path, default=DEFAULT_DB)
    parser.add_argument('--input', action='append', default=[], help='指定 SavedVariables 文件，可多次指定')
    parser.add_argument('--no-sync', action='store_true', help='仅查询已有数据库')
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('sync', 'status', 'characters'):
        p = sub.add_parser(name)
        p.add_argument('--json', action='store_true')
    events = sub.add_parser('events')
    events.add_argument('--type')
    filters(events)
    events.add_argument('--format', choices=['json', 'jsonl'], default='json')
    export = sub.add_parser('export')
    export.add_argument('what', choices=['events'])
    export.add_argument('--type')
    filters(export)
    export.add_argument('--format', choices=['json', 'jsonl'], default='jsonl')
    stats = sub.add_parser('stats').add_subparsers(dest='metric', required=True)
    for metric in ('levels', 'gear', 'item-level'):
        filters(stats.add_parser(metric))
    args = parser.parse_args(argv)
    paths = [Path(p) for p in args.input] if args.input else sorted((GAME_WTF / 'Account').glob('*/SavedVariables/TigerioForeverToolbox.lua'))
    try:
        args.db = safe_db_path(args.db, paths)
        db = connect(args.db)
        if not args.no_sync:
            for path in paths:
                sync_one(db, path)
            for source in db.execute('SELECT source_id,path FROM sources').fetchall():
                if not Path(source['path']).exists():
                    db.execute('UPDATE sources SET last_error=? WHERE source_id=?',
                               ('来源文件不存在，保留上次成功导入的数据', source['source_id']))
            db.commit()
        data = query(db, args)
        db.close()
        if args.command in ('events', 'export') and args.format == 'jsonl':
            for event in data['events']:
                print(json.dumps(event, ensure_ascii=False, separators=(',', ':')))
        else:
            print(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=False))
        if args.command == 'sync' and (not data['sources'] or any(s['last_error'] for s in data['sources'])):
            return 1
        return 0
    except (ValueError, OSError, sqlite3.Error) as exc:
        print(json.dumps({'error': str(exc)}, ensure_ascii=False), file=sys.stderr)
        return 1


if __name__ == '__main__':
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8')
    if hasattr(sys.stderr, 'reconfigure'):
        sys.stderr.reconfigure(encoding='utf-8')
    raise SystemExit(main())
