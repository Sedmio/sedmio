cmake_minimum_required(VERSION 3.22)
project(sedmio-files VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Widgets Quick QuickControls2)
find_package(KF6CoreAddons 6.10 REQUIRED)
find_package(KF6KIO 6.10 REQUIRED)
find_package(KF6Service 6.10 REQUIRED)
find_package(KF6Solid 6.10 REQUIRED)
find_package(KF6WindowSystem 6.10 REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-files main.cpp images.cpp)

set_source_files_properties(qml/Theme.qml qml/Format.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(sedmio-files
    URI Sedmio.Files
    VERSION 1.0
    SOURCES
        foldermodel.cpp foldermodel.h
        placesmodel.cpp placesmodel.h
        fileops.cpp fileops.h
        app.cpp app.h
        prompts.cpp prompts.h
        properties.cpp properties.h
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
        qml/Format.qml
        qml/SText.qml
        qml/SIcon.qml
        qml/ToolButton.qml
        qml/SButton.qml
        qml/Sidebar.qml
        qml/PathBar.qml
        qml/FolderView.qml
        qml/FolderTab.qml
        qml/FileIcon.qml
        qml/Menu.qml
        qml/ConfirmDialog.qml
        qml/PromptWindow.qml
        qml/PropertiesWindow.qml
        qml/QuickLook.qml
)

target_link_libraries(sedmio-files PRIVATE
    Qt6::DBus
    Qt6::Widgets
    Qt6::Quick
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::KIOCore
    KF6::KIOGui
    KF6::KIOWidgets
    KF6::KIOFileWidgets
    KF6::Service
    KF6::Solid
    KF6::WindowSystem
)

# Уведомление о подключённой флешке (devices.cpp) — отдельная маленькая
# программа без интерфейса: работает весь сеанс, «Файлы» — нет.
qt_add_executable(sedmio-devices devices.cpp)
target_link_libraries(sedmio-devices PRIVATE Qt6::DBus KF6::CoreAddons KF6::Solid)

install(TARGETS sedmio-files sedmio-devices RUNTIME DESTINATION bin)
install(FILES sedmio-devices.service DESTINATION lib/systemd/user)
install(FILES sedmio-files.desktop DESTINATION share/applications)
# Шина запускает нас, когда кто-то просит показать папку или файл.
install(FILES org.sedmio.Files.FileManager1.service DESTINATION share/dbus-1/services)
