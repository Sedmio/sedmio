// Экран входа Sedmio. greetd запускает его от пользователя greeter
// (usr/lib/sedmio/greeter/start: свой KWin на весь экран, внутри —
// quickshell --path /usr/share/sedmio/greeter). Пароль проверяет greetd
// через PAM, он же потом запускает сеанс Plasma.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Greetd
import "file:///usr/share/sedmio/login-ui"

ShellRoot {
    id: root

    readonly property string stateDir: Quickshell.env("SEDMIO_GREETER_STATE") || "/var/lib/sedmio-greeter"

    // Кто может войти: обычные пользователи из /etc/passwd.
    FileView { id: passwd; path: "/etc/passwd"; blockLoading: true }
    readonly property var users: {
        const list = [];
        for (const line of passwd.text().split("\n")) {
            const f = line.split(":");
            if (f.length < 7) continue;
            const uid = parseInt(f[2]);
            if (uid < 1000 || uid >= 60000 || /(nologin|false)$/.test(f[6])) continue;
            list.push({ name: f[0], realName: f[4].split(",")[0] || f[0] });
        }
        return list;
    }

    // Кто входил последним — его и предлагаем.
    FileView { id: lastUser; path: root.stateDir + "/last-user"; blockLoading: true; printErrors: false }
    property int current: Math.max(0, users.findIndex(u => u.name === lastUser.text().trim()))
    readonly property var user: users[current] ?? { name: "", realName: "" }

    property bool busy: false
    property string message
    property bool messageIsError: false
    property int rejections: 0
    property bool leaving: false
    // Пароль ждёт, пока PAM о нём спросит (он может быть и пустым).
    property string pending
    property bool hasPending: false

    function login(password) {
        busy = true;
        message = "";
        messageIsError = false;
        pending = password;
        hasPending = true;
        Greetd.createSession(user.name); // идущий разговор greetd отменит сам
    }

    function reject(text) {
        busy = false;
        pending = "";
        hasPending = false;
        message = text;
        messageIsError = true;
        rejections++;
    }

    function switchUser(step) {
        if (busy || users.length < 2) return;
        current = (current + step + users.length) % users.length;
        message = "";
        messageIsError = false;
    }

    Connections {
        target: Greetd

        function onAuthMessage(text, error, responseRequired, echoResponse) {
            if (responseRequired) {
                // Второй вопрос (код, отпечаток и т. п.) мы задать не умеем.
                if (!root.hasPending) {
                    Greetd.cancelSession();
                    root.reject(text);
                    return;
                }
                Greetd.respond(root.pending);
                root.pending = "";
                root.hasPending = false;
            } else if (text) {
                root.message = text;
                root.messageIsError = error;
            }
        }
        function onAuthFailure(text) { root.reject("Неверный пароль"); }
        // После отказа greetd присылает ещё ошибку отменённого разговора — её не показываем.
        function onError(text) { if (root.busy) root.reject("Не удалось войти: " + text); }
        function onReadyToLaunch() {
            lastUser.setText(root.user.name);
            root.leaving = true;
            launchTimer.start();
        }
    }

    // Сначала экран гаснет, потом greetd запускает сеанс (и закрывает нас).
    Timer {
        id: launchTimer
        interval: 320
        onTriggered: Greetd.launch(
            ["/usr/lib/plasma-dbus-run-session-if-needed", "/usr/bin/startplasma-wayland"],
            ["XDG_SESSION_TYPE=wayland", "XDG_SESSION_DESKTOP=KDE", "XDG_CURRENT_DESKTOP=KDE", "DESKTOP_SESSION=plasma"])
    }

    Process { id: power }
    function run(command) { power.command = command; power.running = true; }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property bool main: modelData === Quickshell.screens[0]

            screen: modelData
            anchors { left: true; right: true; top: true; bottom: true }
            exclusionMode: ExclusionMode.Ignore
            color: Theme.paper
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "sedmio-greeter"
            WlrLayershell.keyboardFocus: main ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            Backdrop { anchors.fill: parent }

            ClockBlock {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: card.top
                anchors.bottomMargin: Math.max(40, win.height * 0.07)
            }

            LoginCard {
                id: card
                visible: win.main
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: win.height * 0.08

                displayName: root.user.realName
                avatar: root.user.name ? "file:///var/lib/AccountsService/icons/" + root.user.name : ""
                canSwitch: root.users.length > 1
                busy: root.busy
                message: root.users.length === 0 ? "Нет пользователей, которые могут войти" : root.message
                messageIsError: root.messageIsError || root.users.length === 0

                onSubmitted: text => root.login(text)
                onEdited: if (root.messageIsError) { root.message = ""; root.messageIsError = false; }
                onPreviousUser: { root.switchUser(-1); focusInput(); }
                onNextUser: { root.switchUser(1); focusInput(); }

                Connections {
                    target: root
                    function onRejectionsChanged() { card.rejected(); }
                }
                Component.onCompleted: focusInput()
            }

            Row {
                visible: win.main
                anchors { right: parent.right; bottom: parent.bottom; margins: 28 }
                spacing: 12
                LayoutChip {}
                RoundButton { icon: "system-suspend"; label: "Сон"; onClicked: root.run(["systemctl", "suspend"]) }
                RoundButton { icon: "system-reboot"; label: "Перезагрузка"; onClicked: root.run(["systemctl", "reboot"]) }
                RoundButton { icon: "system-shutdown"; label: "Выключение"; onClicked: root.run(["systemctl", "poweroff"]) }
            }

            // Уход в сеанс: экран плавно заливается бумагой.
            Rectangle {
                anchors.fill: parent
                color: Theme.paper
                opacity: root.leaving ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
            }
        }
    }
}
