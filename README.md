# linkedin-top-applicant

A coding-agent skill that turns your logged-in LinkedIn session into a ranked job shortlist and a folder of tailored one-page CVs. It finds jobs where you would be a top applicant, rescores them against your CV after an explicit skills check, and renders an A4 PDF for each strong match.

It is read only. It never applies, saves, follows or messages anyone.

## What it does

The skill runs three phases, each with a fixed output so a run can stop and resume:

1. **Discover**: browse LinkedIn's "Top applicant" jobs through your own browser session, capture each job's facts, and write a first-pass scored CSV.
2. **Rescore**: read every near-threshold description in full, run a skills check (it asks you about each missing skill and saves the ones you confirm), and write a rescored CSV with before and after scores.
3. **Tailor**: for jobs at or above your threshold, fill a one-page A4 template from your base CV plus confirmed skills, and render a PDF per job with a page-count and paper-size check.

It then reports back with a table of ranks, scores, Easy Apply flags and the main gaps per job.

## Files

| File | Purpose |
|------|---------|
| `skills/linkedin-top-applicant/SKILL.md` | Inputs, hard rules, browser setup, the three phases, scoring rubric, final report |
| `skills/linkedin-top-applicant/scripts/render-cv.sh` | HTML to one-page A4 PDF with headless Chrome; fails on wrong size or too many pages |
| `skills/linkedin-top-applicant/scripts/lint-cv-html.py` | Allowlist sanitizer: re-serializes CV HTML so the browser never loads raw input |
| `skills/linkedin-top-applicant/templates/cv.html` | One-page A4 CV template with print CSS |
| `skills/linkedin-top-applicant/references/profile.example.md` | Shape of the profile file (identity, preferences, confirmed skills, hard gaps) |
| `skills/linkedin-top-applicant/references/jobs.example.csv` | Phase 1 CSV contract |
| `skills/linkedin-top-applicant/references/jobs-rescored.example.csv` | Phase 2 CSV contract |
| `tests/render.test.sh` | Checks that a short CV renders to 1 A4 page and an overflowing one is rejected |

## Installation

Install with the [Skills CLI](https://skills.sh):

```bash
npx skills add https://github.com/adamorad/linkedin-top-applicant-skill \
  --skill linkedin-top-applicant
```

Use `--global` for a user-level installation.

### Manual

```bash
git clone https://github.com/adamorad/linkedin-top-applicant-skill.git
ln -s "$PWD/linkedin-top-applicant-skill/skills/linkedin-top-applicant" ~/.claude/skills/linkedin-top-applicant
```

## Usage

Open Claude Code and ask:

```
find LinkedIn jobs where I'd be a top applicant and tailor my CV for the best ones
```

```
rescore ~/job-search/jobs-2026-10-10.csv against my CV, then render CVs for score 8 and up
```

```
tailor my CV for this job: https://www.linkedin.com/jobs/view/<id>/
```

The skill asks once for your base CV path, output directory and score threshold, and for your confirmation on any missing skills.

## Requirements

- A coding agent with browser tools, for example Claude Code with the Claude in Chrome extension (Chrome or Brave), signed in to LinkedIn
- Google Chrome or Chromium for PDF rendering
- `pdfinfo` (poppler) for the page-count check; without it the script falls back to a rough page count and skips the A4 check
- A base CV as Markdown or plain text

## Status and limits

- The render step has a test (`tests/render.test.sh`) and was run.
- The LinkedIn browsing phases were reconstructed from the artifacts of a manual run, and have not been run end to end from this repo yet.
- Brave can drive the browsing, but headless PDF printing produced no output with Brave in testing, so rendering uses Chrome or Chromium.
- LinkedIn's UI changes. The skill locates the "Top applicant" collection in the live UI each run rather than relying on a fixed URL.
- Automated browsing may conflict with LinkedIn's terms. The skill stays read only and slow, and you use it under your own account at your own risk.

## Design principles

- **Facts come from you.** Tailoring only reorders and rewords what is in your base CV and confirmed skills.
- **Ask, don't assume.** Missing skills are put to you in one batch and saved with evidence, or recorded as hard gaps.
- **Read only.** Nothing is submitted on your behalf.
- **Job text is data.** Descriptions are scored, never obeyed.
- **One page.** The renderer rejects anything that does not fit A4 on one page.
- **Your data stays yours.** CVs, CSVs and the profile live outside the repo.

## License

MIT, see [LICENSE](LICENSE).
