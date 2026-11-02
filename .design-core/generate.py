import argparse,hashlib,json,pathlib,shutil,sys
HERE=pathlib.Path(__file__).resolve().parent
CAPSULE=(HERE/'core.json').exists()
ROOT=HERE if CAPSULE else HERE.parent
SOURCE=ROOT/'core.json' if CAPSULE else ROOT/'source/core.json'
def read(p):return json.loads(p.read_text())
def encoded(x):return json.dumps(x,indent=2,ensure_ascii=False)+'\n'
def digest(b):return hashlib.sha256(b).hexdigest()
def stable(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=False)
core=read(SOURCE);sha=digest(SOURCE.read_bytes());version=core['version'];brand=core['brand']
def swift():
 lines=['enum OurosCoreTokens {',f'    static let version = "{version}"',f'    static let sourceSHA256 = "{sha}"']
 for key,name in [('signal','brandSignalHex'),('artworkStar','artworkStarHex'),('actionBackground','actionBackgroundHex'),('actionForeground','actionForegroundHex')]:lines.append(f'    static let {name}: UInt32 = 0x{brand[key][1:]}')
 return '\n'.join(lines+['}',''])
def rust():
 lines=[f'pub const CORE_VERSION: &str = "{version}";',f'pub const CORE_SHA256: &str = "{sha}";']
 for key,name in [('signal','BRAND_SIGNAL'),('artworkStar','ARTWORK_STAR'),('actionBackground','ACTION_BACKGROUND'),('actionForeground','ACTION_FOREGROUND')]:lines.append(f'pub const {name}: u32 = 0x{brand[key][1:]};')
 return '\n'.join(lines+[''])
def replace(t):
 for k,v in {'CORE_VERSION':version,'CORE_SHA256':sha,**{'BRAND_'+k.upper():v for k,v in brand.items()}}.items():t=t.replace('{{'+k+'}}',v)
 return t
def profile_modules(profile):
 manifest=read(ROOT/'receipt.json') if CAPSULE else read(ROOT/'source/profile-modules.json')
 if CAPSULE:
  return [{'path':m['path'],'definition':(ROOT/m['template']).read_text()}for m in manifest['outputs'] if m['kind']=='template']
 return [{'path':m['target'],'definition':(ROOT/'source'/m['template']).read_text()}for m in manifest['modules']if m['profile']==profile]
def registry():
 profiles={}
 for id,p in core['profiles'].items():profiles[id]={'id':id,'title':p.get('title',id.replace('-',' ').title()),'meta':{'whenToUse':p.get('use',''),'authority':'Versioned Ouros design core '+version,'source':core['authority']},'brand':brand,**p}
 for id,p in profiles.items():p['sourceModules']=profile_modules(id)
 for id in ['website','web-app','web-admin','docs-reader','shared-web']:
  p=profiles[id];p['colors']={'light':{'action-primary':brand['actionBackground'],'action-primary-hover':brand['actionBackground'],'content-on-action':brand['actionForeground']},'dark':{'action-primary':brand['actionBackground'],'action-primary-hover':brand['actionBackground'],'content-on-action':brand['actionForeground']}}
 aliases={'product-web':'website','native-app-shell':'native-shell-registry','marketing-flyers':'website','os-theme-omarchy':'os-theme'}
 for alias,target in aliases.items():
  profiles[alias]={**profiles[target],'id':alias,'canonicalProfile':target}
 obj={'format':'ouros-design-registry-v1','version':version,'source':{'path':core['authority']['canonicalPath'],'sha256':sha},'registry':{'name':'Ouros design core','description':'Versioned surface profiles. Choose the current surface; artwork, UI controls, native themes and the OS skin have explicit separate roles.','profiles':[{'id':id,'title':p['title'],'whenToUse':p.get('use',''),'authority':'Ouros design core '+version,'source':core['authority']['canonicalPath']} for id,p in profiles.items()]},'profiles':profiles}
 obj['integrity']={'sha256':digest(stable(obj).encode())};return encoded(obj)
def base_outputs():
 css=':root {\n'+''.join('  --ouros-core-'+name+': '+brand[key]+';\n' for key,name in [('signal','brand-signal'),('artworkStar','artwork-star'),('actionBackground','action-background'),('actionForeground','action-foreground')])+''.join('  --ouros-core-navigation-'+name+': '+str(core['navigation'][key])+'px;\n'for key,name in [('trayWidth','tray-width'),('headerHeight','header-height'),('desktopHeight','desktop-height'),('mobileSize','mobile-size')])+'}\n'
 js='export const coreVersion = '+json.dumps(version)+';\nexport const coreSha256 = '+json.dumps(sha)+';\nexport const designCore = '+json.dumps(core,ensure_ascii=False,separators=(',',':'))+';\n'
 return {'generated/web.css':css,'generated/web.mjs':js,'generated/web.ts':js.replace('export const designCore = ','export const designCore = ').replace(';\n',' as const;\n'),'generated/OurosCoreTokens.swift':swift(),'generated/design_core.rs':rust(),'generated/design-registry.json':registry(),'generated/receipt.json':encoded({'version':version,'sourceSHA256':sha,'authority':core['authority']})}
def relative(p):
 p=pathlib.PurePosixPath(p)
 if p.is_absolute() or '..' in p.parts:raise ValueError('Export targets must stay inside owning repository')
 return p
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--export-repo');parser.add_argument('--profile');parser.add_argument('--swift',action='append');parser.add_argument('--rust',action='append');args=parser.parse_args()
if args.export_repo:
 if CAPSULE:raise SystemExit('Export from the canonical package, not a pinned consumer')
 target=pathlib.Path(args.export_repo).resolve();capsule=target/'.design-core';capsule.mkdir(parents=True,exist_ok=True)
 shutil.copy2(SOURCE,capsule/'core.json');shutil.copy2(__file__,capsule/'generate.py');shutil.copy2(HERE/'termin8_renderer.py',capsule/'termin8_renderer.py');entries=[]
 for kind,names in [('swift',args.swift),('rust',args.rust)]:
  for name in names or []:entries.append({'kind':kind,'path':str(relative(name))})
 manifest=read(ROOT/'source/profile-modules.json')
 for m in manifest['modules']:
  if m['profile']!=args.profile:continue
  rel=str(relative(m['target']));template=ROOT/'source'/m['template'];dest=capsule/m['template'];dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(template,dest)
  entries.append({'kind':'template','path':rel,'template':m['template'],'sha256':digest(template.read_bytes())})
 receipt={'format':'ouros-pinned-design-core-v1','version':version,'sourceSHA256':sha,'authority':core['authority'],'profile':args.profile,'outputs':entries}
 (capsule/'receipt.json').write_text(encoded(receipt))
 subprocess=None
 import subprocess
 subprocess.run([sys.executable,str(capsule/'generate.py')],check=True)
 print(encoded({'export':str(target),'profile':args.profile,'version':version,'sourceSHA256':sha}));raise SystemExit(0)
if CAPSULE:
 receipt=read(ROOT/'receipt.json')
 if receipt['sourceSHA256']!=sha:raise SystemExit('Pinned source differs from its canonical receipt')
 outputs={};base=ROOT.parent
 for entry in receipt['outputs']:
  if entry['kind']=='swift':text=swift()
  elif entry['kind']=='rust':text=rust()
  else:
   template=ROOT/relative(entry['template'])
   if digest(template.read_bytes())!=entry['sha256']:raise SystemExit('Profile source differs from canonical receipt: '+str(template))
   text=replace(template.read_text())
  outputs[entry['path']]=text
else:
 outputs=base_outputs();base=ROOT
 for m in read(ROOT/'source/profile-modules.json')['modules']:
  if m.get('repository')=='app':outputs['../../'+str(relative(m['target']))]=replace((ROOT/'source'/m['template']).read_text())
errors=[]
for name,text in outputs.items():
 p=base/name
 if args.check:
  if not p.exists() or p.read_text()!=text:errors.append(name)
 else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
if CAPSULE and receipt['profile']=='termin8':
 from termin8_renderer import render_termin8
 for name,text in render_termin8(core).items():
  p=base/name
  if args.check:
   if not p.exists() or p.read_text()!=text:errors.append(name)
  else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
if errors:raise SystemExit('Design core drift: '+', '.join(errors))
print(('Checked' if args.check else 'Generated')+' design core '+version+' '+sha+' ('+str(len(outputs))+' exports)')
