# 机构销售产品池查询工具

## 项目概述
单文件 Vue 3 应用（CDN 引入，无构建工具），供中欧基金机构销售在客户机构产品池语境下快速查询基金可投性、经理覆盖、路演聚合等。所有代码在 `index.html` 一个文件里（约 6300 行）。

部署：GitHub Pages → https://dunk0713.github.io/fund-pool/

## 架构边界
- **单文件 + CDN**：Vue 3、Tesseract.js、PDF.js 全部 CDN，**禁止**引入 npm/vite/webpack
- **localStorage 存储**：机构、产品、经理别名映射等。**不**迁移到 IndexedDB
- **数据源**：天天基金（pingzhongdata、FundSearch、fundgz）+ OCR 识别图片/PDF
- **目标用户**：机构销售，**不是**零售投资者 — 不做行情/买卖/组合/资讯

## 已实现功能（按 commit 倒序）

### OCR 与导入
- 双 PSM 识别（PSM 4 主 + PSM 6 补漏，PSM 4 顺序优先）
- 预处理：长边 ≥2400px、对比度 1.7×、灰度
- Tesseract 参数：`oem=1`（仅 LSTM）+ `preserve_interword_spaces=0`（中文专用）
- 全文扫描代码（`_extractFundEntries`）：跨行数字粘合 + 7/8 位干扰串智能选窗
- 代码合法性 `isLikelyFundCode`（范围 [000001, 989999]）
- 自动核对（`verifyPreviewProducts`）：拉天天基金 API 用官方名替换 OCR 名
- **核对未完成时禁用「确认导入」按钮**（防 race condition）
- 静默修复历史 OCR 错名（`_silentBackfillProductNames`，选机构时触发）
- 导入预览批量工具：「重新核对」「仅保留已核对」「移除已在池」
- PDF 多页解析：每页独立 linesMap（防跨页 Y 坐标互相覆盖）

### 经理相关
- `normalizeManagerName`：strip 空白 + 去括号注释（"李华(代任)" → "李华"）
- `managerAliasMap`（持久化在 localStorage）：手动合并 API 同人异名
- `managerIndex`：基于 `_fundMetaCacheVersion + institutions.length` 轻量记忆化
- 后台静默 `_silentBackfillManagers`（与 `backfillManagers` 共享 `_managerBackfillLock`）
- 经理详情「汇总到机构」开关：路演透视视图 + 复制 Markdown

### 查询场景
- 跨机构全局速查（「全部机构」chip）：客户电话突袭时秒答"哪几家可投"
- UI 状态保留（sessionStorage `uiState_v1`）：刷新/切视图保留 selectedInstitution + fundQuery + quickFilter
- 老用户空态精简：`institutions.length > 0` 时只显示一行提示

### 基础正确性
- `formatNavDate`：本地时区格式化（避免 UTC 转换的"昨天"bug）
- `resolveFundClassification`：权威分类表（不再依赖 name 启发式）
- 同 code 不同 name 导入时 toast 警告（不再静默跳过）

## 开发约束

### 提交流程（铁律）
1. 改完做基础自检（regex 模拟、字符串解析、调用链通顺）
2. 按主题拆 commit；commit message 中文、动机优于实现
3. **commit 后立即 `git push origin main`**（用户反复要求过，必做）

### 改动风格
- 优先小改 + Edit 工具；新文件极少
- regex 改动需保留旧规则作 fallback；风险高，要在历史截图回归
- 模板改动要保持 v-if/v-else 链完整，不要漏 key
- localStorage key 命名带版本号（`_v1`），便于将来迁移

### 已知雷区
- `new Date(x).toISOString()` 在 UTC+8 会把"今天"显示成"昨天" → 必须用 `formatNavDate`
- Tesseract PSM 6 单独跑会漏粗体行 → 必须双 PSM
- OCR 7/8 位长串多半是装饰条干扰，不是 OF 后缀干扰；选窗逻辑见 `_extractFundEntries`
- API 偶返同人异名（"华李成"/"华李成 "/"华李成(共管)"）→ 必须 `normalizeManagerName` + aliasMap
- `verifyPreviewProducts` 需异步并发（`BATCH=5`），用户可能在完成前点导入 → 按钮要 disabled
- 经理 backfill 与产品名 backfill 都用 `inst._xxxBackfillLock`，**不要共用同一把锁**

## 明确不做（避免功能膨胀）
- ❌ 行情 / K 线 / 涨跌排行
- ❌ 模拟买卖 / 持仓组合
- ❌ 资讯 / 公告 / 研报集成
- ❌ 全市场基金库（不接入"中欧全产品列表"做缺口分析）
- ❌ 多用户协作 / 团队共享
- ❌ IndexedDB 迁移 / 构建工具引入
- ❌ AI 经理推荐 / 摘要

## 关键文件 & 锚点
- `index.html` — 唯一源文件
  - 全局工具函数：L3066+（`isLikelyFundCode` `normalizeManagerName` `formatNavDate`）
  - `fetchFundMeta`：L3811
  - `managerIndex` computed：L3737 区
  - `_extractFundEntries`：L5587 区（whole-text 扫描）
  - `_processImageFile`：L5937
  - `preprocessImage`：L5889
  - `cleanOcrText`：L6003
  - `verifyPreviewProducts`：L6090
  - `_silentBackfillProductNames`：L5078
  - `_silentBackfillManagers`：L5042

## 调试技巧
- OCR 问题：用 node 模拟 `_extractFundEntries` 跑文本，确认 regex 选窗对路
- 经理重合：检查 `managerAliasMap` localStorage + `normalizeManagerName` 输出
- 净值日期：先看 raw 是 `Date` 还是字符串，再走 `formatNavDate`
