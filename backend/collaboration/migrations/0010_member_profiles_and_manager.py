from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies=[('collaboration','0009_profile_template_binding')]
    operations=[
        migrations.AddField(model_name='cloudidentity',name='avatar_seed',field=models.CharField(blank=True,max_length=64)),
        migrations.AddField(model_name='cloudidentity',name='job_title',field=models.CharField(blank=True,max_length=80)),
        migrations.AlterField(model_name='membership',name='role',field=models.CharField(choices=[('owner','Owner'),('manager','Manager'),('operator','Operator'),('viewer','Viewer')],max_length=12)),
        migrations.AlterField(model_name='invitation',name='role',field=models.CharField(choices=[('owner','Owner'),('manager','Manager'),('operator','Operator'),('viewer','Viewer')],max_length=12)),
    ]
