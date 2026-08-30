.pragma library

// MPRIS access via busctl subprocesses (run through Plasma5Support's
// "executable" DataSource engine). Avoids depending on any Plasma-private
// QML module, so this stays stable across Plasma versions.
//
// Spotify only, by design: querying every registered MPRIS player and
// picking "the best one" turned out to be genuinely unreliable in practice
// (a browser tab with no track metadata could tie with or beat Spotify,
// non-deterministically depending on which subprocess answered first -
// see git history). Targeting Spotify's fixed bus name directly sidesteps
// that whole class of bug.

var SPOTIFY_SERVICE = "org.mpris.MediaPlayer2.spotify";

function getAllPropertiesCommand() {
    return "busctl --user --json=short call " + SPOTIFY_SERVICE +
        " /org/mpris/MediaPlayer2 org.freedesktop.DBus.Properties GetAll s org.mpris.MediaPlayer2.Player";
}

// Parses the JSON output of the GetAll call above into a plain object.
// Position/length are converted from MPRIS microseconds to seconds.
// valid stays false if Spotify isn't running (the busctl call fails, so
// stdout is empty/unparseable) - that's the normal "no player" case, not
// an error.
function parsePlayerProperties(stdout) {
    var empty = {
        valid: false,
        playbackStatus: "Stopped",
        position: 0,
        title: "",
        artist: "",
        album: "",
        length: 0,
        artUrl: "",
        trackId: "",
        canGoNext: false,
        canGoPrevious: false,
        canPlay: false,
        canPause: false,
        canSeek: false
    };
    if (!stdout) return empty;
    try {
        var result = JSON.parse(stdout);
        var props = result.data[0];

        var playbackStatus = (props.PlaybackStatus && props.PlaybackStatus.data) || "Stopped";
        var positionUs = (props.Position && typeof props.Position.data === "number") ? props.Position.data : 0;

        var meta = (props.Metadata && props.Metadata.data) || {};
        var title = (meta["xesam:title"] && meta["xesam:title"].data) || "";
        var artistField = meta["xesam:artist"] && meta["xesam:artist"].data;
        var artist = (Array.isArray(artistField) && artistField.length > 0) ? artistField[0] : "";
        var album = (meta["xesam:album"] && meta["xesam:album"].data) || "";
        var lengthUs = (meta["mpris:length"] && typeof meta["mpris:length"].data === "number") ? meta["mpris:length"].data : 0;
        var artUrl = (meta["mpris:artUrl"] && meta["mpris:artUrl"].data) || "";
        var trackId = (meta["mpris:trackid"] && meta["mpris:trackid"].data) || "";

        return {
            valid: true,
            playbackStatus: playbackStatus,
            position: positionUs / 1000000,
            title: title,
            artist: artist,
            album: album,
            length: lengthUs / 1000000,
            artUrl: artUrl,
            trackId: trackId,
            canGoNext: !!(props.CanGoNext && props.CanGoNext.data),
            canGoPrevious: !!(props.CanGoPrevious && props.CanGoPrevious.data),
            canPlay: !!(props.CanPlay && props.CanPlay.data),
            canPause: !!(props.CanPause && props.CanPause.data),
            canSeek: !!(props.CanSeek && props.CanSeek.data)
        };
    } catch (e) {
        return empty;
    }
}

// ---------------------------------------------------------------------
// Playback control commands. Fire-and-forget: caller doesn't need to
// parse a response, just connectSource() one of these through a DataSource.
// ---------------------------------------------------------------------

function playPauseCommand() {
    return "busctl --user call " + SPOTIFY_SERVICE + " /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player PlayPause";
}

function nextCommand() {
    return "busctl --user call " + SPOTIFY_SERVICE + " /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Next";
}

function previousCommand() {
    return "busctl --user call " + SPOTIFY_SERVICE + " /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player Previous";
}

// trackId is an MPRIS object path (e.g. "/com/spotify/track/xxxx"); the
// SetPosition method signature is "ox" (object-path, int64 microseconds).
function setPositionCommand(trackId, positionSeconds) {
    var positionUs = Math.round(positionSeconds * 1000000);
    return "busctl --user call " + SPOTIFY_SERVICE +
        " /org/mpris/MediaPlayer2 org.mpris.MediaPlayer2.Player SetPosition ox '" + trackId + "' " + positionUs;
}
