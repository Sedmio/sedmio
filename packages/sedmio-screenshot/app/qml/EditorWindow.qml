import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import Sedmio.ScreenshotEditor
import Sedmio.Style

// Редактор снимков «Ножниц», как в Windows 11: сверху инструменты (перо,
// маркер, ластик, стрелка, рамка, овал, текст, скрыть, обрезка) и
// действия (отменить, повторить, копировать, сохранить), под ними — цвет и
// толщина выбранного инструмента. Снимок посередине, вписан в окно.
//
// Снимок не меняется: пометки — список объектов (Annotation.qml) поверх
// него, обрезка — какую часть показывать. Сохранение и копирование
// рисуют всё вместе в картинку (grabToImage) в размер снимка. Отменять
// можно всё, включая обрезку и ластик.
ApplicationWindow {
    id: win
    visible: true
    color: Theme.paper
    minimumWidth: 760
    minimumHeight: 460
    title: (dirty ? "● " : "") + Editor.fileName + " — Ножницы"

    readonly property real imageWidth: picture.implicitWidth
    readonly property real imageHeight: picture.implicitHeight
    // На больших снимках линии толще — на экране они те же.
    readonly property real unit: Math.max(1, Math.min(imageWidth, imageHeight) / 1080)

    // ── Состояние ───────────────────────────────────────────────────────
    property string tool: "pen"
    // Каким рисовали до обрезки — к нему возвращаемся.
    property string drawTool: "pen"
    property var items: []
    // Видимая часть снимка, в точках снимка.
    property var crop: ({ x: 0, y: 0, w: 0, h: 0 })
    // Что сохранено: изменилось с тех пор — спросить при закрытии.
    property var savedItems: []
    property var savedCrop: crop
    readonly property bool dirty: items !== savedItems || crop !== savedCrop
    property var past: []
    property var future: []
    // Пометка, которую сейчас рисуют.
    property var drawing: null

    readonly property var colors: ["#E5484D", "#F76B15", "#FFC53D", "#30A46C", "#0090FF", "#1C2024", "#FFFFFF"]
    readonly property var markerColors: ["#FFE629", "#7CE38B", "#FF8DC7", "#70B8FF"]
    property color penColor: colors[0]
    property color markerColor: markerColors[0]
    // Толщина: 0 — тонко, 1 — средне, 2 — толсто.
    property int level: 1

    readonly property bool usesStyle: ["pen", "marker", "arrow", "rect", "ellipse", "text"].includes(tool)

    function strokeWidth(t) {
        const w = t === "marker" ? [10, 18, 30][level] : t === "pen" ? [2, 4, 8][level] : [2, 4, 7][level];
        return w * unit;
    }
    function textSize() { return [22, 32, 48][level] * unit; }
    function colorFor(t) { return t === "marker" ? markerColor : penColor; }

    // ── Отмена ──────────────────────────────────────────────────────────
    function snapshot() { return { items: items, crop: crop }; }
    function remember(state) {
        past = past.concat([state]);
        future = [];
    }
    function change(newItems, newCrop) {
        remember(snapshot());
        items = newItems;
        if (newCrop) crop = newCrop;
    }
    function undo() {
        finishText();
        if (past.length === 0) return;
        future = future.concat([snapshot()]);
        const s = past[past.length - 1];
        past = past.slice(0, -1);
        items = s.items;
        crop = s.crop;
        cropDraft = crop;
    }
    function redo() {
        finishText();
        if (future.length === 0) return;
        past = past.concat([snapshot()]);
        const s = future[future.length - 1];
        future = future.slice(0, -1);
        items = s.items;
        crop = s.crop;
        cropDraft = crop;
    }

    // ── Инструменты ─────────────────────────────────────────────────────
    function setTool(t) {
        finishText();
        if (tool === "crop" && t !== "crop") applyCrop();
        if (t === "crop") {
            cropDraft = crop;
            if (tool !== "crop") drawTool = tool;
        }
        tool = t;
    }

    // Обрезка: пока инструмент выбран, виден весь снимок и рамка.
    property var cropDraft: crop
    readonly property var shown: tool === "crop" ? ({ x: 0, y: 0, w: imageWidth, h: imageHeight }) : crop
    function applyCrop() {
        const d = cropDraft;
        if (d.w < 4 || d.h < 4) return;
        if (d.x !== crop.x || d.y !== crop.y || d.w !== crop.w || d.h !== crop.h)
            change(items, d);
    }
    function cancelCrop() {
        cropDraft = crop;
        tool = drawTool;
    }
    function rectFrom(x1, y1, x2, y2) {
        const cx = v => Math.max(0, Math.min(imageWidth, v));
        const cy = v => Math.max(0, Math.min(imageHeight, v));
        const a = cx(Math.min(x1, x2)), b = cy(Math.min(y1, y2));
        return { x: Math.round(a), y: Math.round(b),
                 w: Math.round(cx(Math.max(x1, x2)) - a), h: Math.round(cy(Math.max(y1, y2)) - b) };
    }

    // Текст: пишут прямо на снимке; Enter — готово, Shift+Enter — новая
    // строка, Esc — отмена. Щелчок мимо или другой инструмент — тоже готово.
    property bool textEditing: false
    property point textPos: Qt.point(0, 0)
    function startText(p) {
        finishText();
        textPos = p;
        textEditor.text = "";
        textEditing = true;
        textEditor.forceActiveFocus();
    }
    function finishText() {
        if (!textEditing) return;
        const text = textEditor.text.replace(/\s+$/, "");
        textEditing = false;
        if (text.trim() !== "") {
            change(items.concat([{
                type: "text", color: penColor, size: textSize(),
                x: textPos.x, y: textPos.y, text: text,
                w: textEditor.contentWidth, h: textEditor.contentHeight
            }]));
        }
        textEditor.text = "";
        keys.forceActiveFocus();
    }
    function cancelText() {
        textEditing = false;
        textEditor.text = "";
        keys.forceActiveFocus();
    }

    // Ластик: стирает пометку целиком, если провести по ней.
    function segmentDistance(p, ax, ay, bx, by) {
        const dx = bx - ax, dy = by - ay;
        const len2 = dx * dx + dy * dy;
        const t = len2 === 0 ? 0 : Math.max(0, Math.min(1, ((p.x - ax) * dx + (p.y - ay) * dy) / len2));
        return Math.hypot(p.x - (ax + t * dx), p.y - (ay + t * dy));
    }
    function hits(a, p, tol) {
        const l = Math.min(a.x1, a.x2), r = Math.max(a.x1, a.x2);
        const t = Math.min(a.y1, a.y2), b = Math.max(a.y1, a.y2);
        switch (a.type) {
        case "pen":
        case "marker": {
            const pts = a.points, near = tol + a.width / 2;
            if (pts.length === 1) return Math.hypot(p.x - pts[0].x, p.y - pts[0].y) <= near;
            for (let i = 1; i < pts.length; i++)
                if (segmentDistance(p, pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y) <= near) return true;
            return false;
        }
        case "arrow":
            return segmentDistance(p, a.x1, a.y1, a.x2, a.y2) <= tol + a.width * 2;
        case "rect": {
            const near = tol + a.width / 2;
            return segmentDistance(p, l, t, r, t) <= near || segmentDistance(p, r, t, r, b) <= near
                || segmentDistance(p, r, b, l, b) <= near || segmentDistance(p, l, b, l, t) <= near;
        }
        case "ellipse": {
            const rx = Math.max(1, (r - l) / 2), ry = Math.max(1, (b - t) / 2);
            const k = Math.hypot((p.x - l - rx) / rx, (p.y - t - ry) / ry);
            return Math.abs(k - 1) * Math.min(rx, ry) <= tol + a.width / 2;
        }
        case "hide":
            return p.x >= l - tol && p.x <= r + tol && p.y >= t - tol && p.y <= b + tol;
        case "text":
            return p.x >= a.x - tol && p.x <= a.x + a.w + tol && p.y >= a.y - tol && p.y <= a.y + a.h + tol;
        }
        return false;
    }
    property var eraseStart: null
    function eraseAt(p) {
        const tol = 6 / stage.fit;
        for (let i = items.length - 1; i >= 0; i--) {
            if (hits(items[i], p, tol)) {
                items = items.slice(0, i).concat(items.slice(i + 1));
                return;
            }
        }
    }

    // ── Готовая картинка ────────────────────────────────────────────────
    property string toast: ""
    Timer { id: toastTimer; interval: 2200; onTriggered: win.toast = "" }
    function say(text) {
        toast = text;
        toastTimer.restart();
    }

    // Всё вместе — картинкой в размер видимой части снимка.
    function render(then) {
        finishText();
        if (tool === "crop") setTool(drawTool);
        Qt.callLater(() => canvas.grabToImage(result => then(result.image),
                                              Qt.size(Math.round(canvas.width), Math.round(canvas.height))));
    }
    function markSaved(state) {
        savedItems = state.items;
        savedCrop = state.crop;
    }
    function save(after) {
        render(image => {
            const state = snapshot();
            if (Editor.save(image)) {
                markSaved(state);
                say("Сохранено");
                if (after) after();
            } else {
                say("Не удалось сохранить");
            }
        });
    }
    function copy() {
        render(image => say(Editor.copy(image) ? "Скопировано в буфер обмена" : "Не удалось скопировать"));
    }

    FileDialog {
        id: saveAsDialog
        title: "Сохранить снимок как"
        fileMode: FileDialog.SaveFile
        currentFolder: "file://" + Editor.folder
        selectedFile: "file://" + Editor.path
        defaultSuffix: "png"
        nameFilters: ["Картинка PNG (*.png)", "Картинка JPEG (*.jpg *.jpeg)"]
        onAccepted: {
            const target = selectedFile.toString();
            win.render(image => {
                const state = win.snapshot();
                if (Editor.save(image, target)) {
                    win.markSaved(state);
                    win.say("Сохранено: " + Editor.fileName);
                } else {
                    win.say("Не удалось сохранить");
                }
            });
        }
    }

    // ── Закрытие ────────────────────────────────────────────────────────
    property bool askClose: false
    property bool closeAnyway: false
    onClosing: close => {
        finishText();
        if (dirty && !closeAnyway) {
            close.accepted = false;
            askClose = true;
        }
    }

    // ── Клавиши ─────────────────────────────────────────────────────────
    Shortcut { sequences: [StandardKey.Undo]; enabled: !win.textEditing; onActivated: win.undo() }
    Shortcut { sequences: [StandardKey.Redo, "Ctrl+Y"]; enabled: !win.textEditing; onActivated: win.redo() }
    Shortcut { sequences: [StandardKey.Copy]; enabled: !win.textEditing; onActivated: win.copy() }
    Shortcut { sequences: [StandardKey.Save]; onActivated: win.save() }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: { win.finishText(); saveAsDialog.open(); } }
    Shortcut { sequences: [StandardKey.Close, StandardKey.Quit]; onActivated: win.close() }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (win.askClose && event.key === Qt.Key_Escape) {
                win.askClose = false;
            } else if (win.tool === "crop" && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                win.setTool(win.drawTool);
            } else if (win.tool === "crop" && event.key === Qt.Key_Escape) {
                win.cancelCrop();
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        crop = { x: 0, y: 0, w: imageWidth, h: imageHeight };
        savedItems = items;
        savedCrop = crop;
        cropDraft = crop;
        // Окно по снимку, но не больше экрана.
        width = Math.round(Math.min(Screen.desktopAvailableWidth * 0.85, Math.max(minimumWidth, imageWidth + 96)));
        height = Math.round(Math.min(Screen.desktopAvailableHeight * 0.85, Math.max(minimumHeight, imageHeight + 100 + 96)));
    }

    // ── Полоса инструментов ─────────────────────────────────────────────
    component Separator: Rectangle {
        width: 1
        height: 20
        color: Theme.line
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    }

    Item {
        id: toolbar
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 56

        WindowDragArea { anchors.fill: parent }

        Row {
            id: tools
            anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 4

            ToolButton { icon: "draw-freehand"; hint: "Перо"; checked: win.tool === "pen"; onClicked: win.setTool("pen") }
            ToolButton { icon: "draw-highlight"; hint: "Маркер"; checked: win.tool === "marker"; onClicked: win.setTool("marker") }
            ToolButton { icon: "draw-eraser"; hint: "Ластик"; checked: win.tool === "eraser"; onClicked: win.setTool("eraser") }
            Separator {}
            ToolButton { icon: "draw-arrow"; hint: "Стрелка"; checked: win.tool === "arrow"; onClicked: win.setTool("arrow") }
            ToolButton { icon: "draw-rectangle"; hint: "Рамка"; checked: win.tool === "rect"; onClicked: win.setTool("rect") }
            ToolButton { icon: "draw-ellipse"; hint: "Овал"; checked: win.tool === "ellipse"; onClicked: win.setTool("ellipse") }
            Separator {}
            ToolButton { icon: "draw-text"; hint: "Текст"; checked: win.tool === "text"; onClicked: win.setTool("text") }
            ToolButton { icon: "view-hidden"; hint: "Скрыть"; checked: win.tool === "hide"; onClicked: win.setTool("hide") }
            ToolButton { icon: "transform-crop"; hint: "Обрезать"; checked: win.tool === "crop"; onClicked: win.tool === "crop" ? win.setTool(win.drawTool) : win.setTool("crop") }
        }

        Row {
            anchors { right: windowControls.visible ? windowControls.left : parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
            spacing: 4

            ToolButton { icon: "edit-undo"; hint: "Отменить (Ctrl+Z)"; enabled_: win.past.length > 0; onClicked: win.undo() }
            ToolButton { icon: "edit-redo"; hint: "Повторить (Ctrl+Y)"; enabled_: win.future.length > 0; onClicked: win.redo() }
            Separator {}
            ToolButton { icon: "edit-copy"; hint: "Копировать (Ctrl+C)"; onClicked: win.copy() }
            ToolButton { icon: "document-save"; hint: "Сохранить (Ctrl+S)"; onClicked: win.save() }
            ToolButton { icon: "document-save-as"; hint: "Сохранить как…"; onClicked: { win.finishText(); saveAsDialog.open(); } }
        }

        WindowControls {
            id: windowControls
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
        }
    }

    // ── Цвет и толщина; подсказка ластика, скрытия, обрезки ────────────
    Item {
        id: optionsBar
        anchors { left: parent.left; right: parent.right; top: toolbar.bottom }
        height: 44

        Row {
            visible: win.usesStyle
            anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 6

            Repeater {
                model: win.tool === "marker" ? win.markerColors : win.colors
                Item {
                    required property string modelData
                    readonly property bool current: Qt.colorEqual(win.colorFor(win.tool), modelData)
                    width: 30
                    height: 30
                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 28
                        radius: 14
                        color: "transparent"
                        border.width: parent.current ? 2 : 0
                        border.color: Theme.green
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 20
                        height: 20
                        radius: 10
                        color: parent.modelData
                        border.width: 1
                        border.color: Theme.line
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            if (win.tool === "marker") win.markerColor = parent.modelData;
                            else win.penColor = parent.modelData;
                            if (win.textEditing) textEditor.forceActiveFocus();
                        }
                    }
                }
            }

            Separator {}

            Repeater {
                model: [
                    { level: 0, dot: 4, hint: "Тонко" },
                    { level: 1, dot: 7, hint: "Средне" },
                    { level: 2, dot: 11, hint: "Толсто" }
                ]
                Rectangle {
                    required property var modelData
                    width: 32
                    height: 30
                    radius: 8
                    color: win.level === modelData.level ? Theme.greenWash : widthArea.containsMouse ? Theme.surface : Qt.alpha(Theme.surface, 0)
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.modelData.dot
                        height: width
                        radius: width / 2
                        color: win.level === parent.modelData.level ? Theme.green : Theme.inkSoft
                    }
                    MouseArea {
                        id: widthArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            win.level = parent.modelData.level;
                            if (win.textEditing) textEditor.forceActiveFocus();
                        }
                    }
                }
            }
        }

        SText {
            visible: !win.usesStyle
            anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
            color: Theme.inkMuted
            text: win.tool === "eraser" ? "Проведите по пометке — она сотрётся целиком."
                : win.tool === "hide" ? "Выделите, что спрятать: пароль, адрес, лицо."
                : win.tool === "crop" ? "Потяните за края рамки или выделите заново. Enter — готово, Esc — отмена."
                : ""
        }

        Row {
            visible: win.tool === "crop"
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            spacing: 8
            SButton {
                text: "Весь снимок"
                onClicked: win.cropDraft = { x: 0, y: 0, w: win.imageWidth, h: win.imageHeight }
            }
            SButton { text: "Отмена"; onClicked: win.cancelCrop() }
            SButton { text: "Готово"; primary: true; onClicked: win.setTool(win.drawTool) }
        }

        // Что вышло: «Сохранено», «Скопировано».
        Rectangle {
            visible: win.toast !== "" && win.tool !== "crop"
            anchors { right: parent.right; rightMargin: 18; verticalCenter: parent.verticalCenter }
            width: toastText.implicitWidth + 24
            height: 30
            radius: 15
            color: Theme.greenWash
            SText {
                id: toastText
                anchors.centerIn: parent
                text: win.toast
                size: 13
                weight: 550
                color: Theme.green
            }
        }
    }

    // ── Снимок ──────────────────────────────────────────────────────────
    Rectangle {
        id: stage
        anchors { left: parent.left; right: parent.right; top: optionsBar.bottom; bottom: parent.bottom }
        color: Theme.paperDeep
        clip: true

        readonly property real fit: win.shown.w > 0 && win.shown.h > 0
            ? Math.min(1, (width - 48) / win.shown.w, (height - 48) / win.shown.h) : 1
        readonly property real viewWidth: win.shown.w * fit
        readonly property real viewHeight: win.shown.h * fit

        Rectangle {
            x: viewport.x - 1
            y: viewport.y - 1
            width: stage.viewWidth + 2
            height: stage.viewHeight + 2
            color: "transparent"
            border.width: 1
            border.color: Theme.line
        }

        Item {
            id: viewport
            x: Math.round((stage.width - stage.viewWidth) / 2)
            y: Math.round((stage.height - stage.viewHeight) / 2)
            width: win.shown.w
            height: win.shown.h
            scale: stage.fit
            transformOrigin: Item.TopLeft

            // Это и сохраняется.
            Item {
                id: canvas
                width: win.shown.w
                height: win.shown.h
                clip: true

                Item {
                    id: content
                    x: -win.shown.x
                    y: -win.shown.y
                    width: win.imageWidth
                    height: win.imageHeight

                    Image {
                        id: picture
                        source: Editor.sourceUrl
                        cache: false
                        smooth: true
                        mipmap: true
                    }

                    Repeater {
                        model: win.items
                        Annotation {
                            required property var modelData
                            a: modelData
                            base: picture
                            width: win.imageWidth
                            height: win.imageHeight
                        }
                    }

                    Annotation {
                        visible: win.drawing !== null
                        a: win.drawing ?? ({ type: "" })
                        base: picture
                        width: win.imageWidth
                        height: win.imageHeight
                    }

                    TextEdit {
                        id: textEditor
                        visible: win.textEditing
                        x: win.textPos.x
                        y: win.textPos.y
                        color: win.penColor
                        font.family: Theme.fontFamily
                        font.pixelSize: win.textSize()
                        font.variableAxes: ({ "wght": 600 })
                        selectionColor: Theme.greenSelect
                        wrapMode: TextEdit.NoWrap
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                win.cancelText();
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                                       && !(event.modifiers & Qt.ShiftModifier)) {
                                win.finishText();
                                event.accepted = true;
                            }
                        }
                        Rectangle {
                            z: -1
                            anchors.fill: parent
                            anchors.margins: -4 / stage.fit
                            radius: 4 / stage.fit
                            color: "transparent"
                            border.width: 1 / stage.fit
                            border.color: Theme.green
                        }
                    }
                }
            }

            // Рамка обрезки: снаружи затемнено, за края и углы тянут.
            Item {
                visible: win.tool === "crop"
                anchors.fill: parent
                readonly property var r: win.cropDraft
                readonly property real px: 1 / stage.fit

                Rectangle { x: 0; y: 0; width: parent.width; height: parent.r.y; color: "#80000000" }
                Rectangle { x: 0; y: parent.r.y + parent.r.h; width: parent.width; height: parent.height - y; color: "#80000000" }
                Rectangle { x: 0; y: parent.r.y; width: parent.r.x; height: parent.r.h; color: "#80000000" }
                Rectangle { x: parent.r.x + parent.r.w; y: parent.r.y; width: parent.width - x; height: parent.r.h; color: "#80000000" }
                Rectangle {
                    x: parent.r.x
                    y: parent.r.y
                    width: parent.r.w
                    height: parent.r.h
                    color: "transparent"
                    border.width: 2 * parent.px
                    border.color: "white"
                }
                Repeater {
                    model: [[0, 0], [1, 0], [0, 1], [1, 1], [0.5, 0], [0.5, 1], [0, 0.5], [1, 0.5]]
                    Rectangle {
                        required property var modelData
                        readonly property real side: 12 * parent.px
                        x: parent.r.x + parent.r.w * modelData[0] - side / 2
                        y: parent.r.y + parent.r.h * modelData[1] - side / 2
                        width: side
                        height: side
                        radius: side / 2
                        color: "white"
                        border.width: parent.px
                        border.color: Theme.green
                    }
                }
            }
        }

        MouseArea {
            id: input
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: win.tool === "text" ? Qt.IBeamCursor
                       : win.tool === "eraser" ? Qt.PointingHandCursor
                       : Qt.CrossCursor

            property var cropDrag: null

            function imagePoint(mouse) {
                const p = content.mapFromItem(stage, mouse.x, mouse.y);
                return Qt.point(p.x, p.y);
            }
            function clampToShown(p) {
                return Qt.point(Math.max(win.shown.x, Math.min(win.shown.x + win.shown.w, p.x)),
                                Math.max(win.shown.y, Math.min(win.shown.y + win.shown.h, p.y)));
            }
            // Shift: квадрат и круг, стрелка — по 45°.
            function constrain(start, p, mouse) {
                if (!(mouse.modifiers & Qt.ShiftModifier)) return p;
                const dx = p.x - start.x, dy = p.y - start.y;
                if (win.tool === "arrow") {
                    const angle = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
                    const len = Math.hypot(dx, dy);
                    return Qt.point(start.x + Math.cos(angle) * len, start.y + Math.sin(angle) * len);
                }
                const side = Math.max(Math.abs(dx), Math.abs(dy));
                return Qt.point(start.x + Math.sign(dx || 1) * side, start.y + Math.sign(dy || 1) * side);
            }

            onPressed: mouse => {
                // Щелчок по тексту, который пишут, — ему (курсор, выделение).
                if (win.textEditing) {
                    const t = textEditor.mapFromItem(stage, mouse.x, mouse.y);
                    if (t.x >= -6 && t.y >= -6 && t.x <= textEditor.width + 6 && t.y <= textEditor.height + 6) {
                        mouse.accepted = false;
                        return;
                    }
                }
                const p = imagePoint(mouse);
                switch (win.tool) {
                case "pen":
                case "marker":
                    win.finishText();
                    win.drawing = { type: win.tool, color: win.colorFor(win.tool), width: win.strokeWidth(win.tool), points: [{ x: p.x, y: p.y }] };
                    break;
                case "arrow":
                case "rect":
                case "ellipse":
                case "hide": {
                    win.finishText();
                    const s = clampToShown(p);
                    win.drawing = { type: win.tool, color: win.colorFor(win.tool), width: win.strokeWidth(win.tool), x1: s.x, y1: s.y, x2: s.x, y2: s.y };
                    break;
                }
                case "text":
                    if (win.textEditing) win.finishText();
                    else win.startText(clampToShown(p));
                    break;
                case "eraser":
                    win.finishText();
                    win.eraseStart = win.snapshot();
                    win.eraseAt(p);
                    break;
                case "crop": {
                    const r = win.cropDraft, tol = 14 / stage.fit;
                    const inY = p.y > r.y - tol && p.y < r.y + r.h + tol;
                    const inX = p.x > r.x - tol && p.x < r.x + r.w + tol;
                    const edges = {
                        l: inY && Math.abs(p.x - r.x) < tol,
                        r: inY && Math.abs(p.x - (r.x + r.w)) < tol,
                        t: inX && Math.abs(p.y - r.y) < tol,
                        b: inX && Math.abs(p.y - (r.y + r.h)) < tol
                    };
                    if (edges.l && edges.r) edges.r = false;
                    if (edges.t && edges.b) edges.b = false;
                    if (edges.l || edges.r || edges.t || edges.b)
                        cropDrag = { mode: "resize", edges: edges, rect: r };
                    // Рамка во весь снимок — двигать некуда: внутри
                    // выделяют заново.
                    else if ((r.w < win.imageWidth || r.h < win.imageHeight)
                             && p.x > r.x && p.x < r.x + r.w && p.y > r.y && p.y < r.y + r.h)
                        cropDrag = { mode: "move", start: p, rect: r };
                    else
                        cropDrag = { mode: "new", start: p };
                    break;
                }
                }
            }

            onPositionChanged: mouse => {
                if (!pressed) return;
                const p = imagePoint(mouse);
                if (win.drawing) {
                    const d = win.drawing;
                    if (d.type === "pen" || d.type === "marker") {
                        const last = d.points[d.points.length - 1];
                        if (Math.hypot(p.x - last.x, p.y - last.y) * stage.fit < 1.5) return;
                        win.drawing = Object.assign({}, d, { points: d.points.concat([{ x: p.x, y: p.y }]) });
                    } else {
                        const q = constrain(Qt.point(d.x1, d.y1), clampToShown(p), mouse);
                        win.drawing = Object.assign({}, d, { x2: q.x, y2: q.y });
                    }
                } else if (win.tool === "eraser") {
                    win.eraseAt(p);
                } else if (win.tool === "crop" && cropDrag) {
                    const c = cropDrag;
                    if (c.mode === "new") {
                        win.cropDraft = win.rectFrom(c.start.x, c.start.y, p.x, p.y);
                    } else if (c.mode === "move") {
                        const r = c.rect;
                        const x = Math.max(0, Math.min(win.imageWidth - r.w, r.x + p.x - c.start.x));
                        const y = Math.max(0, Math.min(win.imageHeight - r.h, r.y + p.y - c.start.y));
                        win.cropDraft = { x: Math.round(x), y: Math.round(y), w: r.w, h: r.h };
                    } else {
                        const r = c.rect;
                        let x1 = r.x, y1 = r.y, x2 = r.x + r.w, y2 = r.y + r.h;
                        if (c.edges.l) x1 = p.x;
                        if (c.edges.r) x2 = p.x;
                        if (c.edges.t) y1 = p.y;
                        if (c.edges.b) y2 = p.y;
                        win.cropDraft = win.rectFrom(x1, y1, x2, y2);
                    }
                }
            }

            onReleased: mouse => {
                if (win.drawing) {
                    const d = win.drawing;
                    win.drawing = null;
                    const small = d.points === undefined
                        && Math.hypot(d.x2 - d.x1, d.y2 - d.y1) * stage.fit < 4;
                    if (!small) win.change(win.items.concat([d]));
                } else if (win.tool === "eraser" && win.eraseStart) {
                    if (win.items !== win.eraseStart.items) win.remember(win.eraseStart);
                    win.eraseStart = null;
                } else if (win.tool === "crop") {
                    // Слишком маленькая рамка — как была.
                    if (win.cropDraft.w < 8 || win.cropDraft.h < 8)
                        win.cropDraft = cropDrag && cropDrag.rect ? cropDrag.rect : win.crop;
                    cropDrag = null;
                }
            }
        }
    }

    // ── «Сохранить изменения?» ──────────────────────────────────────────
    Rectangle {
        visible: win.askClose
        anchors.fill: parent
        color: "#66000000"
        MouseArea { anchors.fill: parent }

        Rectangle {
            anchors.centerIn: parent
            width: 420
            height: dialogColumn.implicitHeight + 48
            radius: 16
            color: Theme.paper
            border.width: 1
            border.color: Theme.line

            Column {
                id: dialogColumn
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
                spacing: 18

                SText {
                    width: parent.width
                    text: "Сохранить изменения в «" + Editor.fileName + "»?"
                    size: 17
                    weight: 650
                    wrapMode: Text.Wrap
                }
                SText {
                    width: parent.width
                    text: "Без сохранения пометки и обрезка пропадут, снимок останется как был."
                    color: Theme.inkMuted
                    wrapMode: Text.Wrap
                }
                Row {
                    anchors.right: parent.right
                    spacing: 8
                    SButton { text: "Отмена"; onClicked: win.askClose = false }
                    SButton {
                        text: "Не сохранять"
                        onClicked: {
                            win.closeAnyway = true;
                            win.close();
                        }
                    }
                    SButton {
                        text: "Сохранить"
                        primary: true
                        onClicked: {
                            win.askClose = false;
                            win.save(() => {
                                win.closeAnyway = true;
                                win.close();
                            });
                        }
                    }
                }
            }
        }
    }
}
