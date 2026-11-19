# Замена LibKWorkspace (plasma-workspace) для powerdevil: только класс
# SessionManagement — сон и гибернация через logind, выход и выключение
# через org.sedmio.SessionManager / org.kde.LogoutPrompt (sedmio-session-manager),
# блокировка через org.freedesktop.ScreenSaver (KWin). Цель называется
# PW::KWorkspace, как в LibKWorkspace, — остальной CMake powerdevil не
# меняется.
add_library(sedmio_kworkspace STATIC sessionmanagement.cpp sessionmanagement.h)
set_target_properties(sedmio_kworkspace PROPERTIES POSITION_INDEPENDENT_CODE ON AUTOMOC ON)
target_include_directories(sedmio_kworkspace PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sedmio_kworkspace PUBLIC Qt::Core Qt::DBus)
add_library(PW::KWorkspace ALIAS sedmio_kworkspace)
