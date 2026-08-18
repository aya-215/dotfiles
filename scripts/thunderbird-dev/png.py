import zlib,struct
from collections import Counter
def load(path):
    d=open(path,'rb').read(); i=8; idat=b''; w=h=bd=ct=None
    while i<len(d):
        ln=struct.unpack('>I',d[i:i+4])[0]; t=d[i+4:i+8]; b=d[i+8:i+8+ln]
        if t==b'IHDR': w,h,bd,ct=struct.unpack('>IIBB',b[:10])
        elif t==b'IDAT': idat+=b
        elif t==b'IEND': break
        i+=12+ln
    ch={0:1,2:3,3:1,4:2,6:4}[ct]; raw=zlib.decompress(idat)
    bpp=ch*bd//8; st=w*bpp; out=[]; prev=bytearray(st); p=0
    for y in range(h):
        f=raw[p]; p+=1; L=bytearray(raw[p:p+st]); p+=st
        for x in range(st):
            a=L[x-bpp] if x>=bpp else 0; b2=prev[x]; c=prev[x-bpp] if x>=bpp else 0
            if f==1: L[x]=(L[x]+a)&255
            elif f==2: L[x]=(L[x]+b2)&255
            elif f==3: L[x]=(L[x]+(a+b2)//2)&255
            elif f==4:
                pp=a+b2-c; pa,pb,pc=abs(pp-a),abs(pp-b2),abs(pp-c)
                L[x]=(L[x]+(a if (pa<=pb and pa<=pc) else (b2 if pb<=pc else c)))&255
        out.append(bytes(L)); prev=L
    return w,h,ch,out
def top(path,n=6):
    w,h,ch,rows=load(path); c=Counter()
    for r in rows:
        for x in range(0,len(r),ch): c[(r[x],r[x+1],r[x+2])]+=1
    res=[]
    for rgb,cnt in c.most_common(n):
        L=0.2125*rgb[0]+0.7154*rgb[1]+0.0721*rgb[2]
        res.append((f'#{rgb[0]:02x}{rgb[1]:02x}{rgb[2]:02x}', cnt*100/(w*h), L))
    return w,h,res
