"""Package the verified offline checkpoint without private configuration."""
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'tool/package_product_batch.py').read_text(encoding='utf-8')
source = source.replace('1.1.22', '1.1.23').replace('8032', '8034')
source = source.replace("('sso','product-batch')", "('sso','product-batch','offline-batch')")
source = source.replace("'flutter_tests_passed':113", "'flutter_tests_passed':117")
source = source.replace("'django_tests_passed':32", "'django_tests_passed':33")
source = source.replace('本批新增：', '本批新增：按身份及工作区隔离的检验与整改草稿、加密照片重试队列、冲突确认后续填、通知持久已读、授权关闭入口。此前已接入：')
source = source.replace('检验离线草稿与上传队列、通知已读、', '')
exec(compile(source, str(root / 'tool/package_product_batch.py'), 'exec'))

