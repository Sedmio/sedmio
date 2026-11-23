cmake_minimum_required(VERSION 3.22)
project(sedmio-screenshot VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Widgets Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-capture capture.cpp)
target_link_libraries(sedmio-capture PRIVATE Qt6::DBus Qt6::Gui)

# Редактор снимков: открывает уведомление о снимке («Изменить»).
qt_add_executable(sedmio-screenshot-editor editor.cpp)
qt_add_qml_module(sedmio-screenshot-editor
    URI Sedmio.ScreenshotEditor
    VERSION 1.0
    SOURCES
        editor.h
    QML_FILES
        qml/EditorWindow.qml
        qml/Annotation.qml
        qml/ToolButton.qml
        qml/SText.qml
        qml/SIcon.qml
        qml/SButton.qml
)
target_link_libraries(sedmio-screenshot-editor PRIVATE Qt6::Widgets Qt6::Quick Qt6::QuickControls2)

install(TARGETS sedmio-capture RUNTIME DESTINATION lib/sedmio)
install(TARGETS sedmio-screenshot-editor RUNTIME DESTINATION bin)
install(FILES sedmio-screenshot-editor.desktop DESTINATION share/applications)
