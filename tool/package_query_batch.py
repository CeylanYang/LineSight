"""Package the shared filtering and evidence report checkpoint."""
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = (root / 'tool/package_product_batch.py').read_text(encoding='utf-8')
source = source.replace('1.1.22', '1.1.24').replace('8032', '8036')
source = source.replace("('sso','product-batch')", "('sso','product-batch','offline-batch','query-batch')")
source = source.replace("'flutter_tests_passed':113", "'flutter_tests_passed':117")
source = source.replace("'django_tests_passed':32", "'django_tests_passed':34")
source = source.replace('本批新增：', '本批新增：任务/记录/报告共享筛选、异常类别分布与下钻、报告预览、追溯码、证据缩略图、CSV范围与轮次明细。此前已接入：检验与整改离线草稿、加密图片上传重试队列、冲突续填、通知已读、授权关闭。')
source = source.replace('检验离线草稿与上传队列、通知已读、完整统计筛选与图表下钻、', '趋势日期下钻、检验时间段筛选、二维码、受控导入、')
exec(compile(source, str(root / 'tool/package_product_batch.py'), 'exec'))
report['source_commit'] = subprocess.check_output(['git','rev-parse','HEAD'], cwd=root, text=True).strip()
(destination / 'build.json').write_text(json.dumps(report, indent=2)+'\n', encoding='utf-8')
