"""Escape from Unova: writes tools/efu/wild_groups.json, the groups of wild Pokémon that count as equivalent.

Each species that can be met in the wild goes in one group, its first egg group's. Those the egg groups leave out
go where they fit best: a baby in its evolution's group, Nidorina and Nidoqueen with Nidoran F (Monster), Ditto with
the shapeless Pokémon (Amorphous) and Unown with the living objects (Mineral). Legendary and mythical Pokémon are in
no group, since none can be caught in the wild. Run it again after changing a species' egg groups.
"""
import json, os

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))

# The legendary and mythical Pokémon: in the Undiscovered egg group with no evolution, plus Manaphy and Phione, the
# mythical pair in Water 1
LEGENDARY_EXTRA = {'SPECIES_MANAPHY', 'SPECIES_PHIONE'}
# The rest of Undiscovered and Ditto's group, placed by hand
PLACED = {
    'SPECIES_NIDORINA': 'EGG_GROUP_MONSTER',
    'SPECIES_NIDOQUEEN': 'EGG_GROUP_MONSTER',
    'SPECIES_DITTO': 'EGG_GROUP_AMORPHOUS',
    'SPECIES_UNOWN': 'EGG_GROUP_MINERAL',
}
LEFT_OUT = ('EGG_GROUP_UNDISCOVERED', 'EGG_GROUP_DITTO', 'EGG_GROUP_NONE')


def species_list():
    names = []
    for line in open(os.path.join(root, 'generated/species.txt')):
        line = line.split('#')[0].split('=')[0].strip()
        if line.startswith('SPECIES_') and line != 'SPECIES_NONE':
            names.append(line)
    return names


def load(species):
    path = os.path.join(root, 'res/pokemon', species[len('SPECIES_'):].lower(), 'data.json')
    return json.load(open(path)) if os.path.exists(path) else None


def main():
    data = {}
    for species in species_list():
        d = load(species)
        if d is None or species in ('SPECIES_EGG', 'SPECIES_BAD_EGG'):
            break
        data[species] = d
    groups = {}
    for species, d in data.items():
        group = PLACED.get(species)
        if group is None:
            # A baby takes its evolution's group (following the line until one has a group: Pichu's is Pikachu's)
            at = species
            while data[at]['egg_groups'][0] in LEFT_OUT and data[at]['evolutions']:
                at = data[at]['evolutions'][0]['species']
            group = data[at]['egg_groups'][0]
        if group in LEFT_OUT or species in LEGENDARY_EXTRA:
            continue
        groups.setdefault(group, []).append(species)
    out = {'$comment': 'Written by wild_groups.py: wild Pokémon that count as equivalent, by egg group (docs/efu.md)',
           'groups': {g[len('EGG_GROUP_'):].lower(): s for g, s in sorted(groups.items())}}
    with open(os.path.join(here, 'wild_groups.json'), 'w') as f:
        f.write(json.dumps(out, indent=4) + '\n')
    for g, s in out['groups'].items():
        print(g, len(s))
    print('left out', sorted(set(data) - {s for v in groups.values() for s in v}))


if __name__ == '__main__':
    main()
