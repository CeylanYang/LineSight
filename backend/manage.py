#!/usr/bin/env python3
import os
import sys

try:
    import pysqlite3

    sys.modules["sqlite3"] = pysqlite3
except ImportError:
    pass

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "linesight.settings")

from django.core.management import execute_from_command_line  # noqa: E402

execute_from_command_line(sys.argv)
