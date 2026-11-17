"""Предпросмотр страниц установщика Sedmio на Windows/Linux без Calamares.

Запуск окна:
    python preview.py
    python preview.py --page users

Скриншоты всех страниц в папку:
    python preview.py --screenshots out
"""

import argparse
import os
import sys
from pathlib import Path

from PySide6.QtCore import Q_ARG, QEventLoop, QMetaObject, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine, QQmlComponent, QQmlContext, qmlRegisterSingletonInstance
from PySide6.QtQuick import QQuickWindow  # noqa: F401 — чтобы корень окна был QQuickWindow

import mocks

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
BRANDING = ROOT / "packages/sedmio-calamares/files/etc/calamares/branding/sedmio"

# (ключ, название шага как в Calamares, файл страницы)
STEPS = [
    ("welcome", "Добро пожаловать", "welcomeq.qml"),
    ("locale", "Местоположение", "localeq.qml"),
    ("partition", "Разметка", None),
    ("users", "Пользователи", "usersq.qml"),
    ("summary", "Итог", "summaryq.qml"),
    ("install", "Установка", "show.qml"),
    ("finished", "Завершение", "finishedq.qml"),
]
EXEC_INDEX = 5

PARTITION_PLACEHOLDER = """
import QtQuick
import "components"
SPage {
    stage: 3
    PageHeader {
        width: parent.width
        eyebrow: "Разметка диска"
        title: "Здесь будет выбор диска"
        subtitle: "Эта страница в Calamares сделана на виджетах, а не на QML. "
                + "В предпросмотре её нет: оформление задаётся в stylesheet.qss."
    }
}
"""


def wait(ms):
    loop = QEventLoop()
    QTimer.singleShot(ms, loop.quit)
    loop.exec()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--page", choices=[s[0] for s in STEPS], default="welcome")
    parser.add_argument("--screenshots", metavar="DIR", help="сохранить скриншоты всех страниц и выйти")
    parser.add_argument("--fail-storage", action="store_true", help="не хватает места на диске")
    parser.add_argument("--fail-install", action="store_true", help="установка завершилась ошибкой")
    args = parser.parse_args()

    app = QGuiApplication(sys.argv)

    configs = {
        "welcome": mocks.WelcomeConfig(args.fail_storage),
        "locale": mocks.LocaleConfig(),
        "users": mocks.UsersConfig(),
        "finished": mocks.FinishedConfig(args.fail_install),
    }
    configs["summary"] = mocks.SummaryConfig(configs["locale"], configs["users"])

    pages = {}
    progress_timer = QTimer()
    progress_timer.setInterval(50)

    def ready(index):
        key = STEPS[index][0]
        if key == "welcome":
            return configs["welcome"].requirementsModel.satisfiedMandatory
        if key == "users":
            return configs["users"].ready
        return index < EXEC_INDEX

    def on_step(index):
        key = STEPS[index][0]
        if key == "summary":
            configs["summary"].refresh()
        if key == "install":
            vm.set_progress(0.0)
            progress_timer.start()
        page = pages.get(index)
        if page is not None and page.metaObject().indexOfMethod("onActivate()") >= 0:
            QMetaObject.invokeMethod(page, "onActivate")

    def tick():
        value = vm.execProgress + 0.008
        if value >= 1.0:
            progress_timer.stop()
            vm.go(EXEC_INDEX + 1)
        else:
            vm.set_progress(value)

    progress_timer.timeout.connect(tick)

    vm = mocks.ViewManager([s[1] for s in STEPS], EXEC_INDEX, ready, on_step, app.quit)
    configs["users"].changed.connect(vm.refresh)

    stubs = [mocks.BrandingStub(), mocks.GlobalStub(), mocks.NetworkStub()]
    qmlRegisterSingletonInstance(mocks.ViewManager, "io.calamares.ui", 1, 0, "ViewManager", vm)
    qmlRegisterSingletonInstance(mocks.BrandingStub, "io.calamares.ui", 1, 0, "Branding", stubs[0])
    qmlRegisterSingletonInstance(mocks.GlobalStub, "io.calamares.core", 1, 0, "Global", stubs[1])
    qmlRegisterSingletonInstance(mocks.NetworkStub, "io.calamares.core", 1, 0, "Network", stubs[2])

    # Движок создаём только после регистрации заглушек, иначе QML ломается.
    engine = QQmlApplicationEngine()

    engine.rootContext().setContextProperty("brandingDir", QUrl.fromLocalFile(str(BRANDING)).toString())
    engine.load(QUrl.fromLocalFile(str(HERE / "shell.qml")))
    if not engine.rootObjects():
        return 1
    window = engine.rootObjects()[0]

    keep = []
    for index, (key, _, filename) in enumerate(STEPS):
        context = QQmlContext(engine.rootContext())
        if key in configs:
            context.setContextProperty("config", configs[key])
        component = QQmlComponent(engine)
        if filename:
            component.loadUrl(QUrl.fromLocalFile(str(BRANDING / filename)))
        else:
            component.setData(PARTITION_PLACEHOLDER.encode("utf-8"), QUrl.fromLocalFile(str(BRANDING / "_placeholder.qml")))
        page = component.create(context)
        if page is None:
            for error in component.errors():
                print(error.toString(), file=sys.stderr)
            return 1
        keep += [context, component]
        pages[index] = page
        QMetaObject.invokeMethod(window, "attach", Q_ARG("QVariant", page), Q_ARG("QVariant", index))

    start = [s[0] for s in STEPS].index(args.page)
    vm.go(start)
    on_step(start)

    if args.screenshots:
        out = Path(args.screenshots)
        out.mkdir(parents=True, exist_ok=True)
        users = configs["users"]
        for index, (key, _, _) in enumerate(STEPS):
            if key == "install":
                progress_timer.stop()
                vm._index = index
                vm.set_progress(0.42)
                pages[index].setProperty("activatedInCalamares", True)
            else:
                vm.go(index)
                progress_timer.stop()
            if key == "users":
                wait(900)
                window.grabWindow().save(str(out / f"{index + 1}-{key}-empty.png"))
                users.setFullName("Иван Петров")
                users.setUserPassword("secret")
                users.setUserPasswordSecondary("secret")
                pages[index].setProperty("showAdvanced", True)
                wait(100)
                QMetaObject.invokeMethod(pages[index], "scrollToEnd")
            wait(900)
            window.grabWindow().save(str(out / f"{index + 1}-{key}.png"))
            print("сохранено:", key)
        return 0

    return app.exec()


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    # Выходим сразу: иначе Python уничтожает заглушки раньше страниц,
    # и QML сыплет ошибками про пустой config.
    os._exit(code)
