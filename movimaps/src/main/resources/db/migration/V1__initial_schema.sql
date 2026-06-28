-- V1__initial_schema.sql

-- 1. EXTENSIONES Y ESQUEMAS ESPACIALES
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
CREATE EXTENSION IF NOT EXISTS address_standardizer;
CREATE EXTENSION IF NOT EXISTS address_standardizer_data_us;

CREATE SCHEMA IF NOT EXISTS tiger;
CREATE EXTENSION IF NOT EXISTS postgis_tiger_geocoder WITH SCHEMA tiger;

-- 2. TABLAS BASE
CREATE TABLE public.zona (
    id_zona bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cvegeo character varying(20) UNIQUE,
    nombre character varying(100) NOT NULL,
    tipo_densidad character varying(6) DEFAULT 'MEDIA' NOT NULL,
    ultima_actualizacion timestamp DEFAULT NOW() NOT NULL,
    nivel_seg_tempra numeric(4,2),
    nivel_seg_tarde numeric(4,2),
    nivel_seg_noche numeric(4,2),
    geom public.geometry(MultiPolygon,4326) NOT NULL,
    CONSTRAINT check_zona_tipo_densidad CHECK (tipo_densidad::text = ANY (ARRAY['ALTA', 'MEDIA', 'BAJA']::text[]))
);

-- 1. CREACION DE TIPOS ENUM
CREATE TYPE public.Genero AS ENUM (
    'MASCULINO', 
    'FEMININO', 
    'PREFIERO_NO_DECIR'
);
CREATE TYPE public.RangoEdad AS ENUM (
    'MENOR_DE_EDAD', 
    'RANGO_18_26', 
    'RANGO_27_59', 
    'RANGO_60_MAS'
);
CREATE TABLE public.usuario (
    id_usuario uuid PRIMARY KEY,
    tipo_usuario character varying(17) DEFAULT 'FANTASMA' NOT NULL,
    refresh_token TEXT,
    confianza numeric(5,2) DEFAULT 0 NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    genero public.Genero,
    rango_edad public.RangoEdad,
    email character varying(100),
    zona_id_zona bigint REFERENCES public.zona(id_zona),
    CONSTRAINT check_usuario_tipo_usuario CHECK (tipo_usuario::text = ANY (ARRAY['FANTASMA', 'ANON_PERSISTENTE', 'VERIFICADO']::text[]))
);

CREATE TABLE public.tipo_transporte (
    id_tipo bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo character varying(30) NOT NULL
);

CREATE TABLE public.parada (
    id_parada bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    coord public.geometry(Point,4326) NOT NULL,
    estado character varying(22) DEFAULT 'REPORTADA' NOT NULL,
    confianza numeric(5,2) DEFAULT 0 NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    zona_id_zona bigint REFERENCES public.zona(id_zona),
    CONSTRAINT check_parada_estado CHECK (estado::text = ANY (ARRAY['REPORTADA', 'EN_OBSERVACION', 'CONFIRMADA', 'ALTA_CONFIANZA', 'POSIBLEMENTE_OBSOLETA', 'OBSOLETA']::text[]))
);

CREATE TABLE public.alias_parada (
    id_alias bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre character varying(30) NOT NULL,
    frecuencia_uso bigint DEFAULT 1 NOT NULL,
    estado character varying(9) DEFAULT 'ACTIVO' NOT NULL,
    parada_id_parada bigint NOT NULL REFERENCES public.parada(id_parada),
    usuario_id_usuario uuid NOT NULL REFERENCES public.usuario(id_usuario),
    CONSTRAINT check_alias_parada_estado CHECK (estado::text = ANY (ARRAY['ACTIVO', 'OBSOLETO']::text[]))
);

CREATE TYPE public.tipo_recorrido AS ENUM (
    'PRINCIPAL_IDA',
    'PRINCIPAL_VUELTA',
    'RAMAL_ALTERNO',        -- ej. CTM o UNI (Colosio)
    'TEMPORAL_DESVIO',      -- ej. por tianguis o por un bloque/marcha (tiene fecha)
    'TEMPORAL_PARO'
);

CREATE TABLE public.ruta (
    id_ruta bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre character varying(35) NOT NULL,
    estado character varying(15) DEFAULT 'ACTIVA' NOT NULL,
    confianza_global numeric(7,2) DEFAULT 0 NOT NULL,
    fecha_creacion timestamp with time zone DEFAULT now() NOT NULL,
    tipo_transporte_id_tipo bigint NOT NULL REFERENCES public.tipo_transporte(id_tipo),
    usuario_id_usuario uuid NOT NULL REFERENCES public.usuario(id_usuario),
    geom_polilinea public.geometry(LineString,4326),
    CONSTRAINT check_ruta_estado CHECK (estado::text = ANY (ARRAY['REPORTADA', 'EN OBSERVACION', 'CONFIRMADA', 'OBSOLETA']::text[]))
);

CREATE TABLE public.ruta_recorrido (
    id_recorrido bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ruta_id_ruta bigint NOT NULL REFERENCES public.ruta(id_ruta) ON DELETE CASCADE,
    nombre_recorrido character varying(50) NOT NULL     -- ej. Ida - CTM; Desvio tianguis
    tipo_recorrido public.tipo_recorrido DEFAULT 'PRINCIPAL_IDA' NOT NULL,
    activo boolean DEFAULT true NOT NULL,
    evento_temporal_id_evento bigint REFERENCES public.evento_temporal(id_evento) ON DELETE SET NULL,
    geom_polilinea public.geometry(LineString,4326) NOT NULL
);

ALTER TABLE public.ruta_recorrido 
    ADD CONSTRAINT fk_recorrido_evento FOREIGN KEY (id_evento_temporal) REFERENCES public.evento_temporal(id_evento) ON DELETE SET NULL;

CREATE TABLE public.ruta_parada (
    id_ruta_parada bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    recorrido_id_recorrido bigint NOT NULL REFERENCES public.ruta_recorrido(id_recorrido) ON DELETE CASCADE,
    parada_id_parada bigint NOT NULL REFERENCES public.parada(id_parada) ON DELETE CASCADE,
    orden integer NOT NULL,
    observaciones character varying(45),
    CONSTRAINT unique_recorrdio_orden UNIQUE (recorrido_id_recorrido, orden)
);

CREATE TABLE public.evidencia_visual (
    id_evidencia bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    url_img text NOT NULL,
    tipo character varying(7) DEFAULT 'UNIDAD' NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    confianza numeric(5,2) DEFAULT 0 NOT NULL,
    usuario_id_usuario uuid NOT NULL REFERENCES public.usuario(id_usuario),
    ruta_id_ruta bigint REFERENCES public.ruta(id_ruta) ON DELETE SET NULL,
    parada_id_parada bigint REFERENCES public.parada(id_parada) ON DELETE SET NULL,
    CONSTRAINT check_evidencia_visual_tipo CHECK (tipo::text = ANY (ARRAY['UNIDAD', 'PARADA']::text[])),
    CONSTRAINT check_evidencia_objetivo_puro CHECK (
        (tipo = 'UNIDAD' AND ruta_id_ruta IS NOT NULL AND parada_id_parada IS NULL) OR 
        (tipo = 'PARADA' AND ruta_id_ruta IS NULL AND parada_id_parada IS NOT NULL)
    )
);

CREATE TABLE public.historial_contribucion (
    id_historial bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_contribucion character varying(45) NOT NULL,
    resultado character varying(12) DEFAULT 'CONFIRMADO' NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    usuario_id_usuario uuid NOT NULL REFERENCES public.usuario(id_usuario) ON DELETE CASCADE,
    id_tabla_afectada bigint,
    CONSTRAINT check_historial_contribucion_resultado CHECK (resultado::text = ANY (ARRAY['CONFIRMADO', 'DESCARTADO', 'EN REVISION']::text[]))
);

CREATE TABLE public.horario (
    id_horario bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    frecuencia_valle integer DEFAULT 5 NOT NULL,
    frecuencia_pico integer,
    hora_inicio_aprox time without time zone,
    hora_fin_aprox time without time zone,
    tipo_dia character varying(8) DEFAULT 'L-V',
    ruta_id_ruta bigint NOT NULL REFERENCES public.ruta(id_ruta) ON DELETE CASCADE,
    CONSTRAINT check_horario_orden_horario CHECK (hora_fin_aprox > hora_inicio_aprox),
    CONSTRAINT check_horario_tipo_dia CHECK (tipo_dia::text = ANY (ARRAY['L-V', 'SAB', 'DOM', 'FESTIVO']::text[]))
);

CREATE TABLE public.tarifa_reportada (
    id_tarifa bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_cobro character varying(14) DEFAULT 'FIJO',
    monto_min numeric(6,1),
    monto_max numeric(6,1),
    ultimo_reporte timestamp with time zone DEFAULT now() NOT NULL,
    ruta_id_ruta bigint NOT NULL REFERENCES public.ruta(id_ruta) ON DELETE SET NULL,
    CONSTRAINT check_tipo_cobro CHECK (tipo_cobro::text = ANY (ARRAY['FIJO', 'POR DISTANCIA', 'POR ZONA']::text[]))
);

CREATE TABLE public.evento_temporal (
    id_evento bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo character varying(15) DEFAULT 'BLOQUEO' NOT NULL,
    descripcion character varying(50),
    geom public.geometry(Point,4326) NOT NULL,
    inicio timestamp with time zone DEFAULT now() NOT NULL,
    fin_estimado timestamp with time zone,
    estado character varying(11) DEFAULT 'ACTIVO' NOT NULL,
    confianza numeric(5,2) DEFAULT 0 NOT NULL,
    usuario_id_usuario uuid NOT NULL REFERENCES public.usuario(id_usuario) ON DELETE SET NULL,
    zona_id_zona bigint REFERENCES public.zona(id_zona) ON UPDATE CASCADE ON DELETE SET NULL,
    CONSTRAINT check_eventotmp_estado CHECK (estado::text = ANY (ARRAY['ACTIVO', 'DUDOSO', 'FINALIZADO']::text[])),
    CONSTRAINT check_eventotmp_tipo CHECK (tipo::text = ANY (ARRAY['BLOQUEO', 'MARCHA', 'ACCIDENTE', 'OTRO']::text[]))
);

CREATE TABLE public.canal_externo (
    id_canal bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo character varying(9) DEFAULT 'WHATSAPP' NOT NULL,
    descripcion character varying(30),
    vigencia timestamp with time zone DEFAULT (now() + '3 mons'::interval) NOT NULL,
    estado character varying(23) DEFAULT 'ACTIVO' NOT NULL,
    usuario_id_usuario uuid REFERENCES public.usuario(id_usuario) ON DELETE SET NULL,
    ruta_id_ruta bigint REFERENCES public.ruta(id_ruta) ON DELETE CASCADE,
    zona_id_zona bigint REFERENCES public.zona(id_zona) ON DELETE CASCADE,
    CONSTRAINT check_canal_externo_tipo CHECK (tipo::text = ANY (ARRAY['WHATSAPP', 'TELEGRAM', 'OTRO']::text[])),
    CONSTRAINT check_target_ruta_zona CHECK (ruta_id_ruta IS NOT NULL OR zona_id_zona IS NOT NULL)
);

CREATE TABLE public.historico_evento (
    id_evento bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo character varying(15) DEFAULT 'BLOQUEO' NOT NULL,
    descripcion character varying(30),
    geom public.geometry(Point,4326) NOT NULL,
    fecha_inicio timestamp with time zone NOT NULL,
    fecha_fin_real timestamp with time zone NOT NULL,
    confianza_total numeric(5,2) DEFAULT 0 NOT NULL,
    fuente_principal character varying(12) DEFAULT 'PASIVA' NOT NULL,
    total_reportes bigint DEFAULT 1 NOT NULL,
    CONSTRAINT check_historico_fuente_principal CHECK (fuente_principal::text = ANY (ARRAY['COMUNITARIA', 'PASIVA']::text[])),
    CONSTRAINT check_historico_tipo CHECK (tipo::text = ANY (ARRAY['BLOQUEO', 'MARCHA', 'ACCIDENTE', 'OTRO']::text[]))
);

CREATE TABLE public.reporte (
    id_reporte bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_reporte character varying(20) DEFAULT 'OCUPACION' NOT NULL,
    valor_reportado text, -- ocupacion 'LLENO' o la hora '06:45'
    procesado_por_job boolean DEFAULT false NOT NULL,
    fecha timestamp with time zone DEFAULT now() NOT NULL,
    ruta_id_ruta bigint REFERENCES public.ruta(id_ruta) ON DELETE SET NULL,
    parada_id_parada bigint REFERENCES public.parada(id_parada) ON DELETE SET NULL,
    usuario_id_usuario uuid NOT NULL REFERENCES public.usuario(id_usuario),
    CONSTRAINT check_tipo_reporte CHECK (tipo_reporte::text = ANY (ARRAY['HORARIO ERRONEO', 'OCUPACION', 'UBICACION PARADA']::text[]))
);

-- 3. INDICES

CREATE INDEX idx_evidencia_parada ON public.evidencia_visual (parada_id_parada) WHERE (parada_id_parada IS NOT NULL);
CREATE INDEX idx_evidencia_ruta ON public.evidencia_visual (ruta_id_ruta) WHERE (ruta_id_ruta IS NOT NULL);
CREATE INDEX idx_evidencia_usuario ON public.evidencia_visual (usuario_id_usuario);
CREATE INDEX idx_historial_usuario ON public.historial_contribucion (usuario_id_usuario);
CREATE INDEX idx_horario_ruta ON public.horario (ruta_id_ruta);
CREATE INDEX idx_reporte_job_pendiente ON public.reporte (fecha) WHERE (procesado_por_job IS FALSE);
CREATE INDEX idx_ruta_parada_parada ON public.ruta_parada (parada_id_parada);
CREATE INDEX idx_ruta_parada_ruta ON public.ruta_parada (ruta_id_ruta);

-- INDICES ESPACIALES
CREATE INDEX idx_zona_geom ON public.zona USING GIST (geom);
CREATE INDEX idx_parada_coord ON public.parada USING GIST (coord);
CREATE INDEX idx_recorrido_geom ON public.ruta_recorrido USING GIST (geom_polilinea);
CREATE INDEX idx_evento_geom ON public.evento_temporal USING GIST (geom);
