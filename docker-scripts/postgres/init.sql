--
-- PostgreSQL database dump
--

-- Dumped from database version 16.1
-- Dumped by pg_dump version 16.1

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


CREATE TYPE public.meal_category AS ENUM (
    'breakfast',
    'lunch',
    'dinner',
    'snack',
    'misc'
);


ALTER TYPE public.meal_category OWNER TO postgres;


CREATE TYPE public.measurement AS ENUM (
    'weight',
    'waist',
    'hips',
    'neck',
    'height'
);


ALTER TYPE public.measurement OWNER TO postgres;


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


CREATE TABLE public.food (
    id integer NOT NULL,
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
    created_by integer NOT NULL,
    added_sugars double precision,
    vitamin_d double precision,
    sugar_alcohols double precision,
    food_grams double precision NOT NULL
);


ALTER TABLE public.food OWNER TO postgres;


CREATE SEQUENCE public."Food_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Food_id_seq" OWNER TO postgres;


ALTER SEQUENCE public."Food_id_seq" OWNED BY public.food.id;



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


CREATE SEQUENCE public."Log_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Log_id_seq" OWNER TO postgres;


ALTER SEQUENCE public."Log_id_seq" OWNED BY public.entry.id;



CREATE TABLE public.measurements (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    type public.measurement NOT NULL,
    value double precision NOT NULL,
    user_id integer NOT NULL
);


ALTER TABLE public.measurements OWNER TO postgres;


COMMENT ON COLUMN public.measurements.value IS 'metric system';



CREATE SEQUENCE public."Measurement_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Measurement_id_seq" OWNER TO postgres;


ALTER SEQUENCE public."Measurement_id_seq" OWNED BY public.measurements.id;



CREATE TABLE public.servings (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    amount double precision NOT NULL,
    unit character varying(255) NOT NULL,
    multiplier double precision NOT NULL,
    food_id integer NOT NULL
);


ALTER TABLE public.servings OWNER TO postgres;


COMMENT ON COLUMN public.servings.multiplier IS 'Multiplier stands for what you have to multiply your values defined in the Food table to achieve the amount of the unit';



CREATE SEQUENCE public."Servings_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."Servings_id_seq" OWNER TO postgres;


ALTER SEQUENCE public."Servings_id_seq" OWNED BY public.servings.id;



CREATE TABLE public.users (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    display_name character varying(255) NOT NULL,
    username character varying(255) NOT NULL,
    password character varying(255) NOT NULL
);


ALTER TABLE public.users OWNER TO postgres;


CREATE SEQUENCE public."User_id_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."User_id_seq" OWNER TO postgres;


ALTER SEQUENCE public."User_id_seq" OWNED BY public.users.id;



CREATE TABLE public.exercise (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255)
);


ALTER TABLE public.exercise OWNER TO postgres;


CREATE TABLE public.exercise_category (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    name character varying(255) NOT NULL,
    description character varying(255)
);


ALTER TABLE public.exercise_category OWNER TO postgres;


CREATE SEQUENCE public.exercise_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.exercise_category_id_seq OWNER TO postgres;


ALTER SEQUENCE public.exercise_category_id_seq OWNED BY public.exercise_category.id;



CREATE TABLE public.exercise_entry (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    exercise_id integer NOT NULL,
    value double precision NOT NULL,
    unit_id integer NOT NULL,
    notes character varying(255)
);


ALTER TABLE public.exercise_entry OWNER TO postgres;


CREATE SEQUENCE public.exercise_entry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.exercise_entry_id_seq OWNER TO postgres;


ALTER SEQUENCE public.exercise_entry_id_seq OWNED BY public.exercise_entry.id;



CREATE TABLE public.exercise_has_category (
    exercise_id integer NOT NULL,
    category_id integer NOT NULL
);


ALTER TABLE public.exercise_has_category OWNER TO postgres;


CREATE SEQUENCE public.exercise_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.exercise_id_seq OWNER TO postgres;


ALTER SEQUENCE public.exercise_id_seq OWNED BY public.exercise.id;



CREATE TABLE public.exercise_unit (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    created_by integer NOT NULL,
    amount double precision NOT NULL,
    unit character varying(255) NOT NULL,
    multiplier double precision NOT NULL,
    exercise_id integer NOT NULL
);


ALTER TABLE public.exercise_unit OWNER TO postgres;


CREATE SEQUENCE public.exercise_value_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.exercise_value_id_seq OWNER TO postgres;


ALTER SEQUENCE public.exercise_value_id_seq OWNED BY public.exercise_unit.id;



CREATE TABLE public.goals (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    target public.goal_targets NOT NULL,
    value double precision NOT NULL,
    created_by integer NOT NULL
);


ALTER TABLE public.goals OWNER TO postgres;


CREATE SEQUENCE public.goals_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.goals_id_seq OWNER TO postgres;


ALTER SEQUENCE public.goals_id_seq OWNED BY public.goals.id;



CREATE TABLE public.note_entry (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    note_id integer NOT NULL,
    created_by integer NOT NULL
);


ALTER TABLE public.note_entry OWNER TO postgres;


CREATE SEQUENCE public.note_entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.note_entries_id_seq OWNER TO postgres;


ALTER SEQUENCE public.note_entries_id_seq OWNED BY public.note_entry.id;



CREATE TABLE public.notes (
    id integer NOT NULL,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    title character varying(255) NOT NULL,
    description character varying(255),
    created_by integer NOT NULL
);


ALTER TABLE public.notes OWNER TO postgres;


CREATE SEQUENCE public.notes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.notes_id_seq OWNER TO postgres;


ALTER SEQUENCE public.notes_id_seq OWNED BY public.notes.id;



ALTER TABLE ONLY public.entry ALTER COLUMN id SET DEFAULT nextval('public."Log_id_seq"'::regclass);



ALTER TABLE ONLY public.exercise ALTER COLUMN id SET DEFAULT nextval('public.exercise_id_seq'::regclass);



ALTER TABLE ONLY public.exercise_category ALTER COLUMN id SET DEFAULT nextval('public.exercise_category_id_seq'::regclass);



ALTER TABLE ONLY public.exercise_entry ALTER COLUMN id SET DEFAULT nextval('public.exercise_entry_id_seq'::regclass);



ALTER TABLE ONLY public.exercise_unit ALTER COLUMN id SET DEFAULT nextval('public.exercise_value_id_seq'::regclass);



ALTER TABLE ONLY public.food ALTER COLUMN id SET DEFAULT nextval('public."Food_id_seq"'::regclass);



ALTER TABLE ONLY public.goals ALTER COLUMN id SET DEFAULT nextval('public.goals_id_seq'::regclass);



ALTER TABLE ONLY public.measurements ALTER COLUMN id SET DEFAULT nextval('public."Measurement_id_seq"'::regclass);



ALTER TABLE ONLY public.note_entry ALTER COLUMN id SET DEFAULT nextval('public.note_entries_id_seq'::regclass);



ALTER TABLE ONLY public.notes ALTER COLUMN id SET DEFAULT nextval('public.notes_id_seq'::regclass);



ALTER TABLE ONLY public.servings ALTER COLUMN id SET DEFAULT nextval('public."Servings_id_seq"'::regclass);



ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public."User_id_seq"'::regclass);



ALTER TABLE ONLY public.food
    ADD CONSTRAINT "Food_pkey" PRIMARY KEY (id);



ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Log_pkey" PRIMARY KEY (id);



ALTER TABLE ONLY public.measurements
    ADD CONSTRAINT "Measurement_pkey" PRIMARY KEY (id);



ALTER TABLE ONLY public.servings
    ADD CONSTRAINT "Servings_pkey" PRIMARY KEY (id);



ALTER TABLE ONLY public.users
    ADD CONSTRAINT "User_pkey" PRIMARY KEY (id);



ALTER TABLE ONLY public.exercise_category
    ADD CONSTRAINT exercise_category_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.exercise_entry
    ADD CONSTRAINT exercise_entry_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.exercise_has_category
    ADD CONSTRAINT exercise_has_category_pkey PRIMARY KEY (exercise_id, category_id);



ALTER TABLE ONLY public.exercise
    ADD CONSTRAINT exercise_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.exercise_unit
    ADD CONSTRAINT exercise_value_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.goals
    ADD CONSTRAINT goals_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.note_entry
    ADD CONSTRAINT note_entries_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.notes
    ADD CONSTRAINT notes_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);



CREATE INDEX entry_index_4 ON public.entry USING btree (created_at);



CREATE INDEX idx_entry_food_id ON public.entry USING btree (food_id);



ALTER TABLE ONLY public.notes
    ADD CONSTRAINT "Created by To User" FOREIGN KEY (created_by) REFERENCES public.users(id) ON UPDATE CASCADE;



ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Entry to Food" FOREIGN KEY (food_id) REFERENCES public.food(id);



ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Entry to Serving" FOREIGN KEY (serving_id) REFERENCES public.servings(id);



ALTER TABLE ONLY public.entry
    ADD CONSTRAINT "Entry to User" FOREIGN KEY (user_id) REFERENCES public.users(id);



ALTER TABLE ONLY public.food
    ADD CONSTRAINT "Food to User" FOREIGN KEY (created_by) REFERENCES public.users(id);



ALTER TABLE ONLY public.measurements
    ADD CONSTRAINT "Measurement_relation_1" FOREIGN KEY (user_id) REFERENCES public.users(id);



ALTER TABLE ONLY public.note_entry
    ADD CONSTRAINT "Note Entries to Note's ID" FOREIGN KEY (id) REFERENCES public.notes(id) ON UPDATE CASCADE;



ALTER TABLE ONLY public.note_entry
    ADD CONSTRAINT "Note Entry to User ID" FOREIGN KEY (created_by) REFERENCES public.users(id) ON UPDATE CASCADE;



ALTER TABLE ONLY public.servings
    ADD CONSTRAINT "Servings to Food" FOREIGN KEY (food_id) REFERENCES public.food(id);



ALTER TABLE ONLY public.servings
    ADD CONSTRAINT "Servings to User" FOREIGN KEY (created_by) REFERENCES public.users(id);



ALTER TABLE ONLY public.exercise_category
    ADD CONSTRAINT exercise_category_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);



ALTER TABLE ONLY public.exercise_entry
    ADD CONSTRAINT exercise_entry_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);



ALTER TABLE ONLY public.exercise_entry
    ADD CONSTRAINT exercise_entry_relation_2 FOREIGN KEY (exercise_id) REFERENCES public.exercise(id);



ALTER TABLE ONLY public.exercise_entry
    ADD CONSTRAINT exercise_entry_relation_3 FOREIGN KEY (unit_id) REFERENCES public.exercise_unit(id);



ALTER TABLE ONLY public.exercise_has_category
    ADD CONSTRAINT exercise_has_category_relation_1 FOREIGN KEY (exercise_id) REFERENCES public.exercise(id);



ALTER TABLE ONLY public.exercise_has_category
    ADD CONSTRAINT exercise_has_category_relation_2 FOREIGN KEY (category_id) REFERENCES public.exercise_category(id);



ALTER TABLE ONLY public.exercise
    ADD CONSTRAINT exercise_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);



ALTER TABLE ONLY public.exercise_unit
    ADD CONSTRAINT exercise_unit_relation_2 FOREIGN KEY (exercise_id) REFERENCES public.exercise(id);



ALTER TABLE ONLY public.exercise_unit
    ADD CONSTRAINT exercise_value_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);



ALTER TABLE ONLY public.goals
    ADD CONSTRAINT goals_relation_1 FOREIGN KEY (created_by) REFERENCES public.users(id);



