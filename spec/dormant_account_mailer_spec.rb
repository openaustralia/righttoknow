# frozen_string_literal: true

# If defined, ALAVETELI_TEST_THEME will be loaded in config/initializers/theme_loader
ALAVETELI_TEST_THEME = 'righttoknow'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'spec', 'spec_helper'))

RSpec.describe DormantAccountMailer, '#notice' do
  # The host loads spec/fixtures/users.yml globally, and some of those accounts
  # fall in this cohort, so these examples assert on the records they create
  # rather than on absolute counts.
  let(:out) { StringIO.new }
  let(:removal_date) { Date.new(2026, 11, 2) }

  let!(:dormant) { FactoryBot.create(:user, created_at: 3.years.ago) }

  before do
    # `User.unused` creates the CONTACT_EMAIL account if it is missing, so
    # reference it up front and keep that side effect out of the examples.
    User.internal_admin_user
  end

  describe '#notice' do
    subject(:mail) { described_class.notice(dormant, removal_date) }

    it 'is addressed to the account holder' do
      expect(mail.to).to eq([dormant.email])
    end

    it 'returns bounces to the blackhole address, so they can be recorded' do
      expect(mail['Return-Path'].to_s).to include(
        AlaveteliConfiguration.blackhole_prefix
      )
    end

    it 'sends replies to the contact address' do
      expect(mail['Reply-To'].to_s).to include(
        AlaveteliConfiguration.contact_email
      )
    end

    it 'marks itself auto-generated and suppresses out of office replies' do
      expect(mail['Auto-Submitted'].value).to eq('auto-generated')
      expect(mail['X-Auto-Response-Suppress'].value).to eq('OOF')
    end

    # `mail_user` sets these too, so setting them in the action as SurveyMailer
    # does would send each one twice.
    it 'sets each header only once' do
      %w[Return-Path Reply-To Auto-Submitted X-Auto-Response-Suppress].each do |header|
        expect(Array(mail[header]).size).to eq(1), "#{header} appears more than once"
      end
    end

    it 'says the account will be removed unless they sign in' do
      expect(mail.subject)
        .to eq("Your #{AlaveteliConfiguration.site_name} account will be " \
               'removed unless you sign in')
    end

    it 'quotes the removal date in words' do
      expect(mail.body.to_s).to include('2 November 2026')
    end

    it 'links to the sign in page' do
      expect(mail.body.to_s).to include('/profile/sign_in')
    end

    it 'gives the contact address' do
      expect(mail.body.to_s).to include(AlaveteliConfiguration.contact_email)
    end

    # Unsubscribing would not stop the deletion, so offering it would mislead.
    it 'does not offer an unsubscribe link' do
      expect(mail.body.to_s.downcase).not_to include('unsubscribe')
    end
  end
end

RSpec.describe DormantAccountMailer, '.send_notices' do
  # The host loads spec/fixtures/users.yml globally, and some of those accounts
  # fall in this cohort, so these examples assert on the records they create
  # rather than on absolute counts.
  let(:out) { StringIO.new }
  let(:removal_date) { Date.new(2026, 11, 2) }

  let!(:dormant) { FactoryBot.create(:user, created_at: 3.years.ago) }

  before do
    # `User.unused` creates the CONTACT_EMAIL account if it is missing, so
    # reference it up front and keep that side effect out of the examples.
    User.internal_admin_user
  end

  describe '.send_notices' do
    context 'by default' do
      it 'sends nothing' do
        described_class.send_notices(out: out)
        expect(ActionMailer::Base.deliveries).to be_empty
      end

      it 'records nothing against the account' do
        described_class.send_notices(out: out)
        expect(dormant.reload.has_tag?(described_class::TAG)).to eq(false)
      end

      it 'lists the account it would notify' do
        described_class.send_notices(out: out)
        expect(out.string).to match(/^#{dormant.id}$/)
        expect(out.string).to match(/DRY RUN: would notify \d+ dormant accounts/)
      end

      it 'names the removal date it would quote' do
        travel_to(Date.new(2026, 9, 3)) do
          described_class.send_notices(out: out)
          expect(out.string).to include('2026-11-02')
        end
      end
    end

    context 'when DRYRUN is off' do
      it 'notifies the dormant account' do
        described_class.send_notices(dryrun: false, out: out)
        expect(ActionMailer::Base.deliveries.map(&:to).flatten)
          .to include(dormant.email)
      end

      it 'tags the account with the date it was notified' do
        travel_to(Date.new(2026, 9, 3)) do
          described_class.send_notices(dryrun: false, out: out)
        end

        expect(dormant.reload.tag_string)
          .to include("#{described_class::TAG}:2026-09-03")
      end

      it 'does not notify the same account twice' do
        described_class.send_notices(dryrun: false, out: out)
        ActionMailer::Base.deliveries = []

        described_class.send_notices(dryrun: false, out: out)

        expect(ActionMailer::Base.deliveries.map(&:to).flatten)
          .not_to include(dormant.email)
      end

      context 'with an account that should not be emailed' do
        # should_be_emailed? is the single gate for all outgoing mail, so each
        # of its four conditions is checked here.
        {
          'banned' => { ban_text: 'Banned' },
          'closed' => { closed_at: Time.zone.now },
          'never confirmed' => { email_confirmed: false },
          'opted out of alerts' => { receive_email_alerts: false },
          'already bounced' => { email_bounced_at: Time.zone.now }
        }.each do |description, attributes|
          it "does not notify an account that is #{description}" do
            dormant.update_columns(attributes)

            described_class.send_notices(dryrun: false, out: out)

            expect(ActionMailer::Base.deliveries.map(&:to).flatten)
              .not_to include(dormant.email)
          end
        end
      end

      it 'does not notify an account created within the last two years' do
        recent = FactoryBot.create(:user, created_at: 1.year.ago)

        described_class.send_notices(dryrun: false, out: out)

        expect(ActionMailer::Base.deliveries.map(&:to).flatten)
          .not_to include(recent.email)
      end

      context 'when a delivery fails' do
        # The :test delivery method cannot fail on its own, so the failure is
        # injected at the transport, which is the seam sendmail fails at in
        # production. raise_delivery_errors is on, so this is what the run sees.
        before do
          call = 0
          allow_any_instance_of(Mail::TestMailer)
            .to receive(:deliver!).and_wrap_original do |original, *args|
              call += 1
              raise Errno::EPIPE if call == 1

              original.call(*args)
            end
        end

        let!(:second_dormant) do
          FactoryBot.create(:user, created_at: 3.years.ago)
        end

        it 'carries on to the next account' do
          described_class.send_notices(dryrun: false, out: out)

          expect(ActionMailer::Base.deliveries.map(&:to).flatten)
            .to include(second_dormant.email)
        end

        it 'leaves the failed account untagged, so a later run retries it' do
          described_class.send_notices(dryrun: false, out: out)

          expect(dormant.reload.has_tag?(described_class::TAG)).to eq(false)
        end

        it 'logs the account id and error class, not the address' do
          described_class.send_notices(dryrun: false, out: out)

          expect(out.string)
            .to include("user #{dormant.id}: delivery failed (Errno::EPIPE)")
          expect(out.string).not_to include(dormant.email)
        end
      end

      context 'when every delivery fails' do
        before do
          allow_any_instance_of(Mail::TestMailer)
            .to receive(:deliver!).and_raise(Errno::EPIPE)

          Array.new(described_class::MAX_CONSECUTIVE_FAILURES) do
            FactoryBot.create(:user, created_at: 3.years.ago)
          end
        end

        # A local pipe that is broken would fail for the whole tranche, so the
        # run stops rather than attempting every account.
        it 'stops after too many consecutive failures' do
          described_class.send_notices(dryrun: false, limit: 100, out: out)

          expect(out.string).to match(/Stopping: \d+ consecutive failures/)
        end
      end
    end

    context 'with a limit' do
      before do
        Array.new(2) { FactoryBot.create(:user, created_at: 3.years.ago) }
      end

      it 'notifies no more than the limit' do
        described_class.send_notices(dryrun: false, limit: 2, out: out)

        expect(ActionMailer::Base.deliveries.size).to eq(2)
      end
    end
  end
end
