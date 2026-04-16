-- ==========================================================
-- Экзаменационный проект: ИС туристической компании
-- PostgreSQL 14+ (подходит и для более новых версий)
-- ==========================================================

DROP SCHEMA IF EXISTS tour_agency CASCADE;
CREATE SCHEMA tour_agency;
SET search_path TO tour_agency, public;

-- --------------------------
-- 1. Справочники
-- --------------------------

CREATE TABLE country (
    country_id      BIGSERIAL PRIMARY KEY,
    country_name    TEXT NOT NULL UNIQUE,
    iso_code        CHAR(2) NOT NULL UNIQUE,
    CHECK (iso_code ~ '^[A-Z]{2}$')
);

CREATE TABLE manager (
    manager_id      BIGSERIAL PRIMARY KEY,
    full_name       TEXT NOT NULL,
    phone           VARCHAR(20) NOT NULL,
    email           TEXT,
    hire_date       DATE NOT NULL DEFAULT CURRENT_DATE,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    CHECK (email IS NULL OR email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$')
);

CREATE TABLE organizer_company (
    organizer_company_id BIGSERIAL PRIMARY KEY,
    company_name         TEXT NOT NULL UNIQUE,
    contact_phone        VARCHAR(20),
    contact_email        TEXT,
    CHECK (contact_email IS NULL OR contact_email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$')
);

CREATE TABLE application_status (
    status_id        SMALLSERIAL PRIMARY KEY,
    status_code      TEXT NOT NULL UNIQUE,
    status_name      TEXT NOT NULL UNIQUE
);

INSERT INTO application_status (status_id, status_code, status_name) VALUES
    (1, 'NEW', 'Новая'),
    (2, 'APPROVED', 'Одобрена'),
    (3, 'REJECTED', 'Отклонена'),
    (4, 'RESCHEDULED', 'Перенесена');

SELECT setval(
    pg_get_serial_sequence('tour_agency.application_status', 'status_id'),
    (SELECT MAX(status_id) FROM application_status)
);

-- --------------------------
-- 2. Основные сущности
-- --------------------------

CREATE TABLE tour (
    tour_id                           BIGSERIAL PRIMARY KEY,
    tour_name                         TEXT NOT NULL,
    country_id                        BIGINT NOT NULL REFERENCES country(country_id) ON UPDATE CASCADE,
    manager_id                        BIGINT NOT NULL REFERENCES manager(manager_id) ON UPDATE CASCADE,
    organizer_company_id              BIGINT NOT NULL REFERENCES organizer_company(organizer_company_id) ON UPDATE CASCADE,
    start_date                        DATE NOT NULL,
    end_date                          DATE NOT NULL,
    capacity                          INTEGER NOT NULL,
    base_price                        NUMERIC(12,2) NOT NULL,
    requires_international_passport   BOOLEAN NOT NULL DEFAULT FALSE,
    is_active                         BOOLEAN NOT NULL DEFAULT TRUE,
    description                       TEXT,
    CHECK (end_date >= start_date),
    CHECK (capacity > 0),
    CHECK (base_price >= 0)
);

CREATE TABLE client (
    client_id                  BIGSERIAL PRIMARY KEY,
    full_name                  TEXT NOT NULL,
    birth_date                 DATE NOT NULL,
    phone                      VARCHAR(20) NOT NULL,
    email                      TEXT,
    russian_passport_series    CHAR(4) NOT NULL,
    russian_passport_number    CHAR(6) NOT NULL,
    russian_passport_issued_by TEXT NOT NULL,
    russian_passport_issue_date DATE NOT NULL,
    CHECK (birth_date < CURRENT_DATE),
    CHECK (russian_passport_series ~ '^[0-9]{4}$'),
    CHECK (russian_passport_number ~ '^[0-9]{6}$'),
    CHECK (email IS NULL OR email ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$')
);

CREATE TABLE international_passport (
    international_passport_id BIGSERIAL PRIMARY KEY,
    client_id                 BIGINT NOT NULL UNIQUE REFERENCES client(client_id) ON DELETE CASCADE,
    passport_number           VARCHAR(32) NOT NULL UNIQUE,
    issue_date                DATE NOT NULL,
    expiry_date               DATE NOT NULL,
    CHECK (expiry_date > issue_date)
);

CREATE TABLE tour_application (
    application_id     BIGSERIAL PRIMARY KEY,
    tour_id            BIGINT NOT NULL REFERENCES tour(tour_id) ON UPDATE CASCADE,
    client_id          BIGINT NOT NULL REFERENCES client(client_id) ON UPDATE CASCADE,
    manager_id         BIGINT NOT NULL REFERENCES manager(manager_id) ON UPDATE CASCADE,
    desired_date       DATE NOT NULL,
    status_id          SMALLINT NOT NULL DEFAULT 1 REFERENCES application_status(status_id) ON UPDATE CASCADE,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    comment_text       TEXT,
    rejection_reason   TEXT,
    CHECK (
        (status_id <> 3 AND rejection_reason IS NULL)
        OR (status_id = 3 AND rejection_reason IS NOT NULL)
    )
);

CREATE TABLE booking (
    booking_id                    BIGSERIAL PRIMARY KEY,
    application_id                BIGINT NOT NULL UNIQUE REFERENCES tour_application(application_id) ON DELETE CASCADE,
    organizer_confirmation_code   TEXT NOT NULL UNIQUE,
    seats_count                   INTEGER NOT NULL DEFAULT 1,
    booked_at                     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (seats_count > 0)
);

-- --------------------------
-- 3. Индексы
-- --------------------------

CREATE INDEX idx_tour_country_dates ON tour(country_id, start_date, end_date);
CREATE INDEX idx_tour_manager ON tour(manager_id);
CREATE INDEX idx_tour_requires_foreign ON tour(requires_international_passport);

CREATE INDEX idx_application_tour_date ON tour_application(tour_id, desired_date);
CREATE INDEX idx_application_status ON tour_application(status_id);
CREATE INDEX idx_application_client ON tour_application(client_id);

CREATE INDEX idx_booking_application ON booking(application_id);

-- --------------------------
-- 4. Бизнес-правила (триггеры)
-- --------------------------

CREATE OR REPLACE FUNCTION fn_validate_tour_application()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_requires_international_passport BOOLEAN;
    v_tour_manager_id                 BIGINT;
    v_tour_start_date                 DATE;
    v_tour_end_date                   DATE;
    v_has_valid_international_passport BOOLEAN;
BEGIN
    SELECT t.requires_international_passport, t.manager_id, t.start_date, t.end_date
      INTO v_requires_international_passport, v_tour_manager_id, v_tour_start_date, v_tour_end_date
      FROM tour t
     WHERE t.tour_id = NEW.tour_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Тур с id=% не найден', NEW.tour_id;
    END IF;

    IF NEW.manager_id <> v_tour_manager_id THEN
        RAISE EXCEPTION
            'Менеджер заявки (id=%) не является куратором тура (id=%)',
            NEW.manager_id, NEW.tour_id;
    END IF;

    IF NEW.desired_date < v_tour_start_date OR NEW.desired_date > v_tour_end_date THEN
        RAISE EXCEPTION
            'Желаемая дата % не входит в интервал тура [% - %]',
            NEW.desired_date, v_tour_start_date, v_tour_end_date;
    END IF;

    IF v_requires_international_passport THEN
        SELECT EXISTS (
            SELECT 1
              FROM international_passport ip
             WHERE ip.client_id = NEW.client_id
               AND ip.expiry_date >= NEW.desired_date
        )
          INTO v_has_valid_international_passport;

        IF NOT v_has_valid_international_passport THEN
            RAISE EXCEPTION
                'Для данного тура требуется действующий загранпаспорт клиента на дату %',
                NEW.desired_date;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_tour_application
BEFORE INSERT OR UPDATE OF tour_id, client_id, manager_id, desired_date
ON tour_application
FOR EACH ROW
EXECUTE FUNCTION fn_validate_tour_application();

CREATE OR REPLACE FUNCTION fn_validate_booking_capacity()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_tour_id            BIGINT;
    v_desired_date       DATE;
    v_status_code        TEXT;
    v_capacity           INTEGER;
    v_reserved_seats     INTEGER;
BEGIN
    SELECT ta.tour_id, ta.desired_date, s.status_code
      INTO v_tour_id, v_desired_date, v_status_code
      FROM tour_application ta
      JOIN application_status s ON s.status_id = ta.status_id
     WHERE ta.application_id = NEW.application_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Заявка с id=% не найдена', NEW.application_id;
    END IF;

    IF v_status_code <> 'APPROVED' THEN
        RAISE EXCEPTION 'Бронирование возможно только для заявок со статусом APPROVED';
    END IF;

    SELECT t.capacity
      INTO v_capacity
      FROM tour t
     WHERE t.tour_id = v_tour_id;

    SELECT COALESCE(SUM(b.seats_count), 0)
      INTO v_reserved_seats
      FROM booking b
      JOIN tour_application ta ON ta.application_id = b.application_id
     WHERE ta.tour_id = v_tour_id
       AND ta.desired_date = v_desired_date
       AND (
            TG_OP = 'INSERT'
            OR b.booking_id <> NEW.booking_id
       );

    IF (v_reserved_seats + NEW.seats_count) > v_capacity THEN
        RAISE EXCEPTION
            'Недостаточно мест: доступно %, запрошено %',
            v_capacity - v_reserved_seats, NEW.seats_count;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_validate_booking_capacity
BEFORE INSERT OR UPDATE OF seats_count, application_id
ON booking
FOR EACH ROW
EXECUTE FUNCTION fn_validate_booking_capacity();

-- --------------------------
-- 5. Представления (для UI)
-- --------------------------

CREATE OR REPLACE VIEW v_tour_catalog AS
SELECT
    t.tour_id,
    t.tour_name,
    c.country_name,
    m.full_name AS manager_name,
    o.company_name AS organizer_name,
    t.start_date,
    t.end_date,
    t.base_price,
    t.capacity,
    COALESCE(bs.booked_seats, 0) AS booked_seats,
    (t.capacity - COALESCE(bs.booked_seats, 0)) AS available_seats,
    t.requires_international_passport,
    t.is_active
FROM tour t
JOIN country c ON c.country_id = t.country_id
JOIN manager m ON m.manager_id = t.manager_id
JOIN organizer_company o ON o.organizer_company_id = t.organizer_company_id
LEFT JOIN (
    SELECT
        ta.tour_id,
        SUM(b.seats_count) AS booked_seats
    FROM booking b
    JOIN tour_application ta ON ta.application_id = b.application_id
    GROUP BY ta.tour_id
) bs ON bs.tour_id = t.tour_id;

-- --------------------------
-- 6. Тестовые данные
-- --------------------------

INSERT INTO country (country_name, iso_code) VALUES
    ('Россия', 'RU'),
    ('Турция', 'TR'),
    ('Италия', 'IT');

INSERT INTO manager (full_name, phone, email, hire_date) VALUES
    ('Иванов Иван Иванович', '+79990001122', 'ivanov@travel.local', '2023-01-10'),
    ('Петрова Анна Сергеевна', '+79990002233', 'petrova@travel.local', '2024-03-01');

INSERT INTO organizer_company (company_name, contact_phone, contact_email) VALUES
    ('Global Trips', '+78121234567', 'contact@globaltrips.example'),
    ('SunSea Tour', '+78127654321', 'office@sunsea.example');

INSERT INTO tour (
    tour_name,
    country_id,
    manager_id,
    organizer_company_id,
    start_date,
    end_date,
    capacity,
    base_price,
    requires_international_passport,
    description
) VALUES
    ('Золотое кольцо', 1, 1, 1, '2026-05-10', '2026-05-16', 30, 45000.00, FALSE, 'Автобусный тур по городам Золотого кольца'),
    ('Стамбул Weekend', 2, 2, 2, '2026-06-05', '2026-06-09', 20, 72000.00, TRUE, 'Короткая поездка в Стамбул'),
    ('Римские каникулы', 3, 2, 1, '2026-07-12', '2026-07-19', 15, 99000.00, TRUE, 'Экскурсионный тур в Рим');

INSERT INTO client (
    full_name,
    birth_date,
    phone,
    email,
    russian_passport_series,
    russian_passport_number,
    russian_passport_issued_by,
    russian_passport_issue_date
) VALUES
    ('Смирнов Алексей Павлович', '1997-04-17', '+79000001111', 'smirnov@mail.local', '4010', '123456', 'ГУ МВД России', '2017-08-12'),
    ('Кузнецова Мария Олеговна', '1995-11-22', '+79000002222', 'kuznetsova@mail.local', '4011', '654321', 'ГУ МВД России', '2018-02-25');

INSERT INTO international_passport (client_id, passport_number, issue_date, expiry_date) VALUES
    (1, '76N1234567', '2021-03-01', '2031-03-01'),
    (2, '76N7654321', '2020-10-10', '2030-10-10');

INSERT INTO tour_application (tour_id, client_id, manager_id, desired_date, status_id, comment_text) VALUES
    (1, 1, 1, '2026-05-10', 2, 'Подтверждение по стандартному пакету'),
    (2, 2, 2, '2026-06-05', 1, 'Ожидание подтверждения от организатора');

INSERT INTO booking (application_id, organizer_confirmation_code, seats_count) VALUES
    (1, 'GT-BOOK-0001', 1);

-- --------------------------
-- 7. Пример запроса фильтрации (для WinForms)
-- --------------------------
-- SELECT *
--   FROM tour_agency.v_tour_catalog
--  WHERE is_active = TRUE
--    AND (country_name = :country_name OR :country_name IS NULL)
--    AND start_date >= :date_from
--    AND end_date   <= :date_to
--  ORDER BY start_date, tour_name;
