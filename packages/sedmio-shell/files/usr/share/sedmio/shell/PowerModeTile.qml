import QtQuick
import Quickshell.Services.UPower

// Плитка «Режим питания»: клик — следующий режим (экономия →
// сбалансированный → производительность). В Пуске и в разделе батареи.
QuickTile {
    id: root
    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]
    readonly property var profile: PowerProfiles.profile

    icon: profile === PowerProfile.PowerSaver ? "battery-profile-powersave"
        : profile === PowerProfile.Performance ? "battery-profile-performance"
        : "battery-profile-balanced"
    title: "Режим питания"
    subtitle: profile === PowerProfile.PowerSaver ? "Экономия энергии"
        : profile === PowerProfile.Performance ? "Производительность" : "Сбалансированный"
    active: profile !== PowerProfile.Balanced
    onToggled: {
        const i = profiles.indexOf(PowerProfiles.profile);
        PowerProfiles.profile = profiles[(i + 1) % profiles.length];
    }
}
