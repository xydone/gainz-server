--
-- PostgreSQL database dump
--

-- Dumped from database version 16.1 (Debian 16.1-1.pgdg120+1)
-- Dumped by pg_dump version 16.1 (Debian 16.1-1.pgdg120+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: auth; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA auth;


ALTER SCHEMA auth OWNER TO postgres;

--
-- Name: training; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA training;


ALTER SCHEMA training OWNER TO postgres;

--
-- Name: goal_targets; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.goal_targets AS ENUM (
    'weight',
    'calories',
    'fat',
    'sat_fat',
    'polyunsat_fat',
    'monounsat_fat',
    'trans_fat',
    'cholesterol',
    'sodium',
    'potassium',
    'carbs',
    'fiber',
    'sugar',
    'protein',
    'vitamin_a',
    'vitamin_c',
    'calcium',
    'iron',
    'added_sugars',
    'vitamin_d',
    'sugar_alcohols'
);


ALTER TYPE public.goal_targets OWNER TO postgres;

--
-- Name: meal_category; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.meal_category AS ENUM (
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'misc'
);


ALTER TYPE public.meal_category OWNER TO postgres;

--
-- Name: measurement; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.measurement AS ENUM (
    'weight',
    'waist',
    'hips',
    'neck',
    'height'
);


ALTER TYPE public.measurement OWNER TO postgres;

--
-- Name: nutrients; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.nutrients AS ENUM (
    'calories',
    'fat',
    'sat_fat',
    'polyunsat_fat',
    'monounsat_fat',
    'trans_fat',
    'cholesterol',
    'sodium',
    'potassium',
    'carbs',
    'fiber',
    'sugar',
    'protein',
    'vitamin_a',
    'vitamin_c',
    'calcium',
    'iron',
    'added_sugars',
    'vitamin_d',
    'sugar_alcohols'
);


ALTER TYPE public.nutrients OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: api_keys; Type: TABLE; Schema: auth; Owner: postgres
--

CREATE TABLE auth.api_keys (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    user_id integer NOT NULL,
    token character varying(255) NOT NULL
);


ALTER TABLE auth.api_keys OWNER TO postgres;

--
-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: auth; Owner: postgres
--

CREATE SEQUENCE auth.api_keys_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE auth.api_keys_id_seq OWNER TO postgres;

--
-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: auth; Owner: postgres
--

ALTER SEQUENCE auth.api_keys_id_seq OWNED BY auth.api_keys.id;


--
-- Name: food; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.food (
    id integer NOT NULL,
    created_by integer,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    calories double precision NOT NULL,
    fat double precision,
    sat_fat double precision,
    polyunsat_fat double precision,
    monounsat_fat double precision,
    trans_fat double precision,
    cholesterol double precision,
    sodium double precision,
    potassium double precision,
    carbs double precision,
    fiber double precision,
    sugar double precision,
    protein double precision,
    vitamin_a double precision,
    vitamin_c double precision,
    calcium double precision,
    iron double precision,
    brand_name character varying(255),
    food_name character varying(255),
    added_sugars double precision,
    vitamin_d double precision,
    sugar_alcohols double precision,
    food_grams double precision NOT NULL
);


ALTER TABLE public.food OWNER TO postgres;

--
-- Name: Food_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Food_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Food_id_seq" OWNER TO postgres;

--
-- Name: Food_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Food_id_seq" OWNED BY public.food.id;


--
-- Name: entry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.entry (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    user_id integer NOT NULL,
    food_id integer NOT NULL,
    category public.meal_category NOT NULL,
    amount double precision NOT NULL,
    serving_id integer NOT NULL
);
ALTER TABLE ONLY public.entry ALTER COLUMN food_id SET STATISTICS 100;
ALTER TABLE ONLY public.entry ALTER COLUMN serving_id SET STATISTICS 100;


ALTER TABLE public.entry OWNER TO postgres;

--
-- Name: Log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Log_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Log_id_seq" OWNER TO postgres;

--
-- Name: Log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Log_id_seq" OWNED BY public.entry.id;


--
-- Name: measurements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.measurements (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    type public.measurement NOT NULL,
    value double precision NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.measurements OWNER TO postgres;

--
-- Name: COLUMN measurements.value; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.measurements.value IS 'metric system';


--
-- Name: Measurement_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Measurement_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Measurement_id_seq" OWNER TO postgres;

--
-- Name: Measurement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Measurement_id_seq" OWNED BY public.measurements.id;


--
-- Name: servings; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.servings (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer,
    amount double precision NOT NULL,
    unit character varying(255) NOT NULL,
    multiplier double precision NOT NULL,
    food_id integer NOT NULL
);


ALTER TABLE public.servings OWNER TO postgres;

--
-- Name: COLUMN servings.multiplier; Type: COMMENT; Schema: public; Owner: postgres
--

COMMENT ON COLUMN public.servings.multiplier IS 'Multiplier stands for what you have to multiply your values defined in the Food table to achieve the amount of the unit';


--
-- Name: Servings_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."Servings_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Servings_id_seq" OWNER TO postgres;

--
-- Name: Servings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."Servings_id_seq" OWNED BY public.servings.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.users (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    display_name character varying(255) NOT NULL,
    username character varying(255) NOT NULL,
    password character varying(255) NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;

--
-- Name: User_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."User_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."User_id_seq" OWNER TO postgres;

--
-- Name: User_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."User_id_seq" OWNED BY public.users.id;


--
-- Name: goals; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.goals (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    target public.goal_targets NOT NULL,
    value double precision NOT NULL,
    created_by integer NOT NULL
);


ALTER TABLE public.goals OWNER TO postgres;

--
-- Name: goals_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.goals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.goals_id_seq OWNER TO postgres;

--
-- Name: goals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.goals_id_seq OWNED BY public.goals.id;


--
-- Name: note_entry; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.note_entry (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    note_id integer NOT NULL,
    created_by integer NOT NULL
);


ALTER TABLE public.note_entry OWNER TO postgres;

--
-- Name: note_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.note_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.note_entries_id_seq OWNER TO postgres;

--
-- Name: note_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.note_entries_id_seq OWNED BY public.note_entry.id;


--
-- Name: notes; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.notes (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255),
    created_by integer NOT NULL
);


ALTER TABLE public.notes OWNER TO postgres;

--
-- Name: notes_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.notes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notes_id_seq OWNER TO postgres;

--
-- Name: notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.notes_id_seq OWNED BY public.notes.id;


--
-- Name: exercise; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.exercise (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255)
);


ALTER TABLE training.exercise OWNER TO postgres;

--
-- Name: exercise_category; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.exercise_category (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255)
);


ALTER TABLE training.exercise_category OWNER TO postgres;

--
-- Name: exercise_category_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.exercise_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.exercise_category_id_seq OWNER TO postgres;

--
-- Name: exercise_category_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.exercise_category_id_seq OWNED BY training.exercise_category.id;


--
-- Name: exercise_entry; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.exercise_entry (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    exercise_id integer NOT NULL,
    value double precision NOT NULL,
    unit_id integer NOT NULL,
    notes character varying(255)
);


ALTER TABLE training.exercise_entry OWNER TO postgres;

--
-- Name: exercise_entry_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.exercise_entry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.exercise_entry_id_seq OWNER TO postgres;

--
-- Name: exercise_entry_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.exercise_entry_id_seq OWNED BY training.exercise_entry.id;


--
-- Name: exercise_has_category; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.exercise_has_category (
    exercise_id integer NOT NULL,
    category_id integer NOT NULL
);


ALTER TABLE training.exercise_has_category OWNER TO postgres;

--
-- Name: exercise_has_unit; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.exercise_has_unit (
    exercise_id integer NOT NULL,
    unit_id integer NOT NULL
);


ALTER TABLE training.exercise_has_unit OWNER TO postgres;

--
-- Name: exercise_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.exercise_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.exercise_id_seq OWNER TO postgres;

--
-- Name: exercise_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.exercise_id_seq OWNED BY training.exercise.id;


--
-- Name: exercise_unit; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.exercise_unit (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    amount double precision NOT NULL,
    unit character varying(255) NOT NULL,
    multiplier double precision NOT NULL
);


ALTER TABLE training.exercise_unit OWNER TO postgres;

--
-- Name: exercise_value_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.exercise_value_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.exercise_value_id_seq OWNER TO postgres;

--
-- Name: exercise_value_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.exercise_value_id_seq OWNED BY training.exercise_unit.id;


--
-- Name: program; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.program (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL
);


ALTER TABLE training.program OWNER TO postgres;

--
-- Name: program_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.program_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.program_id_seq OWNER TO postgres;

--
-- Name: program_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.program_id_seq OWNED BY training.program.id;


--
-- Name: workout; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.workout (
    id integer NOT NULL,
    name character varying(255) NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer
);


ALTER TABLE training.workout OWNER TO postgres;

--
-- Name: workout_exercise; Type: TABLE; Schema: training; Owner: postgres
--

CREATE TABLE training.workout_exercise (
    id integer NOT NULL,
    workout_id integer NOT NULL,
    exercise_id integer NOT NULL,
    notes character varying(255),
    sets integer NOT NULL,
    reps integer NOT NULL
);


ALTER TABLE training.workout_exercise OWNER TO postgres;

--
-- Name: workout_exercise_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.workout_exercise_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.workout_exercise_id_seq OWNER TO postgres;

--
-- Name: workout_exercise_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.workout_exercise_id_seq OWNED BY training.workout_exercise.id;


--
-- Name: workout_id_seq; Type: SEQUENCE; Schema: training; Owner: postgres
--

CREATE SEQUENCE training.workout_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE training.workout_id_seq OWNER TO postgres;

--
-- Name: workout_id_seq; Type: SEQUENCE OWNED BY; Schema: training; Owner: postgres
--

ALTER SEQUENCE training.workout_id_seq OWNED BY training.workout.id;


--
-- Name: api_keys id; Type: DEFAULT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.api_keys ALTER COLUMN id SET DEFAULT nextval('auth.api_keys_id_seq'::regclass);


--
-- Name: entry id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entry ALTER COLUMN id SET DEFAULT nextval('public."Log_id_seq"'::regclass);


--
-- Name: food id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food ALTER COLUMN id SET DEFAULT nextval('public."Food_id_seq"'::regclass);


--
-- Name: goals id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goals ALTER COLUMN id SET DEFAULT nextval('public.goals_id_seq'::regclass);


--
-- Name: measurements id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.measurements ALTER COLUMN id SET DEFAULT nextval('public."Measurement_id_seq"'::regclass);


--
-- Name: note_entry id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_entry ALTER COLUMN id SET DEFAULT nextval('public.note_entries_id_seq'::regclass);


--
-- Name: notes id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notes ALTER COLUMN id SET DEFAULT nextval('public.notes_id_seq'::regclass);


--
-- Name: servings id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servings ALTER COLUMN id SET DEFAULT nextval('public."Servings_id_seq"'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public."User_id_seq"'::regclass);


--
-- Name: exercise id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise ALTER COLUMN id SET DEFAULT nextval('training.exercise_id_seq'::regclass);


--
-- Name: exercise_category id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_category ALTER COLUMN id SET DEFAULT nextval('training.exercise_category_id_seq'::regclass);


--
-- Name: exercise_entry id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_entry ALTER COLUMN id SET DEFAULT nextval('training.exercise_entry_id_seq'::regclass);


--
-- Name: exercise_unit id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_unit ALTER COLUMN id SET DEFAULT nextval('training.exercise_value_id_seq'::regclass);


--
-- Name: program id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.program ALTER COLUMN id SET DEFAULT nextval('training.program_id_seq'::regclass);


--
-- Name: workout id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout ALTER COLUMN id SET DEFAULT nextval('training.workout_id_seq'::regclass);


--
-- Name: workout_exercise id; Type: DEFAULT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout_exercise ALTER COLUMN id SET DEFAULT nextval('training.workout_exercise_id_seq'::regclass);


--
-- Data for Name: api_keys; Type: TABLE DATA; Schema: auth; Owner: postgres
--

COPY auth.api_keys (id, created_at, user_id, token) FROM stdin;
\.


--
-- Data for Name: entry; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.entry (id, created_at, user_id, food_id, category, amount, serving_id) FROM stdin;
\.


--
-- Data for Name: food; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.food (id, created_by, created_at, calories, fat, sat_fat, polyunsat_fat, monounsat_fat, trans_fat, cholesterol, sodium, potassium, carbs, fiber, sugar, protein, vitamin_a, vitamin_c, calcium, iron, brand_name, food_name, added_sugars, vitamin_d, sugar_alcohols, food_grams) FROM stdin;
\.


--
-- Data for Name: goals; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.goals (id, created_at, target, value, created_by) FROM stdin;
\.


--
-- Data for Name: measurements; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.measurements (id, created_at, type, value, user_id) FROM stdin;
\.


--
-- Data for Name: note_entry; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.note_entry (id, created_at, note_id, created_by) FROM stdin;
\.


--
-- Data for Name: notes; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.notes (id, created_at, title, description, created_by) FROM stdin;
\.


--
-- Data for Name: servings; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.servings (id, created_at, created_by, amount, unit, multiplier, food_id) FROM stdin;
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.users (id, created_at, display_name, username, password) FROM stdin;
\.


--
-- Data for Name: exercise; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.exercise (id, created_at, created_by, name, description) FROM stdin;
\.


--
-- Data for Name: exercise_category; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.exercise_category (id, created_at, created_by, name, description) FROM stdin;
\.


--
-- Data for Name: exercise_entry; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.exercise_entry (id, created_at, created_by, exercise_id, value, unit_id, notes) FROM stdin;
\.


--
-- Data for Name: exercise_has_category; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.exercise_has_category (exercise_id, category_id) FROM stdin;
\.


--
-- Data for Name: exercise_has_unit; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.exercise_has_unit (exercise_id, unit_id) FROM stdin;
\.


--
-- Data for Name: exercise_unit; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.exercise_unit (id, created_at, created_by, amount, unit, multiplier) FROM stdin;
\.


--
-- Data for Name: program; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.program (id, created_at) FROM stdin;
\.


--
-- Data for Name: workout; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.workout (id, name, created_at, created_by) FROM stdin;
\.


--
-- Data for Name: workout_exercise; Type: TABLE DATA; Schema: training; Owner: postgres
--

COPY training.workout_exercise (id, workout_id, exercise_id, notes, sets, reps) FROM stdin;
\.


--
-- Name: api_keys_id_seq; Type: SEQUENCE SET; Schema: auth; Owner: postgres
--

SELECT pg_catalog.setval('auth.api_keys_id_seq', 1, false);


--
-- Name: Food_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Food_id_seq"', 1, false);


--
-- Name: Log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Log_id_seq"', 1, false);


--
-- Name: Measurement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Measurement_id_seq"', 1, false);


--
-- Name: Servings_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."Servings_id_seq"', 1, false);


--
-- Name: User_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public."User_id_seq"', 1, false);


--
-- Name: goals_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.goals_id_seq', 1, false);


--
-- Name: note_entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.note_entries_id_seq', 1, false);


--
-- Name: notes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.notes_id_seq', 1, false);


--
-- Name: exercise_category_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.exercise_category_id_seq', 1, false);


--
-- Name: exercise_entry_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.exercise_entry_id_seq', 1, false);


--
-- Name: exercise_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.exercise_id_seq', 1, false);


--
-- Name: exercise_value_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.exercise_value_id_seq', 1, false);


--
-- Name: program_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.program_id_seq', 1, false);


--
-- Name: workout_exercise_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.workout_exercise_id_seq', 1, false);


--
-- Name: workout_id_seq; Type: SEQUENCE SET; Schema: training; Owner: postgres
--

SELECT pg_catalog.setval('training.workout_id_seq', 1, false);


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: food Food_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food
    ADD CONSTRAINT "Food_pkey" PRIMARY KEY (id);


--
-- Name: entry Log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Log_pkey" PRIMARY KEY (id);


--
-- Name: measurements Measurement_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.measurements
    ADD CONSTRAINT "Measurement_pkey" PRIMARY KEY (id);


--
-- Name: servings Servings_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servings
    ADD CONSTRAINT "Servings_pkey" PRIMARY KEY (id);


--
-- Name: users User_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT "User_pkey" PRIMARY KEY (id);


--
-- Name: goals goals_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goals
    ADD CONSTRAINT goals_pkey PRIMARY KEY (id);


--
-- Name: note_entry note_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_entry
    ADD CONSTRAINT note_entries_pkey PRIMARY KEY (id);


--
-- Name: notes notes_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: exercise_category exercise_category_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_category
    ADD CONSTRAINT exercise_category_pkey PRIMARY KEY (id);


--
-- Name: exercise_entry exercise_entry_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_entry
    ADD CONSTRAINT exercise_entry_pkey PRIMARY KEY (id);


--
-- Name: exercise_has_category exercise_has_category_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_has_category
    ADD CONSTRAINT exercise_has_category_pkey PRIMARY KEY (exercise_id, category_id);


--
-- Name: exercise_has_unit exercise_has_unit_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_has_unit
    ADD CONSTRAINT exercise_has_unit_pkey PRIMARY KEY (exercise_id, unit_id);


--
-- Name: exercise exercise_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise
    ADD CONSTRAINT exercise_pkey PRIMARY KEY (id);


--
-- Name: exercise_unit exercise_value_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_unit
    ADD CONSTRAINT exercise_value_pkey PRIMARY KEY (id);


--
-- Name: program program_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.program
    ADD CONSTRAINT program_pkey PRIMARY KEY (id);


--
-- Name: workout_exercise workout_exercise_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout_exercise
    ADD CONSTRAINT workout_exercise_pkey PRIMARY KEY (id);


--
-- Name: workout workout_pkey; Type: CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout
    ADD CONSTRAINT workout_pkey PRIMARY KEY (id);


--
-- Name: api_keys_index_2; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE UNIQUE INDEX api_keys_index_2 ON auth.api_keys USING btree (token);


--
-- Name: api_keys_index_3; Type: INDEX; Schema: auth; Owner: postgres
--

CREATE INDEX api_keys_index_3 ON auth.api_keys USING btree (user_id);


--
-- Name: entry_index_4; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX entry_index_4 ON public.entry USING btree (created_at);


--
-- Name: idx_entry_food_id; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_entry_food_id ON public.entry USING btree (food_id);


--
-- Name: api_keys api_keys_relation_1; Type: FK CONSTRAINT; Schema: auth; Owner: postgres
--

ALTER TABLE ONLY auth.api_keys
    ADD CONSTRAINT api_keys_relation_1 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- Name: notes Created by To User; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.notes
    ADD CONSTRAINT "Created by To User" FOREIGN KEY (created_by) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: entry Entry to Food; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Entry to Food" FOREIGN KEY (food_id) REFERENCES public.food(id);


--
-- Name: entry Entry to Serving; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Entry to Serving" FOREIGN KEY (serving_id) REFERENCES public.servings(id);


--
-- Name: entry Entry to User; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Entry to User" FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: food Food to User; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.food
    ADD CONSTRAINT "Food to User" FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: measurements Measurement_relation_1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.measurements
    ADD CONSTRAINT "Measurement_relation_1" FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: note_entry Note Entries to Note's ID; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_entry
    ADD CONSTRAINT "Note Entries to Note's ID" FOREIGN KEY (id) REFERENCES public.notes(id) ON UPDATE CASCADE;


--
-- Name: note_entry Note Entry to User ID; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.note_entry
    ADD CONSTRAINT "Note Entry to User ID" FOREIGN KEY (created_by) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: servings Servings to Food; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servings
    ADD CONSTRAINT "Servings to Food" FOREIGN KEY (food_id) REFERENCES public.food(id) ON DELETE CASCADE;


--
-- Name: servings Servings to User; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.servings
    ADD CONSTRAINT "Servings to User" FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: goals goals_relation_1; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.goals
    ADD CONSTRAINT goals_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: workout Created by To User; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout
    ADD CONSTRAINT "Created by To User" FOREIGN KEY (created_by) REFERENCES public.users(id) ON UPDATE CASCADE;


--
-- Name: exercise_category exercise_category_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_category
    ADD CONSTRAINT exercise_category_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: exercise_entry exercise_entry_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_entry
    ADD CONSTRAINT exercise_entry_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: exercise_entry exercise_entry_relation_2; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_entry
    ADD CONSTRAINT exercise_entry_relation_2 FOREIGN KEY (exercise_id) REFERENCES training.exercise(id);


--
-- Name: exercise_entry exercise_entry_relation_3; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_entry
    ADD CONSTRAINT exercise_entry_relation_3 FOREIGN KEY (unit_id) REFERENCES training.exercise_unit(id);


--
-- Name: exercise_has_category exercise_has_category_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_has_category
    ADD CONSTRAINT exercise_has_category_relation_1 FOREIGN KEY (exercise_id) REFERENCES training.exercise(id);


--
-- Name: exercise_has_category exercise_has_category_relation_2; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_has_category
    ADD CONSTRAINT exercise_has_category_relation_2 FOREIGN KEY (category_id) REFERENCES training.exercise_category(id);


--
-- Name: exercise_has_unit exercise_has_unit_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_has_unit
    ADD CONSTRAINT exercise_has_unit_relation_1 FOREIGN KEY (exercise_id) REFERENCES training.exercise(id);


--
-- Name: exercise_has_unit exercise_has_unit_relation_2; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_has_unit
    ADD CONSTRAINT exercise_has_unit_relation_2 FOREIGN KEY (unit_id) REFERENCES training.exercise_unit(id);


--
-- Name: exercise exercise_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise
    ADD CONSTRAINT exercise_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: exercise_unit exercise_value_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.exercise_unit
    ADD CONSTRAINT exercise_value_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);


--
-- Name: workout_exercise workout_exercise_relation_1; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout_exercise
    ADD CONSTRAINT workout_exercise_relation_1 FOREIGN KEY (workout_id) REFERENCES training.workout(id);


--
-- Name: workout_exercise workout_exercise_relation_2; Type: FK CONSTRAINT; Schema: training; Owner: postgres
--

ALTER TABLE ONLY training.workout_exercise
    ADD CONSTRAINT workout_exercise_relation_2 FOREIGN KEY (exercise_id) REFERENCES training.exercise(id);


--
-- PostgreSQL database dump complete
--

