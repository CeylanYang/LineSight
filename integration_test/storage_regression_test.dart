// Run the affected workflows in one Android build, each with its own database.
import 'data_management_test.dart' as data;
import 'large_backup_test.dart' as backup;
import 'local_workflow_test.dart' as local;
import 'startup_validation_test.dart' as startup;
import 'state_storage_test.dart' as chunks;
import 'storage_recovery_test.dart' as recovery;

void main() {
  chunks.main();
  startup.main();
  data.main();
  local.main();
  recovery.main();
  backup.main();
}
