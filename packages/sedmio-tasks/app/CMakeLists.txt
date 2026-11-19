cmake_minimum_required(VERSION 3.22)
project(sedmio-tasks VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Quick QuickControls2)
# Имя и значок программы по её группе systemd — из .desktop.
find_package(KF6Service 6.10 REQUIRED)
# «Запустить новую задачу»: разбор команды (KShell).
find_package(KF6CoreAddons 6.10 REQUIRED)
# Поднять уже открытое окно (токен активации Wayland).
find_package(KF6WindowSystem 6.10 REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-tasks main.cpp)

qt_add_qml_module(sedmio-tasks
    URI Sedmio.Tasks
    VERSION 1.0
    SOURCES
        tasks.cpp tasks.h
        keyedmodel.cpp keyedmodel.h
        launcher.cpp launcher.h
    QML_FILES
        qml/TasksWindow.qml
        qml/SText.qml
        qml/SIcon.qml
        qml/SButton.qml
        qml/Card.qml
        qml/SField.qml
)

target_link_libraries(sedmio-tasks PRIVATE
    Qt6::DBus
    Qt6::Quick
    Qt6::QuickControls2
    KF6::Service
    KF6::CoreAddons
    KF6::WindowSystem
)

install(TARGETS sedmio-tasks RUNTIME DESTINATION bin)
install(FILES sedmio-tasks.desktop DESTINATION share/applications)
