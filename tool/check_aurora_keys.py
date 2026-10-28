"""Host-JVM checks for the Android Activity's non-consuming double-press classifier."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
stage = root / '.artifact-work/aurora84/java'
stage.mkdir(parents=True, exist_ok=True)
fixture = stage / 'AuroraKeySequenceCheck.java'
fixture.write_text('''import com.example.linesight_flutter.AuroraKeySequence;
public class AuroraKeySequenceCheck {
  private static void check(boolean condition) { if (!condition) throw new AssertionError(); }
  public static void main(String[] args) {
    AuroraKeySequence keys = new AuroraKeySequence();
    check(!keys.onDown(25, 0, 100)); check(keys.onDown(25, 0, 300));
    check(!keys.onDown(25, 0, 400)); check(!keys.onDown(25, 0, 1000));
    keys.reset(); check(!keys.onDown(25, 0, 2000));
    check(!keys.onDown(25, 1, 2050)); check(!keys.onDown(25, 4, 2100));
    check(!keys.onDown(25, 0, 2500));
    keys.reset(); check(!keys.onDown(25, 0, 3000)); check(!keys.onDown(24, 0, 3050)); check(!keys.onDown(25, 0, 3100));
    keys.reset(); check(!keys.onDown(25, 0, 4000)); keys.reset(); check(!keys.onDown(25, 0, 4100));
    keys.setWindowMs(200); check(!keys.onDown(25, 0, 5000)); check(keys.onDown(25, 0, 5200));
    keys.reset(); check(!keys.onDown(25, 0, 6000)); check(!keys.onDown(25, 0, 6000));
    System.out.println("Aurora native key sequence checks passed");
  }
}''', encoding='utf-8')
jdk = Path('C:/Program Files/Java/jdk-21/bin')
subprocess.run([str(jdk/'javac.exe'), '-d', str(stage), str(root/'android/app/src/main/java/com/example/linesight_flutter/AuroraKeySequence.java'), str(fixture)],check=True)
subprocess.run([str(jdk/'java.exe'), '-cp', str(stage), 'AuroraKeySequenceCheck'],check=True)
activity = (root/'android/app/src/main/kotlin/com/example/linesight_flutter/MainActivity.kt').read_text(encoding='utf-8')
assert 'return super.dispatchKeyEvent(event)' in activity
assert 'auroraForeground = false' in activity and 'auroraKeys.reset()' in activity
