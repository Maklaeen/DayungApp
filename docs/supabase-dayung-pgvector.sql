create extension if not exists vector with schema extensions;

alter table public.dayung_rules
  add column if not exists transportation_assistance boolean default false,
  add column if not exists chapel_assistance boolean default false,
  add column if not exists before_burial_claim_release boolean default false,
  add column if not exists claims_assistance_at_funeral_home boolean default false,
  add column if not exists open_membership boolean default false,
  add column if not exists age_restriction boolean default false,
  add column if not exists barangay_residents_only boolean default false,
  add column if not exists wake_preparation_assistance boolean default false,
  add column if not exists prayer_support boolean default false;

alter table public.user_preferences
  add column if not exists transportation_assistance boolean default false,
  add column if not exists chapel_assistance boolean default false,
  add column if not exists before_burial_claim_release boolean default false,
  add column if not exists claims_assistance_at_funeral_home boolean default false,
  add column if not exists open_membership boolean default false,
  add column if not exists age_restriction boolean default false,
  add column if not exists barangay_residents_only boolean default false,
  add column if not exists wake_preparation_assistance boolean default false,
  add column if not exists prayer_support boolean default false;

alter table public.dayung_rules
  add column if not exists preference_vector extensions.vector(37);

create or replace function public.dayung_rule_preference_vector(
  p_meeting_frequency text,
  p_collection_fee_range text,
  p_membership_payment text,
  p_penalty_payment text,
  p_payment_method text,
  p_open_for_all boolean,
  p_transportation_assistance boolean,
  p_chapel_assistance boolean,
  p_before_burial_claim_release boolean,
  p_claims_assistance_at_funeral_home boolean,
  p_open_membership boolean,
  p_age_restriction boolean,
  p_barangay_residents_only boolean,
  p_wake_preparation_assistance boolean,
  p_prayer_support boolean
)
returns extensions.vector(37)
language sql
immutable
set search_path = public, extensions
as $$
  select (
    '[' || array_to_string(array[
      case when lower(trim(coalesce(p_meeting_frequency, ''))) = 'weekly' then '1' else '0' end,
      case when lower(trim(coalesce(p_meeting_frequency, ''))) = 'monthly' then '1' else '0' end,
      case when lower(trim(coalesce(p_meeting_frequency, ''))) = 'needed' then '1' else '0' end,
      case when lower(trim(coalesce(p_payment_method, ''))) = 'cash' then '1' else '0' end,
      case when lower(trim(coalesce(p_payment_method, ''))) = 'gcash' then '1' else '0' end,
      case when lower(trim(coalesce(p_payment_method, ''))) = 'both' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '50-100' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '100-150' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '150-200' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '200-250' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '250-300' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '300-350' then '1' else '0' end,
      case when lower(trim(coalesce(p_collection_fee_range, ''))) = '400 plus' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '50-100' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '100-150' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '150-200' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '200-250' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '250-300' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '300-350' then '1' else '0' end,
      case when lower(trim(coalesce(p_membership_payment, ''))) = '400 plus' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '50-100' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '100-150' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '150-200' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '200-250' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '250-300' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '300-350' then '1' else '0' end,
      case when lower(trim(coalesce(p_penalty_payment, ''))) = '400 plus' then '1' else '0' end,
      case when coalesce(p_open_for_all, false) then '1' else '0' end,
      case when coalesce(p_transportation_assistance, false) then '1' else '0' end,
      case when coalesce(p_chapel_assistance, false) then '1' else '0' end,
      case when coalesce(p_before_burial_claim_release, false) then '1' else '0' end,
      case when coalesce(p_claims_assistance_at_funeral_home, false) then '1' else '0' end,
      case when coalesce(p_open_membership, false) then '1' else '0' end,
      case when coalesce(p_age_restriction, false) then '1' else '0' end,
      case when coalesce(p_barangay_residents_only, false) then '1' else '0' end,
      case when coalesce(p_wake_preparation_assistance, false) then '1' else '0' end,
      case when coalesce(p_prayer_support, false) then '1' else '0' end
    ], ',') || ']')::extensions.vector(37);
$$;

create or replace function public.set_dayung_rule_preference_vector()
returns trigger
language plpgsql
set search_path = public, extensions
as $$
begin
  new.preference_vector := public.dayung_rule_preference_vector(
    new.meeting_frequency::text,
    new.collection_fee_range::text,
    new.membership_payment::text,
    new.penalty_payment::text,
    new.payment_method::text,
    new.open_for_all,
    new.transportation_assistance,
    new.chapel_assistance,
    new.before_burial_claim_release,
    new.claims_assistance_at_funeral_home,
    new.open_membership,
    new.age_restriction,
    new.barangay_residents_only,
    new.wake_preparation_assistance,
    new.prayer_support
  );
  return new;
end;
$$;

drop trigger if exists dayung_rules_preference_vector on public.dayung_rules;
create trigger dayung_rules_preference_vector
before insert or update of
  meeting_frequency,
  collection_fee_range,
  membership_payment,
  penalty_payment,
  payment_method,
  open_for_all,
  transportation_assistance,
  chapel_assistance,
  before_burial_claim_release,
  claims_assistance_at_funeral_home,
  open_membership,
  age_restriction,
  barangay_residents_only,
  wake_preparation_assistance,
  prayer_support
on public.dayung_rules
for each row
execute function public.set_dayung_rule_preference_vector();

update public.dayung_rules as rules
set preference_vector = public.dayung_rule_preference_vector(
  rules.meeting_frequency::text,
  rules.collection_fee_range::text,
  rules.membership_payment::text,
  rules.penalty_payment::text,
  rules.payment_method::text,
  rules.open_for_all,
  rules.transportation_assistance,
  rules.chapel_assistance,
  rules.before_burial_claim_release,
  rules.claims_assistance_at_funeral_home,
  rules.open_membership,
  rules.age_restriction,
  rules.barangay_residents_only,
  rules.wake_preparation_assistance,
  rules.prayer_support
);

create index if not exists dayung_rules_preference_vector_hnsw_idx
  on public.dayung_rules
  using hnsw (preference_vector extensions.vector_cosine_ops);

create or replace function public.match_dayung_units(
  p_query_vector extensions.vector(37),
  p_selected_count integer,
  p_minimum_score double precision default 0.3,
  p_match_count integer default 1000
)
returns table (recommendation jsonb, final_score double precision)
language sql
stable
security invoker
set search_path = public, extensions
as $$
  with nearest as materialized (
    select
      rules.*,
      units.latitude,
      units.longitude,
      units.barangay,
      units.city,
      units.province,
      1 - (rules.preference_vector <=> p_query_vector) as cosine_similarity,
      -(rules.preference_vector <#> p_query_vector) as matched_selected_count
    from public.dayung_rules as rules
    left join public.dayung_units as units
      on units.id = rules.dayung_unit_id
    where rules.preference_vector is not null
    order by rules.preference_vector <=> p_query_vector
    limit least(greatest(coalesce(p_match_count, 1000), 1), 5000)
  ), scored as (
    select
      nearest.*,
      case
        when p_selected_count <= 0 then 1.0
        else 1.0 + 0.25 * greatest(matched_selected_count, 0) / p_selected_count
      end as match_boost
    from nearest
  )
  select
    jsonb_build_object(
      'id', scored.dayung_unit_id,
      'rule_id', scored.id,
      'dayung_unit_id', scored.dayung_unit_id,
      'dayung_unit_name', scored.dayung_unit_name,
      'name', coalesce(scored.dayung_unit_name, scored.dayung_unit_id::text),
      'meeting_frequency', scored.meeting_frequency,
      'collection_fee_range', scored.collection_fee_range,
      'membership_payment', scored.membership_payment,
      'penalty_payment', scored.penalty_payment,
      'payment_method', scored.payment_method,
      'open_for_all', scored.open_for_all,
      'transportation_assistance', scored.transportation_assistance,
      'chapel_assistance', scored.chapel_assistance,
      'before_burial_claim_release', scored.before_burial_claim_release,
      'claims_assistance_at_funeral_home', scored.claims_assistance_at_funeral_home,
      'open_membership', scored.open_membership,
      'age_restriction', scored.age_restriction,
      'barangay_residents_only', scored.barangay_residents_only,
      'wake_preparation_assistance', scored.wake_preparation_assistance,
      'prayer_support', scored.prayer_support,
      'latitude', scored.latitude,
      'longitude', scored.longitude,
      'barangay', scored.barangay,
      'city', scored.city,
      'province', scored.province,
      '__cosine_similarity', scored.cosine_similarity,
      '__match_boost', scored.match_boost,
      '__score', scored.cosine_similarity * scored.match_boost
    ) as recommendation,
    scored.cosine_similarity * scored.match_boost as final_score
  from scored
  where scored.cosine_similarity is not null
    and scored.cosine_similarity * scored.match_boost >= p_minimum_score
  order by final_score desc, scored.dayung_unit_name asc
  limit least(greatest(coalesce(p_match_count, 1000), 1), 5000);
$$;

revoke all on function public.dayung_rule_preference_vector(
  text, text, text, text, text, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, boolean, boolean, boolean
) from public, anon;
grant execute on function public.dayung_rule_preference_vector(
  text, text, text, text, text, boolean, boolean, boolean, boolean,
  boolean, boolean, boolean, boolean, boolean, boolean
) to authenticated;
revoke all on function public.set_dayung_rule_preference_vector() from public, anon, authenticated;
revoke all on function public.match_dayung_units(
  extensions.vector, integer, double precision, integer
) from public, anon;
grant execute on function public.match_dayung_units(
  extensions.vector, integer, double precision, integer
) to authenticated;