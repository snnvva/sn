# Пункт 3 задания: реализация в Windows Forms (CRUD туров + фильтры)

Ниже — минимально достаточный и при этом «экзаменационно полный» вариант реализации.

## 1) Что реализуем

Приложение должно поддерживать:

1. Добавление тура
2. Редактирование тура
3. Удаление тура (мягкое удаление через `is_active = false` или физическое `DELETE`)
4. Фильтрация туров:
   - по стране
   - по срокам (дата начала/окончания)

## 2) Рекомендуемая структура проекта WinForms

```
TourAgency.WinForms
 ├─ Program.cs
 ├─ App.config
 ├─ Forms
 │   ├─ MainForm.cs              // список туров + фильтры + кнопки CRUD
 │   └─ TourEditForm.cs          // диалог добавления/редактирования тура
 ├─ Data
 │   ├─ DbConnectionFactory.cs
 │   ├─ TourRepository.cs
 │   └─ LookupRepository.cs      // страны, менеджеры, организаторы
 └─ Models
     ├─ TourDto.cs
     └─ TourFilter.cs
```

## 3) NuGet-пакет

Установи пакет:

```powershell
Install-Package Npgsql
```

## 4) Строка подключения

`App.config`:

```xml
<configuration>
  <connectionStrings>
    <add name="TourDb"
         connectionString="Host=localhost;Port=5432;Database=postgres;Username=postgres;Password=postgres"
         providerName="Npgsql" />
  </connectionStrings>
</configuration>
```

Если ты создаешь отдельную БД, например `tour_agency_db`, замени `Database`.

## 5) SQL-запросы для функционала

### Получение списка туров с фильтрами

```sql
SELECT
    t.tour_id,
    t.tour_name,
    c.country_name,
    t.start_date,
    t.end_date,
    t.base_price,
    t.capacity,
    t.is_active
FROM tour_agency.tour t
JOIN tour_agency.country c ON c.country_id = t.country_id
WHERE t.is_active = TRUE
  AND (@country_id IS NULL OR t.country_id = @country_id)
  AND (@date_from IS NULL OR t.start_date >= @date_from)
  AND (@date_to   IS NULL OR t.end_date   <= @date_to)
ORDER BY t.start_date, t.tour_name;
```

### Добавление тура

```sql
INSERT INTO tour_agency.tour
(
    tour_name, country_id, manager_id, organizer_company_id,
    start_date, end_date, capacity, base_price,
    requires_international_passport, is_active, description
)
VALUES
(
    @tour_name, @country_id, @manager_id, @organizer_company_id,
    @start_date, @end_date, @capacity, @base_price,
    @requires_international_passport, TRUE, @description
);
```

### Редактирование тура

```sql
UPDATE tour_agency.tour
SET
    tour_name = @tour_name,
    country_id = @country_id,
    manager_id = @manager_id,
    organizer_company_id = @organizer_company_id,
    start_date = @start_date,
    end_date = @end_date,
    capacity = @capacity,
    base_price = @base_price,
    requires_international_passport = @requires_international_passport,
    description = @description
WHERE tour_id = @tour_id;
```

### Удаление тура (рекомендуется мягкое)

```sql
UPDATE tour_agency.tour
SET is_active = FALSE
WHERE tour_id = @tour_id;
```

## 6) Пример репозитория (Npgsql)

```csharp
using System;
using System.Collections.Generic;
using System.Configuration;
using Npgsql;

public sealed class TourRepository
{
    private readonly string _connectionString =
        ConfigurationManager.ConnectionStrings["TourDb"].ConnectionString;

    public List<TourDto> GetTours(int? countryId, DateTime? dateFrom, DateTime? dateTo)
    {
        const string sql = @"
SELECT
    t.tour_id,
    t.tour_name,
    c.country_name,
    t.start_date,
    t.end_date,
    t.base_price,
    t.capacity,
    t.is_active
FROM tour_agency.tour t
JOIN tour_agency.country c ON c.country_id = t.country_id
WHERE t.is_active = TRUE
  AND (@country_id IS NULL OR t.country_id = @country_id)
  AND (@date_from IS NULL OR t.start_date >= @date_from)
  AND (@date_to   IS NULL OR t.end_date   <= @date_to)
ORDER BY t.start_date, t.tour_name;";

        var result = new List<TourDto>();
        using var cn = new NpgsqlConnection(_connectionString);
        using var cmd = new NpgsqlCommand(sql, cn);
        cmd.Parameters.AddWithValue("@country_id", (object?)countryId ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@date_from", (object?)dateFrom ?? DBNull.Value);
        cmd.Parameters.AddWithValue("@date_to", (object?)dateTo ?? DBNull.Value);

        cn.Open();
        using var rd = cmd.ExecuteReader();
        while (rd.Read())
        {
            result.Add(new TourDto
            {
                TourId = rd.GetInt64(0),
                TourName = rd.GetString(1),
                CountryName = rd.GetString(2),
                StartDate = rd.GetDateTime(3),
                EndDate = rd.GetDateTime(4),
                BasePrice = rd.GetDecimal(5),
                Capacity = rd.GetInt32(6),
                IsActive = rd.GetBoolean(7)
            });
        }

        return result;
    }
}
```

## 7) UI (MainForm) — что должно быть на форме

1. `DataGridView dgvTours` — таблица туров  
2. `ComboBox cbCountryFilter` — фильтр по стране (`-- Все страны --`)  
3. `DateTimePicker dtpFrom` + `DateTimePicker dtpTo` + `CheckBox` для опциональности дат  
4. Кнопки:
   - `btnApplyFilter`
   - `btnResetFilter`
   - `btnAddTour`
   - `btnEditTour`
   - `btnDeleteTour`

### Поведение

- При запуске формы:
  - загрузить страны в `cbCountryFilter`
  - загрузить список туров в `dgvTours`
- По `btnApplyFilter`: перечитать данные с выбранными фильтрами.
- По `btnResetFilter`: сбросить значения и перечитать список.
- `btnAddTour`: открыть `TourEditForm` в режиме создания.
- `btnEditTour`: открыть `TourEditForm` по выбранной записи.
- `btnDeleteTour`: подтвердить удаление и выполнить soft delete.

## 8) Валидации (обязательно)

В `TourEditForm`:

1. Название тура не пустое.
2. Страна выбрана.
3. Менеджер и организатор выбраны.
4. `end_date >= start_date`.
5. `capacity > 0`.
6. `base_price >= 0`.

## 9) Как запустить с нуля

1. Запусти PostgreSQL.
2. Выполни скрипт `sql/01_tour_agency_schema.sql`.
3. Создай WinForms-проект и подключи `Npgsql`.
4. Пропиши connection string в `App.config`.
5. Реализуй формы и репозитории по шаблону выше.
6. Проверь CRUD и фильтры тест-кейсами из `tests/test-cases.md`.
