"""Escape from Unova: writes tools/efu/wild_groups.json, the groups of wild Pokémon that count as equivalent.

Each species that can be met in the wild goes in one of 34 groups by where it lives and the part it plays (route
birds, route rodents, cave dwellers, open sea...), a whole evolution line together, babies included. Each also gets a
tier, its point in its line by feel: 1 for the first stage, 2 for a middle one, 3 for a final one. A Pokémon that
doesn't evolve, or the end of a two-stage line, is 2 or 3 by strength (3 from a base stat total of 470), with FEEL
overriding where the numbers don't match how strong it feels. An exploration swaps a wild Pokémon only for one of
the same group and tier (build_raid.py's build_wild_swap). Legendary and mythical Pokémon are in no group, since none
can be caught in the wild.
"""
import json, os

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(os.path.dirname(here))

# Each group's evolution lines, by the first Pokémon of each (a baby where there is one)
GROUPS = {
    'route_birds': 'pidgey spearow hoothoot taillow starly pidove',
    'uncommon_birds': 'farfetchd doduo murkrow swablu chatot rufflet vullaby skarmory',
    'route_rodents': 'rattata sentret zigzagoon bidoof patrat minccino buneary',
    'route_cats_dogs': 'meowth glameow skitty purrloin lillipup poochyena shinx electrike',
    'pasture': 'mareep tauros miltank stantler deerling blitzle ponyta girafarig bouffalant kangaskhan lickitung',
    'forest_beasts': 'teddiursa aipom slakoth munchlax',
    'grassland_predators': 'ekans nidoran_f nidoran_m seviper zangoose',
    'fairies': 'cleffa igglybuff togepi snubbull audino happiny',
    'rare_curiosities': 'eevee ditto smeargle castform spinda kecleon',
    'route_bugs': 'caterpie weedle wurmple kricketot burmy spinarak sewaddle venipede',
    'flying_insects': 'ledyba yanma combee volbeat illumise venonat nincada',
    'beetles': 'scyther pinsir heracross pineco shuckle karrablast shelmet durant',
    'meadow_flowers': 'oddish bellsprout hoppip sunkern budew cherubi cottonee petilil',
    'forest_plants': 'seedot shroomish paras tangela exeggcute tropius carnivine foongus ferroseed',
    'partners': 'bulbasaur charmander squirtle chikorita cyndaquil totodile treecko torchic mudkip turtwig chimchar piplup snivy tepig oshawott pansage pansear panpour',
    'volcanic': 'vulpix growlithe slugma numel torkoal houndour magby darumaka heatmor',
    'electric_critters': 'pichu plusle minun pachirisu emolga joltik tynamo',
    'machines': 'magnemite voltorb porygon klink rotom elekid',
    'city_alley': 'grimer koffing trubbish gulpin stunky zorua pawniard absol',
    'cave_dwellers': 'zubat woobat whismur sableye mawile dunsparce gligar',
    'living_rock': 'geodude onix roggenrola nosepass aron bonsly lunatone solrock',
    'burrowers': 'sandshrew diglett drilbur cubone rhyhorn phanpy',
    'desert': 'trapinch hippopotas sandile cacnea maractus larvesta dwebble skorupi',
    'ghosts': 'gastly misdreavus shuppet duskull drifloon litwick spiritomb',
    'ancient_ruins': 'unown baltoy golett bronzor sigilyph yamask elgyem',
    'psychics': 'abra drowzee ralts spoink wynaut chingling mime_jr munna gothita solosis natu smoochum',
    'fighters': 'mankey machop tyrogue makuhita meditite riolu croagunk timburr throh sawk mienfoo scraggy',
    'snow_ice': 'swinub snorunt sneasel delibird snover vanillite cubchoo cryogonal spheal seel',
    'pond_swamp': 'poliwag psyduck wooper azurill lotad surskit tympole buizel stunfisk',
    'river_fish': 'goldeen magikarp barboach corphish feebas basculin',
    'beach_shore': 'krabby shellder staryu corsola clamperl shellos slowpoke wingull ducklett',
    'open_sea': 'tentacool horsea chinchou qwilfish remoraid carvanha wailmer mantyke finneon luvdisc frillish alomomola relicanth lapras',
    'fossils': 'omanyte kabuto aerodactyl lileep anorith cranidos shieldon tirtouga archen',
    'apex': 'dratini bagon gible axew deino druddigon larvitar beldum',
}

# Tiers set by feel, over the rule
FEEL = {
    # The first form players know, though a baby comes before it
    'pikachu': 1, 'clefairy': 1, 'jigglypuff': 1, 'marill': 1,
    # Ends of lines that stay modest
    'wigglytuff': 2, 'azumarill': 2, 'stunfisk': 2,
    # Ends of lines that hit hard
    'hitmonlee': 3, 'hitmonchan': 3, 'hitmontop': 3, 'mr_mime': 3, 'jynx': 3, 'throh': 3, 'sawk': 3, 'absol': 3,
    'skarmory': 3, 'breloom': 3, 'sharpedo': 3,
    # First forms that are already strong, since their evolution came in a later generation
    'scyther': 3, 'lickitung': 2, 'tangela': 2, 'yanma': 2, 'murkrow': 2, 'misdreavus': 2, 'gligar': 2,
    'sneasel': 2, 'onix': 2, 'nosepass': 2,
}
FINAL_BST = 470


def species_list():
    names = []
    for line in open(os.path.join(root, 'generated/species.txt')):
        line = line.split('#')[0].split('=')[0].strip()
        if line.startswith('SPECIES_') and line != 'SPECIES_NONE':
            names.append(line)
    return names


def load(species):
    return json.load(open(os.path.join(root, 'res/pokemon', species[len('SPECIES_'):].lower(), 'data.json')))


def main():
    order = species_list()
    line_of = {}
    for group, firsts in GROUPS.items():
        for first in firsts.split():
            line_of['SPECIES_' + first.upper()] = group
    data, before = {}, {}
    todo = list(line_of)
    while todo:
        species = todo.pop()
        data[species] = load(species)
        for evo in data[species]['evolutions']:
            if evo['species'] not in data and evo['species'] not in todo:
                before.setdefault(evo['species'], species)
                todo.append(evo['species'])

    def first_of(species):
        while species in before:
            species = before[species]
        return species

    groups, tiers = {g: [] for g in GROUPS}, {}
    for species in sorted(data, key=order.index):
        groups[line_of[first_of(species)]].append(species)
        name = species[len('SPECIES_'):].lower()
        evolves = bool(data[species]['evolutions'])
        if name in FEEL:
            tier = FEEL[name]
        elif species not in before:
            tier = 1 if evolves else None
        elif evolves or before[species] in before:
            tier = 2 if evolves else 3
        else:
            tier = None
        if tier is None:
            tier = 3 if sum(data[species]['base_stats'].values()) >= FINAL_BST else 2
        tiers[species] = tier
    out = {'$comment': 'Written by wild_groups.py: wild Pokémon that count as equivalent, by habitat, and each '
                       'one\'s tier (1 first stage, 2 middle, 3 final) (docs/efu.md)',
           'groups': groups, 'tiers': tiers}
    with open(os.path.join(here, 'wild_groups.json'), 'w') as f:
        f.write(json.dumps(out, indent=4, ensure_ascii=False) + '\n')
    print(len(groups), 'groups,', len(tiers), 'species')


if __name__ == '__main__':
    main()
