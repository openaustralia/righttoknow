# Right To Know

- [Right To Know](#right-to-know)
  - [Development](#development)
  - [Development Environment - Simple Steps](#development-environment---simple-steps)
  - [Seeding test data](#seeding-test-data)
  - [Pro subscriptions](#pro-subscriptions)
    - [Restricting a coupon to a billing interval](#restricting-a-coupon-to-a-billing-interval)
    - [Promotion codes](#promotion-codes)
  - [Contributing](#contributing)
  - [Deployment](#deployment)
    - [Prerequisites](#prerequisites)
    - [Deploy commands](#deploy-commands)
    - [First-time server setup](#first-time-server-setup)
  - [Authorities](#authorities)
    - [Adding new authorities](#adding-new-authorities)
      - [Should an agency be added?](#should-an-agency-be-added)
      - [Format of state name in authority names](#format-of-state-name-in-authority-names)
      - [Request email](#request-email)
      - [Public notes](#public-notes)
      - [Short name](#short-name)
      - [Removing an authority](#removing-an-authority)
    - [Jurisdictions](#jurisdictions)
    - [Categories](#categories)
      - [Federal](#federal)
      - [State and Territory](#state-and-territory)
      - [Local](#local)
    - [Adding more jurisdictions](#adding-more-jurisdictions)

[Right To Know](https://www.righttoknow.org.au/) lets you make and browse
Freedom of Information (FOI) requests in Australia. It is powered by the open
source FOI request platform [Alaveteli](http://www.alaveteli.org/).

This repository contains the the theme package for Alaveteli for the Australian
deployment. If you find a problem with Right to Know, please report it to this
repository's
[issue tracker](https://github.com/openaustralia/righttoknow/issues).

## Development

At present, we [use a fork of Alaveteli](https://github.com/openaustralia/alaveteli) which contains minor changes to the core to support us. Our plan is to transition to using upstream as soon as possible.

To find out which version of Alaveteli a site is currently running, ask the site
rather than this README, which would only go stale:

- Production: <https://www.righttoknow.org.au/version.json>
- Staging: `https://staging.righttoknow.org.au/version.json`

If there is a fix or enhancement that is not specific to Right to Know/Australia changes should be submitted to the upstream [Alaveteli repository](https://github.com/mysociety/alaveteli) via a pull request. In the vast majority of cases we will not deploy a fix until it's been accepted upstream. This ensures we're all using the same code as much as possible.

However if you'd like to adjust the look and feel of Right To Know, or to update copy like that found on the help pages, this is the place to make those changes.

## Development Environment - Simple Steps

We use Docker to create an Alaveteli instance. You can find more information on the [Alaveteli Website](https://alaveteli.org/docs/installing/docker/)

A shortened version:

1. Pull a copy of our [Alaveteli Fork](https://github.com/openaustralia/alaveteli) onto your machine
2. Create a sub-folder at the same level as the Alaveteli folder called `alaveteli-themes`
3. Pull a copy of the Right to Know repository into the `alaveteli-themes` directory.
4. Copy `alaveteli\config\general.yml.example` to `alaveteli\config\general-righttoknow.yml` and modify the file. An exmaple of our current `general.yml` file can be found in the [infrastructure repository](https://github.com/openaustralia/infrastructure/blob/main/roles/internal/righttoknow/templates/general.yml).
5. Continue following the instructions on the [Alaveteli Website](https://alaveteli.org/docs/installing/docker/)

## Seeding test data

[`script/seed_test_data.rb`](script/seed_test_data.rb) fills a development or
test environment with a realistic subset of production data so authority
listings, jurisdiction logic and request states behave like the real site.

It creates:

- A handful of **real authorities** per jurisdiction tag, taken from
  production's public `all-authorities.csv` export (public information only —
  name, tags, URL slug — no request PII). Every seeded authority is given a
  **dummy `@example.com` request email** so the environment can never contact a
  real authority.
- **Dummy requests** per authority spread across a range of statuses, with a
  subset of authorities carrying 3+ `requester_only` (prominence) requests.
- A **browse-by-category taxonomy** synthesised from the jurisdiction tags on
  the imported authorities. This is _not_ a copy of production's own category
  structure — production does not publish its category definitions.

The script refuses to run in `production`.

Run it against the Alaveteli **app** (not this theme repo) with `rails runner`:

```bash
bundle exec rails runner \
  ../alaveteli-themes/righttoknow/script/seed_test_data.rb
```

or inside Docker:

```bash
docker compose run --rm app \
  bundle exec rails runner \
  alaveteli-themes/righttoknow/script/seed_test_data.rb
```

Authorities and the browse-by-category page work immediately. Search and the
request listings are Xapian-backed and will **not** show seeded data until the
index is updated — either re-run with `SEED_REBUILD_INDEX=1`, or run:

```bash
bundle exec rake xapian:destroy_and_rebuild_index \
  models="PublicBody User InfoRequestEvent"
```

Optional environment variables:

| Variable              | Purpose                                                                                                          |
| --------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `SEED_CSV_URL`        | Override the production authorities CSV URL.                                                                     |
| `SEED_CSV_PATH`       | Read authorities from a local CSV instead of fetching (handy offline; expects the `all-authorities.csv` format). |
| `SEED_BODIES_PER_TAG` | Number of authorities per jurisdiction tag (default `5`).                                                        |
| `SEED_REBUILD_INDEX`  | Set to `1` to update the Xapian index at the end so seeded data shows up in search and request listings.         |

The script is idempotent: re-running it reuses existing authorities and
categories and won't stack additional seeded requests onto authorities that
already have them.

## Pro subscriptions

### Restricting a coupon to a billing interval

Stripe coupons can only be limited to a **product**, not to an individual
**price**. Because the Pro monthly and annual plans are two prices under one
product, Stripe's own `applies_to` restriction cannot stop a coupon from
discounting both. Some coupons are meant for a single plan (for example, a
monthly-only referral coupon).

The theme enforces a per-interval restriction itself, driven by coupon
**metadata** so the rule lives with the coupon in Stripe (no code change or
deploy needed to add or adjust restricted coupons):

- Add a metadata key `interval` to the coupon in the Stripe dashboard, set to
  the billing interval the coupon is allowed on: `day`, `week`, `month` or
  `year`. A monthly-only coupon takes `interval` = `month`.
- A coupon **without** an `interval` metadata key is unrestricted and applies to
  any plan, exactly as before.

With `interval` set, [`lib/controller_patches.rb`](lib/controller_patches.rb)
blocks the coupon at checkout on a non-matching plan (before any subscription is
created) and the live plan-page price preview refuses it too, so a discount is
never advertised that checkout would then reject.

For extra defence-in-depth you can also set the coupon's native `applies_to`
products to the Pro product; this stops it discounting any other product, though
it still can't separate monthly from annual.

### Promotion codes

The "Do you have a coupon code?" field on the plan page accepts a Stripe
**promotion code** as well as a coupon id. A promotion code is a customer-facing
string pointing at a coupon, and it carries restrictions a coupon cannot express:
a redemption cap for that code alone, first-time subscribers only, and an expiry
independent of the coupon's. Many codes can share one coupon, so a campaign can
be tracked and retired without touching the discount itself.

To add one, open the coupon in the Stripe dashboard and create a promotion code
against it.

Two things differ from coupons:

- **Promotion codes are not namespaced.** Coupon ids are prefixed with
  `STRIPE_NAMESPACE` (a typed `FOO` looks up the coupon `RTK-FOO`), but a
  promotion code is matched exactly as typed. Create the code as the string you
  want people to type.
- **Coupons win a collision.** A typed code is looked up as a coupon first, then
  as a promotion code, so a coupon `RTK-FOO` takes precedence over a promotion
  code `FOO`. Avoid using the same string for both.

Only **active** promotion codes resolve. Stripe deactivates a code when it
expires or hits its redemption cap, and a deactivated code reads as invalid
rather than expired.

Who enforces what:

| Restriction | Enforced by |
| --- | --- |
| `max_redemptions`, `expires_at`, per-customer | Stripe, on redemption |
| `first_time_transaction` | Stripe, plus a check here before any charge |
| `minimum_amount` | Stripe, plus a check here before any charge |
| `interval` metadata (see above) | This theme |

A `minimum_amount` is compared against the plan price **before tax and before
the discount**, so a $10 monthly plan meets a minimum of 1000 but not 1050. A
minimum set only in another currency is treated as unmeetable.

The `interval` and `humanized_terms` metadata keys are read from the underlying
coupon. You can override either on the promotion code's own metadata, so one
coupon can back several codes that describe themselves differently.

## Contributing

If you want to modify the customised look and feel of Right To Know then you
should edit this repository however if it's something more general you probably
want to edit the upstream
[core Alaveteli software](https://github.com/mysociety/alaveteli/).

To contribute an enhancement or a fix to this theme:

- Fork the project on GitHub.
- Make a topic branch from the `staging` branch.
- Make your changes and test.
- Commit the changes without making changes to any files that aren't related to your enhancement or fix.
- Send a pull request against the `staging` branch.

## Deployment

The application is deployed using [Capistrano 3](https://capistranorb.com/). Deployment is run from this repository against the [alaveteli](https://github.com/openaustralia/alaveteli) codebase.

### Prerequisites

Capistrano looks up the EC2 deploy targets dynamically by their `Application` and `Stage` tags
and tunnels SSH through [AWS SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
rather than connecting to a public hostname, so you need:

- The [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  and the [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
  installed
- An AWS profile named `oaf` with permission to describe EC2 instances and start SSM sessions
- An SSH key for the `deploy` user (SSH still runs as normal inside the SSM tunnel). If your
  key isn't picked up by default, add a `Host i-*` entry with `IdentityFile` to `~/.ssh/config`
- Gems installed: `bundle install --with deployment`
- The server must have `shared/rbenv-version`, `shared/general.yml`, and all other shared files in place (managed by the [infrastructure repo](https://github.com/openaustralia/infrastructure))

To check which instances a stage will deploy to:

```bash
bundle exec cap staging aws:ec2:instances
```

### Deploy commands

Deploy to staging:

```bash
bundle exec cap staging deploy
```

Deploy to production:

```bash
bundle exec cap production deploy
```

Run database migrations only (maintenance page shown automatically):

```bash
bundle exec cap staging deploy:migrate
bundle exec cap production deploy:migrate
```

Restart the application without deploying:

```bash
bundle exec cap staging deploy:restart
bundle exec cap production deploy:restart
```

Rebuild the Xapian search index:

```bash
bundle exec cap staging xapian:destroy_and_rebuild_index
bundle exec cap production xapian:destroy_and_rebuild_index
```

### First-time server setup

After the [infrastructure repo](https://github.com/openaustralia/infrastructure) has provisioned the host, the shared path needs the config files in place before the first deploy. The deploy itself auto-creates any missing shared directories (cache, logs, storage, xapian indexes, vendored bundle, etc.) on each run via `deploy:check_shared`.

One-time bootstrap per server:

1. Ensure `<deploy_to>/shared/` exists (`ssh deploy@<host> 'mkdir -p <deploy_to>/shared'`).
2. Place the shared config files at the **top level of `shared/`** (basename only, not under `shared/config/`). The expected files — drawn from `SHARED_FILES` in `alaveteli/config/general-righttoknow.yml` — are:
   - `general.yml`
   - `database.yml`
   - `sidekiq.yml`
   - `storage.yml`
   - `user_spam_scorer.yml`
   - `rails_env.rb`
   - `newrelic.yml`
   - `foi-live-creation.png`
   - `foi-user-use.png`
   - `rbenv-version`
3. Run the first deploy: `bundle exec cap <stage> deploy`.

`deploy:check_shared` runs at the start of every deploy and fails fast if any required file is missing.

### whatismyip trust-boundary check

`GET /whatismyip` reports the IP Rails sees for the request, to aid in checking cloudflare proxying
with a one-line curl rather than a real sign-in or a log dig. It returns the IP, or the IP plus
` FAIL` if that IP falls within Cloudflare's own published ranges - a sign the trust boundary isn't rewriting
it to the real visitor IP.

It should report the same value as https://whatismyip.akamai.com/

Off by default; set `PROVIDE_WHATISMYIP: true` in `general.yml` to turn it on.

```bash
curl https://staging.righttoknow.org.au/whatismyip
curl https://www.righttoknow.org.au/whatismyip
```

## Authorities

### Adding new authorities

#### Should an agency be added?

Not everything that the government considers to be a distinct agency is an
entity that people actually want to make requests to. It is very much a
subjective call, but always try and make the site most useful to the people who
use it. If there is a lot of unnecessary sub-division authorities for example,
requests will be more difficult to find in the site. Try to avoid this.
For example, the IT division or the head office of an agency are probably
just part of the agency itself for the purpose of information requests.

If a sub-department agency has a distinct office, it’s own website and
information request email address, and does stuff that people would want to make
requests about, it should probably be a distinct authority in Right To Know.

If in doubt, ask the team.

#### Format of state name in authority names

For state authorities often the name of the state appears in the name of the authority.

On the [_Art Gallery of NSW_ website](http://www.artgallery.nsw.gov.au/about-us/) they refer to their own name in three different forms: _Art Gallery NSW_, _Art Gallery of New South Wales_, and _Art Gallery of NSW_. We're currently using [_Art Gallery of NSW_](https://www.righttoknow.org.au/body/agnsw) because it is commonly used, succinct, and searchable. Therefore if the name of the state is in the name of the authority, use the form they use or the form in most common use.

When you need to choose, use real acronyms (NSW, ACT, WA, SA, NT) but not contractions (use Victoria, Tasmania, and Queensland, not VIC, TAS, or QLD).

#### Request email

When collecting the email address that requests to the authority are sent to, we need to find the
best address to deal with them directly. A specific address for the authority
isn’t always available, especially when they exist within a bigger department.
This is the order of preference for the authority’s request email:

1. Specific FOI address for sub-department agency (e.g.
   <foi@special_agency.gov.au>)
2. Specific address for sub-department agency at department (e.g.
   <special_agency@department.gov.au>)
3. Specific FOI address for department (e.g. <foi@department.gov.au>)
4. Generic address for department (e.g. <info@department.gov.au>)
5. Address for a specific person at the agency (e.g. <jane.zhang@dept.gov.au>)

A person’s address is the absolute last resort.

#### Public notes

You can add public notes about the authority. The notes are displayed on
the authority’s page, as an excerpt in lists of authorities, and as a highlighted
notice when someone makes a request to the authority. They are covered in the site search.

The note could include important information about requesting from this
department, key terms people might use when searching for the agency, and a
basic description of the authority. For example:

> HomeStart was created by the South Australian Government in 1989,
> as a response to high interest rates and a lack of affordable home loan
> finance options. HomeStart was established as a statutory corporation under
> the Housing and Urban Development (Administrative Arrangements) Act 1995 and
> reports to the Minister for Housing and Urban Development.

#### Short name

You can add abbreviated version of the authority’s name as it’s _short name_.
These are really useful because the common name for an agency might not be it’s
full formal name. For example, people commonly search “ABS” when looking for
the “Australian Bureau of Statistics”.

It’s very important to only add acronyms or abbreviations that people _really_ do use.
These are displayed on authority pages and lists of authorities, and having lots
of irrelevant short names adds unnecessary noise to the page.

#### Removing an authority

Authorities that are defunct aren’t actually removed from Right To Know.
Add the `defunct` tag to the authority and it will no longer be available for requests.
People can still find requests to the authority in search results and see all
the requests that were made to them while they were active.

### Jurisdictions

A unique aspect of Right To Know compared to other Alaveteli installations is
that we're in the process of supporting 9 different jurisdictions - Federal and
all the states and territories.

We have customisations in this theme to adjust the length of time authorities
have to respond to a request and the law names depending on what jurisdiction
an authority is covered by. These customisations rely on the use of Alaveteli's
tags to work out what jurisdiction an authority is covered by.

The table below show what tag you need to use for each jurisdiction. Don't
forget to also add the appropriate category tag, described in the section
below, for the authority you're adding.

| Jurisdiction | Tag       |
| ------------ | --------- |
| Federal      | `federal` |
| ACT          | `ACT`     |
| NSW          | `NSW`     |
| NT           | `NT`      |
| QLD          | `QLD`     |
| SA           | `SA`      |
| TAS          | `TAS`     |
| VIC          | `VIC`     |
| WA           | `WA`      |

### Categories

Public authority categories are configured in the Alaveteli admin interface.
This how we want Right To Know's categories organised:

#### Federal

| Title                                   | Description                                                   | Tag                                       |
| --------------------------------------- | ------------------------------------------------------------- | ----------------------------------------- |
| Agriculture                             | part of the Agriculture portfolio                             | `agriculture`                             |
| Attorney-General                        | part of the Attorney-General portfolio                        | `attorney_general`                        |
| Communications                          | part of the Communications portfolio                          | `communications`                          |
| Defence                                 | part of the Defence portfolio                                 | `defence`                                 |
| Education and Training                  | part of the Education and Training portfolio                  | `education_and_training`                  |
| Employment                              | part of the Employment portfolio                              | `employment`                              |
| Environment                             | part of the Environment portfolio                             | `environment`                             |
| Finance                                 | part of the Finance portfolio                                 | `finance`                                 |
| Foreign Affairs and Trade               | part of the Foreign Affairs and Trade portfolio               | `foreign_affairs_and_trade`               |
| Health                                  | part of the Health portfolio                                  | `health`                                  |
| Immigration & Border Protection         | part of the Immigration & Border Protection portfolio         | `immigration_and_border_protection`       |
| Industry and Science                    | part of the Industry and Science portfolio                    | `industry_and_science`                    |
| Infrastructure and Regional Development | part of the Infrastructure and Regional Development portfolio | `infrastructure_and_regional_development` |
| Prime Minister                          | part of the Prime Minister portfolio                          | `prime_minister`                          |
| Social Services                         | part of the Social Services portfolio                         | `social_services`                         |
| Treasury                                | part of the Treasury portfolio                                | `treasury`                                |
| Veterans' Affairs                       | part of the Veterans' Affairs portfolio                       | `veterans_affairs`                        |
| All Federal authorities                 | a Federal authority                                           | `federal`                                 |

#### State and Territory

| Title              | Description                    | Tag         |
| ------------------ | ------------------------------ | ----------- |
| ACT                | an ACT authority               | `ACT_state` |
| New South Wales    | a NSW authority                | `NSW_state` |
| Northern Territory | a Northern Territory authority | `NT_state`  |
| Queensland         | a Queensland authority         | `QLD_state` |
| South Australia    | a South Australian authority   | `SA_state`  |
| Tasmania           | a Tasmanian authority          | `TAS_state` |
| Victoria           | a Victorian authority          | `VIC_state` |
| Western Australia  | a Western Australian authority | `WA_state`  |

#### Local

| Title              | Description                  | Tag           |
| ------------------ | ---------------------------- | ------------- |
| New South Wales    | a NSW Council                | `NSW_council` |
| Northern Territory | a Northern Territory Council | `NT_council`  |
| Queensland         | a Queensland Council         | `QLD_council` |
| South Australia    | a South Australian Council   | `SA_council`  |
| Tasmania           | a Tasmanian Council          | `TAS_council` |
| Victoria           | a Victorian Council          | `VIC_council` |
| Western Australia  | a Western Australian Council | `WA_council`  |

### Adding more jurisdictions

When adding authorities for jurisdictions we don't yet cover we need to:

- Update help and other text:
  - [https://www.righttoknow.org.au/help/unhappy#complaining](https://github.com/openaustralia/righttoknow/blob/338b2d26891b81f326fb5e4dda9a26861f01d2d5/lib/views/help/unhappy.html.erb#L58-L67)
  - [https://www.righttoknow.org.au/help/requesting#missing_body](https://github.com/openaustralia/righttoknow/blob/338b2d26891b81f326fb5e4dda9a26861f01d2d5/lib/views/help/requesting.html.erb#L59-L70)
  - [https://www.righttoknow.org.au/help/requesting#ico_help](https://github.com/openaustralia/righttoknow/blob/338b2d26891b81f326fb5e4dda9a26861f01d2d5/lib/views/help/requesting.html.erb#L265-L287)
  - [https://www.righttoknow.org.au/body/list/all](https://github.com/openaustralia/righttoknow/blob/338b2d26891b81f326fb5e4dda9a26861f01d2d5/lib/views/public_body/_list_sidebar_extra.html.erb#L1-L3)
- Upload the new authorities (with the correct tags, see above)
- Add categories (see above)

This project is tested with [BrowserStack](https://email.browserstack.com/c/eJwkyDtywyAQANDTmA4GMN-Cs2RW7K7NyBIRSFGOnyLtw-IXj1FQMTHoYKwNSbyLjcnTM9pcvdOBjKWYELJlHWMmH0UrIbGuDPDMkeHLVPZGa2dtMM44NRvS2g7Jg46L9lMyyu-O1ySYp5EbtN3L1yDaZfIZcwjOL3Ku-Hs8nKYN2kfxoPlGmquqfROfct-3Wka_J415Qv3nURbaH053YNXHS8Elfor9CwAA__9z00N9)
