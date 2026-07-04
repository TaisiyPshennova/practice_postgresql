--проверка что айди уникальные
select 
    count(*) - count( distinct "data.general.id") as duplicates
from education_data.education_data;

--назначаем id как первичный клю
alter table education_data.education_data
add primary key ("data.general.id");

--последовательность
create sequence if not exists education_data.education_data_id_seq
start with 1
increment by 1;

--Следующих 3 запросов не было в скрипте с прошлым набором данных, решила добавить здесь
-- устанавливаем последовательность 
select setval('education_data.education_data_id_seq', 
    (select max("data.general.id") from education_data.education_data));

-- привязываем последовательность к колонке data.general.id
alter sequence education_data.education_data_id_seq 
owned by education_data.education_data."data.general.id";

-- назначаем как значение по умолчанию
alter table education_data.education_data 
alter column "data.general.id" set default nextval('education_data.education_data_id_seq');

--not null:
-- название 
alter table education_data.education_data 
alter column "data.general.name" set not null;

-- полный адрес 
alter table education_data.education_data 
alter column "data.general.address.fullAddress" set not null;

-- часовой пояс 
alter table education_data.education_data 
alter column "data.general.locale.timezone" set not null;

--проверка будет ли уникальным имя + адрес(вывод 0- 0 дубликатов. Значит подходит)
select 
    count(*) - count(distinct (
        "data.general.name", 
        "data.general.address.fullAddress"
    )) as duplicates
from education_data.education_data
where "data.general.organization.inn" is not null;

-- удаляем всё, что не Вологодская область
delete from education_data.education_data 
where "data.general.address.fullAddress" not like '%Вологодская%';

-- устанавливаем расширение postgis уже установлено, но все таки добавим запрос
create extension if not exists postgis;

-- добавляем колонку geomЫ
alter table education_data.education_data 
add column if not exists geom geometry(Point, 4326);

--сначала запрос выводил ошибку, потому что некоторые учреждения не имеют координат
--поэтому нужно учитывать и это 
-- заполняем geom только для записей, у которых есть coordinates
update education_data.education_data 
set geom = st_setsrid(
    st_makepoint(
        ("data.general.address.mapPosition"::jsonb->'coordinates'->>0)::numeric,
        ("data.general.address.mapPosition"::jsonb->'coordinates'->>1)::numeric
    ),
    4326
)
where "data.general.address.mapPosition" is not null
    and "data.general.address.mapPosition"::jsonb->'coordinates' is not null;

-- создаём таблицу tags
create table if not exists education_data.tags (
    id bigserial primary key,
    tag_name text not null unique,
    usage_count bigint
);

-- заполняем тегами 	
insert into education_data.tags (tag_name, usage_count)
select 
    elem->>'name' as tag_name,
    count(*) as usage_count
from education_data.education_data,
    lateral jsonb_array_elements("data.general.tags") as elem
where "data.general.tags" is not null 
    and "data.general.tags" != '[]'::jsonb
    and elem->>'name' is not null
    and elem->>'name' != ''
group by elem->>'name';


-- создаём таблицу для связи
create table education_data.m2m_education_data_tags (
    education_place_id bigint,
    tag_id bigint,
    primary key (education_place_id, tag_id)
);

-- добавляем внешние ключи
alter table education_data.m2m_education_data_tags 
add foreign key (education_place_id) 
references education_data.education_data("data.general.id");

alter table education_data.m2m_education_data_tags 
add foreign key (tag_id) 
references education_data.tags(id);

-- заполняем
insert into education_data.m2m_education_data_tags (education_place_id, tag_id)
select 
    ed."data.general.id",
    t.id
from education_data.education_data ed,
    lateral jsonb_array_elements(ed."data.general.tags") as elem
join education_data.tags t on t.tag_name = elem->>'name'
where ed."data.general.tags" is not null;

-- индексы
create index idx_m2m_place on education_data.m2m_education_data_tags (education_place_id);
create index idx_m2m_tag on education_data.m2m_education_data_tags (tag_id);

--Сильный проблем не возникало. Только одна,когда переносила данные в колонку
--geom, не учитывала объекты, у которых не указаны координаты(