package com.example.linesight_flutter;

/** Activity-local double-press classifier. It never consumes an Android key. */
public final class AuroraKeySequence {
    private long firstDown = -1;
    private int windowMs = 360;
    public void setWindowMs(int value) { windowMs = Math.max(200, Math.min(600, value)); reset(); }
    public void reset() { firstDown = -1; }
    public boolean onDown(int keyCode, int repeatCount, long eventTime) {
        if (keyCode != 25) { reset(); return false; }
        if (repeatCount != 0) return false;
        if (firstDown >= 0 && eventTime > firstDown && eventTime - firstDown <= windowMs) {
            reset(); return true;
        }
        firstDown = eventTime;
        return false;
    }
}
