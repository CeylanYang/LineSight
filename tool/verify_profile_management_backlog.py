"""Read-only OOXML preservation check for the targeted import backlog edit."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET
import zipfile

root=Path(__file__).resolve().parents[1]
ns={'s':'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}
def read(path):
    with zipfile.ZipFile(path) as archive:
        strings=[]
        if 'xl/sharedStrings.xml' in archive.namelist():
            strings=[''.join(n.itertext()) for n in ET.fromstring(archive.read('xl/sharedStrings.xml'))]
        sheets={}
        for name in archive.namelist():
            if not (name.startswith('xl/worksheets/sheet') and name.endswith('.xml')):continue
            tree=ET.fromstring(archive.read(name)); cells={}
            data=tree.find('s:sheetData',ns)
            row_props=[dict(row.attrib) for row in data]
            for c in data.findall('.//s:c',ns):
                value=c.findtext('s:v',namespaces=ns)
                if c.get('t')=='s':value=strings[int(value)]
                if c.get('t')=='inlineStr':value=''.join(c.find('s:is',ns).itertext())
                cells[c.get('r')]=(value,c.findtext('s:f',namespaces=ns),c.get('s'))
            tree.remove(data)
            rel_path=str(Path(name).parent.as_posix())+'/_rels/'+Path(name).name+'.rels'
            if rel_path in archive.namelist():
                rels={row.get('Id'):(row.get('Type'),row.get('Target')) for row in ET.fromstring(archive.read(rel_path))}
                rid='{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'
                for row in tree.iter():
                    if rid in row.attrib: row.set(rid,str(rels[row.get(rid)]))
            sheets[name]=(cells,row_props,ET.tostring(tree))
        workbook=ET.fromstring(archive.read('xl/workbook.xml'))
        rels={row.get('Id'):(row.get('Type'),row.get('Target')) for row in ET.fromstring(archive.read('xl/_rels/workbook.xml.rels'))}
        rid='{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id'
        for row in workbook.iter():
            if rid in row.attrib: row.set(rid,str(rels[row.get(rid)]))
        return sheets,archive.read('xl/styles.xml'),ET.tostring(workbook),set(archive.namelist())

a,sa,wa,pa=read(root/'.artifact-work/profile-management-backlog-original.xlsx')
b,sb,wb,pb=read(root/'docs/product/linesight/LineSight_Development_Backlog.xlsx')
assert sa==sb,'Styles changed'
assert wa==wb,'Workbook structure changed'
assert pa==pb,'Native part inventory changed'
changes=[]
for name,(cells,rows,structure) in a.items():
    new,new_rows,new_structure=b[name]
    assert rows==new_rows and structure==new_structure,(name,'Row or sheet settings changed')
    assert cells.keys()==new.keys(),(name,'Cell inventory changed')
    for cell,value in cells.items():
        other=new[cell]
        assert value[1:]==other[1:],(name,cell,'Formula/style changed')
        if value[0]==other[0] or value[1] is not None:continue
        row=''.join(filter(str.isdigit,cell));col=''.join(filter(str.isalpha,cell))
        assert cells.get('A'+row,('',None,None))[0] in {'QC-01','SEC-04','UI-08','UI-11','QA-04'} and col in {'D','E','H','I','J'},(name,cell,'Unrelated value changed')
        changes.append({'sheet':name,'cell':cell})
assert changes
with zipfile.ZipFile(root/'.artifact-work/profile-management-backlog-original.xlsx') as old, zipfile.ZipFile(root/'docs/product/linesight/LineSight_Development_Backlog.xlsx') as new:
    for name in pa:
        if name.startswith('xl/tables/') and name.endswith('.xml'):
            assert old.read(name)==new.read(name),(name,'Native table changed')
report={'changed_cells':changes,'styles_preserved':True,'all_sheet_settings_preserved':True,'formulas_preserved':True,'unrelated_values_preserved':True,'native_parts_preserved':True}
(root/'docs/product/linesight/acceptance/profile-management-batch/workbook-preservation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'changed_cells':len(changes),'preservation_verified':True}))
