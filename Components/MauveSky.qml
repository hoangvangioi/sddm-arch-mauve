// Animated "Mauve" sky — port of the Dreamy Galaxy canvas sketch to QML Canvas.
//
// Ported for the SDDM greeter, where CPU/GPU budget is far tighter than a browser:
//  * 30 fps by default (config.BackgroundFps, code fallback the same), not 60.
//  * No ctx.shadowBlur: QML's setter ignores 0 (qquickcontext2d.cpp:2177 only
//    accepts blur > 0), so `shadowBlur = 0` would never clear it and every hill
//    would get a glow outline. The glowing accent stars use one radial gradient
//    each instead, which is also much cheaper than a blurred fill.
//  * Fewer stars (config.StarCount) and a coarser hill step at high resolutions.
//  * Movement rates/amplitudes are tuned so the motion is visible at a glance
//    (see AnimationIntensity): cycles of a few seconds, not tens of seconds.
//  * One static frame when config.PauseBackground is "true".
//  * getContext() is only legal once Canvas.available is true, i.e. after the
//    scene graph has been initialised (qquickcanvasitem.cpp:828). It is never
//    called from Component.onCompleted: seeding happens there, painting starts
//    from onAvailableChanged -> requestPaint() -> onPaint.
//
// New file for this theme; the canvas is derived from the Dreamy Galaxy sketch.
// Distributed under the GPLv3+ License https://www.gnu.org/licenses/gpl-3.0.html
// Copyright (C) 2022-2025 Keyitdev (sddm-astronaut-theme, GPL-3.0-or-later)
// Modifications © 2026 hoangvangioi

import QtQuick 2.15
import QtQuick.Window 2.15

Canvas {
    id: sky

    anchors.fill: parent

    renderStrategy: Canvas.Threaded
    renderTarget: Canvas.Image
    antialiasing: true

    property color skyTop:        "#17152f"
    property color skyUpper:      "#39365e"
    property color skyMid:        "#8b729b"
    property color skyHorizon:    "#d4a6bd"
    property color skyBottom:     "#252d50"

    property color glowPink:      "#efb5d8"
    property color glowViolet:    "#8c6fbe"
    property color glowBlue:      "#709dd2"

    property color starColor:     "#fff5ff"
    property color starAccent:    "#ffd9ed"

    property color hill1:         "#45446d"
    property color hill2:         "#34395f"
    property color hill3:         "#242d4e"
    property color hill4:         "#171f3c"

    property int   starCount: config.StarCount === "" ? 120 : config.StarCount
    property int   fps:       config.BackgroundFps === "" ? 30 : config.BackgroundFps
    property bool  animated:  config.PauseBackground != "true"

    // How lively the animation is: "subtle", "normal" (default) or "strong".
    // Every amplitude and angular rate below is a multiple of these, so the
    // three presets differ only by which set of numbers is chosen.
    readonly property string intensity: {
        var v = String(config.AnimationIntensity || "").toLowerCase()
        return v === "subtle" || v === "strong" ? v : "normal"
    }

    // Star twinkle: cycle 2.5-7.5s at speed 0.2-0.7 (was 10-31s: too slow to see).
    readonly property real starRate:      intensity === "subtle" ? 0.0020
                                        : intensity === "strong" ? 0.0070 : 0.0040
    // Shallow (0.22) to bright (1.00).
    readonly property real starAlphaMin:  intensity === "subtle" ? 0.30
                                        : intensity === "strong" ? 0.12 : 0.18
    readonly property real starAlphaSpan: intensity === "subtle" ? 0.45
                                        : intensity === "strong" ? 0.88 : 0.82
    // Slight size breathing so stars read as near/far rather than flat dots.
    readonly property real starSizeBreath: intensity === "subtle" ? 0.15
                                         : intensity === "strong" ? 0.55 : 0.50

    // Accent-star halo pulse.
    readonly property real accentRate:    intensity === "subtle" ? 0.0012
                                        : intensity === "strong" ? 0.0032 : 0.0022
    readonly property real accentDepth:   intensity === "subtle" ? 0.20
                                        : intensity === "strong" ? 0.45 : 0.40
    readonly property real accentHalo:    intensity === "subtle" ? 1.0
                                        : intensity === "strong" ? 1.6 : 1.4

    // Horizon glow drift: 45px over a ~10s cycle.
    readonly property real glowRate:      intensity === "subtle" ? 0.0003
                                        : intensity === "strong" ? 0.0009 : 0.0006
    readonly property real glowDrift:     intensity === "subtle" ? 20
                                        : intensity === "strong" ? 60 : 45

    // Hill layers drift laterally in the sin() phase, ~12s cycle.
    readonly property real hillRate:      intensity === "subtle" ? 0.00025
                                        : intensity === "strong" ? 0.0008 : 0.0005

    // Cap device pixel ratio like the original sketch did (min(dpr, 2)).
    readonly property real dpr: Math.min(Screen.devicePixelRatio || 1, 2)

    property var stars: []
    property real elapsed: 0

    // Canvas cannot hand out a drawing context before the scene graph exists,
    // so nothing here may paint in Component.onCompleted. Seeding happens on
    // completion/size change; drawing happens on availableChanged and onPaint.
    property bool ready: false
    property bool needsFullRepaint: true

    onWidthChanged:  reinitialise()
    onHeightChanged: reinitialise()
    Component.onCompleted: reinitialise()

    onAvailableChanged: {
        if (!available)
            return
        ready = true
        needsFullRepaint = true
        requestPaint()
    }

    // Runs on every repaint: resizes, expose events, the greeter re-showing
    // the screen. Drawing only here keeps Threaded rendering consistent.
    onPaint: {
        if (ready)
            frame(elapsed)
    }

    // Threaded rendering skips redraws while invisible, so force a full frame
    // when the item comes back.
    onVisibleChanged: {
        if (visible && ready) {
            needsFullRepaint = true
            requestPaint()
        }
    }

    function reinitialise() {
        var w = width
        var h = height
        if (w <= 0 || h <= 0)
            return

        canvasSize = Qt.size(Math.round(w * dpr), Math.round(h * dpr))

        stars = []
        for (var i = 0; i < starCount; ++i) {
            stars.push({
                x: Math.random() * w,
                y: Math.random() * h * 0.85,
                r: Math.random() * 1.1 + 0.25,
                phase: Math.random() * Math.PI * 2,
                speed: Math.random() * 0.5 + 0.2
            })
        }

        // Do NOT paint here: Component.onCompleted and size changes both run
        // before/independently of Canvas.available. Just ask for a repaint.
        needsFullRepaint = true
        if (ready)
            requestPaint()
    }

    Timer {
        id: ticker
        interval: sky.fps > 0 ? Math.round(1000 / sky.fps) : 50
        repeat: true
        running: sky.animated && sky.visible
        onTriggered: {
            sky.elapsed += interval
            // With Canvas.Threaded the texture is rebuilt from the command
            // buffer on repaint; drawing straight from the timer would not be
            // picked up. This also caps the redraw rate at `fps`.
            sky.requestPaint()
        }
    }

    function frame(t) {
        var ctx = getContext("2d")
        if (!ctx)
            return

        var w = width
        var h = height

        ctx.setTransform(1, 0, 0, 1, 0, 0)
        if (needsFullRepaint) {
            // A partial paint (expose event) leaves the rest of the texture
            // stale, so clear the whole surface when taking that path.
            ctx.clearRect(0, 0, w * dpr, h * dpr)
            needsFullRepaint = false
        }
        ctx.setTransform(dpr, 0, 0, dpr, 0, 0)

        drawSky(ctx, t, w, h)
        drawStars(ctx, t)
        drawSpecialStars(ctx, t, w, h)
        drawLandscape(ctx, t, w, h)
    }

    // Soft light — radial gradients are rebuilt each frame so the coordinates
    // follow the drifting centre without depending on transform semantics.
    function glow(ctx, x, y, radius, cssColor, alpha) {
        var g = ctx.createRadialGradient(x, y, 0, x, y, radius)
        g.addColorStop(0, cssColor.replace("ALPHA", alpha))
        g.addColorStop(0.45, cssColor.replace("ALPHA", alpha * 0.35))
        g.addColorStop(1, cssColor.replace("ALPHA", 0))

        ctx.fillStyle = g
        ctx.fillRect(x - radius, y - radius, radius * 2, radius * 2)
    }

    function drawSky(ctx, t, w, h) {
        var bg = ctx.createLinearGradient(0, 0, 0, h)
        bg.addColorStop(0, skyTop)
        bg.addColorStop(0.35, skyUpper)
        bg.addColorStop(0.65, skyMid)
        bg.addColorStop(0.82, skyHorizon)
        bg.addColorStop(1, skyBottom)

        ctx.fillStyle = bg
        ctx.fillRect(0, 0, w, h)

        var move = Math.sin(t * glowRate) * glowDrift

        glow(ctx, w * 0.5 + move, h * 0.67, w * 0.45, "rgba(239,181,216,ALPHA)", 0.32)
        glow(ctx, w * 0.22, h * 0.32, w * 0.30, "rgba(140,111,190,ALPHA)", 0.12)
        glow(ctx, w * 0.80, h * 0.28, w * 0.30, "rgba(112,157,210,ALPHA)", 0.12)
    }

    function drawStars(ctx, t) {
        var c = starColor
        for (var i = 0; i < stars.length; ++i) {
            var s = stars[i]
            var osc = Math.sin(t * starRate * s.speed + s.phase)
            ctx.globalAlpha = starAlphaMin + (osc + 1) * starAlphaSpan * 0.5
            ctx.beginPath()
            ctx.arc(s.x, s.y, s.r * (1 + starSizeBreath * osc), 0, Math.PI * 2)
            ctx.fillStyle = c
            ctx.fill()
        }
        ctx.globalAlpha = 1
    }

    // The three accent stars. The browser version used shadowBlur; here the halo
    // is three stacked circles, which renders the same at a fraction of the cost.
    function drawSpecialStars(ctx, t, w, h) {
        var points = [[0.38, 0.34], [0.52, 0.44], [0.68, 0.37]]

        for (var i = 0; i < points.length; ++i) {
            var x = w * points[i][0]
            var y = h * points[i][1]
            var pulse = 1 - accentDepth * 0.5 + Math.sin(t * accentRate + i) * accentDepth
            var r = 1.5 * pulse

            // Smooth halo. Stacked solid circles produce visible concentric
            // rings, so use a radial gradient instead - it is what the
            // original shadowBlur produced, and only 3 are drawn per frame.
            var halo = r * 10
            var g = ctx.createRadialGradient(x, y, 0, x, y, halo)
            var a1 = Math.min(1, 0.55 * accentHalo * pulse)
            var a2 = Math.min(1, 0.22 * accentHalo * pulse)
            g.addColorStop(0,    "rgba(255,217,237," + a1.toFixed(3) + ")")
            g.addColorStop(0.18, "rgba(255,217,237," + a2.toFixed(3) + ")")
            g.addColorStop(0.45, "rgba(255,217,237," + (a2 * 0.35).toFixed(3) + ")")
            g.addColorStop(1,    "rgba(255,217,237,0)")

            ctx.fillStyle = g
            ctx.fillRect(x - halo, y - halo, halo * 2, halo * 2)

            // Bright core.
            ctx.fillStyle = starAccent
            ctx.globalAlpha = 1
            ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill()
        }
    }

    function drawHill(ctx, baseY, amplitude, color, offset, w, h) {
        // Coarser sampling on wide screens: 4px steps are wasteful at 1080p.
        var step = Math.max(4, Math.round(w / 480))

        ctx.beginPath()
        ctx.moveTo(0, h)

        for (var x = 0; x <= w; x += step) {
            var y = baseY
                  + Math.sin(x * 0.004 + offset) * amplitude
                  + Math.sin(x * 0.009 + offset * 2) * amplitude * 0.25
            ctx.lineTo(x, y)
        }

        ctx.lineTo(w, h)
        ctx.closePath()
        ctx.fillStyle = color
        ctx.fill()
    }

    function drawLandscape(ctx, t, w, h) {
        var move = Math.sin(t * hillRate)

        drawHill(ctx, h * 0.83, h * 0.045, hill1, move,       w, h)
        drawHill(ctx, h * 0.88, h * 0.035, hill2, move + 1,   w, h)
        drawHill(ctx, h * 0.94, h * 0.025, hill3, move + 2,   w, h)
        drawHill(ctx, h * 1.02, h * 0.015, hill4, move + 3,   w, h)
    }
}
