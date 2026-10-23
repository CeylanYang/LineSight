from django.db import migrations


def seed(apps, schema_editor):
    Template = apps.get_model('collaboration', 'CheckTemplate')
    for name, labels in [
        ('通用外观检查', ['表面完整', '无裂纹或分层', '边缘与支撑清理', '标识与包装']),
        ('尺寸与装配检查', ['关键尺寸', '孔位与配合', '装配适配', '紧固与稳定性']),
        ('打印工艺检查', ['首层与底面', '层间结合', '翘曲与变形', '材料与工艺参数']),
    ]:
        Template.objects.create(name=name, version=1, workspace=None,
            items=[{'id': f'item-{index + 1}', 'label': label, 'required': True, 'allow_na': index == 3}
                   for index, label in enumerate(labels)])
    Inspection = apps.get_model('collaboration', 'QualityInspection')
    current, count = None, 0
    for check in Inspection.objects.order_by('job_id', 'created_at', 'pk').iterator():
        if check.job_id != current:
            current, count = check.job_id, 0
        count += 1
        Inspection.objects.filter(pk=check.pk).update(round_no=count)


class Migration(migrations.Migration):
    dependencies = [('collaboration', '0004_evidence_content_hash_evidence_inspection_and_more')]
    operations = [migrations.RunPython(seed, migrations.RunPython.noop)]
