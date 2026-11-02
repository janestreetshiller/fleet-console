import argparse,hashlib,json,pathlib,shutil,sys,re
sys.dont_write_bytecode=True
HERE=pathlib.Path(__file__).resolve().parent
CAPSULE=(HERE/'core.json').exists()
ROOT=HERE if CAPSULE else HERE.parent
SOURCE=ROOT/'core.json' if CAPSULE else ROOT/'source/core.json'
def read(p):return json.loads(p.read_text())
def encoded(x):return json.dumps(x,indent=2,ensure_ascii=False)+'\n'
def digest(b):return hashlib.sha256(b).hexdigest()
def stable(x):return json.dumps(x,sort_keys=True,separators=(',',':'),ensure_ascii=False)
core=read(SOURCE);sha=digest(SOURCE.read_bytes());version=core['version'];brand=core['brand']
if core.get('generatorSHA256')!=digest(pathlib.Path(__file__).read_bytes()):raise SystemExit('Core generator identity drift')
for name,expected in core.get('rendererSHA256',{}).items():
 if digest((HERE/name).read_bytes())!=expected:raise SystemExit('Core renderer identity drift: '+name)
if not CAPSULE:
 if digest((ROOT/'scripts/check.mjs').read_bytes())!=core['checkerSHA256']:raise SystemExit('Core hosted checker identity drift')
 if digest((ROOT/'source/profile-modules.json').read_bytes())!=core['profileModuleManifestSHA256']:raise SystemExit('Core module manifest identity drift')
 for asset in core.get('assets',{}).values():
  if digest((ROOT/'source'/asset['bundlePath']).read_bytes())!=asset['sha256']:raise SystemExit('Original artwork identity drift: '+asset['bundlePath'])
 for module in read(ROOT/'source/profile-modules.json')['modules']:
  if digest((ROOT/'source'/module['template']).read_bytes())!=module['sha256']:raise SystemExit('Core profile source identity drift: '+module['template'])
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
 def resolved(x):
  if isinstance(x,dict) and set(x)=={'$ref'}:
   value=core
   for key in x['$ref'].split('.'):value=value[key]
   return value
  if isinstance(x,dict):return {k:resolved(v)for k,v in x.items()}
  if isinstance(x,list):return [resolved(v)for v in x]
  return x
 profiles={}
 for id,p in core['profiles'].items():profiles[id]={'id':id,'title':p.get('title',id.replace('-',' ').title()),'meta':{'whenToUse':p.get('use',''),'authority':'Versioned Ouros design core '+version,'source':core['authority']},'brand':brand,**resolved(p)}
 for id,p in profiles.items():p['sourceModules']=profile_modules(id)
 native=profiles['native-shell-registry'].get('nativeShell',{})
 for source,target in [('color','colors'),('space','spacing'),('type','typography'),('geometry','geometry'),('motion','motion'),('material','material')]:
  if source in native:profiles['native-shell-registry'][target]=native[source]
 for key in ['colors','ansi','assets','rights','usage','doNot']:
  if key in profiles['os-theme'].get('osTheme',{}):profiles['os-theme'][key]=profiles['os-theme']['osTheme'][key]
 for id in ['website','docs-reader','native-shell-registry']:
  profiles[id]['assets']=core.get('assets',{})
 for id in ['website','web-app']:
  p=profiles[id];p['colors']={'light':{'action-primary':brand['actionBackground'],'action-primary-hover':brand['actionBackground'],'content-on-action':brand['actionForeground']},'dark':{'action-primary':brand['actionBackground'],'action-primary-hover':brand['actionBackground'],'content-on-action':brand['actionForeground']}}
 admin_sources=profile_modules('web-admin')
 admin_text=next((m['definition']for m in admin_sources if m['path'].endswith('admin-palette.ts')),'')
 admin_colors={}
 for mode in ['light','dark']:
  match=re.search(mode+r':\s*\{(.*?)\}',admin_text,re.S)
  if match:
   values=dict(re.findall(r'(\w+):\s*[\"\']([^\"\']+)[\"\']',match[1]))
   admin_colors[mode]={'action-primary':values['primary'],'action-primary-hover':values['hover'],'content-on-action':values['onPrimary']}
 profiles['web-admin']['colors']=admin_colors
 aliases={'product-web':'web-app','native-app-shell':'native-shell-registry','marketing-flyers':'website','os-theme-omarchy':'os-theme'}
 for alias,target in aliases.items():
  profiles[alias]={**profiles[target],'id':alias,'canonicalProfile':target}
 obj={'format':'ouros-design-registry-v1','version':version,'source':{'path':core['authority']['canonicalPath'],'sha256':sha},'registry':{'name':'Ouros design core','description':'Versioned surface profiles. Choose the current surface; artwork, UI controls, native themes and the OS skin have explicit separate roles.','profiles':[{'id':id,'title':p['title'],'whenToUse':p.get('use',''),'authority':'Ouros design core '+version,'source':core['authority']['canonicalPath']} for id,p in profiles.items()]},'profiles':profiles}
 def normalize(x):
  if isinstance(x,float)and x.is_integer():return int(x)
  if isinstance(x,dict):return {k:normalize(v)for k,v in x.items()}
  if isinstance(x,list):return [normalize(v)for v in x]
  return x
 obj=normalize(obj)
 obj['integrity']={'sha256':digest(stable(obj).encode())};return encoded(obj)
def base_outputs():
 css=':root {\n'
 for key,name in [('signal','brand-signal'),('artworkStar','artwork-star'),('actionBackground','action-background'),('actionForeground','action-foreground')]:css+='  --ouros-core-'+name+': '+brand[key]+';\n'
 for key,name in [('trayWidth','tray-width'),('headerHeight','header-height'),('desktopHeight','desktop-height'),('mobileSize','mobile-size'),('iconSize','icon-size'),('wordmarkWidth','wordmark-width'),('wordmarkHeight','wordmark-height'),('brandGap','brand-gap'),('mobileIconSize','mobile-icon-size')]:css+='  --ouros-core-navigation-'+name+': '+str(core['navigation'][key])+'px;\n'
 for key in ['surface','foreground']:css+='  --ouros-core-navigation-'+key+': '+core['navigation'][key]+';\n'
 css+='}\n'
 js='export const coreVersion = '+json.dumps(version)+';\nexport const coreSha256 = '+json.dumps(sha)+';\nexport const designCore = '+json.dumps(core,ensure_ascii=False,separators=(',',':'))+';\n'
 safe='export const coreVersion = '+json.dumps(version)+';\nexport const coreSha256 = '+json.dumps(sha)+';\nexport const brand = '+json.dumps(brand,separators=(',',':'))+';\n'
 return {'generated/brand.mjs':safe,'generated/brand.ts':safe.replace(';\n',' as const;\n'),'generated/web.css':css,'generated/web.mjs':js,'generated/web.ts':js.replace('export const designCore = ','export const designCore = ').replace(';\n',' as const;\n'),'generated/OurosCoreTokens.swift':swift(),'generated/design_core.rs':rust(),'generated/design-registry.json':registry(),'generated/receipt.json':encoded({'version':version,'sourceSHA256':sha,'authority':core['authority']})}
def relative(p):
 p=pathlib.PurePosixPath(p)
 if p.is_absolute() or '..' in p.parts:raise ValueError('Export targets must stay inside owning repository')
 return p
parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');parser.add_argument('--export-repo');parser.add_argument('--profile');parser.add_argument('--swift',action='append');parser.add_argument('--rust',action='append');args=parser.parse_args()
if args.export_repo:
 if not args.profile or args.profile not in core['profiles']:parser.error('Choose a known active core profile')
 requested=[{'kind':kind,'path':str(relative(name))}for kind,names in [('swift',args.swift),('rust',args.rust)]for name in names or []]
 expected=core.get('runtimeExports',{}).get(args.profile,[])
 if requested and sorted(requested,key=lambda e:e['path'])!=sorted(expected,key=lambda e:e['path']):parser.error('Runtime export paths must match the canonical profile')
 if not requested:
  args.swift=[e['path']for e in expected if e['kind']=='swift'];args.rust=[e['path']for e in expected if e['kind']=='rust']
 if CAPSULE:raise SystemExit('Export from the canonical package, not a pinned consumer')
 target=pathlib.Path(args.export_repo).resolve();capsule=target/'.design-core';capsule.mkdir(parents=True,exist_ok=True)
 shutil.copy2(SOURCE,capsule/'core.json');shutil.copy2(ROOT/'source/profile-modules.json',capsule/'profile-modules.json');shutil.copy2(__file__,capsule/'generate.py');shutil.copy2(HERE/'termin8_renderer.py',capsule/'termin8_renderer.py');entries=[]
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
 if digest((ROOT/'profile-modules.json').read_bytes())!=core['profileModuleManifestSHA256']:raise SystemExit('Pinned canonical module manifest drift')
 manifest=read(ROOT/'profile-modules.json')
 expected_templates={(m['target'],m['template'],m['sha256'])for m in manifest['modules']if m['profile']==receipt['profile']}
 actual_templates={(m['path'],m['template'],m['sha256'])for m in receipt['outputs']if m['kind']=='template'}
 if expected_templates!=actual_templates:raise SystemExit('Pinned profile entries differ from the canonical module manifest')
 if args.profile and args.profile!=receipt['profile']:raise SystemExit('Pinned profile differs from owning application')
 actual_globals=[{'kind':m['kind'],'path':m['path']}for m in receipt['outputs']if m['kind'] in ['swift','rust']]
 if sorted(actual_globals,key=lambda e:e['path'])!=sorted(core.get('runtimeExports',{}).get(receipt['profile'],[]),key=lambda e:e['path']):raise SystemExit('Pinned runtime export paths differ from canonical profile')
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
  if m.get('repository')=='app' and (ROOT.parent.parent/'.git').exists():outputs['../../'+str(relative(m['target']))]=replace((ROOT/'source'/m['template']).read_text())
errors=[]
for name,text in outputs.items():
 p=base/name
 if args.check:
  if not p.exists() or p.read_text()!=text:errors.append(name)
 else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
if CAPSULE and receipt['profile']=='termin8':
 import importlib.util
 spec=importlib.util.spec_from_file_location('ouros_core_termin8_renderer',HERE/'termin8_renderer.py');renderer=importlib.util.module_from_spec(spec);spec.loader.exec_module(renderer)
 for name,text in renderer.render_termin8(core).items():
  p=base/name
  if args.check:
   if not p.exists() or p.read_text()!=text:errors.append(name)
  else:p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
if errors:raise SystemExit('Design core drift: '+', '.join(errors))
print(('Checked' if args.check else 'Generated')+' design core '+version+' '+sha+' ('+str(len(outputs))+' exports)')
