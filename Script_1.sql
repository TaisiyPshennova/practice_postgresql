--Проверка, что id никальные,иначе мы не можем этот столбец взять как первичный ключ
SELECT COUNT(*) - COUNT(DISTINCT "data.general.id") as duplicates
FROM culture_data.culture_palaces_clubs;

--добавляем PRAIMARY KEY
ALTER TABLE culture_data.culture_palaces_clubs 
ADD PRIMARY KEY ("data.general.id");

--Последовательность
CREATE SEQUENCE IF NOT EXISTS culture_data.culture_palaces_clubs_id_seq
START WITH 1
INCREMENT BY 1;

--Для названия
ALTER TABLE culture_data.culture_palaces_clubs 
ALTER COLUMN "data.general.name" SET NOT NULL;

--Для адреса
ALTER TABLE culture_data.culture_palaces_clubs 
ALTER COLUMN "data.general.address.fullAddress" SET NOT NULL;

--Для часового пояса 
ALTER TABLE culture_data.culture_palaces_clubs 
ALTER COLUMN "data.general.locale.timezone" SET NOT NULL;

--Проверка уникальности инн + название + адрес(не уникально, поэтому PRIMARY KEY единственное уник ограничение)
SELECT 
    "data.general.organization.inn" as inn,
    "data.general.name" as name,
    "data.general.address.fullAddress" as address,
    COUNT(*) as duplicate_count
FROM culture_data.culture_palaces_clubs
WHERE "data.general.organization.inn" IS NOT NULL
GROUP BY 
    "data.general.organization.inn",
    "data.general.name",
    "data.general.address.fullAddress"
HAVING COUNT(*) > 1;
-- сначала пробовала сделать UNIQUE на название, но там были дубликаты
-- потом проверила инн + название + адрес - тоже дубли
-- так что оставила только PRIMARY KEY

--установка расширения
CREATE EXTENSION IF NOT EXISTS postgis;

--Добавляем новый столбец
ALTER TABLE culture_data.culture_palaces_clubs 
ADD COLUMN IF NOT EXISTS geom geometry(Point, 4326);

--заполняем его
UPDATE culture_data.culture_palaces_clubs 
SET geom = ST_GeomFromGeoJSON("data.general.address.mapPosition"::text)
WHERE "data.general.address.mapPosition" IS NOT NULL;

--создаем новую таблицу tags
CREATE TABLE IF NOT EXISTS culture_data.tags (
    id BIGSERIAL PRIMARY KEY,           -- id
    tag_name TEXT NOT NULL UNIQUE,      -- название тега 
    usage_count INTEGER DEFAULT 1       -- кол-во учреждений с этим тегом
);
--Может возникнуть вопрос,а зачем id если теги с точки зрения логики 
--хорошо подходят для первичного ключа. Есть несколько причин такого решения
-- 1) Числовые ключи работаю быстрее строковых
-- 2) В случае возникновение опечатки в теге, это ломает все!

--поиск по названию тега
CREATE INDEX idx_tags_tag_name ON culture_data.tags (tag_name);

--заполняем таблицу
INSERT INTO culture_data.tags (tag_name, usage_count)
SELECT 
    elem->>'name' as tag_name,
    COUNT(*) as usage_count
FROM culture_data.culture_palaces_clubs,
    LATERAL jsonb_array_elements("data.general.tags") AS elem
WHERE "data.general.tags" IS NOT NULL 
    AND "data.general.tags" != '[]'::jsonb
    AND elem->>'name' IS NOT NULL
    AND elem->>'name' != ''
GROUP BY elem->>'name'
ON CONFLICT (tag_name) DO UPDATE 
SET usage_count = EXCLUDED.usage_count;

--Создаем промижуточную таблицу 
CREATE TABLE IF NOT EXISTS culture_data.m2m_culture_palaces_clubs_tags (
    culture_place_id BIGINT NOT NULL,
    tag_id BIGINT NOT NULL,
    PRIMARY KEY (culture_place_id, tag_id)
);

--Вставляем внешние ключи
ALTER TABLE culture_data.m2m_culture_palaces_clubs_tags
ADD CONSTRAINT fk_m2m_culture_place 
FOREIGN KEY (culture_place_id) 
REFERENCES culture_data.culture_palaces_clubs("data.general.id") 
ON DELETE CASCADE;

ALTER TABLE culture_data.m2m_culture_palaces_clubs_tags
ADD CONSTRAINT fk_m2m_tag 
FOREIGN KEY (tag_id) 
REFERENCES culture_data.tags(id) 
ON DELETE CASCADE;

--Заполняем таблицу m2m...
INSERT INTO culture_data.m2m_culture_palaces_clubs_tags (culture_place_id, tag_id)
SELECT DISTINCT
    (cp."data.general.id")::BIGINT as culture_place_id,
    t.id as tag_id
FROM culture_data.culture_palaces_clubs cp,
    LATERAL jsonb_array_elements(cp."data.general.tags") AS elem
JOIN culture_data.tags t ON t.tag_name = elem->>'name'
WHERE cp."data.general.tags" IS NOT NULL 
    AND cp."data.general.tags" != '[]'::jsonb
    AND elem->>'name' IS NOT NULL
    AND elem->>'name' != ''
ON CONFLICT (culture_place_id, tag_id) DO NOTHING;

--так же индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_m2m_culture_place_id 
ON culture_data.m2m_culture_palaces_clubs_tags (culture_place_id);

CREATE INDEX IF NOT EXISTS idx_m2m_tag_id 
ON culture_data.m2m_culture_palaces_clubs_tags (tag_id);

CREATE INDEX IF NOT EXISTS idx_m2m_culture_tag 
ON culture_data.m2m_culture_palaces_clubs_tags (culture_place_id, tag_id);

SELECT 
    COUNT(*) as total_links
FROM culture_data.m2m_culture_palaces_clubs_tags;


