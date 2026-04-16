# Как запустить скрипт в PostgreSQL и увидеть диаграмму

## 1) Запуск скрипта

```bash
psql -U postgres -d postgres -f sql/01_tour_agency_schema.sql
```

Если нужно создать отдельную БД:

```bash
createdb -U postgres tour_agency_db
psql -U postgres -d tour_agency_db -f sql/01_tour_agency_schema.sql
```

## 2) Проверка, что всё создалось

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'tour_agency'
ORDER BY table_name;
```

## 3) Как увидеть ER-диаграмму «внутри» клиента БД

### Вариант A: pgAdmin

1. Открой `Tools -> ERD Tool`.
2. Выбери схему `tour_agency`.
3. Добавь таблицы в полотно (или `Add all`).
4. Связи подтянутся автоматически по внешним ключам.

### Вариант B: DBeaver

1. ПКМ по схеме `tour_agency` -> `View Diagram`.
2. Если нужно, выбери все таблицы вручную.
3. DBeaver отрисует связи по FK.

### Вариант C: Mermaid (для отчета/защиты)

Используй файл:

- `docs/diagrams/er-tour-agency.md`

Его удобно вставлять в пояснительную записку и презентацию.
