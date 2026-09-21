# Changelog

## Unreleased

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
