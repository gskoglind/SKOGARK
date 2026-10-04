"""Render Bermuda scenes to final PNGs via headless Chrome. Usage: python3 render.py [scene ...]"""
import subprocess, sys, os
from PIL import Image
from scenes import SCENES, SIZE

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 and os.path.isdir(sys.argv[1]) else os.path.join(HERE, 'out')
names = [a for a in sys.argv[1:] if a in SCENES] or list(SCENES)
os.makedirs(os.path.join(HERE, 'svg'), exist_ok=True)
os.makedirs(OUT, exist_ok=True)

for name in names:
    for o, label in (('L', 'landscape'), ('P', 'portrait')):
        w, h = SIZE[o]
        svg = os.path.join(HERE, 'svg', f'bg_bermuda_{name}_{label}.svg')
        html = svg.replace('.svg', '.html')
        with open(svg, 'w') as f:
            f.write(SCENES[name](o))
        with open(html, 'w') as f:
            f.write(f'<html><body style="margin:0"><img src="file://{svg}" width="{w}" height="{h}"></body></html>')
        png = os.path.join(OUT, f'bg_bermuda_{name}_{label}.png')
        subprocess.run([CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars',
                        '--force-device-scale-factor=1', f'--window-size={w},{h}',
                        f'--screenshot={png}', f'file://{html}'], capture_output=True)
        im = Image.open(png).convert('RGB')
        assert im.size == (w, h), (png, im.size)
        im.save(png, optimize=True)
        print(png, im.size)
