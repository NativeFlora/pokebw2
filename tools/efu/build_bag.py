"""Escape from Unova: the bag's pockets.

Medicine and berries go in the Items pocket, so the bag has only Items (where the one-item limit applies), TMs and HMs,
and Key Items. The save code's own table of pockets (src/system/myitem_savedata.c) is edited by hand; this script
sets each item's field_pocket in res/items to match, starting from the decomp's data in BASE_COMMIT.
"""
import json, os, subprocess

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))
BASE_COMMIT = 'origin/main'
MERGED = {'BAG_POCKET_MEDICINE', 'BAG_POCKET_BERRIES'}
# The Blank HM, Burgh's reward, takes the place of Gram 1, which nothing gives in the hack: a key item that can't be
# tossed, drawn as HM01 is (its disc with TM05's Normal-type palette), since main's table of icons can't change
BLANK_HM = 'gram_1'
BLANK_HM_DATA = {'name': 'Blank HM', 'name_article': 'a', 'name_plural': 'Blank HMs',
                 'description': 'A Hidden Machine with nothing on it.\nOne day it can be made into the HM\nof your choice.',
                 'important': True}
BLANK_HM_ICON = {'icon.png': 'res/items/hm01/icon.png', 'icon.pal': 'res/items/tm05/icon.pal'}


def build_pockets():
    names = subprocess.run(['git', 'ls-tree', '--name-only', f'{BASE_COMMIT}:res/items'], cwd=root,
                           capture_output=True, check=True, text=True).stdout.split()
    moved = 0
    for name in names:
        path = f'res/items/{name}/data.json'
        text = subprocess.run(['git', 'show', f'{BASE_COMMIT}:{path}'], cwd=root, capture_output=True,
                              text=True).stdout
        if not text:
            continue
        pocket = json.loads(text)['field_pocket']
        if pocket in MERGED:
            text = text.replace(f'"field_pocket": "{pocket}"', '"field_pocket": "BAG_POCKET_ITEMS"')
            moved += 1
        with open(os.path.join(root, path), 'w', encoding='utf-8', newline='\n') as f:
            f.write(text)
    return moved


def build_blank_hm():
    path = f'res/items/{BLANK_HM}/data.json'
    data = json.loads(subprocess.run(['git', 'show', f'{BASE_COMMIT}:{path}'], cwd=root, capture_output=True,
                                     check=True).stdout.decode('utf-8'))
    data.update(BLANK_HM_DATA)
    with open(os.path.join(root, path), 'w', encoding='utf-8', newline='\n') as f:
        f.write(json.dumps(data, indent=4, ensure_ascii=False) + '\n')
    for name, source in BLANK_HM_ICON.items():
        blob = subprocess.run(['git', 'show', f'{BASE_COMMIT}:{source}'], cwd=root, capture_output=True,
                              check=True).stdout
        with open(os.path.join(root, f'res/items/{BLANK_HM}', name), 'wb') as f:
            f.write(blob)


if __name__ == '__main__':
    print('moved to Items', build_pockets())
    build_blank_hm()
