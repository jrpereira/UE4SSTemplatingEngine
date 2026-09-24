local category = {
    name = "player.quickslots",
    single = true,
    events = { "GroupSelected", "SlotActivated" },

    paths = {
        switcher = "WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher",
    },

    contexts = { "combat", "openworld" },
}

return category
