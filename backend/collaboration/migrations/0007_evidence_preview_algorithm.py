from django.db import migrations, models

class Migration(migrations.Migration):
    dependencies = [('collaboration', '0006_notificationreceipt')]
    operations = [migrations.AddField(model_name='evidence',name='preview_algorithm',field=models.CharField(blank=True,default='',max_length=48))]
