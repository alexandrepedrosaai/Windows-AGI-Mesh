from PIL import Image, ImageDraw
import numpy as np, matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
# 3D graph
fig=plt.figure(figsize=(6,4))
ax=fig.add_subplot(111,projection='3d')
labels=['Reasoning','Tools','Memory','SelfCorr','Coord','Consensus']
vals=[88.2,96.1,83.7,90,92,100]
xs=np.arange(len(vals)); ys=np.zeros(len(vals)); zs=np.zeros(len(vals))
ax.bar3d(xs,ys,zs,0.6,0.6,vals,color=['#4F81BD']*6)
ax.set_xticks(xs+0.3); ax.set_xticklabels(labels,rotation=20)
ax.set_zlabel('Score')
ax.set_title('AGI Mesh Capability Index')
plt.tight_layout(); plt.savefig('/mnt/data/AGI_Mesh_3D_Graph.png'); plt.close()
# animated gif
frames=[]
for i in range(24):
    img=Image.new('RGB',(800,450),(10,15,30))
    d=ImageDraw.Draw(img)
    d.text((20,20),'Windows AGI Mesh',fill=(0,255,255))
    w=int((i+1)/24*600)
    d.rectangle((100,200,100+w,240),fill=(0,200,255))
    d.text((100,260),f'Capability Index {(91.67*(i+1)/24):.1f}',fill='white')
    frames.append(img)
frames[0].save('/mnt/data/AGI_Mesh_Animated.gif',save_all=True,append_images=frames[1:],duration=120,loop=0)
print('done')
