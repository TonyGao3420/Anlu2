from pathlib import Path
from pypdf import PdfReader
root=Path(__file__).resolve().parents[2];build=root/'sim/build/roi_original_20261027'
board=root.parent/'9_康芯开发板使用手册及实验平台/新HX1P35A开发板手册-HDL版2604.pdf'
pages=[]
for n,page in enumerate(PdfReader(board).pages):
 text=page.extract_text() or ''
 if any(k in text for k in ['SW3','拨码','SW1','A4']):
  pages.append(f'PAGE {n+1}\n{text}');print('board page',n+1,flush=True)
(build/'board_switches.txt').write_text('\n\n'.join(pages),encoding='utf-8')
guide=Path("C:/Users/11512/Desktop/全国大学生嵌入式芯片与系统设计竞赛'2026FPGA赛道选题指南-安路科技.pdf")
pdf=PdfReader(guide)
(build/'track2_guide.txt').write_text('\n\n'.join(f'PAGE {n+1}\n'+(pdf.pages[n].extract_text() or '') for n in [15,16,17]),encoding='utf-8')
