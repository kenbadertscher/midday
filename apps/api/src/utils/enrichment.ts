/**
 * Customer enrichment is powered by the CompanyEnrich API
 * (packages/customers/src/enrichment/company-enrich.ts), which requires
 * `COMPANY_ENRICH_API_KEY`. Without it `lookupCompany()` returns null before
 * making any request, the job finishes having verified zero fields, and the
 * customer is left with nothing gained.
 *
 * Worse, queueing the job sets `enrichment_status = 'pending'` up front. If no
 * worker is consuming the `customers` queue, the record sits in the UI showing
 * a "Enriching" spinner indefinitely (the spinner is driven purely by that
 * status). So don't start work that cannot finish: check this first.
 */
export function isEnrichmentEnabled(): boolean {
  return Boolean(process.env.COMPANY_ENRICH_API_KEY);
}
