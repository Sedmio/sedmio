# Рамки окон KWin по теме Sedmio: заголовок, кнопки, скругление, тень.
# Нет плагина или он не загрузился — KWin рисует Breeze.
find_package(KDecoration3 6.3 REQUIRED)
find_package(KF6CoreAddons 6.0 REQUIRED)

add_library(org.sedmio.decoration MODULE
    decoration.cpp decoration.h
    button.cpp button.h
    shadow.cpp shadow.h
    sedmio.json
)
set_target_properties(org.sedmio.decoration PROPERTIES PREFIX "")
target_link_libraries(org.sedmio.decoration PRIVATE
    Qt6::Gui
    KDecoration3::KDecoration
    KF6::CoreAddons
    sedmio-themedata
)

install(TARGETS org.sedmio.decoration LIBRARY DESTINATION ${QT6_INSTALL_PLUGINS}/org.kde.kdecoration3)
