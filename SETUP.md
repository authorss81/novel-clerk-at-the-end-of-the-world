# Setup

Add the repository Actions secret `OPENCODE_API_KEY` before starting the workflow.

The primary model is `opencode/space-bunny-free`. The workflow records available models and uses the approved free fallback chain only for provider errors, rate limits, or unavailable models.

Run the workflow manually from Actions after the secret is configured. The first phases create the bible, series outline, ending outline, and the first 10-chapter batch.

This is a public repository. Do not commit API keys or other secrets.