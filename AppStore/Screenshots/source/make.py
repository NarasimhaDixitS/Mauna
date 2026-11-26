import os, subprocess, sys
root=os.path.dirname(os.path.abspath(__file__))  # ui/ holds MAUNA_SNAPSHOT_SCALE=3 renders; writes out/
CSS='''
*{margin:0;box-sizing:border-box}
html,body{width:2880px;height:1800px;overflow:hidden}
body{font-family:-apple-system,"SF Pro Display",BlinkMacSystemFont,sans-serif;color:#F6F0E3;
 background:radial-gradient(1500px 1100px at var(--gx,78%) var(--gy,22%),rgba(214,170,86,.30),rgba(214,170,86,.07) 45%,transparent 70%),
 radial-gradient(1200px 900px at 10% 110%,rgba(120,86,30,.28),transparent 70%),linear-gradient(160deg,#141210,#0A0908 60%,#0D0B09);
 -webkit-font-smoothing:antialiased;position:relative}
.grain{position:absolute;inset:0;opacity:.05;background-image:url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='200' height='200'><filter id='n'><feTurbulence baseFrequency='.9' numOctaves='2'/></filter><rect width='200' height='200' filter='url(%23n)'/></svg>")}
.eyebrow{display:flex;align-items:center;gap:26px;font-size:40px;font-weight:600;letter-spacing:.16em;text-transform:uppercase;color:#E6C98A}
.eyebrow img{width:104px;height:104px;filter:drop-shadow(0 10px 30px rgba(233,199,123,.35))}
h1{font-size:132px;line-height:1.04;font-weight:700;letter-spacing:-.025em;margin-top:56px}
h1 em{font-style:normal;background:linear-gradient(180deg,#F5E1AE,#C99E52);-webkit-background-clip:text;color:transparent}
p.sub{font-size:50px;line-height:1.38;color:#BFB49F;margin-top:44px;font-weight:400}
.left{position:absolute;left:210px;top:0;bottom:0;width:1240px;display:flex;flex-direction:column;justify-content:center}
.top{position:absolute;left:0;right:0;top:130px;text-align:center}
.top h1{margin-top:0;font-size:120px}.top p.sub{margin:30px auto 0;max-width:1900px}
.menubar{position:absolute;left:0;right:0;top:0;height:76px;background:rgba(30,27,22,.55);backdrop-filter:blur(30px);
 border-bottom:1px solid rgba(255,255,255,.06);display:flex;justify-content:flex-end;align-items:center;gap:44px;padding-right:60px;font-size:34px;font-weight:500;color:#EDE6D8}
.mb-glyph{width:84px;height:58px;border-radius:14px;background:rgba(255,255,255,.16);display:flex;align-items:center;justify-content:center}
.pop{position:absolute;top:104px;border-radius:38px;overflow:hidden;box-shadow:0 60px 140px rgba(0,0,0,.6),0 0 0 1.5px rgba(255,255,255,.13),0 0 120px rgba(214,170,86,.12)}
.pop img{display:block}
.win{position:absolute;left:50%;transform:translateX(-50%);border-radius:34px;overflow:hidden;
 box-shadow:0 70px 160px rgba(0,0,0,.65),0 0 0 1.5px rgba(255,255,255,.12),0 0 160px rgba(214,170,86,.10)}
.win img{display:block}
.lights{position:absolute;left:30px;top:24px;display:flex;gap:18px}
.lights i{width:26px;height:26px;border-radius:50%;display:block}
.fade{position:absolute;left:0;right:0;bottom:0;height:260px;background:linear-gradient(transparent,#0B0A08)}
'''
BARS='<svg width="44" height="30" viewBox="0 0 44 30"><g fill="#F1DEAE">'+''.join(f'<rect x="{x}" y="{15-h/2}" width="5" height="{h}" rx="2.5"/>' for x,h in [(2,10),(11,22),(20,30),(29,16),(38,8)])+'</g></svg>'
def menubar(): return f'<div class="menubar"><div class="mb-glyph">{BARS}</div><span>Thu 26 Nov&nbsp;&nbsp;9:41</span></div>'
def lights(): return '<div class="lights"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div>'
def page(body, gx='78%', gy='22%'):
    return f'<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body style="--gx:{gx};--gy:{gy}"><div class="grain"></div>{body}</body></html>'
def left(eyebrow, title, sub):
    eb=f'<div class="eyebrow"><img src="../ui/icon.png">Mauna</div>' if eyebrow else ''
    return f'<div class="left">{eb}<h1>{title}</h1><p class="sub">{sub}</p></div>'
def popslide(img, h, title, sub, eyebrow=False, crop=None):
    style=f'right:240px;width:960px;height:{crop or h}px'
    return page(menubar()+left(eyebrow,title,sub)+f'<div class="pop" style="{style}"><img src="../ui/{img}" width="960"></div>')
def winslide(img, w, title, sub, top, height=None, sidebar=None):
    hs=f'height:{height}px;' if height else ''
    # A title bar strip for the window controls: sidebar colour on the left, content colour on the right.
    side=round(600*w/ (2580 if sidebar is None else 2460)) if sidebar else 0
    hs+=f'padding-top:74px;background:linear-gradient(90deg,#272727 0 {side}px,#1E1E1E {side}px);' 
    fade='<div class="fade"></div>' if height else ''
    return page(f'<div class="top"><h1>{title}</h1><p class="sub">{sub}</p></div><div class="win" style="top:{top}px;width:{w}px;{hs}"><img src="../ui/{img}" width="{w}">{lights()}</div>{fade}', gx='50%', gy='0%')
slides={
 '1-hero': popslide('pop-focus.png',1416,'Your music steps aside, <em>on its own.</em>','Pick the apps that need quiet. Mauna pauses or lowers your music while you use them, then brings it back.',eyebrow=True),
 '2-calls': popslide('pop-call.png',1416,'Calls pause your music. <em>Automatically.</em>','“In a call” notices when Zoom or FaceTime takes the microphone, even while you work in another app.'),
 '3-rules': winslide('rules.png',2000,'A rule for <em>every app.</em>','Pause for films and games, lower for focus. Apps sort themselves into groups you can fold.',top=460,height=1400,sidebar=True),
 '4-players': popslide('pop-choose.png',1862,'Works with the player <em>you love.</em>','Apple Music, Spotify, and YouTube Music in Chrome or Safari. Switch any time from the menu bar.',crop=1640),
 '5-sound': winslide('sound.png',2050,'Fades in. Fades out. <em>Never jolts.</em>','Music eases away and drifts back, at the volume you choose.',top=540,sidebar=True),
 '6-pro': winslide('upgrade.png',2080,'Pay once. <em>Yours for life.</em>','Try every Pro feature free for 7 days. No subscription, ever.',top=440),
}
chrome='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
os.makedirs(f'{root}/out',exist_ok=True)
for name,html in slides.items():
    path=f'{root}/html/{name}.html'; open(path,'w').write(html)
    subprocess.run([chrome,'--headless=new','--disable-gpu','--hide-scrollbars','--force-device-scale-factor=1','--window-size=2880,1800',f'--screenshot={root}/out/{name}.png','file://'+path],stderr=subprocess.DEVNULL,stdout=subprocess.DEVNULL)
    print(name)
