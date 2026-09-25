# Setup

Add the repository Actions secret `OPENCODE_API_KEY` before starting the workflow.

The primary model is `opencode/space-bunny-free`. The workflow records available models and uses the approved free fallback chain only for provider errors, rate limits, or unavailable models.

Run a safe key/model probe from the Actions tab with `probe` set to true, or from the command line:

```text
gh workflow run novel-batch --repo <owner/repo> -f probe=true
```

The probe does not write novel files. A successful log contains `MODEL_PROBE_OK`.

After the probe succeeds, run the workflow normally. The first phases create the bible, series outline, ending outline, and the first 10-chapter batch. Later batches read the previous 20 chapters and extend to 30 when the verified context budget allows it.

This is a public repository. Do not commit API keys or other secrets.
