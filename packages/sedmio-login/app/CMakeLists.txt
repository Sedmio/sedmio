cmake_minimum_required(VERSION 3.22)
project(sedmio-login VERSION 0.1.0 LANGUAGES CXX)

# Модуль QML Sedmio.Login для экранов входа (Quickshell) и блокировки
# (kscreenlocker): Caps Lock, раскладка, сон — вместо модулей
# plasma-workspace (keyboardindicator, keyboardlayout, sessions).

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Qml)
find_package(KF6GuiAddons REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_qml_module(sedmiologin
    URI Sedmio.Login
    VERSION 1.0
    PLUGIN_TARGET sedmiologin
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Sedmio/Login
    SOURCES
        keystate.cpp keystate.h
        keyboardlayout.cpp keyboardlayout.h
        power.cpp power.h
)

target_link_libraries(sedmiologin PRIVATE Qt6::DBus Qt6::Gui Qt6::Qml KF6::GuiAddons)

set(QML_DIR lib/qt6/qml/Sedmio/Login)
install(TARGETS sedmiologin LIBRARY DESTINATION ${QML_DIR})
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/Sedmio/Login/qmldir
    ${CMAKE_CURRENT_BINARY_DIR}/Sedmio/Login/sedmiologin.qmltypes
    DESTINATION ${QML_DIR})
