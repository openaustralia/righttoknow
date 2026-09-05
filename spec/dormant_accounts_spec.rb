# frozen_string_literal: true

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

RSpec.describe DormantAccounts do
  # The host loads spec/fixtures/users.yml globally, and those fixtures include
  # accounts that legitimately fall in this cohort (`unconfirmed_user` was
  # created in 2007). So these examples assert on the records they create
  # rather than on absolute counts.
  let(:out) { StringIO.new }

  let!(:dormant_unconfirmed) do
    FactoryBot.create(:user, :unconfirmed, created_at: 3.years.ago)
  end

  before do
    # `User.unused` creates the CONTACT_EMAIL account if it is missing, so
    # reference it up front and keep that side effect out of the examples.
    User.internal_admin_user
  end

  describe '.scope' do
    subject { described_class.scope }

    it 'includes a content-free confirmed account over two years old' do
      user = FactoryBot.create(:user, created_at: 3.years.ago)
      is_expected.to include(user)
    end

    it 'includes a content-free never-confirmed account over two years old' do
      is_expected.to include(dormant_unconfirmed)
    end

    it 'excludes an account created within the last two years' do
      user = FactoryBot.create(:user, :unconfirmed, created_at: 1.year.ago)
      is_expected.not_to include(user)
    end

    it 'excludes an account that signed in within the last two years' do
      user = FactoryBot.create(:user, :unconfirmed, created_at: 3.years.ago,
                                                    last_sign_in_at: 1.year.ago)
      is_expected.not_to include(user)
    end

    it 'excludes an account with a retained sign-in record' do
      # Inserted rather than built through the factory: this environment sets
      # USER_SIGN_IN_ACTIVITY_RETENTION_DAYS to 0, so User::SignIn's
      # before_create aborts and the factory can never save a row. The scope
      # reads the table, so a directly inserted row is the real thing.
      now = Time.zone.now
      User::SignIn.insert_all(
        [{ user_id: dormant_unconfirmed.id, created_at: now, updated_at: now }]
      )

      is_expected.not_to include(dormant_unconfirmed)
    end

    # One example only, to prove the scope delegates to User.unused. The host's
    # spec/models/user/unused_spec.rb covers the rest of its conditions.
    it 'excludes an account that has made a request' do
      dormant_unconfirmed.update_columns(info_requests_count: 1)
      is_expected.not_to include(dormant_unconfirmed)
    end

    it 'excludes the internal admin account' do
      is_expected.not_to include(User.internal_admin_user)
    end
  end

  describe '.never_confirmed' do
    subject { described_class.never_confirmed }

    it 'includes a never-confirmed account in the cohort' do
      is_expected.to include(dormant_unconfirmed)
    end

    it 'excludes a confirmed account in the cohort' do
      confirmed = FactoryBot.create(:user, created_at: 3.years.ago)
      is_expected.not_to include(confirmed)
    end
  end

  describe '.destroy_never_confirmed' do
    context 'by default' do
      it 'destroys nothing' do
        described_class.destroy_never_confirmed(out: out)
        expect(User.exists?(dormant_unconfirmed.id)).to eq(true)
      end

      it 'lists the account it would destroy' do
        described_class.destroy_never_confirmed(out: out)
        expect(out.string).to include(
          "#{dormant_unconfirmed.id}\t#{dormant_unconfirmed.created_at.iso8601}"
        )
        expect(out.string).to match(/DRY RUN: would destroy \d+ never-confirmed/)
      end

      it 'does not list a confirmed account in the cohort' do
        confirmed = FactoryBot.create(:user, created_at: 3.years.ago)
        described_class.destroy_never_confirmed(out: out)
        expect(out.string).not_to match(/^#{confirmed.id}\t/)
      end

      it 'does not print personal details' do
        described_class.destroy_never_confirmed(out: out)
        expect(out.string).not_to include(dormant_unconfirmed.email)
        expect(out.string).not_to include(dormant_unconfirmed.name)
      end
    end

    context 'when DRYRUN is off' do
      it 'destroys the never-confirmed account' do
        described_class.destroy_never_confirmed(dryrun: false, out: out)
        expect(User.exists?(dormant_unconfirmed.id)).to eq(false)
      end

      it 'reports how many it destroyed' do
        described_class.destroy_never_confirmed(dryrun: false, out: out)
        expect(out.string).to match(/Destroyed \d+ never-confirmed accounts/)
      end

      it 'keeps a confirmed account in the cohort' do
        confirmed = FactoryBot.create(:user, created_at: 3.years.ago)
        described_class.destroy_never_confirmed(dryrun: false, out: out)
        expect(User.exists?(confirmed.id)).to eq(true)
      end

      it 'keeps a never-confirmed account created within two years' do
        recent = FactoryBot.create(:user, :unconfirmed, created_at: 1.year.ago)
        described_class.destroy_never_confirmed(dryrun: false, out: out)
        expect(User.exists?(recent.id)).to eq(true)
      end

      it 'keeps a never-confirmed account that has content' do
        dormant_unconfirmed.update_columns(comments_count: 1)
        described_class.destroy_never_confirmed(dryrun: false, out: out)
        expect(User.exists?(dormant_unconfirmed.id)).to eq(true)
      end

      it 'clears inbound TrackThing references before destroying' do
        # Built directly rather than with the :user_track factory, whose own
        # after(:create) hook raises NameError in the host app.
        track = TrackThing.create!(
          track_type: 'user_updates',
          track_query: 'requested_by:example',
          track_medium: 'email_daily',
          tracking_user: FactoryBot.create(:user, created_at: 1.day.ago),
          tracked_user: dormant_unconfirmed
        )

        described_class.destroy_never_confirmed(dryrun: false, out: out)

        expect(track.reload.tracked_user_id).to be_nil
        expect(User.exists?(dormant_unconfirmed.id)).to eq(false)
      end
    end

    context 'with a limit' do
      before do
        Array.new(2) do
          FactoryBot.create(:user, :unconfirmed, created_at: 3.years.ago)
        end
      end

      it 'destroys exactly the limit, not the whole cohort' do
        expect { described_class.destroy_never_confirmed(dryrun: false, limit: 2, out: out) }
          .to change { described_class.never_confirmed.count }.by(-2)
      end

      it 'lists only the accounts within the limit' do
        described_class.destroy_never_confirmed(limit: 2, out: out)
        expect(out.string.lines.grep(/\t/).size).to eq(2)
      end
    end
  end
end
