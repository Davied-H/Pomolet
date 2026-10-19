from pathlib import Path
import re,xml.etree.ElementTree as ET,subprocess,shutil,sys
from PIL import Image
import numpy as np
from reportlab.graphics.svgpath import SvgPath
from reportlab.graphics.shapes import Drawing,Group,Circle,Rect
from reportlab.graphics import renderPDF
from reportlab.lib.colors import black
root=Path(__file__).resolve().parents[1]
if len(sys.argv) != 2: raise SystemExit("Usage: python3 Tools/prepare-assets.py /path/to/original-demo/outputs")
source_dir=Path(sys.argv[1])
resources=root/'Resources';icons=resources/'Icons';icons.mkdir(parents=True,exist_ok=True)
html=(source_dir/'pomodoro.html').read_text()
for name,body in re.findall(r'<symbol id="icon-([^\"]+)"[^>]*>(.*?)</symbol>',html):
 group=Group();group.translate(0,24);group.scale(1,-1)
 for node in ET.fromstring('<svg>'+body+'</svg>'):
  if node.tag=='path':shape=SvgPath(node.attrib['d'], fillColor=black if name in ['play','pause'] else None)
  elif node.tag=='circle':shape=Circle(float(node.attrib['cx']),float(node.attrib['cy']),float(node.attrib['r']))
  elif node.tag=='rect':shape=Rect(float(node.attrib['x']),float(node.attrib['y']),float(node.attrib['width']),float(node.attrib['height']),rx=float(node.attrib.get('rx',0)))
  else:continue
  shape.fillColor=black if name in ['play','pause'] else None;shape.strokeColor=None if name in ['play','pause'] else black;shape.strokeWidth=1.7;shape.strokeLineCap=1;shape.strokeLineJoin=1;group.add(shape)
 drawing=Drawing(24,24);drawing.add(group);renderPDF.drawToFile(drawing,str(icons/(name+'.pdf')))
for name,path in {'pencil':'m15 4 5 5 M4 20l4-1 12-12a2.1 2.1 0 0 0-3-3 L5 16Z','plus':'M12 5v14M5 12h14','close':'m6 6 12 12 M6 18 18 6','check':'m5 12 4 4 10-10'}.items():
 g=Group();g.translate(0,24);g.scale(1,-1);shape=SvgPath(path,fillColor=None);shape.fillColor=None;shape.strokeColor=black;shape.strokeWidth=1.5 if name=='pencil' else 1.7;shape.strokeLineCap=1;shape.strokeLineJoin=1;g.add(shape);d=Drawing(24,24);d.add(g);renderPDF.drawToFile(d,str(icons/(name+'.pdf')))
shutil.copy2(source_dir/'character-focus-full-poster.png',resources/'poster.png')
pixels=np.asarray(Image.open(resources/'poster.png').convert('RGBA')).copy()
rgb=pixels[:,:,:3].astype(np.float64)/255
luma=rgb[:,:,0]*.2126+rgb[:,:,1]*.7152+rgb[:,:,2]*.0722
pixels[:,:,:3]=np.rint(np.clip(1.09-1.18*luma,0,1)*255).astype(np.uint8)[:,:,None]
Image.fromarray(pixels).save(resources/'poster-dark.png')
for key in ['idle','focus-adjust','short','short-eyes','long','long-yawn']:
 dst=resources/'Videos'/(key+'.mov')
 if dst.exists():continue
 source=source_dir/('character-'+key+'-smooth.webm')
 decoder=subprocess.Popen(['ffmpeg','-v','error','-c:v','libvpx-vp9','-i',str(source),'-an','-f','rawvideo','-pix_fmt','bgra','pipe:1'],stdout=subprocess.PIPE)
 encoder=subprocess.run([str(root/'.build/native/encode-alpha'),str(dst),'540','720','60'],stdin=decoder.stdout)
 decoder.stdout.close();assert decoder.wait()==0 and encoder.returncode==0,key
 print(key,'converted',dst.stat().st_size,flush=True)
