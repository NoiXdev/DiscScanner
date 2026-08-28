## [1.0.0](https://github.com/NoiXdev/DiscScanner/compare/0ebf1653b1ee1857636e4c53084d4e51fbbe52df...v1.0.0) (2026-08-28)

### Features

* add app shell with live scan progress and localization ([db2c049](https://github.com/NoiXdev/DiscScanner/commit/db2c049e3ebdca52d967eda1833d130e209a4318))
* add delete flow with trash and permanent options ([b1b805e](https://github.com/NoiXdev/DiscScanner/commit/b1b805e1723f13a435a4e021d6ffde896d9c7b89))
* add FileNode snapshot model and internal MutableNode tree ([0ebf165](https://github.com/NoiXdev/DiscScanner/commit/0ebf1653b1ee1857636e4c53084d4e51fbbe52df))
* add parallel directory traversal with bottom-up size aggregation ([484a085](https://github.com/NoiXdev/DiscScanner/commit/484a085c46875fcfea2fe16e7f63f625bf35b623))
* add sortable tree list view with live updates and size bars ([ba31e43](https://github.com/NoiXdev/DiscScanner/commit/ba31e43c08c6172f9e1e7558a4d488a085a10f57))
* add squarified treemap layout algorithm ([3bb6c9e](https://github.com/NoiXdev/DiscScanner/commit/3bb6c9e751766dd87cbde3210b76aad05c440e34))
* add startup Full Disk Access check with settings shortcut ([e282b41](https://github.com/NoiXdev/DiscScanner/commit/e282b415843da717b94ad0f4fc49b7a2e83e0e80))
* add startup shortcuts, scan timing estimate, app icon, and live-snapshot depth cap ([1040993](https://github.com/NoiXdev/DiscScanner/commit/10409931d2370875dac3acfad3a11d5da1d65d72))
* add trash and permanent deletion with per-item error reporting ([6cff18b](https://github.com/NoiXdev/DiscScanner/commit/6cff18bce4aa82d1fee502b5b1e1b04236c1eeef))
* add tree pruning with size re-aggregation after deletion ([109c8ca](https://github.com/NoiXdev/DiscScanner/commit/109c8ca89f17783deb0ac79ccf7ffafd12b882de))
* add treemap view with zoom and breadcrumb navigation ([679be49](https://github.com/NoiXdev/DiscScanner/commit/679be491afd3d89431348d1c6fd68d72248556b1))
* stream batched scan snapshots and progress via AsyncStream ([d6c523c](https://github.com/NoiXdev/DiscScanner/commit/d6c523c134147189ec0ce93ad5314a7516edfed1))

### Bug Fixes

* cache file icons by extension to avoid per-row icon lookups ([28507b2](https://github.com/NoiXdev/DiscScanner/commit/28507b2494ca22babf334aeadc0307cce9842e6e))
* correct breadcrumb paths for root scans and cache treemap tile lookups ([5c8554e](https://github.com/NoiXdev/DiscScanner/commit/5c8554e9173fa3f5df59d47fb8329562e4ad6bc5))
* guard scan generations, generic folder icons, and review polish ([768db1e](https://github.com/NoiXdev/DiscScanner/commit/768db1ef768ea921cae5f996bb372cf2d036becb))
* handle filesystem root in pruneRedundant descendant check ([8fe1cac](https://github.com/NoiXdev/DiscScanner/commit/8fe1cac93806c2b8dbd52caa3c3c64ff609d09ba))
* handle filesystem root path in FileNode.find ([d5718b1](https://github.com/NoiXdev/DiscScanner/commit/d5718b1fabfee634a808cdd01dc59c86092c8707))
* key icon cache by isDirectory to avoid cache poisoning ([08b3911](https://github.com/NoiXdev/DiscScanner/commit/08b3911e6932ce618da16c0845ea78ccef2b0a34))
* repair German strings file quote corruption ([fa48ea4](https://github.com/NoiXdev/DiscScanner/commit/fa48ea435af2c78cab7fc6c129a087d42d250826))
* restore live-snapshot test integrity in scan stream ([b79103f](https://github.com/NoiXdev/DiscScanner/commit/b79103f05733ea9c72e190f30dfb71b413eb21d1))
