# Цвета чужих программ (схема KDE, через неё и GTK) — из темы Sedmio.
find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(KF6Config 6.0 REQUIRED)

qt_add_executable(sedmio-theme-sync main.cpp)
target_link_libraries(sedmio-theme-sync PRIVATE Qt6::DBus KF6::ConfigCore sedmio-themedata)

install(TARGETS sedmio-theme-sync RUNTIME DESTINATION bin)
install(FILES sedmio-theme-sync.service DESTINATION lib/systemd/user)
