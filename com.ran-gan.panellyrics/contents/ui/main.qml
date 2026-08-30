import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

import "../code/mpris.js" as Mpris
import "../code/lyrics.js" as Lyrics
import "../code/lrc.js" as Lrc

PlasmoidItem {
    id: root

    Plasmoid.title: "Panel Lyrics"

    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------

    property string currentArtist: ""
    property string currentTitle: ""
    property string currentAlbum: ""
    property real currentLength: 0        // seconds
    property real currentPosition: 0      // seconds
    property string playbackStatus: "Stopped"

    property string currentArtUrl: ""
    property string currentTrackId: ""
    property bool currentCanGoNext: false
    property bool currentCanGoPrevious: false
    property bool currentCanPlay: false
    property bool currentCanPause: false
    property bool currentCanSeek: false

    // "idle" | "loading" | "synced" | "unsynced" | "none" | "error"
    property string lyricsState: "idle"
    property var parsedLyrics: []         // [{ time, text }], only meaningful when lyricsState === "synced"

    // Bumped on every song change; async lyric-fetch callbacks compare
    // against this to ignore stale results from a since-superseded song.
    property int requestToken: 0

    property string displayText: ""

    function hasActivePlayer() {
        return playbackStatus === "Playing" || playbackStatus === "Paused";
    }

    function updateDisplay() {
        if (!hasActivePlayer()) {
            displayText = ""; // idle panel should just be empty, not a status message
            return;
        }
        if (!cfgShowLyrics) {
            displayText = currentArtist + " – " + currentTitle;
            return;
        }
        switch (lyricsState) {
        case "loading":
            displayText = "Loading lyrics…";
            break;
        case "synced": {
            var line = Lrc.findCurrentLine(parsedLyrics, currentPosition);
            // Real LRC files often have blank lines to mark instrumental/intro
            // gaps (a timestamp with no text) - fall back rather than show nothing.
            displayText = (line && line.text) ? line.text : (currentArtist + " – " + currentTitle);
            break;
        }
        case "unsynced":
            displayText = currentArtist + " – " + currentTitle;
            break;
        case "none":
        case "error":
            displayText = currentArtist + " – " + currentTitle;
            break;
        default:
            displayText = currentArtist + " – " + currentTitle;
        }
    }

    function formatTime(seconds) {
        if (!isFinite(seconds) || seconds < 0) seconds = 0;
        var total = Math.floor(seconds);
        var m = Math.floor(total / 60);
        var s = total % 60;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    // Step 4/6/7 — fetch (with caching) + parse + prepare for sync display.
    function onSongChanged() {
        parsedLyrics = [];
        lyricsState = "idle";

        // Lyrics off -> just show the song name, and skip the API call
        // entirely (per the plan's "don't spam the lyrics API" principle -
        // no point fetching something that won't be shown).
        if (!cfgShowLyrics) {
            updateDisplay();
            return;
        }

        requestToken++;
        var token = requestToken;
        lyricsState = "loading";
        updateDisplay();

        Lyrics.fetchLyrics(currentArtist, currentTitle, currentAlbum, currentLength, function (result) {
            if (token !== requestToken) return; // song changed again meanwhile; drop this result

            if (result.status === "synced") {
                parsedLyrics = Lrc.parseLRC(result.syncedLyrics);
                lyricsState = parsedLyrics.length > 0 ? "synced" : "unsynced";
            } else {
                lyricsState = result.status; // "unsynced" | "none" | "error"
            }
            updateDisplay();
        });
    }

    // ---------------------------------------------------------------
    // Step 2/3 — MPRIS: Spotify's playback state, polled directly.
    // Spotify-only by design (see mpris.js) - no player discovery/
    // selection step needed, just one fixed query per tick.
    // ---------------------------------------------------------------

    function resetToNoPlayer() {
        playbackStatus = "Stopped";
        lyricsState = "idle";
        currentArtUrl = "";
        currentTrackId = "";
        currentCanGoNext = false;
        currentCanGoPrevious = false;
        currentCanPlay = false;
        currentCanPause = false;
        currentCanSeek = false;
        updateDisplay();
    }

    P5Support.DataSource {
        id: mprisPropsSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName); // one-shot: re-arm for the next poll tick

            var props = Mpris.parsePlayerProperties(data["stdout"] || "");
            if (!props.valid) {
                resetToNoPlayer(); // Spotify isn't running
                return;
            }

            playbackStatus = props.playbackStatus;
            currentPosition = props.position;
            currentArtUrl = props.artUrl;
            currentTrackId = props.trackId;
            currentCanGoNext = props.canGoNext;
            currentCanGoPrevious = props.canGoPrevious;
            currentCanPlay = props.canPlay;
            currentCanPause = props.canPause;
            currentCanSeek = props.canSeek;

            var songChanged = props.title !== currentTitle || props.artist !== currentArtist;
            currentArtist = props.artist;
            currentTitle = props.title;
            currentAlbum = props.album;
            currentLength = props.length;

            if (songChanged && props.title !== "") {
                onSongChanged();
            } else {
                updateDisplay();
            }
        }
    }

    // Fire-and-forget playback control calls (PlayPause/Next/Previous/Seek).
    P5Support.DataSource {
        id: mprisControlSource
        engine: "executable"
        connectedSources: []
        onNewData: function (sourceName, data) {
            disconnectSource(sourceName);
            // Refresh promptly so the UI reflects the change without waiting
            // out the rest of the current poll interval.
            mprisPropsSource.connectSource(Mpris.getAllPropertiesCommand());
        }
    }

    function sendPlayPause() {
        mprisControlSource.connectSource(Mpris.playPauseCommand());
    }

    function sendNext() {
        mprisControlSource.connectSource(Mpris.nextCommand());
    }

    function sendPrevious() {
        mprisControlSource.connectSource(Mpris.previousCommand());
    }

    function seekTo(positionSeconds) {
        if (!currentTrackId) return;
        mprisControlSource.connectSource(Mpris.setPositionCommand(currentTrackId, positionSeconds));
        currentPosition = positionSeconds; // optimistic, until the next poll confirms it
    }

    Timer {
        id: pollTimer
        interval: 500 // within the plan's 250-500ms update window
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: mprisPropsSource.connectSource(Mpris.getAllPropertiesCommand())
    }

    // ---------------------------------------------------------------
    // Step 8 — Polish: config-driven sizing/alignment, eliding, smooth
    // transitions and a loading indicator.
    // ---------------------------------------------------------------

    readonly property int cfgFontSize: Plasmoid.configuration.fontSize
    readonly property int cfgWidgetWidth: Plasmoid.configuration.widgetWidth
    readonly property string cfgTextAlignment: Plasmoid.configuration.textAlignment
    readonly property bool cfgShowLyrics: Plasmoid.configuration.showLyrics

    // Toggled via the popup's switch (see fullRepresentation), not just the
    // settings dialog, so react live rather than only reading it lazily.
    onCfgShowLyricsChanged: {
        if (cfgShowLyrics) {
            // Turned back on mid-song: we skipped fetching while it was off
            // (lyricsState stayed "idle"), so fetch now rather than waiting
            // for the next actual song change.
            if (hasActivePlayer() && lyricsState === "idle" && currentTitle !== "") {
                onSongChanged();
            }
        } else {
            requestToken++; // drop any in-flight fetch result
            parsedLyrics = [];
            lyricsState = "idle";
            updateDisplay();
        }
    }

    function alignmentToQt(alignment) {
        switch (alignment) {
        case "center": return Text.AlignHCenter;
        case "right": return Text.AlignRight;
        default: return Text.AlignLeft;
        }
    }

    // -----------------------------------------------------------
    // Compact (panel strip) representation: track-art thumbnail +
    // a marquee viewport that scrolls only when the line is too
    // long to fit, plus a loading spinner overlay.
    // -----------------------------------------------------------
    compactRepresentation: Item {
        id: compactWrapper

        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
        Layout.preferredWidth: root.cfgWidgetWidth
        Layout.maximumWidth: root.cfgWidgetWidth
        Layout.fillHeight: true

        // AppletQuickItem toggles the popup on click for most simple
        // compactRepresentations, but an explicit handler avoids relying on
        // that. Lives outside compactRoot (a RowLayout) since anchoring a
        // layout-managed child is undefined behavior in QtQuick.Layouts.
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            id: compactRoot
            anchors.fill: parent
            spacing: Kirigami.Units.smallSpacing

            Item {
            id: thumbnailContainer
            Layout.preferredWidth: compactRoot.height
            Layout.preferredHeight: compactRoot.height
            Layout.alignment: Qt.AlignVCenter

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Math.min(width, height) * 0.25
                color: "transparent"
                clip: true

                Image {
                    id: thumbnail
                    anchors.fill: parent
                    source: root.currentArtUrl
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
            Kirigami.Icon {
                anchors.fill: parent
                anchors.margins: 1
                source: "audio-x-generic"
                visible: thumbnail.status !== Image.Ready
            }

            PlasmaComponents3.BusyIndicator {
                visible: root.lyricsState === "loading"
                running: visible
                anchors.fill: parent
            }
        }


        Item {
            id: marqueeViewport
            clip: true
            Layout.fillWidth: true
            Layout.fillHeight: true

            readonly property real gap: Kirigami.Units.gridUnit * 2
            readonly property bool overflowing: textA.implicitWidth > width
            property real scrollOffset: 0

            readonly property real staticOffset: {
                if (overflowing || width <= 0) return 0;
                var extra = width - textA.implicitWidth;
                switch (root.cfgTextAlignment) {
                case "center": return extra / 2;
                case "right": return extra;
                default: return 0;
                }
            }

            // Previous line: a static (non-scrolling - it's on its way out)
            // snapshot that only exists to gently dissolve underneath the
            // new one. True overlap with the new line below (rather than a
            // sequential blink to transparent-and-back) is what makes this
            // read as a calm crossfade instead of a flicker.
            //
            // previousX freezes wherever marqueeRow actually was the instant
            // the line changed (mid-scroll or not) - forcing it back to
            // staticOffset here was the bug: an old line caught mid-scroll
            // would visibly snap back to the start right as the fade began,
            // reading as a stagger/glitch instead of a clean transition.
            property string previousText: ""
            property real previousOpacity: 0
            property real previousX: 0

            Text {
                text: marqueeViewport.previousText
                color: Kirigami.Theme.textColor
                font.pointSize: root.cfgFontSize > 0 ? root.cfgFontSize : Kirigami.Theme.defaultFont.pointSize
                x: marqueeViewport.previousX
                y: (marqueeViewport.height - height) / 2
                opacity: marqueeViewport.previousOpacity
                visible: opacity > 0.01
            }

            Row {
                id: marqueeRow
                x: marqueeViewport.overflowing ? marqueeViewport.scrollOffset : marqueeViewport.staticOffset
                y: (marqueeViewport.height - height) / 2
                spacing: marqueeViewport.gap
                opacity: marqueeViewport.newOpacity

                Text {
                    id: textA
                    text: root.displayText
                    color: Kirigami.Theme.textColor
                    font.pointSize: root.cfgFontSize > 0 ? root.cfgFontSize : Kirigami.Theme.defaultFont.pointSize
                }
                Text {
                    text: textA.text
                    color: textA.color
                    font: textA.font
                    visible: marqueeViewport.overflowing
                }
            }

            property real newOpacity: 1

            SequentialAnimation {
                id: marqueeAnim
                loops: Animation.Infinite
                PauseAnimation { duration: 1000 }
                NumberAnimation {
                    target: marqueeViewport
                    property: "scrollOffset"
                    from: 0
                    to: -(textA.implicitWidth + marqueeViewport.gap)
                    duration: Math.max(1, (textA.implicitWidth + marqueeViewport.gap) / 40 * 1000)
                    easing.type: Easing.Linear
                }
            }

            // Both run at once (ParallelAnimation): the old line dissolves
            // while the new one simultaneously appears, so there's never a
            // blank/empty moment - just one line gently giving way to the
            // next. Long duration + InOutSine (no abrupt velocity change
            // anywhere in the curve) is what keeps this feeling calm rather
            // than like a flash.
            ParallelAnimation {
                id: crossfadeAnim
                NumberAnimation { target: marqueeViewport; property: "previousOpacity"; from: 1; to: 0; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { target: marqueeViewport; property: "newOpacity"; from: 0; to: 1; duration: 600; easing.type: Easing.InOutSine }
            }

            property string trackedText: ""

            function resetAndMaybeStart(oldText) {
                previousText = oldText;
                previousX = marqueeRow.x; // capture before touching scrollOffset, which marqueeRow.x is bound to
                previousOpacity = oldText ? 1 : 0;
                newOpacity = 0;
                marqueeAnim.stop();
                scrollOffset = 0;
                crossfadeAnim.restart();
                if (overflowing) marqueeAnim.start();
            }

            onOverflowingChanged: resetAndMaybeStart(trackedText)

            Connections {
                target: root
                function onDisplayTextChanged() {
                    var old = marqueeViewport.trackedText;
                    marqueeViewport.trackedText = root.displayText;
                    marqueeViewport.resetAndMaybeStart(old);
                }
            }

            Component.onCompleted: {
                trackedText = root.displayText;
                resetAndMaybeStart("");
            }
        }
        }
    }

    // -----------------------------------------------------------
    // Expanded ("Now Playing") popup: cover art, title/artist, the
    // current lyric line, a seekbar and transport controls.
    // -----------------------------------------------------------
    fullRepresentation: Item {
        id: fullRoot
        implicitWidth: Kirigami.Units.gridUnit * 20
        implicitHeight: (hasPlayer ? cardColumn.implicitHeight : noPlayerLabel.implicitHeight) + Kirigami.Units.largeSpacing * 2

        readonly property bool hasPlayer: root.hasActivePlayer()

        PlasmaComponents3.Label {
            id: noPlayerLabel
            anchors.centerIn: parent
            visible: !fullRoot.hasPlayer
            text: "No music playing"
            color: Kirigami.Theme.disabledTextColor
        }

        ColumnLayout {
            id: cardColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Kirigami.Units.largeSpacing
            visible: fullRoot.hasPlayer
            spacing: Kirigami.Units.smallSpacing

            Item {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 10
                Layout.preferredHeight: Kirigami.Units.gridUnit * 10
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                    anchors.fill: parent
                    radius: Kirigami.Units.largeSpacing
                    color: Kirigami.Theme.backgroundColor
                    border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                    border.width: 1
                    clip: true

                    Image {
                        id: coverArt
                        anchors.fill: parent
                        source: root.currentArtUrl
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }
                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: parent.width * 0.4
                        height: width
                        source: "audio-x-generic"
                        visible: coverArt.status !== Image.Ready
                    }
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: root.currentTitle
                font.bold: true
                font.pointSize: Kirigami.Theme.defaultFont.pointSize * 1.15
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                text: root.currentArtist
                color: Kirigami.Theme.disabledTextColor
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: "Lyrics"
                    color: Kirigami.Theme.disabledTextColor
                }
                PlasmaComponents3.Switch {
                    checked: root.cfgShowLyrics
                    onToggled: Plasmoid.configuration.showLyrics = checked
                }
            }

            PlasmaComponents3.Label {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                text: root.displayText
                font.italic: true
                color: Kirigami.Theme.highlightColor
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: text.length > 0 && root.cfgShowLyrics
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: root.formatTime(seekSlider.pressed ? seekSlider.value : root.currentPosition)
                    color: Kirigami.Theme.disabledTextColor
                }

                PlasmaComponents3.Slider {
                    id: seekSlider
                    Layout.fillWidth: true
                    from: 0
                    to: Math.max(root.currentLength, 1)
                    enabled: root.currentCanSeek

                    Binding {
                        target: seekSlider
                        property: "value"
                        value: root.currentPosition
                        when: !seekSlider.pressed
                    }

                    onPressedChanged: {
                        if (!pressed) root.seekTo(seekSlider.value);
                    }
                }

                PlasmaComponents3.Label {
                    text: "-" + root.formatTime(Math.max(root.currentLength - (seekSlider.pressed ? seekSlider.value : root.currentPosition), 0))
                    color: Kirigami.Theme.disabledTextColor
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Kirigami.Units.smallSpacing
                spacing: Kirigami.Units.largeSpacing

                PlasmaComponents3.ToolButton {
                    icon.name: "media-skip-backward"
                    enabled: root.currentCanGoPrevious
                    onClicked: root.sendPrevious()
                }
                PlasmaComponents3.ToolButton {
                    icon.name: root.playbackStatus === "Playing" ? "media-playback-pause" : "media-playback-start"
                    enabled: root.playbackStatus === "Playing" ? root.currentCanPause : root.currentCanPlay
                    onClicked: root.sendPlayPause()
                }
                PlasmaComponents3.ToolButton {
                    icon.name: "media-skip-forward"
                    enabled: root.currentCanGoNext
                    onClicked: root.sendNext()
                }
            }
        }
    }
}
