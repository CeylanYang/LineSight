// Run on the disposable emulator in America/New_York; restore its timezone
// afterward. Both suites use independent database paths.
import 'record_query_journey_test.dart' as queries;
import 'time_portability_test.dart' as time;

void main() {
  time.main();
  queries.main();
}
