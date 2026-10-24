"""Derive static report fonts from the bundled OFL variable font (requires fonttools)."""
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from pathlib import Path
for weight,name in [(400,'Regular'),(600,'SemiBold')]:
 font=TTFont('assets/fonts/NotoSansSC.ttf')
 instantiateVariableFont(font, {'wght':weight}, inplace=True)
 output=Path(f'assets/fonts/NotoSansSC-{name}.ttf')
 font.save(output)
 print(output.name,output.stat().st_size)
