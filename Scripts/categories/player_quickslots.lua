--    QuickslotsSwitcher
--    ├─ WBP_HUD_Quickslots
--    │  └─ SizeBox → Overlay
--    │     ├─ cross
--    │     ├─ Left, Top, Right, Bottom buttons
--    │     └─ WBP_HUD_Quickslots_Bindings
--    └─ WBP_AA_Quickslots
--       └─ SizeBox → Overlay
--          ├─ Darken, Glow
--          └─ cross, Left, Top, Right, Bottom buttons,
--             WBP_AA_Quickslots_Bindings


local category = {
    name = "player.quickslots",
    single = true,
    targets = {
        switcher = { object = "WidgetSwitcher /Game/_Dawnwalker/UI/_Unified/HUD/WBP_GameHUD.WBP_GameHUD_C:WidgetTree.QuickslotsSwitcher", required = true,
            properties = {'activeIndex'} },
        abilities = { from = 'switcher', class = 'WBP_AA_Quickslots_C',
            properties = {'parent','order','slot','position','size'} },
        consumables = { from = 'switcher', class = 'WBP_HUD_Quickslots_C',
            properties = {'parent','order','slot','position','size'} },

        ability_box = { from = 'abilities', member = 'WidgetTree.RootWidget' },
        consumable_box = { from = 'consumables', member = 'WidgetTree.RootWidget' },
        ability_panel = { from = 'ability_box', class = 'Overlay' },
        consumable_panel = { from = 'consumable_box', class = 'Overlay' },

        ability_button_left = { from = 'abilities', member = 'Left' },
        ability_button_top = { from = 'abilities', member = 'Top' },
        ability_button_right = { from = 'abilities', member = 'Right' },
        ability_button_bottom = { from = 'abilities', member = 'Bottom' },
        consumable_button_left = { from = 'consumables', member = 'Left' },
        consumable_button_top = { from = 'consumables', member = 'Top' },
        consumable_button_right = { from = 'consumables', member = 'Right' },
        consumable_button_bottom = { from = 'consumables', member = 'Bottom' },

        ability_left = { from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Left' },
        ability_top = { from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Top' },
        ability_right = { from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Right' },
        ability_bottom = { from = 'abilities', member = 'WBP_AA_Quickslots_Bindings.Bottom' },
        consumable_left = { from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Left' },
        consumable_top = { from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Top' },
        consumable_right = { from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Right' },
        consumable_bottom = { from = 'consumables', member = 'WBP_HUD_Quickslots_Bindings.Bottom' },
    },

}

return category
