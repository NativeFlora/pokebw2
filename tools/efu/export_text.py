"""export_text.py OUT.xlsx: every line of dialogue and narration the hack can show, as a spreadsheet to edit.

Sheets:
- Escape from Unova: the hack's own lines (res/text/script/efu.txt), with who says them;
- Trainers: what the hack's Trainers say in and after battle (res/trainers/data), the scavengers, Burgh, his minions
  and the ranch's boss among them;
- Original game: the lines of the original game that the hack's zones can still show, found by following every
  script their people, signs and triggers run (zone scripts only; the item, Pokémon Center and other shared scripts
  are left out);
- Menus: the starter menu's choices;
- Read me: how to edit.

Each line has a "New text" column. The text is shown with real line breaks, and the game's codes as words in
brackets (TAGS, which turn back into the codes the same way). Run after the generators.
"""
import glob
import json
import os
import re
import sys

import openpyxl
from openpyxl.styles import Alignment, Font, PatternFill

root = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..'))
RES = os.path.join(root, 'res')

# The game's codes and how the sheet shows them (both ways)
TAGS = [
    ('{be01}', ' [next box]'),
    ('{be00}', ' [scroll]'),
    ('{ff00:2}', '[colour]'),
    ('{ff00:0}', '[/colour]'),
    ('{0101:0}', '[Pokémon]'),
    ('{0101:1}', '[Pokémon]'),
    ('{0109:0}', '[item]'),
    ('{0204:0}', '[money]'),
    ('{0201:0}', '[number 1]'),
    ('{0201:1}', '[number 2]'),
    ('{0100:0}', '[player]'),
    ('{0100:1}', '[player]'),
]


def show(text):
    for code, word in TAGS:
        text = text.replace(code, word)
    return text.replace('\\n', '\n')


# Who says each of the hack's lines, by the start of its label (the first that fits)
SPEAKERS = [
    ('Wake', 'Narration: waking up in the warehouse'),
    ('WhichType', 'Narration: choosing the Pokémon that stayed'), ('WhichOne', 'Narration: choosing the Pokémon'),
    ('ThisOne', 'Narration: choosing the Pokémon'), ('StayedWithYou', 'Narration: choosing the Pokémon'),
    ('Back', 'Menu'), ('BoardedDoor', 'Sign: a boarded door'), ('Bed', 'Narration: the bed in the base'),
    ('Raid', 'Narration: the east gate (heading out, coming back)'), ('Saving', 'Narration'),
    ('LostSoul', 'Narration: a lost Pokémon joins after a wipe'), ('Blackout', 'Narration: whiting out'),
    ('ScavDrop', 'Narration: a beaten scavenger'), ('TossLost', 'Narration: picking up items'),
    ('Nurse', 'Nurse Joy, in the base'), ('NotEnoughMoney', 'Anyone who charges'),
    ('Joy', 'Nurse Joy, out in the zone (before she joins)'), ('Clerk', 'The clerk, in the base'),
    ('DayCare', 'The Day Care Lady'), ('GateGuide', 'The guide, at the east gate'),
    ('Burgh', 'Burgh, in Rumination Field'), ('ZoneCleared', 'Narration: after beating Burgh'),
    ('GuideMeet', 'The guide (old Route 3 meeting, no longer used)'), ('BlockedDoor', 'Sign: a boulder in a doorway'),
    ('Locker', 'The locker'), ('PaidExit', 'The driver at Route 2\'s old gate'), ('Tinker', 'The tinkerer, in the lab'),
    ('RanchBoss', 'Garrick, Floccesy Ranch\'s boss'), ('GuideCaged', 'The guide, caged in Rumination Field'),
    ('GuideFreed', 'The guide, caged in Rumination Field'), ('Lock', 'Sign: a locked door'),
]


def speaker(key):
    name = key[len('Efu_Text_'):]
    if name.startswith('Lock_') or name.startswith('LockOpen_'):
        return 'Sign: the slot in Route 2\'s hole (lock %s)' % name.rsplit('_', 1)[1]
    return next((who for start, who in SPEAKERS if name.startswith(start)), '')


def read_text(path):
    out = []
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if ' = ' in line and not line.startswith('#'):
            key, text = line.split(' = ', 1)
            out.append((key, text))
    return out


def hack_zones():
    """Every zone a warp reaches from the base and the exploration zone."""
    seen, todo = set(), ['ZONE_NACRENE_GATE', 'ZONE_ROUTE_3', 'ZONE_ROUTE_2', 'ZONE_ROUTE_19', 'ZONE_ROUTE_20',
                         'ZONE_FLOCCESY_RANCH']
    while todo:
        zone = todo.pop()
        if zone in seen:
            continue
        seen.add(zone)
        path = os.path.join(RES, 'field/events', zone[5:].lower() + '.json')
        if os.path.exists(path):
            todo += [w['zone'] for w in json.load(open(path))['warps']]
    return sorted(seen)


def zone_lines(zone):
    """The lines of a zone's text that its events' scripts can reach, in the text file's order."""
    events = json.load(open(os.path.join(RES, 'field/events', zone[5:].lower() + '.json')))
    header = json.load(open(os.path.join(RES, 'field/zones', zone[5:].lower() + '.json')))
    script = os.path.join(RES, 'field/scripts', header['scripts'][len('SCRIPTS_'):].lower() + '.s')
    text = os.path.join(RES, 'text/script', header['text'][len('SCRIPT_TEXT_'):].lower() + '.txt')
    if not os.path.exists(script) or not os.path.exists(text):
        return []
    ids = {e.get('script', 0) for k in ('npcs', 'bg_events', 'triggers', 'init_scripts') for e in events.get(k, [])}
    lines = open(script, encoding='utf-8').read().splitlines()
    entries = [l.split()[1] for l in lines if l.strip().startswith('ScriptEntry ')]
    at = {l[:-1]: i for i, l in enumerate(lines) if re.match(r'^\w+:$', l)}
    todo = [entries[i - 1] for i in ids if 1 <= i <= len(entries)]
    seen, used = set(), set()
    while todo:
        label = todo.pop()
        if label in seen or label not in at:
            continue
        seen.add(label)
        for l in lines[at[label] + 1:]:
            if re.match(r'^\w+:$', l):
                todo.append(l[:-1])  # falls through
                break
            words = re.findall(r'\w+', l)
            used.update(words)
            todo += [w for w in words if w in at]
            op = l.split()[0] if l.split() else ''
            if op in ('VMHalt', 'VMEnd', 'VMReturn', 'VMJump', 'ScriptEnd'):
                break
    return [(k, t) for k, t in read_text(text) if k in used]


TRMSG = {'TRMSG_START': 'Before battle', 'TRMSG_LOSE': 'In battle, when beaten', 2: 'After battle, if talked to',
         'TRMSG_WIN': 'In battle, when they win'}


def trainer_files(zones):
    ids = set()
    for zone in zones:
        path = os.path.join(RES, 'field/events', zone[5:].lower() + '.json')
        if os.path.exists(path):
            ids |= {n['script'] - 3000 for n in json.load(open(path))['npcs'] if 3000 < n['script'] < 4000}
    names = [l.split()[0] for l in open(os.path.join(root, 'generated/trainers.txt')) if l.startswith('TRAINER_')]
    files = {names[i] for i in ids if i < len(names)}
    files |= set(re.findall(r'CallTrainerBattle (TRAINER_\w+)', open(os.path.join(RES, 'field/scripts/efu.s')).read()))
    return sorted(os.path.join(RES, 'trainers/data', n[len('TRAINER_'):].lower() + '.json') for n in files)


def sheet(wb, title, header, rows, widths):
    ws = wb.create_sheet(title)
    ws.append(header)
    for cell in ws[1]:
        cell.font = Font(bold=True, color='FFFFFF')
        cell.fill = PatternFill('solid', fgColor='3B4A5A')
    for row in rows:
        ws.append(row)
    for i, w in enumerate(widths):
        ws.column_dimensions[chr(65 + i)].width = w
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical='top')
    edit = header.index('New text')
    for row in ws.iter_rows(min_row=2, min_col=edit + 1, max_col=edit + 1):
        row[0].fill = PatternFill('solid', fgColor='FFF6D5')
    ws.freeze_panes = 'A2'
    ws.auto_filter.ref = ws.dimensions
    return ws


def main(out):
    wb = openpyxl.Workbook()
    wb.remove(wb.active)
    efu = read_text(os.path.join(RES, 'text/script/efu.txt'))
    menus = [(k, t) for k, t in efu if re.match(r'Efu_Text_(Sp|Type)_', k)]
    story = [(k, t) for k, t in efu if (k, t) not in menus]
    sheet(wb, 'Escape from Unova', ['Key', 'Who / where', 'Text', 'New text', 'Notes'],
          [[k, speaker(k), show(t), '', ''] for k, t in story], [26, 30, 48, 48, 24])
    zones = hack_zones()
    rows = []
    for path in trainer_files(zones):
        t = json.load(open(path))
        key = os.path.basename(path)[:-5]
        for m in t.get('messages', []):
            when = TRMSG.get(m['type'], 'Original game only (not shown in the hack)')
            rows.append([key, t['name'], t['class'][len('TRAINER_CLASS_'):].replace('_', ' ').title(), when,
                         show(m['text']), '', ''])
    sheet(wb, 'Trainers', ['Key', 'Name', 'Class', 'When', 'Text', 'New text', 'Notes'], rows,
          [24, 12, 16, 22, 48, 48, 20])
    rows = []
    for zone in zones:
        place = zone[5:].replace('_', ' ').title()
        rows += [[k, place, show(t), '', ''] for k, t in zone_lines(zone)]
    sheet(wb, 'Original game', ['Key', 'Zone', 'Text', 'New text', 'Notes'], rows, [36, 22, 48, 48, 20])
    sheet(wb, 'Menus', ['Key', 'Text', 'New text'], [[k, show(t), ''] for k, t in menus], [30, 30, 30])
    ws = wb.create_sheet('Read me', 0)
    for line in [
        'Escape from Unova: the game\'s text',
        '',
        'Write a change in the yellow "New text" column and leave "Text" as it is. Blank means no change.',
        'A text box fits two lines of about 36 characters. Keep the line breaks inside the cell.',
        '[next box] waits for A and starts a new box. [scroll] scrolls up a line without waiting.',
        '[Pokémon], [item], [money], [number 1], [number 2] and [player] are filled in by the game.',
        '[colour] ... [/colour] shows a name in colour.',
        'Codes in curly braces are other game codes: leave them where they are.',
        '',
        'Escape from Unova: everything the hack wrote, with who says it.',
        'Trainers: the battle lines of the hack\'s Trainers. "Before battle" shows only for Trainers who spot you.',
        'Original game: lines from the original game that the hack\'s places can still show.',
        'Menus: the starter menu.',
    ]:
        ws.append([line])
    ws['A1'].font = Font(bold=True, size=14)
    ws.column_dimensions['A'].width = 110
    wb.save(out)
    print('%s: %d hack lines, %d trainer lines, %d original lines, %d menu items'
          % (out, len(story), wb['Trainers'].max_row - 1, wb['Original game'].max_row - 1, len(menus)))


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'escape_from_unova_text.xlsx')
