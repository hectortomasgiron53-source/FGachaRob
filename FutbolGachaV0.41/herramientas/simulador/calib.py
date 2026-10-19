import sys, glob
rows = []
for f in sys.argv[1:]:
    ev = [l.strip().split(",") for l in open(f) if l.strip()]
    last = None
    for e in ev:
        if e[1] == "pass":
            last = e
        elif e[1] in ("pass_ok", "pass_lost") and last:
            d, safe = last[4].split(";")[:2]
            rows.append((float(safe), float(d), e[1] == "pass_ok"))
            last = None
        elif e[1] in ("goal", "keeper_claim", "save_catch") :
            last = None
import numpy as np
rows = np.array(rows)
print("pases medidos:", len(rows), " acierto global %.0f%%" % (rows[:,2].mean()*100))
for lo, hi in ((0, .5), (.5, .7), (.7, .8), (.8, .9), (.9, .95), (.95, 1.01)):
    m = (rows[:,0] >= lo) & (rows[:,0] < hi)
    if m.sum():
        print(f"  seguridad {lo:.2f}-{hi:.2f}: {m.sum():3d} pases, real {rows[m,2].mean()*100:5.1f}%  distancia media {rows[m,1].mean():.0f}")
for lo, hi in ((0, 15), (15, 30), (30, 45), (45, 70)):
    m = (rows[:,1] >= lo) & (rows[:,1] < hi)
    if m.sum():
        print(f"  distancia {lo}-{hi}: {m.sum():3d} pases, real {rows[m,2].mean()*100:5.1f}%  prevista {rows[m,0].mean()*100:.0f}%")
