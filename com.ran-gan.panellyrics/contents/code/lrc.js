.pragma library

// Step 5 — LRC Parser.
// Converts LRC-format text (lines like "[00:12.30]Hello") into a
// time-sorted array of { time: <seconds:number>, text: <string> }.
// Supports multiple timestamp tags on one line and 2- or 3-digit fractions.
function parseLRC(lrcText) {
    var result = [];
    if (!lrcText) return result;

    var lines = lrcText.split(/\r?\n/);
    var tagRe = /\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]/g;

    for (var i = 0; i < lines.length; i++) {
        var line = lines[i];
        var times = [];
        var m;
        tagRe.lastIndex = 0;
        while ((m = tagRe.exec(line)) !== null) {
            var minutes = parseInt(m[1], 10);
            var seconds = parseInt(m[2], 10);
            var fracStr = m[3] || "0";
            while (fracStr.length < 3) fracStr += "0";
            var frac = parseInt(fracStr.substring(0, 3), 10);
            times.push(minutes * 60 + seconds + frac / 1000);
        }
        if (times.length === 0) continue;

        var text = line.replace(tagRe, "").trim();
        for (var j = 0; j < times.length; j++) {
            result.push({ time: times[j], text: text });
        }
    }

    result.sort(function (a, b) { return a.time - b.time; });
    return result;
}

// Step 6 — Synchronization.
// Returns the latest lyric line whose timestamp has been reached
// (currentPosition >= lyric.time), or null if none yet / no lyrics.
function findCurrentLine(parsedLyrics, currentPosition) {
    if (!parsedLyrics || parsedLyrics.length === 0) return null;
    var current = null;
    for (var i = 0; i < parsedLyrics.length; i++) {
        if (parsedLyrics[i].time <= currentPosition) {
            current = parsedLyrics[i];
        } else {
            break;
        }
    }
    return current;
}
