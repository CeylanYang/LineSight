# 按版本保存的组件截图

显示 App 版本号的组件截图随版本分目录保存，供 `cloud_nfc_test.dart` 和 `diagnostics_recovery_test.dart` 比对。新增版本先审阅差异，再保存新的参考图；不覆盖历史验收批次图片。这些由 Flutter widget tests 渲染，不是原生 Android 截图。
