import os,sys
import pysqlite3
sys.modules['sqlite3']=pysqlite3
os.environ.setdefault('DJANGO_SETTINGS_MODULE','linesight.production_settings')
from django.core.management import execute_from_command_line
execute_from_command_line(sys.argv)
