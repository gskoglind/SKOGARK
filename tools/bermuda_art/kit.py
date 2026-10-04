"""Drawing kit for SKOGARK Bermuda scenes: flat vector, no outlines (ART_BIBLE.md)."""
import random

# ---------- palette ----------
C = dict(
    coral='#E6A497', coral_d='#D08D80', butter='#F0DA9C', mint='#AFD6BE', pblue='#AECBDD',
    roof='#F5F2EB', roof_d='#E3DED3', lime='#ECE5D7', lime_d='#DDD3C1',
    sky_top='#9FCBE3', sky_bot='#D7ECF3', water='#5DB6B4', water_l='#85CBC6', water_d='#4AA19F',
    wood='#B48A61', wood_d='#8E6B4B', wood_dd='#6E5239', green='#8FB07A', green_d='#6F9460',
    grey='#8C9196', grey_d='#5E646A', ink='#2E2622', white='#F7F5F0',
)

SHADOW = 'rgba(40,30,20,0.13)'


def r(x, y, w, h, fill, rx=0, extra=''):
    return f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx:.1f}" fill="{fill}" {extra}/>'


def el(cx, cy, rx, ry, fill, extra=''):
    return f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{fill}" {extra}/>'


def ci(cx, cy, rad, fill, extra=''):
    return el(cx, cy, rad, rad, fill, extra)


def poly(pts, fill, extra=''):
    p = ' '.join(f'{x:.1f},{y:.1f}' for x, y in pts)
    return f'<polygon points="{p}" fill="{fill}" {extra}/>'


def path(d, fill, extra=''):
    return f'<path d="{d}" fill="{fill}" {extra}/>'


def line(x1, y1, x2, y2, col, w, cap='round'):
    return (f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
            f'stroke="{col}" stroke-width="{w:.1f}" stroke-linecap="{cap}"/>')


def shadow(cx, cy, rx, ry=None):
    return el(cx, cy, rx, ry or rx * 0.16, SHADOW)


def text(x, y, s, size, fill, anchor='middle', weight=700, family="'Marker Felt','Chalkboard SE','Avenir Next',sans-serif", extra=''):
    return (f'<text x="{x:.1f}" y="{y:.1f}" font-family="{family}" font-size="{size:.1f}" '
            f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}" {extra}>{s}</text>')


class Doc:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.defs = []
        self.body = []
        self._n = 0

    def add(self, *parts):
        for p in parts:
            if isinstance(p, (list, tuple)):
                self.body.extend(p)
            else:
                self.body.append(p)

    def lin_grad(self, stops, x1=0, y1=0, x2=0, y2=1):
        self._n += 1
        gid = f'g{self._n}'
        s = ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in
                    [(t + (1,)) if len(t) == 2 else t for t in stops])
        self.defs.append(f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}">{s}</linearGradient>')
        return f'url(#{gid})'

    def rad_grad(self, stops):
        self._n += 1
        gid = f'g{self._n}'
        s = ''.join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
        self.defs.append(f'<radialGradient id="{gid}">{s}</radialGradient>')
        return f'url(#{gid})'

    def clip(self, inner):
        self._n += 1
        cid = f'c{self._n}'
        self.defs.append(f'<clipPath id="{cid}">{inner}</clipPath>')
        return f'clip-path="url(#{cid})"'

    def svg(self):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}"><defs>{"".join(self.defs)}</defs>'
                + ''.join(self.body) + '</svg>')


# ---------- people ----------
def person(cx, feet, H, skin, hair, top, hair_style='short', top_style='shirt', bottom=None,
           socks=None, shoes='#5E4532', face=True, back=False, gaze=0.0, look='front',
           arm_l=4, arm_r=4, seated_y=None, lapel='#F3EEE4', upper_only=False, hat=None):
    """Chunky 3.8-head figure. Angles in degrees, positive = arm swings outward.
    seated_y: y of the seat (front view, thighs foreshortened)."""
    u = H / 3.8
    out = []
    top_y = feet - H
    hcy = top_y + 0.5 * u
    sh_y = top_y + 1.02 * u
    hip_y = sh_y + 1.25 * u
    if seated_y is not None:
        hip_y = seated_y
        sh_y = hip_y - 1.25 * u
        hcy = sh_y - 0.52 * u
    skirt_bot = hip_y + 0.8 * u

    if not upper_only:
        out.append(shadow(cx, feet, 0.85 * u))
        # legs
        leg_top = hip_y if seated_y is None else hip_y + 0.25 * u
        for s in (-1, 1):
            lx = cx + s * 0.25 * u
            out.append(r(lx - 0.17 * u, leg_top, 0.34 * u, feet - leg_top - 0.06 * u, skin, 0.15 * u))
            if socks:
                out.append(r(lx - 0.175 * u, feet - 0.72 * u, 0.35 * u, 0.66 * u, socks, 0.08 * u))
            out.append(r(lx - 0.21 * u + s * 0.04 * u, feet - 0.17 * u, 0.42 * u, 0.19 * u, shoes, 0.09 * u))
        # bottoms
        if top_style == 'dress':
            sb = skirt_bot if seated_y is None else hip_y + 0.45 * u
            out.append(poly([(cx - 0.55 * u, hip_y - 0.2 * u), (cx + 0.55 * u, hip_y - 0.2 * u),
                             (cx + 0.78 * u, sb), (cx - 0.78 * u, sb)], top))
            out.append(r(cx - 0.78 * u, sb - 0.12 * u, 1.56 * u, 0.14 * u, top, 0.07 * u))
        elif bottom:
            sb = hip_y + 0.58 * u if seated_y is None else hip_y + 0.42 * u
            out.append(r(cx - 0.57 * u, hip_y - 0.18 * u, 1.14 * u, 0.36 * u, bottom, 0.08 * u))
            for s in (-1, 1):
                x0 = cx - 0.57 * u if s < 0 else cx + 0.02 * u
                out.append(r(x0, hip_y - 0.05 * u, 0.55 * u, sb - hip_y + 0.05 * u, bottom, 0.06 * u))

    hrx, hry = 0.46 * u, 0.5 * u
    if hair_style in ('bob', 'long') and not back:
        hb = hcy + (0.42 * u if hair_style == 'bob' else 0.95 * u)
        out.append(r(cx - 0.57 * u, hcy - 0.45 * u, 1.14 * u, hb - hcy + 0.45 * u, hair, 0.3 * u))
    # torso
    tw = 1.16 * u
    t_bot = hip_y + 0.02 * u
    out.append(r(cx - 0.12 * u, sh_y - 0.22 * u, 0.24 * u, 0.3 * u, skin))  # neck
    out.append(r(cx - tw / 2, sh_y, tw, t_bot - sh_y, top, 0.24 * u))
    if top_style == 'blazer' and not back:
        out.append(poly([(cx - 0.2 * u, sh_y), (cx + 0.2 * u, sh_y), (cx, sh_y + 0.6 * u)], lapel))
        out.append(r(cx - 0.03 * u, sh_y + 0.6 * u, 0.06 * u, t_bot - sh_y - 0.62 * u, 'rgba(0,0,0,0.12)'))
    if top_style == 'dress' and not back:
        out.append(path(f'M{cx - 0.2 * u:.1f},{sh_y:.1f} Q{cx:.1f},{sh_y + 0.28 * u:.1f} {cx + 0.2 * u:.1f},{sh_y:.1f} Z', skin))
    # arms
    long_sleeve = top_style == 'blazer'
    sleeveless = top_style == 'dress'
    for s, ang in ((-1, arm_l), (1, arm_r)):
        sx = cx + s * (tw / 2 - 0.06 * u)
        sy = sh_y + 0.14 * u
        a = ang if s < 0 else -ang
        g = [f'<g transform="rotate({a:.1f},{sx:.1f},{sy:.1f})">']
        L = 1.22 * u
        aw = 0.27 * u
        g.append(r(sx - aw / 2, sy - 0.1 * u, aw, L, skin, aw / 2))
        if long_sleeve:
            g.append(r(sx - aw / 2 - 0.01 * u, sy - 0.12 * u, aw + 0.02 * u, L - 0.05 * u, top, aw / 2))
        elif not sleeveless:
            g.append(r(sx - aw / 2 - 0.03 * u, sy - 0.14 * u, aw + 0.06 * u, 0.48 * u, top, 0.12 * u))
        g.append(ci(sx, sy + L - 0.06 * u, 0.17 * u, skin))
        g.append('</g>')
        out.extend(g)

    # head
    if hair_style in ('bob', 'long') and back:
        hb = hcy + (0.42 * u if hair_style == 'bob' else 0.95 * u)
        out.append(r(cx - 0.57 * u, hcy - 0.45 * u, 1.14 * u, hb - hcy + 0.45 * u, hair, 0.3 * u))
    if hair_style == 'updo':
        out.append(ci(cx, hcy - 0.55 * u, 0.24 * u, hair))
    if not back:
        out.append(ci(cx - hrx, hcy + 0.05 * u, 0.12 * u, skin))
        out.append(ci(cx + hrx, hcy + 0.05 * u, 0.12 * u, skin))
    out.append(el(cx, hcy, hrx, hry, skin))
    if back:
        out.append(el(cx, hcy - 0.07 * u, hrx * 1.04, hry * 0.93, hair))
        if hair_style in ('bob', 'long'):
            hb = hcy + (0.42 * u if hair_style == 'bob' else 0.95 * u)
            out.append(r(cx - 0.55 * u, hcy - 0.1 * u, 1.1 * u, hb - hcy + 0.1 * u, hair, 0.28 * u))
    else:
        if look == 'up':
            fy, ctl = hcy - 0.18 * u, hcy - 0.38 * u
        else:
            fy, ctl = hcy - 0.02 * u, hcy - 0.2 * u
        rx2 = hrx * 1.04
        out.append(path(f'M{cx - rx2:.1f},{fy:.1f} A{rx2:.1f},{hry * 1.04:.1f} 0 0 1 {cx + rx2:.1f},{fy:.1f} '
                        f'Q{cx:.1f},{ctl:.1f} {cx - rx2:.1f},{fy:.1f} Z', hair))
        if hat:
            out.append(path(f'M{cx - hrx * 1.1:.1f},{hcy - 0.15 * u:.1f} A{hrx * 1.1:.1f},{hry:.1f} 0 0 1 {cx + hrx * 1.1:.1f},{hcy - 0.15 * u:.1f} Z', hat))
            out.append(r(cx - hrx * 1.35, hcy - 0.2 * u, hrx * 2.7, 0.09 * u, hat, 0.04 * u))
        if face:
            ey = hcy + (0.0 if look == 'up' else 0.12 * u)
            for s in (-1, 1):
                out.append(el(cx + s * 0.18 * u + gaze * 0.07 * u, ey, 0.065 * u, 0.085 * u, C['ink']))
                out.append(el(cx + s * 0.3 * u, hcy + 0.27 * u, 0.1 * u, 0.065 * u, '#E58F86', 'opacity="0.6"'))
            if look == 'up':
                out.append(el(cx, hcy + 0.27 * u, 0.06 * u, 0.07 * u, '#4A3028'))
            else:
                my = hcy + 0.29 * u
                out.append(path(f'M{cx - 0.12 * u:.1f},{my:.1f} Q{cx:.1f},{my + 0.09 * u:.1f} {cx + 0.12 * u:.1f},{my:.1f}',
                                'none', f'stroke="#3A2A22" stroke-width="{0.032 * u:.1f}" stroke-linecap="round"'))
    return out


def far_figure(cx, feet, H, skin, top, hat=None, bottom=None):
    """Distant figure: no face."""
    u = H / 3.8
    out = [r(cx - 0.3 * u, feet - 1.5 * u, 0.6 * u, 1.5 * u, bottom or C['grey_d'], 0.15 * u),
           r(cx - 0.55 * u, feet - 2.8 * u, 1.1 * u, 1.45 * u, top, 0.25 * u),
           el(cx, feet - 3.3 * u, 0.45 * u, 0.5 * u, skin)]
    if hat:
        out.append(path(f'M{cx - 0.55 * u:.1f},{feet - 3.4 * u:.1f} A{0.55 * u:.1f},{0.5 * u:.1f} 0 0 1 {cx + 0.55 * u:.1f},{feet - 3.4 * u:.1f} Z', hat))
    return out


# ---------- the cast (friendly, by role) ----------
PLAYER = dict(skin='#EBBF9C', hair='#5A3E2B', top='#87AAC4', bottom='#CDB88E', socks='#3F5B7A', shoes='#6B4E36')
DIANA = dict(skin='#F0C9AA', hair='#8A5A3C', hair_style='bob', top='#EED08A', top_style='dress', shoes='#C48D6C')


# ---------- props ----------
def stepped_roof(x, w, y, steps=3, step_h=None, fill=None):
    """White Bermuda roof: limestone ridges stepping in, sitting on y."""
    sh = step_h or max(10, w * 0.045)
    out = []
    for i in range(steps):
        inset = w * 0.06 * (i + 1) + i * w * 0.04
        f = fill or (C['roof'] if i % 2 == 0 else C['roof_d'])
        out.append(r(x + inset - w * 0.04, y - sh * (i + 1), w - 2 * inset + w * 0.08, sh + 1, f))
    out.append(r(x - w * 0.03, y - sh * 0.35, w * 1.06, sh * 0.5, C['roof']))
    return out


def house(x, y_base, w, h, wall, steps=3, windows=2, shutters='#7FA59A'):
    out = [r(x, y_base - h, w, h, wall)]
    out += stepped_roof(x, w, y_base - h, steps)
    ww = w * 0.16
    for i in range(windows):
        wx = x + w * (i + 1) / (windows + 1) - ww / 2
        wy = y_base - h * 0.68
        out.append(r(wx - ww * 0.35, wy, ww * 0.33, h * 0.36, shutters))
        out.append(r(wx + ww * 1.02, wy, ww * 0.33, h * 0.36, shutters))
        out.append(r(wx, wy, ww, h * 0.36, '#6C7F8A'))
    return out


def ferry(x, y_water, L):
    h = L * 0.16
    return [r(x, y_water - h, L, h, C['white'], h * 0.4),
            r(x, y_water - h * 0.45, L, h * 0.2, '#4F7FA3'),
            r(x + L * 0.25, y_water - h * 1.8, L * 0.5, h * 0.9, C['white'], h * 0.2),
            *[r(x + L * 0.29 + i * L * 0.09, y_water - h * 1.55, L * 0.05, h * 0.35, '#7A9BB0') for i in range(5)],
            r(x + L * 0.05, y_water - 2, L * 0.9, 4, C['water_l'])]


def fan(cx, y_ceiling, span):
    return [r(cx - span * 0.02, y_ceiling, span * 0.04, span * 0.22, '#B9A98E'),
            el(cx, y_ceiling + span * 0.25, span * 0.5, span * 0.035, '#A88A66'),
            el(cx, y_ceiling + span * 0.26, span * 0.09, span * 0.07, '#C4B396')]


def column(x, y_top, y_bot, w):
    return [r(x, y_top, w, y_bot - y_top, C['white']),
            r(x + w * 0.18, y_top + w * 0.5, w * 0.08, y_bot - y_top - w, '#ECE7DE'),
            r(x + w * 0.74, y_top + w * 0.5, w * 0.08, y_bot - y_top - w, '#ECE7DE'),
            r(x - w * 0.15, y_top, w * 1.3, w * 0.3, '#F2EEE6'),
            r(x - w * 0.08, y_top + w * 0.3, w * 1.16, w * 0.14, '#E6E0D5'),
            r(x - w * 0.15, y_bot - w * 0.3, w * 1.3, w * 0.3, '#F2EEE6')]


def scooter(x, y_ground, L, body, facing=-1):
    """Side view; x = centre. facing -1 = front to the left."""
    wr = L * 0.13
    f = facing
    out = [shadow(x, y_ground, L * 0.5)]
    for wx in (x + f * L * 0.36, x - f * L * 0.36):
        out.append(ci(wx, y_ground - wr, wr, '#3C3E42'))
        out.append(ci(wx, y_ground - wr, wr * 0.45, '#9A9EA3'))
    # deck + rear body
    out.append(r(x - L * 0.3, y_ground - wr * 1.6, L * 0.6, wr * 0.55, body, wr * 0.25))
    rb = x - f * L * 0.22
    out.append(path(f'M{rb - L * 0.24:.1f},{y_ground - wr * 1.2:.1f} Q{rb:.1f},{y_ground - wr * 3.6:.1f} {rb + L * 0.24:.1f},{y_ground - wr * 1.2:.1f} Z', body))
    out.append(r(rb - L * 0.2, y_ground - wr * 3.0, L * 0.4, wr * 0.5, '#3E3A38', wr * 0.25))  # seat
    # front shield + stem
    fx = x + f * L * 0.3
    out.append(poly([(fx - f * L * 0.05, y_ground - wr * 1.4), (fx + f * L * 0.04, y_ground - wr * 1.4),
                     (fx + f * L * 0.0, y_ground - wr * 4.2), (fx - f * L * 0.1, y_ground - wr * 4.0)], body))
    out.append(r(fx - L * 0.11, y_ground - wr * 4.5, L * 0.22, wr * 0.32, '#4A4744', wr * 0.15))  # bars
    out.append(ci(fx + f * L * 0.03, y_ground - wr * 3.8, wr * 0.3, '#F3E7B8'))  # lamp
    return out


def helmet(cx, cy, s):
    return [path(f'M{cx - s:.1f},{cy:.1f} A{s:.1f},{s * 0.9:.1f} 0 0 1 {cx + s:.1f},{cy:.1f} Z', C['white']),
            r(cx - s * 1.02, cy - s * 0.12, s * 2.04, s * 0.18, '#DCD8D0', s * 0.08)]


def bluebird_note(cx, cy, w, ang=0):
    """The Bermuda two-dollar note: shapes only, no lettering. The one saturated accent."""
    h = w * 0.5
    x, y = cx - w / 2, cy - h / 2
    g = [f'<g transform="rotate({ang},{cx:.1f},{cy:.1f})">',
         shadow(cx, cy + h * 0.55, w * 0.5, h * 0.1),
         r(x, y, w, h, '#2F7FD6', w * 0.04),
         r(x + w * 0.05, y + h * 0.1, w * 0.9, h * 0.8, '#4A97E4', w * 0.03),
         el(cx + w * 0.22, cy, w * 0.17, h * 0.33, '#8CC2F2'),
         # bluebird
         el(cx - w * 0.12, cy + h * 0.02, w * 0.14, h * 0.17, '#1E5FB3'),
         el(cx - w * 0.15, cy + h * 0.08, w * 0.08, h * 0.1, '#F08A3A'),
         ci(cx - w * 0.24, cy - h * 0.1, w * 0.07, '#1E5FB3'),
         poly([(cx - w * 0.31, cy - h * 0.12), (cx - w * 0.36, cy - h * 0.08), (cx - w * 0.3, cy - h * 0.06)], '#F2C14E'),
         poly([(cx - w * 0.02, cy - h * 0.02), (cx + w * 0.08, cy + h * 0.12), (cx - w * 0.01, cy + h * 0.1)], '#174C93'),
         ci(cx - w * 0.25, cy - h * 0.12, w * 0.012, '#0E2340'),
         r(x + w * 0.08, y + h * 0.72, w * 0.18, h * 0.08, '#8CC2F2', h * 0.03),
         r(x + w * 0.74, y + h * 0.16, w * 0.14, h * 0.1, '#8CC2F2', h * 0.03),
         '</g>']
    return g


def palm_pot(cx, y_floor, s):
    out = [shadow(cx, y_floor, s * 0.4)]
    for ang in (-60, -30, 0, 30, 60, -80, 80):
        out.append(f'<g transform="rotate({ang},{cx:.1f},{y_floor - s * 0.55:.1f})">'
                   + el(cx, y_floor - s * 1.0, s * 0.09, s * 0.45, C['green_d'] if ang % 60 else C['green']) + '</g>')
    out.append(poly([(cx - s * 0.25, y_floor - s * 0.45), (cx + s * 0.25, y_floor - s * 0.45),
                     (cx + s * 0.19, y_floor), (cx - s * 0.19, y_floor)], '#C9876A'))
    return out


def card_ceiling(x, y, w, h, seed=7, cw=46, ch=28):
    rnd = random.Random(seed)
    cols = ['#F4EFE4', '#EAE2D1', '#F8F5EE', '#E2D9C6', '#EFE5D8', '#DDE4E2', '#F0E1D8', '#E8E8DC']
    out = [r(x, y, w, h, '#CDBFA6')]
    row = 0
    yy = y + 3
    while yy < y + h:
        xx = x - (cw / 2 if row % 2 else 0) + 3
        while xx < x + w:
            out.append(r(xx + rnd.uniform(-3, 3), yy + rnd.uniform(-2, 2), cw - 5, ch - 5, rnd.choice(cols), 2))
            xx += cw
        yy += ch
        row += 1
    return out
