pragma Singleton
import QtQuick
import "file:///usr/share/sedmio/login-ui"

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

    // pam_faillock (см. Faillock.qml): до какого момента вход закрыт.
    property double lockedUntil: 0
    // Разговор с PAM, начатый во время блокировки, обречён: pam_faillock
    // (preauth, required) уже сказал «нет», и даже верный пароль в нём не
    // пройдёт. Сообщения о блокировке приходят перед вопросом о пароле —
    // так и узнаём, что текущий разговор такой. Отказ в нём после конца
    // блокировки — тихо повторяем тот же пароль в новом разговоре.
    property bool lockMessageSeen: false
    property bool conversationLocked: false
    property string lastText
    property string retryText

    function lockNotice() {
        return Faillock.notice(lockedUntil);
    }

    // Сообщение PAM → текст для экрана; про блокировку — запоминаем срок.
    function pamText(text) {
        const locked = Faillock.duration(text);
        if (locked === 0) return text;
        lockedUntil = Math.max(lockedUntil, Date.now() + locked);
        lockMessageSeen = true;
        return lockNotice();
    }

    function submit(text) {
        lastText = text;
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
            if (root.conversationLocked && Date.now() >= root.lockedUntil && root.lastText !== "") {
                root.conversationLocked = false;
                root.retryText = root.lastText;
                root.lastText = "";
                authenticator.startAuthenticating();
                return;
            }
            root.lastText = "";
            root.busy = false;
            root.password = "";
            root.message = Date.now() < root.lockedUntil ? root.lockNotice() : "Неверный пароль";
            root.messageIsError = true;
            root.rejections++;
            authenticator.startAuthenticating();
        }
        function onPromptForSecretChanged() {
            // Новый разговор: был ли он начат под блокировкой.
            root.conversationLocked = root.lockMessageSeen;
            root.lockMessageSeen = false;
            if (root.retryText !== "") {
                const text = root.retryText;
                root.retryText = "";
                // Сигнал приходит раньше, чем kscreenlocker запоминает
                // вопрос, — отвечаем после.
                Qt.callLater(() => authenticator.respond(text));
            }
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
                root.message = root.pamText(authenticator.errorMessage);
                root.messageIsError = true;
            }
        }
        function onInfoMessageChanged() {
            if (authenticator.infoMessage) {
                root.message = root.pamText(authenticator.infoMessage);
                root.messageIsError = Date.now() < root.lockedUntil;
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
