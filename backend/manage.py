#!/usr/bin/env python3
import os
import sys

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "linesight.settings")

from django.core.management import execute_from_command_line  # noqa: E402

execute_from_command_line(sys.argv)
