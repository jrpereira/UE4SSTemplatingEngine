# Changelog

## Unreleased

- Validate category event interests and route declared events through service-first template callbacks.
- Retry pending attachments when a declared category event arrives.
- Validate committed provider settings before template attachment.
- Name template declarations `settings` and deliver committed values as `configuration.settings` while preserving persisted setting identities.
- Add `te.widget` helpers for safe UE property reads, transforms, opacity, and slot snapshots.
- Resolve category targets in TE and pass them to `attach`, removing target discovery from template services.
- Add `npc.attacks` and declarative native-class creation events owned and scheduled by TE.
- Split template selection into an aggregate `Templates` DMM page and generated category pages that own each template's detailed controls.
- Add the DMM startup extension that injects generated category pages while keeping their settings rooted in TE's shared `config.ini`.
- Add the `menu.controls` and `menu.templates` template categories.
- Add the `other` category family with the `other.unknown` fallback category.
- Store registered subcategories as `_categories[module][category]`, initialized with `visible`, `count`, and `templates`.
- Add `setCategory(category, values)` for category metadata such as `visible`.
- Track each successfully loaded template in its category's `count` and `templates` fields.

## 0.0.17

- Register individual template files or folders containing Lua templates.
- Validate one template object or nested dense arrays of templates.
- Generate persistent Adaptive Mod Menu controls for `player.quickslots` templates.
- Provide protected, service-first `attach`, `render`, and `detach` lifecycle calls.
- Preserve historical Quickslots setting identifiers across the category rename.
- Recognize the built-in `player.*` and `npc.*` category families.
- Include the menu-test host used while native discovery, input, and visual cutover remain under development.
