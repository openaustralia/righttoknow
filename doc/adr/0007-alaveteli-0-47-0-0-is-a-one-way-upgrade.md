# Alaveteli 0.47.0.0 is a one-way upgrade

Alaveteli 0.47.0.0 encrypts sensitive database columns (users' two factor
authentication secrets and backup codes) with Active Record Encryption, reading
its keys from `config/master.key` and `config/credentials.yml.enc`. Upstream
says rolling back to 0.46.8.0 is unsupported once the secrets are encrypted with
`temp:encrypt_user_otp_secret_keys`: it breaks two factor sign in for people who
enrolled on this release, and for every account once the task has run. Every
account gets a secret when it is created, even with `ENABLE_TWO_FACTOR_AUTH`
off, so the task covers everyone.

We could have deployed, soaked for a week and encrypted afterwards, keeping
rollback possible meanwhile. We chose to run the task at deploy time instead,
for a simpler runbook, and accept that there is no rollback from the first day.

What that commits us to:

- **The recovery route is an RDS snapshot** taken immediately before the
  production deploy, plus redeploying the previous release. Nothing else undoes
  the encryption.
- **The key and credentials file are the single point of failure.** Without
  `config/master.key` and `config/credentials.yml.enc` the encrypted columns
  cannot be read. Each environment gets its own pair, kept in Ansible vault in
  the `infrastructure` repository (as for Planning Alerts and They Vote for You)
  and written to `shared/` by the Right to Know role. They are generated once
  and never regenerated on a server.
- **Staging rehearses the exact mechanism** on its own data, including the
  encrypt task and a sign in afterwards, and production waits for a week with no
  new errors.
- **Two factor authentication stays off** (`ENABLE_TWO_FACTOR_AUTH` false) at
  this release. Enabling it is separate work.

The plan and checklist are tracked in openaustralia/righttoknow#1195.

_Decided 2026-11-27._
