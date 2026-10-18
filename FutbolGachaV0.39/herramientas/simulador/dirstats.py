import numpy as np, sys, glob
fw=bw=lat=0
for f in sys.argv[1:]:
    for l in open(f):
        e=l.strip().split(",")
        if len(e)>4 and e[1]=="pass":
            x=e[4].split(";")
            if len(x)>=7:
                adv=float(x[6])-float(x[5])
                if adv>5: fw+=1
                elif adv<-5: bw+=1
                else: lat+=1
print(f"pases hacia delante {fw}, laterales {lat}, hacia atras {bw}")
