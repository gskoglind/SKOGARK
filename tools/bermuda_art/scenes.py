"""SKOGARK — Bermuda / Hamilton scenes. Each scene(o) returns an SVG string; o is 'L' or 'P'."""
from kit import *

SIZE = {'L': (1920, 1080), 'P': (1080, 1920)}


def harbour_view(d, x, y, w, h, horizon_frac=0.5, ferry_at=None, ship=False):
    """Sky / far shore / turquoise water, drawn into a box."""
    out = [r(x, y, w, h, d.lin_grad([(0, C['sky_top']), (1, C['sky_bot'])]))]
    hy = y + h * horizon_frac
    # far shore with tiny pastel houses
    out.append(r(x, hy - h * 0.06, w, h * 0.07, C['green_d']))
    cols = [C['coral'], C['butter'], C['mint'], C['pblue'], C['white']]
    n = max(3, int(w / 70))
    for i in range(n):
        hx = x + (i + 0.3) * w / n
        hw = w / n * 0.5
        out.append(r(hx, hy - h * 0.09, hw, h * 0.05, cols[i % 5]))
        out.append(r(hx - 2, hy - h * 0.1, hw + 4, h * 0.015, C['roof']))
    out.append(r(x, hy, w, y + h - hy, C['water']))
    for i in range(6):
        sy = hy + (i + 1) * (y + h - hy) / 7
        sx = x + ((i * 137) % 5) / 5 * w * 0.6
        out.append(r(sx, sy, w * 0.25, 3, C['water_l'], 1.5))
    if ferry_at:
        fx, fl = ferry_at
        out += ferry(x + w * fx, hy + (y + h - hy) * 0.35, fl)
    return out


def trolley(cx, y_floor, s):
    brass = '#C9A55C'
    out = [shadow(cx, y_floor, s * 0.55)]
    out.append(r(cx - s * 0.5, y_floor - s * 0.16, s, s * 0.07, '#B08D4C', s * 0.03))  # base
    for wx in (cx - s * 0.4, cx + s * 0.4):
        out.append(ci(wx, y_floor - s * 0.05, s * 0.06, '#4A4642'))
    for px in (cx - s * 0.46, cx + s * 0.42):
        out.append(r(px, y_floor - s * 1.25, s * 0.04, s * 1.1, brass, s * 0.02))
    out.append(path(f'M{cx - s * 0.46:.1f},{y_floor - s * 1.22:.1f} Q{cx - s * 0.02:.1f},{y_floor - s * 1.55:.1f} '
                    f'{cx + s * 0.46:.1f},{y_floor - s * 1.22:.1f} L{cx + s * 0.46:.1f},{y_floor - s * 1.17:.1f} '
                    f'Q{cx - s * 0.02:.1f},{y_floor - s * 1.5:.1f} {cx - s * 0.46:.1f},{y_floor - s * 1.17:.1f} Z', brass))
    # suitcase standing
    out.append(r(cx - s * 0.36, y_floor - s * 0.72, s * 0.7, s * 0.56, '#7D8F9E', s * 0.05))
    out.append(r(cx - s * 0.36, y_floor - s * 0.5, s * 0.7, s * 0.05, '#6B7C8A'))
    out.append(r(cx - s * 0.08, y_floor - s * 0.8, s * 0.16, s * 0.09, '#5E6E7B', s * 0.03))
    # folded shorts on top
    out.append(r(cx - s * 0.24, y_floor - s * 0.87, s * 0.42, s * 0.08, '#CDB88E', s * 0.02))
    out.append(r(cx - s * 0.22, y_floor - s * 0.93, s * 0.38, s * 0.07, '#D9C69E', s * 0.02))
    return out


def chair_with_jacket(cx, y_floor, s):
    w = C['wood_d']
    out = [shadow(cx, y_floor, s * 0.4)]
    # tall slatted back, seat, legs
    for px in (cx - s * 0.3, cx + s * 0.24):
        out.append(r(px, y_floor - s * 1.35, s * 0.06, s * 1.35, w, s * 0.02))
    for i in range(3):
        out.append(r(cx - s * 0.3, y_floor - s * (1.3 - i * 0.2), s * 0.6, s * 0.06, w, s * 0.02))
    out.append(r(cx - s * 0.38, y_floor - s * 0.62, s * 0.76, s * 0.1, '#A07A55', s * 0.04))
    out.append(r(cx + s * 0.3, y_floor - s * 0.55, s * 0.06, s * 0.55, w))
    # jacket slung over the top rail: shoulders over the rail, body hanging down the back
    jc = '#4E5D73'
    out.append(path(f'M{cx - s * 0.4:.1f},{y_floor - s * 1.28:.1f} Q{cx - s * 0.03:.1f},{y_floor - s * 1.42:.1f} {cx + s * 0.34:.1f},{y_floor - s * 1.28:.1f} '
                    f'L{cx + s * 0.3:.1f},{y_floor - s * 0.95:.1f} L{cx - s * 0.36:.1f},{y_floor - s * 0.95:.1f} Z', jc))
    out.append(poly([(cx - s * 0.08, y_floor - s * 1.36), (cx + s * 0.04, y_floor - s * 1.36), (cx - s * 0.02, y_floor - s * 1.12)], '#E9E3D6'))
    out.append(r(cx - s * 0.47, y_floor - s * 1.27, s * 0.11, s * 0.58, jc, s * 0.05))  # sleeve hanging
    return out


def desk(x, y_floor, w, h):
    return [shadow(x + w / 2, y_floor, w * 0.55),
            r(x, y_floor - h, w, h, C['wood'], 4),
            r(x - w * 0.03, y_floor - h - h * 0.08, w * 1.06, h * 0.1, C['wood_d'], 4),
            *[r(x + w * (0.08 + i * 0.3), y_floor - h * 0.78, w * 0.24, h * 0.62, '#A27A54', 3) for i in range(3)]]


def bell(cx, y, s):
    return [r(cx - s * 0.6, y - s * 0.12, s * 1.2, s * 0.12, '#B89A5C'),
            path(f'M{cx - s * 0.45:.1f},{y - s * 0.12:.1f} A{s * 0.45:.1f},{s * 0.42:.1f} 0 0 1 {cx + s * 0.45:.1f},{y - s * 0.12:.1f} Z', '#D9B866'),
            ci(cx, y - s * 0.6, s * 0.08, '#D9B866')]


CONCIERGE = dict(skin='#BC8662', hair='#2E2621', top='#3D4D69', top_style='blazer', bottom='#46587A', socks='#3D4D69', shoes='#2E2A28')


def princess(o):
    W, H = SIZE[o]
    d = Doc(W, H)
    if o == 'L':
        ceil, floor = 90, 640
        feet, fig = 800, 520
        door = (1000, 170, 380)
        cols = [(60, 80), (1790, 80), (880, 70)]
        fans = [(520, 330), (1500, 330)]
        desk_box = (340, 360, 210)
        conc_x, diana_x, bag_x = 250, 790, 862
        trolley_xy, chair_xy = (1530, 815, 210), (1745, 795, 170)
    else:
        ceil, floor = 170, 1120
        feet, fig = 1415, 600
        door = (310, 360, 460)
        cols = [(20, 90), (970, 90)]
        fans = [(540, 380)]
        desk_box = (215, 300, 245)
        conc_x, diana_x, bag_x = 140, 565, 645
        trolley_xy, chair_xy = (815, 1430, 210), (1005, 1395, 150)

    # ceiling + wall + dado
    d.add(r(0, 0, W, ceil, '#F4EFE7'), r(0, ceil - 10, W, 10, '#E8E1D5'))
    d.add(r(0, ceil, W, floor - ceil, d.lin_grad([(0, '#E9AA9D'), (1, C['coral'])])))
    d.add(r(0, floor - 26, W, 26, '#F2ECE3'))
    # marble floor: pale tiles in two tones, receding toward a centre point
    d.add(r(0, floor, W, H - floor, '#EEE8DE'))
    rows = 6
    for i in range(rows):
        y0 = floor + (H - floor) * (i / rows) ** 1.35
        y1 = floor + (H - floor) * ((i + 1) / rows) ** 1.35
        n = 8
        for j in range(-2, n + 2):
            if (i + j) % 2:
                xa = W / 2 + (j / n - 0.5) * W * (0.75 + 0.6 * i / rows)
                xb = W / 2 + ((j + 1) / n - 0.5) * W * (0.75 + 0.6 * i / rows)
                xc = W / 2 + ((j + 1) / n - 0.5) * W * (0.75 + 0.6 * (i + 1) / rows)
                xd = W / 2 + (j / n - 0.5) * W * (0.75 + 0.6 * (i + 1) / rows)
                d.add(poly([(xa, y0), (xb, y0), (xc, y1), (xd, y1)], '#E4DCCF'))
    # arched doorway onto the harbour
    dx, dy, dw = door
    arch = (f'M{dx:.1f},{floor - 26:.1f} L{dx:.1f},{dy + dw / 2:.1f} A{dw / 2:.1f},{dw / 2:.1f} 0 0 1 '
            f'{dx + dw:.1f},{dy + dw / 2:.1f} L{dx + dw:.1f},{floor - 26:.1f} Z')
    frame = 26
    d.add(path(f'M{dx - frame:.1f},{floor - 26:.1f} L{dx - frame:.1f},{dy + dw / 2:.1f} A{dw / 2 + frame:.1f},{dw / 2 + frame:.1f} 0 0 1 '
               f'{dx + dw + frame:.1f},{dy + dw / 2:.1f} L{dx + dw + frame:.1f},{floor - 26:.1f} Z', '#F6F2EB'))
    clip = d.clip(path(arch, '#000'))
    d.add(f'<g {clip}>', harbour_view(d, dx, dy, dw, floor - 26 - dy, 0.52,
                                       ferry_at=(0.18, dw * 0.42)), '</g>')
    # door leaves folded back against the wall
    lw = dw * 0.2
    for lx in (dx - frame - lw - 6, dx + dw + frame + 6):
        d.add(r(lx, dy + dw * 0.35, lw, floor - 26 - dy - dw * 0.35, '#F3EEE6', 4))
        d.add(r(lx + lw * 0.2, dy + dw * 0.45, lw * 0.6, (floor - dy) * 0.3, '#E7E0D4', 3))
        d.add(r(lx + lw * 0.2, dy + dw * 0.45 + (floor - dy) * 0.36, lw * 0.6, (floor - dy) * 0.22, '#E7E0D4', 3))
    # light spilling in from the harbour
    glow = d.rad_grad([(0, '#FFF6E0', 0.55), (1, '#FFF6E0', 0)])
    d.add(el(dx + dw / 2, floor + (H - floor) * 0.12, dw * 0.9, (H - floor) * 0.18, glow))
    for cx_, cw in cols:
        d.add(column(cx_, ceil, floor, cw))
    for fx, span in fans:
        d.add(fan(fx, ceil, span))

    # concierge desk with bell
    bx, bw, bh = desk_box
    d.add(person(conc_x, feet - 18, fig * 0.98, **CONCIERGE, arm_r=12))
    d.add(desk(bx, feet - 10, bw, bh))
    d.add(bell(bx + bw * 0.75, feet - 10 - bh - bh * 0.08, bh * 0.22))
    # Diana at the desk, bag at her feet
    d.add(person(diana_x, feet, fig * 0.95, **DIANA, gaze=-0.8, arm_l=10))
    bs = fig * 0.22
    d.add(shadow(bag_x, feet + 4, bs * 0.6), r(bag_x - bs * 0.5, feet - bs * 0.62, bs, bs * 0.66, '#9C7A5A', bs * 0.12),
          path(f'M{bag_x - bs * 0.28:.1f},{feet - bs * 0.6:.1f} Q{bag_x:.1f},{feet - bs * 1.05:.1f} {bag_x + bs * 0.28:.1f},{feet - bs * 0.6:.1f}',
               'none', f'stroke="#7E6046" stroke-width="{bs * 0.07:.1f}"'))
    cx_, cy_, cs = chair_xy
    d.add(chair_with_jacket(cx_, cy_, cs))
    tx, ty, ts = trolley_xy
    d.add(trolley(tx, ty, ts))
    return d.svg()




# ---------------------------------------------------------------- Front Street
def shade(hex_, k=0.82):
    h = hex_.lstrip('#')
    return '#' + ''.join(f'{int(int(h[i:i + 2], 16) * k):02X}' for i in (0, 2, 4))


def shopfront(d, x, w, h, wall, y_pave, post_step=110, shutters='#7FA59A'):
    out = [r(x, y_pave - h, w, h, wall)]
    out += stepped_roof(x, w, y_pave - h, 3)
    vy = y_pave - h * 0.55          # verandah floor / roof band
    # upper windows with shutters
    n = max(2, int(w / 150))
    for i in range(n):
        wx = x + (i + 0.5) * w / n
        ww, wh = w / n * 0.26, h * 0.22
        wy = y_pave - h * 0.88
        out += [r(wx - ww / 2, wy, ww, wh, '#6C7F8A'),
                r(wx - ww / 2 - ww * 0.42, wy, ww * 0.38, wh, shutters),
                r(wx + ww / 2 + ww * 0.04, wy, ww * 0.38, wh, shutters)]
    # shaded ground floor under the verandah
    out.append(r(x, vy, w, y_pave - vy, shade(wall, 0.8)))
    for i in range(n):
        wx = x + (i + 0.5) * w / n
        out.append(r(wx - w / n * 0.3, vy + (y_pave - vy) * 0.22, w / n * 0.6, (y_pave - vy) * 0.78, shade(wall, 0.55)))
    # verandah: railing, roof band, posts
    rail_y = vy - h * 0.12
    out.append(r(x - 6, rail_y, w + 12, 7, C['white']))
    bx = x
    while bx < x + w:
        out.append(r(bx, rail_y, 5, vy - rail_y, C['white']))
        bx += 16
    out.append(r(x - 8, vy, w + 16, 16, C['white']))
    px = x + 6
    while px <= x + w:
        out.append(r(px, vy + 16, 10, y_pave + 40 - vy - 16, C['white']))
        px += post_step
    return out, vy


def birdcage(cx, y_base, s):
    out = [shadow(cx, y_base, s * 0.35),
           r(cx - s * 0.05, y_base - s * 0.75, s * 0.1, s * 0.75, C['white']),
           r(cx - s * 0.32, y_base - s * 0.8, s * 0.64, s * 0.08, C['white'])]
    out += far_figure(cx, y_base - s * 0.8, s * 0.45, '#9C6B4C', C['white'], hat=C['white'], bottom='#3E4E6A')
    out.append(r(cx - s * 0.02, y_base - s * 1.55, s * 0.04, s * 0.75, C['white']))
    out.append(poly([(cx - s * 0.42, y_base - s * 1.42), (cx + s * 0.42, y_base - s * 1.42), (cx, y_base - s * 1.72)], C['white']))
    out.append(r(cx - s * 0.42, y_base - s * 1.45, s * 0.84, s * 0.06, '#E0DBD2'))
    return out


def cruise_stern(x, y_top, w, h):
    out = [r(x + w * 0.42, y_top - h * 0.12, w * 0.16, h * 0.16, '#E9E6E0', 6),
           r(x + w * 0.42, y_top - h * 0.1, w * 0.16, h * 0.04, '#4F6E8E'),
           r(x + w * 0.08, y_top, w * 0.84, h * 0.14, '#F2F1EE', 14),
           r(x, y_top + h * 0.12, w, h * 0.72, '#F7F6F3', 10),
           r(x, y_top + h * 0.82, w, h * 0.18, '#3B4C66')]
    yy = y_top + h * 0.17
    while yy < y_top + h * 0.8:
        out.append(r(x + w * 0.04, yy, w * 0.92, h * 0.018, '#9FB2C2'))
        yy += h * 0.055
    return out


SCOOTER_COLS = ['#AFD6BE', '#EFE3C4', '#AECBDD', '#E6A497', '#F0DA9C']
AGENT = dict(skin='#C49372', hair='#3A2E28', top='#E9DEC6', bottom='#8FA28A', socks='#EEE9DE', shoes='#5E4532')


def front_street(o):
    W, H = SIZE[o]
    d = Doc(W, H)
    if o == 'L':
        pave, kerb = 640, 700
        ship = (1130, 40, 900, 560)
        shops = [(0, 260, 430, C['butter']), (260, 520, 470, C['pblue']), (780, 360, 440, C['coral']),
                 (1140, 190, 455, C['mint']), (1490, 460, 445, '#F2CDBE')]
        gap = (1330, 1490)
        hire = 1
        scoot = ([250 + i * 150 for i in range(5)], 800, 230)
        helmets = (290, 455, 3, 48)
        board = (560, 645, 125)
        agent = (690, 640, 270)
        cage = (1410, 645, 125)
        diana, player = (1135, 810, 430), (1250, 805, 450)
    else:
        pave, kerb = 1150, 1210
        ship = (520, 260, 700, 760)
        shops = [(0, 400, 520, C['pblue']), (400, 190, 500, C['butter']), (720, 360, 510, C['coral'])]
        gap = (590, 720)
        hire = 0
        scoot = ([110 + i * 140 for i in range(4)], 1310, 220)
        helmets = (40, 935, 2, 46)
        board = (120, 1155, 120)
        agent = (330, 1150, 270)
        cage = (655, 1155, 115)
        diana, player = (790, 1420, 500), (935, 1414, 520)

    d.add(r(0, 0, W, kerb, d.lin_grad([(0, C['sky_top']), (1, C['sky_bot'])])))
    cl = [(0.12, 0.12, 120), (0.38, 0.2, 90)] if o == 'L' else [(0.15, 0.08, 110)]
    for fx, fy, cs in cl:
        d.add(el(W * fx, H * fy, cs, cs * 0.38, '#FFFFFF', 'opacity="0.85"'),
              el(W * fx + cs * 0.55, H * fy - cs * 0.15, cs * 0.6, cs * 0.35, '#FFFFFF', 'opacity="0.85"'))
    # harbour in the gap, cruise ship looming over the roofs
    d.add(r(0, pave - (pave * 0.14), W, pave * 0.14, C['water']))
    d.add(cruise_stern(*ship))
    d.add(r(gap[0], pave - pave * 0.07, gap[1] - gap[0], pave * 0.07, C['water']))
    d.add(r(gap[0], pave - pave * 0.035, gap[1] - gap[0], 3, C['water_l']))
    # pavement + kerb + road
    d.add(r(0, pave, W, kerb - pave, C['lime']), r(0, kerb - 6, W, 10, '#C9C2B6'))
    d.add(r(0, kerb + 4, W, H - kerb, '#B9B2A7'))
    d.add(r(0, kerb + (H - kerb) * 0.5, W, 6, '#C7C0B4'))
    # shops
    hire_vy = None
    for i, (x, w, h, col) in enumerate(shops):
        part, vy = shopfront(d, x, w, h, col, pave)
        d.add(part)
        if i == hire:
            hire_vy = vy
            sx, sw = x, w
    # birdcage, small and distant, in the gap
    d.add(birdcage(*cage))
    # scooter hire: sign, helmets on pegs, rates board, agent on a stool in the shade
    d.add(r(sx + sw * 0.2, hire_vy + 26, sw * 0.6, 44, '#F7F3EA', 4),
          text(sx + sw * 0.5, hire_vy + 59, 'SCOOTER HIRE', 30, '#4F6E8E', family="'Avenir Next','Helvetica Neue',sans-serif", weight=800))
    hx, hy, hn, hs = helmets
    for i in range(hn):
        px = hx + i * hs * 2.5 + hs
        d.add(r(px - 3, hy - hs * 0.2, 6, hs * 0.25, '#7A5E44'))
        d.add(helmet(px, hy + hs * 0.6, hs * 0.8))
    bx_, by_, bs = board
    d.add(poly([(bx_ - bs * 0.4, by_), (bx_ + bs * 0.4, by_), (bx_ + bs * 0.34, by_ - bs * 1.15), (bx_ - bs * 0.34, by_ - bs * 1.15)], '#5E4A3A'),
          r(bx_ - bs * 0.3, by_ - bs * 1.08, bs * 0.6, bs * 0.85, '#3F4A44', 4),
          text(bx_, by_ - bs * 0.9, 'RATES', bs * 0.17, '#F3EEDF'),
          text(bx_, by_ - bs * 0.66, 'DAY', bs * 0.13, '#F3EEDF'),
          text(bx_, by_ - bs * 0.47, 'WEEK', bs * 0.13, '#F3EEDF'))
    ax, ay, ah = agent
    d.add(shadow(ax, ay, ah * 0.12), r(ax - ah * 0.1, ay - ah * 0.3, ah * 0.2, ah * 0.04, C['wood_d'], 3),
          r(ax - ah * 0.08, ay - ah * 0.28, ah * 0.025, ah * 0.28, C['wood_d']), r(ax + ah * 0.055, ay - ah * 0.28, ah * 0.025, ah * 0.28, C['wood_d']))
    d.add(person(ax, ay, ah, **AGENT, seated_y=ay - ah * 0.3, arm_l=-6, arm_r=-6))
    xs, gy, L = scoot
    for i, x in enumerate(xs):
        d.add(scooter(x, gy - (len(xs) - 1 - i) * 0, L, SCOOTER_COLS[i % 5]))
    # Diana eyes the scooters; the player beside her
    d.add(person(diana[0], diana[1], diana[2], **DIANA, gaze=-1.2, arm_l=6))
    d.add(person(player[0], player[1], player[2], **PLAYER, gaze=-0.8, arm_r=8))
    return d.svg()


# ---------------------------------------------------------------- June's office
JUNE = dict(skin='#9C6B4C', hair='#2A2220', hair_style='updo', top='#7A5E86', top_style='blazer', lapel='#F2ECE2')


def rooftop_view(d, x, y, w, h):
    out = [r(x, y, w, h * 0.36, d.lin_grad([(0, C['sky_top']), (1, C['sky_bot'])])),
           r(x, y + h * 0.34, w, h * 0.22, C['water']),
           r(x + w * 0.1, y + h * 0.42, w * 0.25, 3, C['water_l']), r(x + w * 0.55, y + h * 0.48, w * 0.3, 3, C['water_l'])]
    cols = [C['butter'], C['pblue'], C['coral'], C['mint'], '#F2CDBE', C['white']]
    out.append(r(x, y + h * 0.56, w, h * 0.44, C['green_d']))
    n = 4
    for i in range(n):
        bw = w / n * 0.7
        bx = x + (i + 0.15) * w / n
        by = y + h * (0.72 if i % 2 else 0.68)
        out.append(r(bx, by, bw, y + h - by, cols[(i * 2) % 6]))
        out += stepped_roof(bx, bw, by, 3, step_h=h * 0.04)
    return out


def phone(cx, y, s):
    cord = (f'M{cx + s * 0.4:.1f},{y - s * 0.2:.1f} ' +
            ' '.join(f'q{s * 0.06:.1f},{s * (0.12 if k % 2 else -0.12):.1f} {s * 0.12:.1f},0' for k in range(6)))
    return [shadow(cx, y + 2, s * 0.6),
            poly([(cx - s * 0.5, y), (cx + s * 0.5, y), (cx + s * 0.38, y - s * 0.42), (cx - s * 0.38, y - s * 0.42)], '#4B4A4C'),
            r(cx - s * 0.22, y - s * 0.32, s * 0.44, s * 0.14, '#6A696C', 3),
            r(cx - s * 0.58, y - s * 0.6, s * 1.16, s * 0.18, '#3C3B3D', s * 0.09),
            r(cx - s * 0.6, y - s * 0.62, s * 0.26, s * 0.24, '#3C3B3D', s * 0.1),
            r(cx + s * 0.34, y - s * 0.62, s * 0.26, s * 0.24, '#3C3B3D', s * 0.1),
            path(cord, 'none', f'stroke="#3C3B3D" stroke-width="{s * 0.05:.1f}" stroke-linecap="round"')]


def june_office(o):
    W, H = SIZE[o]
    d = Doc(W, H)
    if o == 'L':
        floor = 650
        win = (610, 110, 700, 390)
        june = (960, 650, 540)
        desk_ = (560, 800, 800, 170, 52)
        file_ = (800, 0.5)
        phone_ = (1225, 62)
        diana, player = (420, 820, 570), (580, 812, 600)
        palm = (1640, 800, 300)
    else:
        floor = 1150
        win = (190, 260, 700, 560)
        june = (540, 1150, 600)
        desk_ = (100, 1360, 880, 220, 60)
        file_ = (430, 0.5)
        phone_ = (850, 66)
        diana, player = (170, 1440, 610), (360, 1430, 640)
        palm = None

    d.add(r(0, 0, W, floor, '#EFE5D3'), r(0, floor - 22, W, 22, '#E2D4BD'))
    d.add(r(0, floor, W, H - floor, '#C8AC88'))
    k = 0
    yy = floor
    while yy < H:
        step = 26 + k * 9
        d.add(r(0, yy, W, 3, '#B89A75'))
        yy += step
        k += 1
    # window full of white stepped rooftops, harbour beyond
    wx, wy, ww, wh = win
    glow = d.rad_grad([(0, '#FFF3D6', 0.7), (1, '#FFF3D6', 0)])
    d.add(el(wx + ww / 2, wy + wh / 2, ww * 0.85, wh * 0.95, glow))
    d.add(r(wx - 22, wy - 22, ww + 44, wh + 44, C['white'], 4))
    clip = d.clip(r(wx, wy, ww, wh, '#000'))
    d.add(f'<g {clip}>', rooftop_view(d, wx, wy, ww, wh), '</g>')
    d.add(r(wx + ww / 2 - 8, wy, 16, wh, C['white']), r(wx, wy + wh * 0.5 - 8, ww, 16, C['white']))
    d.add(r(wx - 34, wy + wh + 14, ww + 68, 18, '#E8E1D4', 3))
    # June's chair, then June: the room is arranged around her
    jx, jseat, jh = june
    u = jh / 3.8
    d.add(r(jx - u * 0.95, jseat - u * 2.55, u * 1.9, u * 2.4, '#6C5547', u * 0.4))
    d.add(person(jx, jseat, jh, **JUNE, upper_only=True, seated_y=jseat, arm_l=-8, arm_r=-8))
    # desk: top surface with a little depth, one file, a corded 1990s phone
    dx, dfoot, dw, dh, depth = desk_
    top = dfoot - dh
    d.add(shadow(dx + dw / 2, dfoot, dw * 0.55))
    d.add(poly([(dx + depth * 0.6, top - depth), (dx + dw - depth * 0.6, top - depth), (dx + dw, top), (dx, top)], '#A47D57'))
    d.add(r(dx - 8, top, dw + 16, 18, C['wood_d'], 4), r(dx, top + 18, dw, dh - 18, C['wood'], 4))
    for i in range(2):
        d.add(r(dx + dw * (0.06 + i * 0.66), top + dh * 0.22, dw * 0.28, dh * 0.62, '#A27A54', 4))
    # her hands resting on the desk
    for s in (-1, 1):
        d.add(ci(jx + s * u * 0.5, top - depth * 0.35, u * 0.17, JUNE['skin']))
    fx, _ = file_
    fw = dw * 0.17
    d.add(poly([(fx - fw / 2 + 10, top - depth * 0.62), (fx + fw / 2 + 10, top - depth * 0.62), (fx + fw / 2, top - depth * 0.18), (fx - fw / 2, top - depth * 0.18)], '#E2C48A'),
          poly([(fx - fw / 2 + 18, top - depth * 0.7), (fx - fw / 2 + 60, top - depth * 0.7), (fx - fw / 2 + 58, top - depth * 0.62), (fx - fw / 2 + 16, top - depth * 0.62)], '#D6B678'))
    px_, ps = phone_
    d.add(phone(px_, top - depth * 0.3, ps))
    if palm:
        d.add(palm_pot(*palm))
    # the player and Diana in front of the desk, seen from behind; Diana half a step behind him
    d.add(person(player[0], player[1], player[2], **PLAYER, back=True, arm_l=3, arm_r=3))
    d.add(person(diana[0], diana[1], diana[2], **DIANA, back=True, arm_l=3, arm_r=5))
    return d.svg()


# ---------------------------------------------------------------- Swizzle Inn
BARTENDER = dict(skin='#D2A17E', hair='#3A2E28', top='#5E7A6E')


def pool_table(cx, y_floor, w):
    h = w * 0.36
    top = y_floor - h
    depth = w * 0.09
    out = [shadow(cx, y_floor, w * 0.55)]
    for lx in (cx - w * 0.44, cx + w * 0.38):
        out.append(r(lx, top + h * 0.3, w * 0.06, h * 0.7, C['wood_dd'], 4))
    out.append(poly([(cx - w * 0.46, top - depth), (cx + w * 0.46, top - depth), (cx + w * 0.5, top), (cx - w * 0.5, top)], '#5C8B6B'))
    out.append(poly([(cx - w * 0.43, top - depth * 0.85), (cx + w * 0.43, top - depth * 0.85), (cx + w * 0.46, top - depth * 0.1), (cx - w * 0.46, top - depth * 0.1)], '#679A76'))
    out.append(r(cx - w * 0.52, top - 4, w * 1.04, h * 0.12, '#6E4E36', 5))
    out.append(r(cx - w * 0.5, top + h * 0.12 - 4, w, h * 0.2, C['wood_d'], 4))
    for bx, by, bc in ((-0.2, 0.5, '#F2ECDD'), (0.1, 0.4, '#C9564B'), (0.16, 0.6, '#E7C14E'), (0.22, 0.45, '#3E5C8A'), (0.27, 0.62, '#2E2A28')):
        out.append(ci(cx + w * bx, top - depth * by, w * 0.018, bc))
    out.append(line(cx - w * 0.38, top - depth * 0.55, cx + w * 0.02, top - depth * 0.3, '#C8A878', w * 0.008))
    return out


def lunch_table(cx, y_floor, s):
    out = [shadow(cx, y_floor, s * 0.5)]
    for sx in (-1, 1):
        chx = cx + sx * s * 0.62
        out.append(r(chx - s * 0.04, y_floor - s * 0.95, s * 0.08, s * 0.95, C['wood_d'], 3))
        out.append(r(chx - s * 0.17, y_floor - s * 0.48, s * 0.34, s * 0.07, C['wood_d'], 3))
        out.append(r(chx - s * 0.15 + sx * s * 0.0, y_floor - s * 0.48, s * 0.05, s * 0.48, C['wood_dd']))
        out.append(r(chx + s * 0.1, y_floor - s * 0.48, s * 0.05, s * 0.48, C['wood_dd']))
    out.append(r(cx - s * 0.05, y_floor - s * 0.62, s * 0.1, s * 0.62, C['wood_dd']))
    out.append(r(cx - s * 0.25, y_floor - s * 0.05, s * 0.5, s * 0.05, C['wood_dd'], 2))
    out.append(el(cx, y_floor - s * 0.66, s * 0.5, s * 0.08, '#EFE8DA'))
    out.append(r(cx - s * 0.5, y_floor - s * 0.66, s, s * 0.14, '#EFE8DA', 3))
    return out


def stapler(cx, y_top, L, y_hang):
    return [line(cx, y_top, cx, y_hang, '#E9E2D2', 3),
            r(cx - L * 0.5, y_hang, L, L * 0.26, '#3B3C40', L * 0.08),
            r(cx - L * 0.5, y_hang - L * 0.1, L * 0.88, L * 0.16, '#55575C', L * 0.07)]


def back_bar(x, y, w, h):
    out = [r(x, y, w, h, '#6E5239')]
    cols = ['#7E9A6C', '#C49A55', '#9B5E4A', '#D9C99E', '#6F8C93', '#B9874C']
    for row in range(2):
        sy = y + h * (0.45 if row == 0 else 0.95)
        out.append(r(x, sy - 6, w, 8, '#4E3A2A'))
        n = int(w / 34)
        for i in range(n):
            bx = x + 10 + i * (w - 20) / n
            bh = h * (0.28 + 0.06 * ((i * 7 + row) % 3))
            c = cols[(i + row * 3) % 6]
            out.append(r(bx, sy - 6 - bh, 18, bh, c, 5))
            out.append(r(bx + 6, sy - 6 - bh - 12, 6, 14, c))
    return out


def swizzle_inn(o):
    W, H = SIZE[o]
    d = Doc(W, H)
    if o == 'L':
        ceil, floor = 250, 640
        beams = [0, 120, 240]
        sign = (60, 262, 540, 58)
        bb = (30, 330, 590, 170)
        bar = (0, 800, 640, 240)
        bartender = (330, 640, 500)
        stap = (600, 590, 90, 665)
        win = (1480, 300, 360, 250)
        pool = (1010, 790, 500)
        tables = [(1250, 640, 160), (1730, 805, 220)]
        diana, player = (1340, 805, 500), (1490, 800, 520)
    else:
        ceil, floor = 480, 1150
        beams = [0, 160, 320, 470]
        sign = (30, 500, 480, 66)
        bb = (20, 590, 430, 210)
        bar = (0, 1180, 470, 260)
        bartender = (230, 1000, 520)
        stap = (440, 935, 66, 1000)
        win = (610, 600, 420, 270)
        pool = (450, 1400, 540)
        tables = [(640, 1150, 150)]
        diana, player = (800, 1420, 560), (955, 1412, 580)

    d.add(card_ceiling(0, 0, W, ceil, seed=3 if o == 'L' else 5))
    for by in beams:
        d.add(r(0, by, W, 14, '#5A4331'))
    d.add(r(0, ceil, W, 12, '#5A4331'))
    d.add(r(0, ceil + 12, W, floor - ceil - 12, '#EDE3CF'))
    d.add(r(0, floor - (floor - ceil) * 0.35, W, (floor - ceil) * 0.35, '#8E6B4B'))
    d.add(r(0, floor - (floor - ceil) * 0.35, W, 10, '#6E5239'))
    # terracotta floor
    d.add(r(0, floor, W, H - floor, '#C29A7C'))
    yy, k = floor, 0
    while yy < H:
        d.add(r(0, yy, W, 3, '#B0876A'))
        yy += 30 + k * 10
        k += 1
    # window: scooters parked outside
    wx, wy, ww, wh = win
    d.add(r(wx - 18, wy - 18, ww + 36, wh + 36, '#F2EEE6', 4))
    clip = d.clip(r(wx, wy, ww, wh, '#000'))
    d.add(f'<g {clip}>', r(wx, wy, ww, wh * 0.55, C['sky_top']), r(wx, wy + wh * 0.45, ww, wh * 0.2, C['green']),
          r(wx, wy + wh * 0.62, ww, wh * 0.38, '#BDB6AA'))
    for i, c in enumerate(SCOOTER_COLS[:3]):
        d.add(scooter(wx + ww * (0.2 + i * 0.3), wy + wh * 0.92, ww * 0.24, c))
    d.add('</g>', r(wx + ww / 2 - 6, wy, 12, wh, '#F2EEE6'))
    # sign over the bar (in-world signage)
    sx, sy, sw, sh = sign
    d.add(r(sx, sy, sw, sh, '#4A3526', 6),
          text(sx + sw / 2, sy + sh * 0.68, 'Swizzle Inn, Swagger Out', sh * 0.5, '#F3E6C8'))
    d.add(back_bar(*bb))
    # bartender behind the bar
    bx_, bseat, bh_ = bartender
    d.add(person(bx_, bseat, bh_, **BARTENDER, upper_only=True, seated_y=bseat, arm_l=6, arm_r=20))
    ax, afoot, aw, ah = bar
    d.add(shadow(ax + aw / 2, afoot, aw * 0.5))
    d.add(r(ax, afoot - ah, aw, ah, '#7A5A3E'), r(ax, afoot - ah - 16, aw + 14, 22, '#5A4331', 5))
    for i in range(int(aw / 120)):
        d.add(r(ax + 20 + i * 120, afoot - ah + 30, 90, ah - 50, '#6E5038', 4))
    stx, sty, stl, sth = stap
    d.add(stapler(stx, afoot - ah + 4, stl, afoot - ah + (sth - (afoot - ah))))
    # lunch tables around the pool table
    for t in tables[:-1] if o == 'L' else tables:
        d.add(lunch_table(*t))
    d.add(pool_table(*pool))
    if o == 'L':
        d.add(lunch_table(*tables[-1]))
    # Diana reading the ceiling; the player beside her
    d.add(person(diana[0], diana[1], diana[2], **DIANA, look='up', arm_l=6))
    d.add(person(player[0], player[1], player[2], **PLAYER, gaze=-0.9))
    return d.svg()


# ---------------------------------------------------------------- gift shop
CLERK = dict(skin='#A8775A', hair='#2E2621', hair_style='long', top='#D99A8E')


def tshirt(cx, y, s, col):
    return [poly([(cx - s * 0.12, y - s * 0.12), (cx, y - s * 0.22), (cx + s * 0.12, y - s * 0.12)], '#9A8F80'),
            poly([(cx - s * 0.2, y), (cx + s * 0.2, y), (cx + s * 0.42, y + s * 0.2), (cx + s * 0.32, y + s * 0.34),
                  (cx + s * 0.24, y + s * 0.28), (cx + s * 0.24, y + s * 0.95), (cx - s * 0.24, y + s * 0.95),
                  (cx - s * 0.24, y + s * 0.28), (cx - s * 0.32, y + s * 0.34), (cx - s * 0.42, y + s * 0.2)], col),
            path(f'M{cx - s * 0.08:.1f},{y:.1f} Q{cx:.1f},{y + s * 0.08:.1f} {cx + s * 0.08:.1f},{y:.1f} Z', shade(col, 0.85))]


def cap(cx, y, s, col):
    return [path(f'M{cx - s * 0.5:.1f},{y:.1f} A{s * 0.5:.1f},{s * 0.45:.1f} 0 0 1 {cx + s * 0.5:.1f},{y:.1f} Z', col),
            r(cx + s * 0.2, y - s * 0.08, s * 0.55, s * 0.1, shade(col, 0.8), s * 0.05),
            ci(cx, y - s * 0.44, s * 0.05, shade(col, 0.8))]


def postcard_rack(cx, y_floor, s):
    out = [shadow(cx, y_floor, s * 0.3), r(cx - s * 0.02, y_floor - s * 1.6, s * 0.04, s * 1.6, '#8C9196'),
           r(cx - s * 0.18, y_floor - s * 0.04, s * 0.36, s * 0.04, '#8C9196', 2)]
    cols = ['#9FCBE3', '#E6A497', '#AFD6BE', '#F0DA9C', '#5DB6B4', '#F2CDBE']
    for t in range(4):
        ty = y_floor - s * (1.55 - t * 0.3)
        out.append(r(cx - s * 0.3, ty + s * 0.2, s * 0.6, s * 0.02, '#A3A8AD'))
        for i in range(4):
            out.append(r(cx - s * 0.29 + i * s * 0.15, ty, s * 0.13, s * 0.19, cols[(i + t * 2) % 6], 2))
            out.append(r(cx - s * 0.27 + i * s * 0.15, ty + s * 0.12, s * 0.09, s * 0.04, '#FFFFFF', 1))
    return out


def gift_shop(o):
    W, H = SIZE[o]
    d = Doc(W, H)
    if o == 'L':
        floor = 640
        door = (110, 150, 300, 490)
        rail = (500, 175, 760, 5, 130)
        caps = (1330, 210, 3, 2, 70)
        counter = (560, 790, 780, 225)
        till = (640, 66)
        clerk = (800, 620, 520, 64)
        note = (975, 548, 160, -6)
        player = (1215, 805, 560, 40)
        rack = (1590, 800, 330)
        diana = (1750, 805, 510, -1.3)
    else:
        floor = 1130
        door = None
        rail = (110, 470, 860, 4, 160)
        caps = (190, 230, 4, 1, 95)
        counter = (370, 1330, 710, 250)
        till = (465, 70)
        clerk = (640, 1110, 560, 64)
        note = (790, 1062, 160, -6)
        player = (960, 1420, 600, 36)
        rack = (115, 1395, 380)
        diana = (275, 1410, 560, 1.3)

    d.add(r(0, 0, W, floor, '#EEF3EE'), r(0, floor - 20, W, 20, '#DCE5DE'))
    d.add(r(0, floor, W, H - floor, '#E7DDCC'))
    yy, k = floor, 0
    while yy < H:
        d.add(r(0, yy, W, 3, '#D9CDB9'))
        yy += 28 + k * 10
        k += 1
    if door:
        x, y, w, h = door
        glow = d.rad_grad([(0, '#FFF6DE', 0.75), (1, '#FFF6DE', 0)])
        d.add(el(x + w / 2, floor + 60, w * 0.9, 90, glow))
        d.add(r(x - 18, y - 18, w + 36, h + 18, C['white'], 4))
        d.add(r(x, y, w, h * 0.6, d.lin_grad([(0, C['sky_top']), (1, C['sky_bot'])])))
        d.add(r(x, y + h * 0.6, w, h * 0.4, '#D8D0C2'))
        d.add(house(x + w * 0.1, y + h * 0.6, w * 0.6, h * 0.28, C['butter'], windows=2))
        d.add(palm_pot(x + w * 0.82, y + h * 0.66, h * 0.2))
    # t-shirts on a rail behind the till
    rx, ry, rw, rn, rs = rail
    d.add(r(rx, ry - 6, rw, 8, '#A39A8C', 4))
    tcols = [C['coral'], C['mint'], C['butter'], C['pblue'], '#F7F5F0']
    for i in range(rn):
        d.add(tshirt(rx + (i + 0.5) * rw / rn, ry + rs * 0.22, rs, tcols[i % 5]))
    # caps on pegs
    cx0, cy0, cn, crows, cs = caps
    ccols = ['#4F6E8E', C['coral'], '#7FA59A', '#E6D3A3']
    for row in range(crows):
        for i in range(cn):
            px = cx0 + i * cs * 1.5 + cs * 0.5
            py = cy0 + row * cs * 1.25
            d.add(r(px - 3, py - cs * 0.55, 6, cs * 0.2, '#8E6B4B'))
            d.add(cap(px, py, cs, ccols[(i + row) % 4]))
    # the clerk behind the counter, handing change across
    kx, kseat, kh, karm = clerk
    d.add(person(kx, kseat, kh, **CLERK, upper_only=True, seated_y=kseat, arm_r=karm, gaze=0.8))
    x, foot, w, h = counter
    top = foot - h
    d.add(shadow(x + w / 2, foot, w * 0.55))
    d.add(r(x - 10, top - 14, w + 20, 22, '#C7A57C', 4), r(x, top + 8, w, h - 8, '#EADFCB', 4))
    for i in range(3):
        d.add(r(x + w * (0.05 + i * 0.32), top + h * 0.2, w * 0.26, h * 0.65, '#DED0B7', 4))
    # till
    tx, ts = till
    d.add(r(tx - ts, top - 14 - ts * 0.9, ts * 2, ts * 0.9, '#8C9196', 6),
          r(tx - ts * 0.85, top - 14 - ts * 0.82, ts * 1.2, ts * 0.5, '#B9BEC2', 3),
          poly([(tx - ts * 0.6, top - 14 - ts * 0.9), (tx + ts * 0.7, top - 14 - ts * 0.9), (tx + ts * 0.6, top - 14 - ts * 1.5), (tx - ts * 0.5, top - 14 - ts * 1.5)], '#5E646A'),
          r(tx - ts * 0.4, top - 14 - ts * 1.42, ts * 0.9, ts * 0.38, '#9FB9A6', 3))
    # the note: prominent, the one saturated accent
    nx, ny, nw, na = note
    d.add(bluebird_note(nx, ny, nw, na))
    # the player receiving it (seen from behind), Diana at the rack, watching sidelong
    px_, pf, ph, parm = player
    d.add(person(px_, pf, ph, **PLAYER, back=True, arm_l=parm, arm_r=4))
    d.add(postcard_rack(*rack))
    dx_, df, dh, dg = diana
    d.add(person(dx_, df, dh, **DIANA, gaze=dg))
    return d.svg()


SCENES = {'princess': princess, 'front_street': front_street, 'june_office': june_office,
          'swizzle_inn': swizzle_inn, 'gift_shop': gift_shop}
