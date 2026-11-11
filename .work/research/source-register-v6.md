---
id: s30
title: "30. Реестр источников: что подтверждено и что нет"
source: architecture-v6-2026-11-11
status: historical-context
last_review: "2026-11-11"
---

[Индекс](../INDEX.md) · [Исходник v6](../archive/architecture-v6-original.md) · [Манифест](../MANIFEST.json)

> Исторический контекст, не отдельное новое решение. См. актуальные ADR и v7.

<a id="s30"></a>
## 30. Реестр источников: что подтверждено и что нет

Здесь указаны проверенные URL, тип доказательства и, где релевантно, дата. **Официальная документация подтверждает поведение API и заявленную поддержку**, но не сравнительную скорость конкретной игры. **Пользовательские кейсы** полезны для поиска узких мест и сценариев проверки; их численные результаты нельзя цитировать как измерения на целевой конфигурации.

| ID | Источник | Тип | Что подтверждает / ограничения |
|---|---|---|---|
| [R01](https://godotengine.org/article/maintenance-release-godot-4-7-2/) | Godot 4.7.2 release, 18.08.2026 | Официальный релиз | Версия стабильного движка |
| [R02](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/) | Godot 4.8 beta 3, 09.11.2026 | Официальный релиз | Новая ветка находится в бета-статусе |
| [R03](https://docs.godotengine.org/en/stable/about/release_policy.html) | Godot releases / release policy | Официальная политика | Stable vs development rules |
| [R04](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) | Godot 4.7 rendering backends | Официальная документация | Compatibility/Forward+ возможности и ограничения |
| [R05](https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html) | Godot CLI documentation | Официальная документация | Headless import/export CLI и режимы |
| [R06](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html) | Godot physics interpolation | Официальная документация | Интерполяция для 2D и ограничения |
| [R07](https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html) | Godot RandomNumberGenerator 4.7 | Официальный API | PCG32 implementation detail, seed API |
| [R08](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html) | Godot MultiMesh | Официальный API | Общий resource и границы culling |
| [R09](https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html) | Godot MultiMeshInstance2D | Официальный API | Инстансинг в 2D, layout |
| [R10](https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html) | Godot 2D batching/performance | Официальная документация | Снижение draw calls, необходимость measurement |
| [R11](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilesets.html) | Godot TileSet isometric | Официальная документация | Y sort origin / tile origin |
| [R12](https://www.reddit.com/r/godot/comments/1wq6zv7/100000_goblins_at_30_fps_in_godot_4_c_no_nodes/) | r/godot, 100 000 goblins report, 25.09.2026 | Пользовательский опыт | SoA/spatial strategy, не независимый benchmark |
| [R13](https://www.reddit.com/r/godot/comments/1x6xktk/how_i_optimized_my_godot_bulletheaven_game_for_up/) | r/godot, bullet-heaven optimization, 15.10.2026 | Пользовательский опыт | Drawcalls/UI/FX могут быть bottleneck |
| [R14](https://www.reddit.com/r/godot/comments/1ssmrmj/from_12fps_to_a_120fps_floor_four_godot_4/) | r/godot, April 2026 optimization retrospective | Пользовательский опыт | Качество profiler-first подхода; условия чужие |
| [R15](https://www.reddit.com/r/godot/comments/1xgqhmz/i_got_700_enemies_running_at_once_in_godot_4/) | r/godot, October 2026 ~700 enemies report | Пользовательский опыт | Counting-sort/grid + multimesh experimental |
| [R16](https://docs.godotengine.org/en/4.7/tutorials/io/saving_games.html) | Godot saving games | Официальная документация | JSON/binary/SceneTree save tradeoffs |
| [R17](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) | Godot importing images | Официальная документация | PNG/alpha/VRAM/mipmaps settings |
| [R18](https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/imagegen/SKILL.md) | OpenAI Codex imagegen SKILL.md | Первичный исходный текст | Встроенный imagegen workflow и ограничения |
| [R19](https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan) | OpenAI help — Codex with ChatGPT plan | Официальная документация | Доступ через подписку и лимиты |
| [R20](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html) | Godot typed GDScript | Официальная документация | Типизация, packed arrays и API |
| [R21](https://github.com/bitwes/Gut) | GUT 9.7.1 | Исходники релиза | Ветка для Godot 4.7 |
| [R22](https://github.com/godot-gdunit-labs/gdUnit4) | gdUnit4 v6.2.3 (01.11.2026) | Исходники релиза | Альтернативный test runner; проверить под 4.7.2 |
| [R23](https://github.com/Scony/godot-gdscript-toolkit/releases) | godot-gdscript-toolkit v4.5.0 | Исходники релиза | Актуальный linter/formatter октябрь 2026 |
| [R24](https://github.com/hi-godot/godot-ai/releases) | hi-godot/godot-ai v4.4.1, 02.11.2026 | Исходники релиза | MCP и editor integration, нужен smoke |
| [R25](https://github.com/hybridindie/godot-mcp/blob/main/README.md) | hybridindie/godot-mcp v2026.10.20.1 | Исходники релиза | Альтернативный MCP |
| [R26](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) | awesome-gamedev-agent-skills | GitHub catalog | Широкий набор, реальные skills надо фильтровать |
| [R27](https://github.com/godotengine/godot-cpp/releases) | godot-cpp v10.0.0 | Исходники релиза | Native C++ optional, api 4.7 |
| [R28](https://github.com/godot-rust/gdext/blob/master/Changelog.md) | godot-rust/gdext v0.5.5 | Исходники релиза | Rust optional, api 4.7 |
| [R29](https://github.com/lukeod/vampiresurvivors-modding) | Vampire Survivors modding | GitHub, community | Доступные структуры моддинга и переменные |
| [R30](https://github.com/Salmacis32/VampireSurvivorsRefCompilationProject) | Vampire Survivors Reference Compilation | GitHub, reconstructed source | Исследовательские классы, не первичный source разработчика |
| [R31](https://github.com/OffTheClockMods/vampiresurvivors-mods) | Vampire Survivors mods | GitHub, community | Примеры конкретных usage/patch hooks |
| [R32](https://github.com/SamboyCoding/Cpp2IL) | Cpp2IL | GitHub, RE tooling | Статический анализ IL2CPP metadata и methods |
| [R33](https://github.com/SoulstoneAddons/Skada) | SoulstoneAddons/Skada | GitHub, community | Телеметрия боевых событий, версия требует проверки |
| [R34](https://docs.godotengine.org/ru/4.x/tutorials/performance/cpu_optimization.html) | Godot CPU profiling | Официальная документация | Принципы оптимизации и метрики |
| [R35](https://gut.readthedocs.io/en/latest/Command-Line.html) | GUT command-line runner | Официальная документация GUT | CLI tests and exit handling |
| [R36](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html) | Godot thread-safe APIs | Официальная документация | Ограничения SceneTree и потоков |
| [R37](https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/what_is_gdextension.html) | Godot GDExtension documentation | Официальная документация | ABI/возможности native extension |
| [R38](https://docs.godotengine.org/en/4.7/engine_details/development/profiling/index.html) | Godot engine profiling | Официальная документация | Instrumentation, profiling |
| [R39](https://www.reddit.com/r/godot/comments/1x5pazz/performance_questions/) | r/godot, performance and pooling thread, 14.10.2026 | Пользовательский опыт | Object pools / collision frequency / browser |

| [R40](https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html) | Godot rendering architecture 4.7 | Официальная документация | Внутренние слои рендера |
| [R41](https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html) | Godot renderer features 4.7 | Официальная документация | Compatibility vs Forward+, ограничения |
| [R42](https://www.reddit.com/r/godot/comments/1upc3g3/lessons_from_4_months_building_a_horde_survivor/) | Godot horde-survivor postmortem, 2026 | Пользовательский опыт | Практика MultiMesh, сортировки и бенчмарков; не независимый тест |
| [R43](https://forum.godotengine.org/t/thousands-of-2d-enemies-in-plain-gdscript-flat-arrays-a-counting-sort-grid-and-multimesh/146378) | Godot flat-arrays/horde discussion, 2026 | Форум, пользовательские измерения | Counting-sort spatial grid и SoA; переносимость не доказана |
| [R44](https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html) | Godot MultiMeshInstance2D | Официальный API | Ограничения 2D-инстансинга |
| [R45](https://github.com/godot-gdunit-labs/gdUnit4/releases) | gdUnit4 6.2.3 releases | GitHub release | Альтернативный test framework, обновление 2026-11-01 |
| [R46](https://github.com/hi-godot/godot-ai/releases) | godot-ai v4.4.1 editor MCP | GitHub release | Интеграция Godot+Codex/Claude и live-editor requirement |
| [R47](https://learn.chatgpt.com/docs/image-generation) | OpenAI image generation in Codex | Официальный продукт | Imagegen в подписочном Codex и лимиты, проверить наличие tool |
| [R48](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html) | Godot typed GDScript | Официальная документация | Типизация, оптимизация и поддержка |
| [R49](https://github.com/lukeod/vampiresurvivors-modding/blob/main/il2cpp-guide.md) | Vampire Survivors IL2CPP modding guide | GitHub community primary code | Metadata, interop stubs, пределы интерпретации |
| [R50](https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html) | Godot gamepad controllers 4.7 | Официальная документация | Gamepad and axis mappings |
| [R51](https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html) | Godot using TileMaps 4.7 | Официальная документация | TileMap and projection workflows |
| [R52](https://docs.godotengine.org/en/4.7/classes/class_multimesh.html) | Godot MultiMesh 4.7 | Официальная документация | Shared material/resource and culling |
| [R53](https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html) | Godot physics interpolation 4.7 | Официальная документация | Fixed update и визуальная интерполяция |
| [R54](https://godotengine.org/article/rendering-cpu-optimizations/) | Godot renderer CPU optimizations, 2026 | Первичный devblog | CPU GPU batching tradeoffs; факты релиза не benchmark нашей игры |
| [R55](https://steamdb.info/patchnotes/16793333/) | Soulstone Survivors 14g performance update 2024 | Первичный patch note via SteamDB | Изменение числа снарядов и performance fixes |
| [R56](https://steamdb.info/patchnotes/23706374/) | Soulstone Survivors Gift of the Veil, 2026-06-12 | Первичный patch note via SteamDB | Изменения механик статусов, мультикаста, рун |
| [R57](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html) | Godot importing images 4.7 | Официальная документация | Импорт alpha, filters, formats |
| [R58](https://www.reddit.com/r/VampireSurvivors/comments/1qcpdrz/vampire_survivors_2025_wrap_up/) | Vampire Survivors community 2026 roadmap thread | Сообщество, пользовательские заявления | UX/saves/roadmap feedback, не подтверждение реализации |
| [R59](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html) | Godot audio buses 4.7 | Официальная документация | Смешивание, управление громкостью и шинами |
| [R60](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html) | Godot GUI navigation 4.7 | Официальная документация | Keyboard and controller focus navigation |
| [R61](https://github.com/Salmacis32/VampireSurvivorsRefCompilationProject) | Vampire Survivors Reference Compilation | Восстановленный community project | Имена/структура классов, не оригинальный game source |
| [R62](https://vampire.survivors.wiki/w/Weapons) | Vampire Survivors weapon mechanics | Community wiki | Параметры оружия, версия требует проверки |
| [R63](https://vampire.survivors.wiki/w/Cooldown) | Vampire Survivors cooldown | Community wiki | Cooldown interactions and caps; не доказательство native math |

**Ссылки и точные адреса:**

[R01]: https://godotengine.org/article/maintenance-release-godot-4-7-2/
[R02]: https://godotengine.org/article/dev-snapshot-godot-4-8-beta-3/
[R03]: https://docs.godotengine.org/en/stable/about/release_policy.html
[R04]: https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
[R05]: https://docs.godotengine.org/en/stable/tutorials/editor/command_line_tutorial.html
[R06]: https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html
[R07]: https://docs.godotengine.org/en/4.7/classes/class_randomnumbergenerator.html
[R08]: https://docs.godotengine.org/en/4.7/classes/class_multimesh.html
[R09]: https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html
[R10]: https://docs.godotengine.org/en/4.7/tutorials/performance/gpu_optimization.html
[R11]: https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilesets.html
[R12]: https://www.reddit.com/r/godot/comments/1wq6zv7/100000_goblins_at_30_fps_in_godot_4_c_no_nodes/
[R13]: https://www.reddit.com/r/godot/comments/1x6xktk/how_i_optimized_my_godot_bulletheaven_game_for_up/
[R14]: https://www.reddit.com/r/godot/comments/1ssmrmj/from_12fps_to_a_120fps_floor_four_godot_4/
[R15]: https://www.reddit.com/r/godot/comments/1xgqhmz/i_got_700_enemies_running_at_once_in_godot_4/
[R16]: https://docs.godotengine.org/en/4.7/tutorials/io/saving_games.html
[R17]: https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html
[R18]: https://github.com/openai/codex/blob/main/codex-rs/skills/src/assets/samples/imagegen/SKILL.md
[R19]: https://help.openai.com/en/articles/11369540-using-codex-with-your-chatgpt-plan
[R20]: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html
[R21]: https://github.com/bitwes/Gut
[R22]: https://github.com/godot-gdunit-labs/gdUnit4
[R23]: https://github.com/Scony/godot-gdscript-toolkit/releases
[R24]: https://github.com/hi-godot/godot-ai/releases
[R25]: https://github.com/hybridindie/godot-mcp/blob/main/README.md
[R26]: https://github.com/gamedev-skills/awesome-gamedev-agent-skills
[R27]: https://github.com/godotengine/godot-cpp/releases
[R28]: https://github.com/godot-rust/gdext/blob/master/Changelog.md
[R29]: https://github.com/lukeod/vampiresurvivors-modding
[R30]: https://github.com/Salmacis32/VampireSurvivorsRefCompilationProject
[R31]: https://github.com/OffTheClockMods/vampiresurvivors-mods
[R32]: https://github.com/SamboyCoding/Cpp2IL
[R33]: https://github.com/SoulstoneAddons/Skada
[R34]: https://docs.godotengine.org/ru/4.x/tutorials/performance/cpu_optimization.html
[R35]: https://gut.readthedocs.io/en/latest/Command-Line.html
[R36]: https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html
[R37]: https://docs.godotengine.org/en/4.7/engine_details/engine_api/gdextension/what_is_gdextension.html
[R38]: https://docs.godotengine.org/en/4.7/engine_details/development/profiling/index.html
[R39]: https://www.reddit.com/r/godot/comments/1x5pazz/performance_questions/

[R40]: https://docs.godotengine.org/en/4.7/engine_details/architecture/internal_rendering_architecture.html
[R41]: https://docs.godotengine.org/en/4.7/tutorials/rendering/renderers.html
[R42]: https://www.reddit.com/r/godot/comments/1upc3g3/lessons_from_4_months_building_a_horde_survivor/
[R43]: https://forum.godotengine.org/t/thousands-of-2d-enemies-in-plain-gdscript-flat-arrays-a-counting-sort-grid-and-multimesh/146378
[R44]: https://docs.godotengine.org/en/4.7/classes/class_multimeshinstance2d.html
[R45]: https://github.com/godot-gdunit-labs/gdUnit4/releases
[R46]: https://github.com/hi-godot/godot-ai/releases
[R47]: https://learn.chatgpt.com/docs/image-generation
[R48]: https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/static_typing.html
[R49]: https://github.com/lukeod/vampiresurvivors-modding/blob/main/il2cpp-guide.md
[R50]: https://docs.godotengine.org/en/4.7/tutorials/inputs/controllers_gamepads_joysticks.html
[R51]: https://docs.godotengine.org/en/4.7/tutorials/2d/using_tilemaps.html
[R52]: https://docs.godotengine.org/en/4.7/classes/class_multimesh.html
[R53]: https://docs.godotengine.org/en/4.7/tutorials/physics/interpolation/2d_and_3d_physics_interpolation.html
[R54]: https://godotengine.org/article/rendering-cpu-optimizations/
[R55]: https://steamdb.info/patchnotes/16793333/
[R56]: https://steamdb.info/patchnotes/23706374/
[R57]: https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html
[R58]: https://www.reddit.com/r/VampireSurvivors/comments/1qcpdrz/vampire_survivors_2025_wrap_up/
[R59]: https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html
[R60]: https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html
[R61]: https://github.com/Salmacis32/VampireSurvivorsRefCompilationProject
[R62]: https://vampire.survivors.wiki/w/Weapons
[R63]: https://vampire.survivors.wiki/w/Cooldown
