return {
    name = "player.radial",
    single = true,
    targets = {
        radial = { class = '/Game/_Dawnwalker/UI/_Unified/HUD/CombatFocus/WBP_Combat_Focus_QuickslotBindingsRadial.WBP_Combat_Focus_QuickslotBindingsRadial_C', attach = false },
        radial_left = { from = 'radial', member = 'Left.Button' },
        radial_top = { from = 'radial', member = 'Top.Button' },
        radial_right = { from = 'radial', member = 'Right.Button' },
        radial_bottom = { from = 'radial', member = 'Bottom.Button' },
    },
}
