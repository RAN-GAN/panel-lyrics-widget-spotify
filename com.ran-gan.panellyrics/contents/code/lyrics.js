.pragma library

// Step 4 — LRCLIB lookup, and Step 7 — in-session caching.
//
// callback(result) is invoked exactly once with:
//   { status: "synced" | "unsynced" | "none" | "error",
//     syncedLyrics: <LRC text or null>,
//     plainLyrics: <plain text or null> }

var cache = {};

function cacheKey(artist, title) {
    return (artist || "").trim().toLowerCase() + "||" + (title || "").trim().toLowerCase();
}

function fetchLyrics(artist, title, album, durationSeconds, callback) {
    if (!artist || !title) {
        callback({ status: "none", syncedLyrics: null, plainLyrics: null });
        return;
    }

    var key = cacheKey(artist, title);
    if (cache.hasOwnProperty(key)) {
        callback(cache[key]);
        return;
    }

    var url = "https://lrclib.net/api/get?artist_name=" + encodeURIComponent(artist) +
        "&track_name=" + encodeURIComponent(title);
    if (album) url += "&album_name=" + encodeURIComponent(album);
    if (durationSeconds && durationSeconds > 0) url += "&duration=" + Math.round(durationSeconds);

    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        if (xhr.status === 200) {
            var result;
            try {
                result = buildResult(JSON.parse(xhr.responseText));
            } catch (e) {
                result = null;
            }
            if (result && result.status !== "none") {
                cache[key] = result;
                callback(result);
                return;
            }
        }
        // Exact match missing or failed (typically 404) -> broader search.
        searchFallback(key, artist, title, callback);
    };
    xhr.open("GET", url);
    xhr.send();
}

function searchFallback(key, artist, title, callback) {
    var url = "https://lrclib.net/api/search?artist_name=" + encodeURIComponent(artist) +
        "&track_name=" + encodeURIComponent(title);

    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE) return;
        var result;
        if (xhr.status === 200) {
            try {
                var arr = JSON.parse(xhr.responseText);
                result = (arr && arr.length > 0) ? buildResult(arr[0]) : { status: "none", syncedLyrics: null, plainLyrics: null };
            } catch (e) {
                result = { status: "error", syncedLyrics: null, plainLyrics: null };
            }
        } else {
            result = { status: "error", syncedLyrics: null, plainLyrics: null };
        }
        // Don't cache transient errors -> allow retry on the next song-change event.
        if (result.status !== "error") cache[key] = result;
        callback(result);
    };
    xhr.open("GET", url);
    xhr.send();
}

function buildResult(data) {
    if (!data) return { status: "none", syncedLyrics: null, plainLyrics: null };
    if (data.syncedLyrics) {
        return { status: "synced", syncedLyrics: data.syncedLyrics, plainLyrics: data.plainLyrics || null };
    }
    if (data.plainLyrics) {
        return { status: "unsynced", syncedLyrics: null, plainLyrics: data.plainLyrics };
    }
    if (data.instrumental) {
        return { status: "unsynced", syncedLyrics: null, plainLyrics: "(Instrumental)" };
    }
    return { status: "none", syncedLyrics: null, plainLyrics: null };
}
