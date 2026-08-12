-- RUN-REC-BRIDGE-001
-- DDL reconstruit et validé HUM.
-- Métadonnées techniques Mistral uniquement.
-- Aucun prompt ni contenu utilisateur.

CREATE TABLE IF NOT EXISTS public.baw_mistral_usage_log (
    id                  bigserial PRIMARY KEY,
    created_at          timestamptz NOT NULL DEFAULT now(),
    model               text NOT NULL,
    prompt_tokens       integer NOT NULL DEFAULT 0 CHECK (prompt_tokens >= 0),
    completion_tokens   integer NOT NULL DEFAULT 0 CHECK (completion_tokens >= 0),
    total_tokens        integer NOT NULL DEFAULT 0 CHECK (total_tokens >= 0),
    contract_status     text NOT NULL CHECK (contract_status IN ('valid', 'invalid')),
    http_status         integer,
    mistral_request_id  text
);

CREATE INDEX IF NOT EXISTS idx_baw_mistral_usage_log_created_at
    ON public.baw_mistral_usage_log (created_at DESC);

COMMENT ON TABLE public.baw_mistral_usage_log IS
    'RUN-REC-BRIDGE-001 — métadonnées techniques Mistral uniquement ; aucun prompt ni contenu utilisateur.';
