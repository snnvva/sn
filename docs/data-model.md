# Логическая модель данных ИС турфирмы

## 1) Сущности и связи

1. **country (страна)**  
   Одна страна может иметь много туров (`country 1:N tour`).

2. **manager (менеджер)**  
   Один менеджер курирует много туров (`manager 1:N tour`).  
   Каждый тур имеет только одного менеджера-куратора.

3. **organizer_company (компания-организатор)**  
   Одна компания-организатор может обеспечивать много туров (`organizer_company 1:N tour`).

4. **tour (тур)**  
   Основная сущность каталога: название, страна, куратор, организатор, сроки, цена, вместимость.

5. **client (клиент)**  
   Хранит персональные данные клиента, паспорт РФ.

6. **international_passport (загранпаспорт)**  
   Опциональная сущность для клиента (`client 1:0..1 international_passport`).

7. **application_status (статус заявки)**  
   Справочник статусов: новая, одобрена, отклонена, перенесена.

8. **tour_application (заявка на тур)**  
   Связывает клиента с выбранным туром и менеджером.  
   В заявке фиксируется желаемая дата и статус обработки.

9. **booking (бронирование)**  
   Создается для одобренной заявки, фиксирует факт подтверждения места у организатора.

---

## 2) Бизнес-правила, учтенные в модели

1. Один тур относится строго к одной стране.
2. Один тур курирует только один менеджер.
3. Менеджер в заявке должен совпадать с менеджером-куратором тура.
4. Для заграничных туров (`requires_international_passport = true`) у клиента должен быть действующий загранпаспорт на дату поездки.
5. Бронирование разрешено только для заявок со статусом `APPROVED`.
6. Количество забронированных мест не должно превышать вместимость тура.

---

## 3) Словарь данных (физическая модель)

### country

- `country_id` BIGSERIAL PK — идентификатор страны  
- `country_name` TEXT UNIQUE NOT NULL — название страны  
- `iso_code` CHAR(2) UNIQUE NOT NULL — ISO-код страны (2 латинские буквы)

### manager

- `manager_id` BIGSERIAL PK — идентификатор менеджера  
- `full_name` TEXT NOT NULL — ФИО менеджера  
- `phone` VARCHAR(20) NOT NULL — телефон  
- `email` TEXT NULL — email  
- `hire_date` DATE NOT NULL — дата найма  
- `is_active` BOOLEAN NOT NULL — признак активности

### organizer_company

- `organizer_company_id` BIGSERIAL PK — идентификатор организатора  
- `company_name` TEXT UNIQUE NOT NULL — название компании  
- `contact_phone` VARCHAR(20) NULL — телефон  
- `contact_email` TEXT NULL — email

### tour

- `tour_id` BIGSERIAL PK — идентификатор тура  
- `tour_name` TEXT NOT NULL — название тура  
- `country_id` BIGINT FK -> country.country_id — страна  
- `manager_id` BIGINT FK -> manager.manager_id — менеджер-куратор  
- `organizer_company_id` BIGINT FK -> organizer_company.organizer_company_id — организатор  
- `start_date` DATE NOT NULL — дата начала  
- `end_date` DATE NOT NULL — дата окончания  
- `capacity` INTEGER NOT NULL — вместимость  
- `base_price` NUMERIC(12,2) NOT NULL — базовая цена  
- `requires_international_passport` BOOLEAN NOT NULL — нужен ли загранпаспорт  
- `is_active` BOOLEAN NOT NULL — доступен ли тур  
- `description` TEXT NULL — описание

### client

- `client_id` BIGSERIAL PK — идентификатор клиента  
- `full_name` TEXT NOT NULL — ФИО  
- `birth_date` DATE NOT NULL — дата рождения  
- `phone` VARCHAR(20) NOT NULL — телефон  
- `email` TEXT NULL — email  
- `russian_passport_series` CHAR(4) NOT NULL — серия паспорта РФ  
- `russian_passport_number` CHAR(6) NOT NULL — номер паспорта РФ  
- `russian_passport_issued_by` TEXT NOT NULL — кем выдан  
- `russian_passport_issue_date` DATE NOT NULL — дата выдачи

### international_passport

- `international_passport_id` BIGSERIAL PK — идентификатор загранпаспорта  
- `client_id` BIGINT UNIQUE FK -> client.client_id — клиент  
- `passport_number` VARCHAR(32) UNIQUE NOT NULL — номер  
- `issue_date` DATE NOT NULL — дата выдачи  
- `expiry_date` DATE NOT NULL — срок действия

### application_status

- `status_id` SMALLSERIAL PK — идентификатор статуса  
- `status_code` TEXT UNIQUE NOT NULL — машинный код статуса  
- `status_name` TEXT UNIQUE NOT NULL — отображаемое название

### tour_application

- `application_id` BIGSERIAL PK — идентификатор заявки  
- `tour_id` BIGINT FK -> tour.tour_id — выбранный тур  
- `client_id` BIGINT FK -> client.client_id — клиент  
- `manager_id` BIGINT FK -> manager.manager_id — менеджер  
- `desired_date` DATE NOT NULL — дата поездки (по заявке)  
- `status_id` SMALLINT FK -> application_status.status_id — статус  
- `created_at` TIMESTAMPTZ NOT NULL — дата/время создания  
- `comment_text` TEXT NULL — комментарий  
- `rejection_reason` TEXT NULL — причина отказа (обязательна только для статуса REJECTED)

### booking

- `booking_id` BIGSERIAL PK — идентификатор бронирования  
- `application_id` BIGINT UNIQUE FK -> tour_application.application_id — заявка  
- `organizer_confirmation_code` TEXT UNIQUE NOT NULL — код подтверждения от организатора  
- `seats_count` INTEGER NOT NULL — число мест  
- `booked_at` TIMESTAMPTZ NOT NULL — дата/время бронирования

---

## 4) Что используется приложением (пункт 3 задания)

Для WinForms-приложения по поддержке каталога туров достаточно таблиц:

- `country`
- `manager`
- `organizer_company`
- `tour`
- представление `v_tour_catalog` (удобно для фильтров и отображения)

Остальные таблицы нужны для полной информационной модели процесса заявок и бронирования.
