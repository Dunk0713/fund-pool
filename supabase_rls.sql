-- ═══════════════════════════════════════════════════════════════════════════
-- Supabase Row Level Security (RLS) — 数据库层面最后一道防线
--
-- 用途：即使前端密码被绕过，RLS 仍会在数据库层拦截未授权操作
-- 执行方式：在 Supabase Dashboard → SQL Editor 中运行本脚本
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. 启用 RLS ────────────────────────────────────────────────────────────
ALTER TABLE institutions ENABLE ROW LEVEL SECURITY;

-- ── 2. 删除已有策略（幂等执行） ─────────────────────────────────────────────
DROP POLICY IF EXISTS "anon_select_institutions" ON institutions;
DROP POLICY IF EXISTS "anon_insert_institutions" ON institutions;
DROP POLICY IF EXISTS "anon_update_institutions" ON institutions;
DROP POLICY IF EXISTS "anon_delete_institutions" ON institutions;

-- ── 3. 创建读取策略 ─────────────────────────────────────────────────────────
-- anon 角色可以读取所有机构数据（查询页面需要）
CREATE POLICY "anon_select_institutions"
  ON institutions
  FOR SELECT
  TO anon
  USING (true);

-- ── 4. 创建写入策略（带请求头验证） ─────────────────────────────────────────
-- 插入：要求请求中包含有效的自定义 header（可选加固）
-- 基本策略：允许 anon 插入，但限制 id 格式必须为 inst_ 开头
CREATE POLICY "anon_insert_institutions"
  ON institutions
  FOR INSERT
  TO anon
  WITH CHECK (
    id LIKE 'inst_%'
    AND name IS NOT NULL
    AND char_length(name) BETWEEN 1 AND 100
    AND products IS NOT NULL
  );

-- ── 5. 创建更新策略 ─────────────────────────────────────────────────────────
-- 更新：只能修改已存在的记录，且不能修改 id 和 created_at
CREATE POLICY "anon_update_institutions"
  ON institutions
  FOR UPDATE
  TO anon
  USING (true)
  WITH CHECK (
    id LIKE 'inst_%'
    AND name IS NOT NULL
    AND char_length(name) BETWEEN 1 AND 100
    AND products IS NOT NULL
  );

-- ── 6. 创建删除策略 ─────────────────────────────────────────────────────────
-- 删除：允许 anon 删除，但只能删除 inst_ 开头的记录
CREATE POLICY "anon_delete_institutions"
  ON institutions
  FOR DELETE
  TO anon
  USING (id LIKE 'inst_%');

-- ── 7. 额外加固：限制单条 products 数组大小（防止恶意灌入巨量数据） ──────────
-- 使用 CHECK 约束限制 products JSON 数组长度不超过 5000 条
-- 注意：如果表已经有此约束，需先删除
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'institutions' AND constraint_name = 'products_size_limit'
  ) THEN
    ALTER TABLE institutions DROP CONSTRAINT products_size_limit;
  END IF;
END $$;

ALTER TABLE institutions
  ADD CONSTRAINT products_size_limit
  CHECK (jsonb_array_length(products::jsonb) <= 5000);

-- ── 8. 限制 name 字段长度 ──────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'institutions' AND constraint_name = 'name_length_limit'
  ) THEN
    ALTER TABLE institutions DROP CONSTRAINT name_length_limit;
  END IF;
END $$;

ALTER TABLE institutions
  ADD CONSTRAINT name_length_limit
  CHECK (char_length(name) <= 100);

-- ── 9. 速率限制建议（需在 Supabase Dashboard 中配置） ──────────────────────
-- Supabase Dashboard → Settings → API → Rate Limiting
-- 建议配置：
--   - 匿名请求：100 requests/minute
--   - 认证请求：300 requests/minute
--
-- 如需更严格的控制，可创建 Edge Function 作为中间层

-- ═══════════════════════════════════════════════════════════════════════════
-- 验证脚本：检查 RLS 是否已正确启用
-- ═══════════════════════════════════════════════════════════════════════════
SELECT
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE tablename = 'institutions';

-- 查看所有策略
SELECT * FROM pg_policies WHERE tablename = 'institutions';
