from pathlib import Path
from datetime import datetime,timedelta
from zoneinfo import ZoneInfo
import json,uuid
root=Path(__file__).resolve().parents[1]
folder=root/'.build/parity-fixture';folder.mkdir(parents=True,exist_ok=True)
now=datetime.now(ZoneInfo('Asia/Shanghai'))
reference=datetime(2001,1,1,tzinfo=ZoneInfo('UTC')).timestamp()
rows=[]
for age,count in enumerate([4,2,3,1,5,2,3]):
 for i in range(count):
  end=now-timedelta(days=age,minutes=3+i*4)
  rows.append(dict(id=str(uuid.uuid4()).upper(),endedAt=end.timestamp()-reference,task=['写作','阅读','设计'][i%3],minutes=[25,15,30,20][i%4],modeName='专注'))
state=dict(schemaVersion=1,modes=[dict(id='focus',name='专注',minutes=25,kind='focus'),dict(id='short',name='短休息',minutes=5,kind='short'),dict(id='long',name='长休息',minutes=15,kind='long')],sound=True,dark=False,task='',records=rows,session=dict(selectedID='focus',running=False,remaining=1500,total=1500,roundStarted=False),lastFocusID='focus')
path=folder/'state.json';path.write_text(json.dumps(state,ensure_ascii=False,indent=2));print(path)
