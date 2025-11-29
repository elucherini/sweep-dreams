# gh-actions-etl
A demonstration of a lightweight ETL with GitHub Actions.

## Introduction

GitHub Actions provide a free/cheap and familiar setup to orchestrate ETLs for small project. This repo is a template for a simple ETL (Extract-Tranform-Load) pipeline collecting data from the [San Francisco Open Data](https://datasf.org/opendata/) project. The GitHub Actions included read and lightly parse data about San Francisco addresses, then they store it into two data sinks:

- GitHub Artifacts: the processed data is stored as a CSV file in GitHub; for the right amount of data, you don't need an external storage solution.
- External DB: stored into a Postgres DB. In this demo, I chose Supabase for its ease of use.

## Motivation

Most data pipelines process small data.

Manual runs and cron are solid choices when you're just starting to develop your ETL pipeline. But if you are looking for more flexibility for automating the process, the setup complexity can quickly become overwhelming. Airflow, for instance, is notorious for its steep setup curve. Alternatives like Prefect aim at bridging that gap -- but if your priority is to get something up and running quickly and you are working with small data, GitHub Actions might be your best option.

GitHub Actions offer a reasonably flexible and straightforward solution to set up an ETL pipeline, especially if your computing and memory requirements are low. If you don't care about the limited capacity and retention, you might even be able to  store in GitHub itself.

## Demo setup

- Create a new repo and use this one as a template.
- Navigate to Actions. You'll see two workflows: ETL to CSV and ETL to Supabase.

### GitHub Artifacts as the data sink

No further setup is necessary. To run immediately, click on ETL to CSV > Re-run all jobs. 

By default, the ETL runs every day at 2 a.m. UTC. It also runs whenever you push to the repo (for debugging purposes), or whenever you manually trigger it. To disable any of these behaviors, comment out the relevant portion of `.github/workflows/etl_to_csv.yml`:

```yaml
# Workflow triggers
on:
  schedule:  # Comment me and the next line out to disable scheduling
    - cron: "0 2 * * *" 
  workflow_dispatch:  # Comment me out to disable manual triggering
  push:  # Comment me and the next 2 lines out to disable triggering at push
    branches:
      - 'main'
```

### External DB as the data sink

You can use this template with any externally hosted DB. To run the GitHub action as is, you'll have to create and connect Supabase database. 

#### Create a table with Supabase

[Sign up on Supabase](https://supabase.com/dashboard/sign-up) and follow the instructions to create an organization and a project.

Then, open the SQL Editor and create a table by running the following statement:

```sql
CREATE TABLE sf_addresses (
    eas_fullid TEXT PRIMARY KEY,
    address TEXT NOT NULL,
    zip TEXT NOT NULL,
    latitude FLOAT NOT NULL,
    longitude FLOAT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT (now() AT TIME ZONE 'utc'::text)
);
```

Check that your table has been created successfully by querying it, or navigating to the Table Editor.

#### Connect GitHub Actions to your supabase DB

You'll want to add `SUPABASE_KEY` and `SUPABASE_URL` to your [GitHub secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-a-repository). You can obtain them from your Supabase Home page, scrolling down to Project API.

To add them to your repo, navigate to your GitHub repo > Settings > under Security: Secrets and Variables > Actions. Click on New repository secret and add the two secrets, making sure to name them *exactly* `SUPABASE_URL` and `SUPABASE_KEY`.


#### Run the GitHub action

Now you can run your action: click on ETL to supabase > Re-run all jobs. 

By default, the ETL runs every day at 2 a.m. UTC. It also runs whenever you push to the repo (for debugging purposes), or whenever you manually trigger it. To disable any of these behaviors, comment out the relevant portion of `.github/workflows/etl_to_supabase.yml`. See the [GitHub Artifacts setup](#github-artifacts-as-the-data-sink) for more details on how to change this file.

## Considerations

This workflow is a great starter option, but it has several scalability limits.

### Compute limitations

At the time of this writing, the [Free tier](https://docs.github.com/en/actions/using-github-hosted-runners/using-github-hosted-runners/about-github-hosted-runners#standard-github-hosted-runners-for-public-repositories) will get your public repo a 4-core Linux machine with 16 GB of RAM and 16 GB of SSD storage. The default GitHub-hosted runner does not allow you to run large-scale distributed workflows. [Larger runners](https://docs.github.com/en/actions/using-github-hosted-runners/using-larger-runners) are available at a cost. Self-hosting compute is an option, too, but at that point you might want to consider alternatives.

Keep in mind the [extra usage limits](https://docs.github.com/en/actions/administering-github-actions/usage-limits-billing-and-administration#usage-limits), too.

### Storage limitations

If you want to go the GitHub Artifacts route, you should consider storage and retention limitations. At the time of writing, the GitHub Free tier has a [storage limitation](https://docs.github.com/en/billing/managing-billing-for-your-products/managing-billing-for-github-actions/about-billing-for-github-actions#included-storage-and-minutes) of 500 MB per repo, which includes all Actions and Packages.

The [retention policy](https://docs.github.com/en/actions/administering-github-actions/usage-limits-billing-and-administration#artifact-and-log-retention-policy) is also quite strict: a maximum of 90 days for public repos, or 400 for private repos. Be sure to check that your retention policy is set to the maximum, if this is important to you.
