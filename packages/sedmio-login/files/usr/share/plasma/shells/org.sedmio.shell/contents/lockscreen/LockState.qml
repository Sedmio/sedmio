pragma Singleton
import QtQuick

// Разблокировка — одна на все экраны: kscreenlocker_greet открывает по
// окну на монитор, но движок QML у них общий, и этот объект тоже.
// Пароль, сообщение и ожидание видны на всех мониторах одинаково.
//
// authenticator — PAM от kscreenlocker (свойство корневого контекста).
// Он сам ведёт разговор с PAM: startAuthenticating() начинает его
// (повторный вызов ничего не ломает), respond() отвечает на вопрос
// о пароле, итог — succeeded() или failed().
QtObject {
    id: root

    property string password
    property string message
    property bool messageIsError: false
    property bool busy: false
    // Растёт с каждым неверным паролем — экраны встряхивают поле.
    property int rejections: 0

    // После неверного пароля PAM держит паузу; что ввели за это время —
    // отправим, когда она кончится.
    property string pending

    function submit(text) {
        busy = true;
        message = "";
        messageIsError = false;
        if (authenticator.inPasswordDelay) pending = text;
        else authenticator.respond(text);
    }

    function edited() {
        if (messageIsError) message = "";
        messageIsError = false;
    }

    property Connections pam: Connections {
        target: authenticator

        function onFailed(kind) {
            if (kind !== 0) return; // отпечаток и т. п. — не наш пароль
            root.busy = false;
            root.password = "";
            root.message = "Неверный пароль";
            root.messageIsError = true;
            root.rejections++;
            authenticator.startAuthenticating();
        }
        function onSucceeded() {
            authenticator.stopAuthenticating();
            Qt.quit();
        }
        function onInPasswordDelayChanged() {
            if (!authenticator.inPasswordDelay && root.pending !== "") {
                authenticator.respond(root.pending);
                root.pending = "";
            }
        }
        function onErrorMessageChanged() {
            if (authenticator.errorMessage) {
                root.message = authenticator.errorMessage;
                root.messageIsError = true;
            }
        }
        function onInfoMessageChanged() {
            if (authenticator.infoMessage) {
                root.message = authenticator.infoMessage;
                root.messageIsError = false;
            }
        }
    }

    // Держим разговор с PAM открытым, пока экран заблокирован.
    property Timer heartbeat: Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: !authenticator.unlocked
        onTriggered: authenticator.startAuthenticating()
    }
}
