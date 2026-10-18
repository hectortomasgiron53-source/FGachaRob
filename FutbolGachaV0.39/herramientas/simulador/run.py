"""Ejecuta el simulador con el codigo actual del proyecto, calcula metricas y dibuja fotogramas."""
import csv
import io
import os
import shutil
import subprocess
import sys

import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = sys.argv[1]
SECONDS = int(sys.argv[2]) if len(sys.argv) > 2 else 120
SEED = int(sys.argv[3]) if len(sys.argv) > 3 else 1
TAG = sys.argv[4] if len(sys.argv) > 4 else "run"
SHEET_START = float(sys.argv[5]) if len(sys.argv) > 5 else 10.0
STEP = float(sys.argv[6]) if len(sys.argv) > 6 else 1.0

HEADER = 'local __v = require("./vec")\nlocal Vector3, Color3 = __v.Vector3, __v.Color3\n'
for src, dst in (("src/server/Services/Tactics.lua", "Tactics.lua"), ("src/shared/Config/Balance.lua", "Balance.lua")):
    text = open(os.path.join(PROJ, src)).read().replace("--!strict\n", "", 1)
    open(os.path.join(HERE, dst), "w").write(HEADER + text)

HUMAN = os.environ.get("HUMAN", "0")
res = subprocess.run(["/tmp/luau_bin/luau", "sim.luau", "-a", str(SECONDS), str(SEED), HUMAN], cwd=HERE, capture_output=True, text=True)
if res.returncode != 0:
    print(res.stdout[-3000:])
    print(res.stderr[-3000:])
    sys.exit(1)
out = res.stdout
score = out.split("\n", 1)[0]
frames_txt = out.split("===FRAMES===\n", 1)[1].split("\n===EVENTS===", 1)[0]
events_txt = out.split("===EVENTS===\n", 1)[1] if "===EVENTS===\n" in out else ""

rows = list(csv.reader(io.StringIO(frames_txt)))
header, data = rows[0], rows[1:]
idx = {name: i for i, name in enumerate(header)}
T = np.array([float(r[0]) for r in data])
BX = np.array([float(r[1]) for r in data])
BZ = np.array([float(r[2]) for r in data])
CT = np.array([int(r[3]) for r in data])
P = {}
for pid in range(1, 9):
    P[pid] = {
        "x": np.array([float(r[idx[f"p{pid}_x"]]) for r in data]),
        "z": np.array([float(r[idx[f"p{pid}_z"]]) for r in data]),
        "role": [r[idx[f"p{pid}_role"]] for r in data],
        "tx": np.array([float(r[idx[f"p{pid}_tx"]]) for r in data]),
        "tz": np.array([float(r[idx[f"p{pid}_tz"]]) for r in data]),
    }
field_ids = [1, 2, 3, 5, 6, 7]

import re
_bal = open(os.path.join(HERE, "Balance.lua")).read()
L2 = float(re.search(r"Length = (\d+)", _bal).group(1)) / 2
W2 = float(re.search(r"Width = (\d+)", _bal).group(1)) / 2
CR = float(re.search(r"CenterCircleRadius = (\d+)", _bal).group(1))
AR = float(re.search(r"AreaRadius = (\d+)", _bal).group(1))
ev = [line.split(",") for line in events_txt.strip().split("\n") if line.strip()]
def count(kind):
    return sum(1 for e in ev if e[1] == kind)

minutes = SECONDS / 60
passes = count("pass")
ok = count("pass_ok")
lost = count("pass_lost")
# Jugadores de campo cerca del balon
near = []
spread = []
for i in range(len(T)):
    n = 0
    for pid in field_ids:
        if np.hypot(P[pid]["x"][i] - BX[i], P[pid]["z"][i] - BZ[i]) < 12:
            n += 1
    near.append(n)
    for team_ids in ([1, 2, 3], [5, 6, 7]):
        xs = [P[p]["x"][i] for p in team_ids]
        zs = [P[p]["z"][i] for p in team_ids]
        d = [np.hypot(xs[a] - xs[b], zs[a] - zs[b]) for a in range(3) for b in range(a + 1, 3)]
        spread.append(np.mean(d))
# Tiempo con el balon en el ultimo tercio del que lo tiene
third = []
for i in range(len(T)):
    c = CT[i]
    if 1 <= c <= 8:
        team = 1 if c <= 4 else 2
        a = 1 if team == 1 else -1
        third.append(1 if BX[i] * a > L2 / 3 else 0)
L2b = L2
poss1 = np.mean([1 if 1 <= c <= 4 else 0 for c in CT if c > 0]) if any(CT > 0) else 0
print(f"[{TAG}] {score}  pases {passes} ({passes/minutes:.1f}/min)  completados {ok}  perdidos {lost}  "
      f"tiros {count('shot')}  goles {count('goal')}  entradas {count('tackle_won')}/{count('tackle_won')+count('tackle_fail')}  "
      f"robos {count('steal')}  perdidas {count('turnover')}  croquetas {count('juke')}")
print(f"[{TAG}] jugadores a <12 del balon: media {np.mean(near):.2f}  (>=4: {np.mean(np.array(near) >= 4)*100:.0f}% del tiempo)  "
      f"separacion media entre companeros {np.mean(spread):.1f}  posesion azul {poss1*100:.0f}%  ultimo tercio {np.mean(third)*100:.0f}%")

import re
bal = open(os.path.join(HERE, "Balance.lua")).read()
HL = float(re.search(r"Length = (\d+)", bal).group(1)) / 2
HW = float(re.search(r"Width = (\d+)", bal).group(1)) / 2
CR = float(re.search(r"CenterCircleRadius = (\d+)", bal).group(1))
AR = float(re.search(r"AreaRadius = (\d+)", bal).group(1))
# Hoja de fotogramas
fig, axes = plt.subplots(4, 4, figsize=(20, 12.5))
start = SHEET_START
for n, ax in enumerate(axes.flat):
    t = start + n * STEP
    i = int(np.argmin(np.abs(T - t)))
    ax.set_xlim(-L2 - 2, L2 + 2)
    ax.set_ylim(-W2 - 2, W2 + 2)
    ax.set_aspect("equal")
    ax.add_patch(plt.Rectangle((-L2, -W2), 2 * L2, 2 * W2, fill=True, color="#3c9a4a", zorder=0))
    ax.plot([0, 0], [-W2, W2], color="white", lw=1)
    ax.add_patch(plt.Circle((0, 0), CR, fill=False, color="white", lw=1))
    for gx in (-L2, L2):
        ax.plot([gx, gx], [-14, 14], color="yellow", lw=4)
        ax.add_patch(plt.Circle((gx, 0), AR, fill=False, color="white", lw=0.8))
    for pid in range(1, 9):
        team = 1 if pid <= 4 else 2
        color = "#2f6fe0" if team == 1 else "#e03a2f"
        x, z = P[pid]["x"][i], P[pid]["z"][i]
        role = P[pid]["role"][i]
        ax.plot([x, P[pid]["tx"][i]], [z, P[pid]["tz"][i]], color=color, lw=0.8, ls=":")
        ax.scatter([x], [z], s=110, color=color, edgecolor="black" if CT[i] == pid else "white", linewidth=2.5 if CT[i] == pid else 0.8, zorder=3)
        ax.text(x + 2, z + 2, f"{pid}{role[:2]}", fontsize=7, color="white", zorder=4)
    ax.scatter([BX[i]], [BZ[i]], s=45, color="white", edgecolor="black", zorder=5)
    ax.set_title(f"t={T[i]:.1f}s", fontsize=9)
    ax.set_xticks([])
    ax.set_yticks([])
plt.tight_layout()
path = os.path.join(HERE, f"sheet_{TAG}.png")
plt.savefig(path, dpi=55)
print(path)
with open(os.path.join(HERE, f"events_{TAG}.csv"), "w") as fh:
    fh.write(events_txt)
