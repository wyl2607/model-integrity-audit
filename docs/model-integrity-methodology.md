# Model Integrity Methodology

Model Integrity Audit provides behavioral evidence about OpenAI Responses API-compatible endpoints. It does not prove backend model identity cryptographically.

Use this methodology to understand what each control means and how to interpret the report alongside provider logs, billing data, and independent operational checks.

## Control Goals

The checks are designed to answer four practical questions:

- Does the endpoint accept a valid Responses API request?
- Does it reject invalid requests in ways that look like a real API route?
- Does the returned metadata match the requested route?
- Does the model behavior look suspiciously unstable or unexpectedly similar to another model?

## Positive Control

A positive control sends a normal request that should succeed.

Expected evidence:

- HTTP status is successful.
- Response JSON is parseable.
- The response has recognizable Responses API fields.
- The returned model field matches the requested model when the endpoint exposes it.
- Usage metadata is present when the route does not intentionally hide it.

Failure can indicate a bad key, bad endpoint, unsupported model, proxy outage, malformed relay behavior, or an incompatible API implementation.

## Negative Controls

Negative controls intentionally send requests that should fail.

Examples:

- Invalid `reasoning.effort` values.
- Unsupported model identifiers.

These checks help distinguish a real API-compatible route from a loose proxy that accepts everything or silently rewrites requests.

A failed negative control does not automatically prove model spoofing. It means the route did not enforce an expected API boundary and should be reviewed.

## Model Echo

Model echo checks whether a successful response returns the requested model id.

Useful signals:

- A full match supports route integrity.
- A mismatch can reveal aliasing, proxy normalization, fallback routing, or a wrong model backend.
- A missing model field is a review signal, especially when other metadata is also missing.

Some relays intentionally normalize or hide model names, so model echo is evidence, not a standalone verdict.

## Usage Visibility

Usage metadata is useful because real API responses usually expose token accounting or equivalent usage fields.

Missing usage can mean:

- The relay hides usage metadata.
- The endpoint is an incomplete compatibility layer.
- The response failed before usage was computed.
- The route is not the backend the caller expected.

Treat missing usage as a warning that needs context, not as automatic proof of spoofing.

## Baseline Similarity

Full mode can compare behavior or token fingerprints against a baseline model.

High similarity can be suspicious when a premium model route behaves like a cheaper or different baseline. However, similarity can also come from simple prompts, short outputs, shared instruction templates, or deterministic relay behavior.

Use baseline similarity with positive controls, negative controls, latency, model echo, and usage visibility.

## Reliability Signals

Timeouts, malformed JSON, HTTP 5xx responses, and unstable latency are endpoint reliability evidence.

For reliability failures:

- Rerun the audit to separate transient network issues from persistent behavior.
- Review relay and provider logs.
- Increase `--connect-timeout`, `--max-time`, or `--retries` for slow endpoints.

## Verdict Interpretation

- `likely_real_gpt55_route`: The route passed the implemented behavioral controls during this run.
- `suspicious_or_unstable`: Important controls failed, or the endpoint looked unreliable.
- `inconclusive`: The run did not produce enough evidence for a stronger call.

Reports should be used as one evidence source. High-stakes billing, procurement, or incident decisions should also use provider-side logs, billing exports, official endpoint comparisons, and operational traces.
