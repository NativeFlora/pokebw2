import json,re,collections,sys
root=__import__('os').path.dirname(__import__('os').path.dirname(__import__('os').path.dirname(__import__('os').path.abspath(__file__))))
names=[l.split('=')[0].strip() for l in open(root+'/generated/species.txt') if l.startswith('SPECIES_')]
names=names[1:650]  # Bulbasaur..Genesect
def dirname(c):
    return None
import os
dirs={}
for d in os.listdir(root+'/res/pokemon'):
    p=f'{root}/res/pokemon/{d}/data.json'
    if os.path.exists(p): dirs[d]=json.load(open(p))
# map constant->data by matching name order: constant lower without SPECIES_
data={}
for c in names:
    k=c[8:].lower()
    if k in dirs: data[c]=dirs[k]
missing=[c for c in names if c not in data]
pre=set()
for c,d in data.items():
    for e in d.get('evolutions') or []:
        pre.add(e['species'])
BABIES={'PICHU','CLEFFA','IGGLYBUFF','TOGEPI','TYROGUE','SMOOCHUM','ELEKID','MAGBY','AZURILL','WYNAUT','BUDEW','CHINGLING','BONSLY','MIME_JR','HAPPINY','MUNCHLAX','RIOLU','MANTYKE'}
BABIES={'SPECIES_'+b for b in BABIES}
PSEUDO={'SPECIES_'+b for b in ['DRATINI','LARVITAR','BAGON','BELDUM','GIBLE','DEINO']}
# babies' direct evolutions count as base
babyevo=set()
for b in BABIES:
    for e in data[b].get('evolutions') or []: babyevo.add(e['species'])
out=[]
for c in names:
    d=data.get(c)
    if not d: continue
    evos=[e for e in (d.get('evolutions') or []) if e['species']!='SPECIES_NONE']
    if not evos: continue
    if c in BABIES or c in PSEUDO: continue
    if c in pre and c not in babyevo: continue
    out.append((c,d['name'],d['types']))
print(len(out), 'missing', missing[:5], file=sys.stderr)
bytype=collections.defaultdict(list)
for c,n,t in out:
    bytype[t[0]].append((c,n))
for t,l in sorted(bytype.items(), key=lambda x:-len(x[1])): print(t,len(l), file=sys.stderr)
json.dump(out,open(__import__('os').path.join(__import__('os').path.dirname(__file__),'starters.json'),'w'),indent=0)
